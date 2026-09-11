import SwiftUI
import AyantDomain

// MARK: - HostStore

@MainActor
public final class HostStore: ObservableObject {

    /// Всё состояние кабинета одним значением; вход — только `send(_:)`.
    @Published public private(set) var state = HostState()

    private weak var appStore: AppStore?
    private let repo: HostRepository
    private let clock: Clock

    /// ВНИМАНИЕ: ключи читают уже установленные приложения. Переименование =
    /// потеря кабинета хоста (заведения, акции, профиль) на устройстве.
    private enum Key {
        static let profile = "san.host.profile"
        static let venues = "san.host.venues"
        static let deals = "san.host.deals"
        static let campaigns = "san.host.campaigns"
        /// id заведений/акций, которые сервер хотя бы раз отдал этому владельцу.
        /// По ним `sync()` отличает «удалено на сервере» от «так и не доехало».
        static let knownVenues = "san.host.knownVenues"
        static let knownDeals = "san.host.knownDeals"
    }

    /// Что сервер уже знает (см. `Key.knownVenues`). Пусто у свежего кэша.
    private var knownVenueIDs: Set<String> = []
    private var knownDealIDs: Set<String> = []

    // Внутренние алиасы: тело стора работает с полями состояния как раньше.
    private var profile: HostProfile? {
        get { state.profile } set { state.profile = newValue }
    }
    private var venueDTOs: [HostVenueDTO] {
        get { state.venues } set { state.venues = newValue }
    }
    private var dealDTOs: [HostDealDTO] {
        get { state.deals } set { state.deals = newValue }
    }
    private var campaigns: [AdCampaign] {
        get { state.campaigns } set { state.campaigns = newValue }
    }
    public private(set) var ownerID: String {
        get { state.ownerID } set { state.ownerID = newValue }
    }

    public init(repo: HostRepository, clock: Clock = SystemClock()) {
        self.repo = repo
        self.clock = clock
        profile = decode(Key.profile)
        venueDTOs = decodeList(Key.venues)
        dealDTOs = decodeList(Key.deals)
        campaigns = decodeList(Key.campaigns)
    }

    /// Единственный вход. Читать — через `state`.
    public func send(_ intent: HostIntent) {
        switch intent {
        case .configure(let id):            configure(ownerID: id)
        case .sync:                         Task { await sync() }

        case .createAccount(let name, let category, let phone, let email):
            createAccount(businessName: name, category: category, phone: phone, email: email)
        case .updateProfile(let name, let phone, let email):
            updateProfile(businessName: name, phone: phone, email: email)
        case .updateBusinessInfo(let info):  updateBusinessInfo(info)
        case .requestVerification:           requestVerification()

        case .saveVenue(let existing, let fields):
            _ = saveVenueForm(existing: existing, fields: fields)
        case .togglePause(let venueID):      togglePause(venueID: venueID)
        case .setTodaySpecial(let venueID, let text):
            setTodaySpecial(venueID: venueID, text: text)
        case .deleteVenue(let id):           deleteVenue(id: id)
        case .addItem(let venueID, let name, let emoji, let kind, let imageURL):
            addItem(venueID: venueID, name: name, emoji: emoji, kind: kind, imageURL: imageURL)
        case .deleteItem(let venueID, let itemID):
            deleteItem(venueID: venueID, itemID: itemID)
        case .boostVenue(let id, let until):  boostVenue(id: id, until: until)
        case .savePointsConfig(let venueID, let fields):
            savePointsConfig(venueID: venueID, fields: fields)

        case .saveDeal(let existing, let fields):
            saveDealForm(existing: existing, fields: fields)
        case .setDealStatus(let id, let status): setDealStatus(id: id, status: status)
        case .duplicateDeal(let id):         duplicateDeal(id: id)
        case .deleteDeal(let id):            deleteDeal(id: id)

        case .addCampaign(let c):            addCampaign(c)
        case .launchPush(let headline, let body, let venueID, let dealID):
            launchPush(headline: headline, body: body, venueID: venueID, dealID: dealID)
        case .cancelCampaign(let id):        cancelCampaign(id: id)
        }
    }


    // Привязка к AppStore: контент хоста виден и на пользовательской стороне.
    public func bind(_ store: AppStore) {
        appStore = store
        pushToAppStore()
    }

    /// Ключ кэша, привязанный к владельцу. Пустой ownerID → легаси-глобальный ключ.
    private func key(_ base: String) -> String {
        ownerID.isEmpty ? base : "\(base).\(ownerID)"
    }

    /// Задаёт владельца (uid пользователя). Нужно до создания заведений.
    /// При смене владельца (вход/выход/другой аккаунт) перезагружает кэш этого
    /// аккаунта — так заведения «привязаны к аккаунту» и не утекают между ними.
    private func configure(ownerID id: String?) {
        let newOwner = id ?? ""
        guard newOwner != ownerID else { return }
        ownerID = newOwner
        reloadFromCache()
    }

    /// Перечитывает заведения/предложения/профиль текущего владельца из кэша.
    private func reloadFromCache() {
        profile = decode(key(Key.profile))
        venueDTOs = decodeList(key(Key.venues))
        dealDTOs = decodeList(key(Key.deals))
        campaigns = decodeList(key(Key.campaigns))
        knownVenueIDs = Set(decodeList(key(Key.knownVenues)) as [String])
        knownDealIDs = Set(decodeList(key(Key.knownDeals)) as [String])

        // Миграция: у авторизованного пользователя ещё нет своего кэша, но есть
        // легаси-глобальный (созданный до привязки к аккаунту) — усыновляем его
        // один раз, до-сохраняем в Firestore под ownerID и чистим глобальные ключи,
        // чтобы данные не утекли в другой аккаунт.
        if !ownerID.isEmpty, venueDTOs.isEmpty, dealDTOs.isEmpty,
           case let legacyV = decodeList(Key.venues) as [HostVenueDTO], !legacyV.isEmpty {
            venueDTOs = legacyV
            dealDTOs = decodeList(Key.deals)
            if profile == nil { profile = decode(Key.profile) }
            persistVenues(); persistDeals(); persistProfile(remote: true)
            for v in venueDTOs { remoteSaveVenue(v) }
            for d in dealDTOs { remoteSaveDeal(d) }
            UserDefaults.standard.removeObject(forKey: Key.venues)
            UserDefaults.standard.removeObject(forKey: Key.deals)
            UserDefaults.standard.removeObject(forKey: Key.campaigns)
            UserDefaults.standard.removeObject(forKey: Key.profile)
        }
        pushToAppStore()
    }

    /// Подтягивает заведения/предложения владельца из Firestore.
    /// Локальный кэш остаётся фолбэком при ошибке/офлайне.
    ///
    /// Локальная копия, которой нет на сервере, бывает двух видов, и раньше
    /// стор их не различал (просто оставлял обе на экране):
    ///  • сервер её уже отдавал (`known*`) → удалена админом или с другого
    ///    устройства → убираем и у себя, сервер — источник истины;
    ///  • сервер её никогда не видел → запись не дошла (офлайн, правила,
    ///    проглоченная ошибка) → дозаливаем. Так заведение, созданное без
    ///    сети, всё-таки попадает в Firestore, а не живёт вечно только в
    ///    кэше одного телефона — и не пропадает вместе с ним.
    public func sync() async {
        guard !ownerID.isEmpty else { return }
        state.sync = .syncing
        defer { if state.sync.isSyncing { state.sync = .idle } }
        do {
            async let v = repo.fetchOwnedVenues(ownerID: ownerID)
            async let d = repo.fetchOwnedDeals(ownerID: ownerID)
            let (remoteV, remoteD) = try await (v, d)
            let remoteVenueIDs = Set(remoteV.map(\.id))
            let remoteDealIDs = Set(remoteD.map(\.id))
            let unsentV = venueDTOs.filter { !remoteVenueIDs.contains($0.id) && !knownVenueIDs.contains($0.id) }
            let unsentD = dealDTOs.filter { !remoteDealIDs.contains($0.id) && !knownDealIDs.contains($0.id) }
            venueDTOs = Self.merge(remote: remoteV, local: unsentV, by: \.name)
            dealDTOs = Self.merge(remote: remoteD, local: unsentD, by: \.title)
            knownVenueIDs = remoteVenueIDs
            knownDealIDs = remoteDealIDs
            persist(key(Key.venues), venueDTOs)
            persist(key(Key.deals), dealDTOs)
            persistKnown()
            pushToAppStore()
            for dto in unsentV { remoteSaveVenue(dto) }
            for dto in unsentD { remoteSaveDeal(dto) }
            // Профиль (включая статус верификации, выставленный админом).
            if let remoteProfile = try await repo.fetchProfile(ownerID: ownerID) {
                profile = remoteProfile
                persistProfile(remote: false)
            }
        } catch {
            // Кэш остаётся на экране — ошибка синка не должна опустошать кабинет.
            state.sync = .failed(.network)
            print("⚠️ host sync failed, using local cache: \(error.localizedDescription)")
        }
    }

    /// Remote — источник истины; локальные элементы без удалённой копии сохраняются.
    /// Порядок стабильный: по названию (локализованно, без учёта регистра), затем по id.
    /// Словарь перечисляется как попало — без сортировки список в кабинете
    /// перетасовывался бы после каждого синка.
    private static func merge<T: Identifiable>(remote: [T], local: [T],
                                               by name: (T) -> String) -> [T] where T.ID == String {
        var byID: [String: T] = [:]
        for x in local { byID[x.id] = x }
        for x in remote { byID[x.id] = x }
        return byID.values.sorted { a, b in
            switch name(a).localizedCaseInsensitiveCompare(name(b)) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return a.id < b.id
            }
        }
    }

    /// Запись на сервер. Раньше — `try?` в никуда: заведение, которое сервер
    /// отверг или которое не дошло без сети, показывалось как сохранённое, а
    /// жило только в кэше устройства. Теперь провал виден в `state.sync`, а
    /// `sync()` дозаливает всё, чего сервер не знает.
    private func remoteSaveVenue(_ dto: HostVenueDTO) {
        guard !ownerID.isEmpty else { return }
        let owner = ownerID
        Task {
            do {
                try await repo.saveVenue(dto, ownerID: owner)
                knownVenueIDs.insert(dto.id); persistKnown()
            } catch { reportRemoteFailure(error) }
        }
    }
    private func remoteSaveDeal(_ dto: HostDealDTO) {
        guard !ownerID.isEmpty else { return }
        let owner = ownerID
        Task {
            do {
                try await repo.saveDeal(dto, ownerID: owner)
                knownDealIDs.insert(dto.id); persistKnown()
            } catch { reportRemoteFailure(error) }
        }
    }
    private func remoteDeleteVenue(_ id: String) {
        knownVenueIDs.remove(id); persistKnown()
        Task { do { try await repo.deleteVenue(id: id) } catch { reportRemoteFailure(error) } }
    }
    private func remoteDeleteDeal(_ id: String) {
        knownDealIDs.remove(id); persistKnown()
        Task { do { try await repo.deleteDeal(id: id) } catch { reportRemoteFailure(error) } }
    }

    private func reportRemoteFailure(_ error: Error) {
        state.sync = .failed(Self.appError(from: error))
        print("⚠️ host remote write failed: \(error.localizedDescription)")
    }

    /// Ошибка SDK → доменная. Firestore не импортируем (слой фич), поэтому
    /// по домену/коду `NSError`: 7 — permission denied, 14 — unavailable.
    private static func appError(from error: Error) -> AppError {
        if let app = error as? AppError { return app }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return .network }
        if ns.domain == "FIRFirestoreErrorDomain" {
            switch ns.code {
            case 7: return .permissionDenied
            case 14, 4: return .network
            case 16: return .unauthenticated
            default: return .unknown
            }
        }
        return .unknown
    }

    private func persistKnown() {
        persist(key(Key.knownVenues), Array(knownVenueIDs))
        persist(key(Key.knownDeals), Array(knownDealIDs))
    }

    // MARK: Конверсии

    public var venues: [Venue] { venueDTOs.map(\.asVenue) }
    public var deals: [Deal] { dealDTOs.map(\.asDeal) }
    public var ownedVenueIDs: Set<String> { Set(venueDTOs.map(\.id)) }

    public func deals(forVenue id: String) -> [HostDealDTO] {
        dealDTOs.filter { $0.venueID == id }.sorted { $0.startDate > $1.startDate }
    }

    public func venueDTO(id: String) -> HostVenueDTO? { venueDTOs.first { $0.id == id } }

    // MARK: Аккаунт хоста

    private func createAccount(businessName: String, category: VenueCategory, phone: String, email: String) {
        profile = HostProfile(businessName: businessName, categoryRaw: category.rawValue,
                              phone: phone, email: email, verification: .none)
        persistProfile()
    }

    private func updateProfile(businessName: String, phone: String, email: String) {
        profile?.businessName = businessName
        profile?.phone = phone
        profile?.email = email
        persistProfile()
    }

    /// Полное обновление информации о бизнесе (экран «Информация о бизнесе»).
    private func updateBusinessInfo(_ info: BusinessInfo) {
        if profile == nil {
            profile = HostProfile(businessName: info.businessName,
                                  categoryRaw: info.category.rawValue,
                                  phone: info.phone, email: info.email)
        }
        profile?.businessName = info.businessName
        profile?.categoryRaw = info.category.rawValue
        profile?.phone = info.phone
        profile?.email = info.email
        profile?.legalForm = info.legalForm
        profile?.legalName = info.legalName
        profile?.inn = info.inn
        profile?.registrationAddress = info.registrationAddress
        profile?.website = info.website
        profile?.about = info.about
        persistProfile()
    }

    private func requestVerification() {
        profile?.verification = .pending
        persistProfile()
    }

    // MARK: Заведения
    // Создание/правка заведения из формы — единая точка `saveVenueForm` ниже
    // (сборка DTO живёт в сторе, не во вью).

    private func updateVenue(_ dto: HostVenueDTO) {
        if let i = venueDTOs.firstIndex(where: { $0.id == dto.id }) { venueDTOs[i] = dto }
        persistVenues()
        remoteSaveVenue(dto)
    }

    /// Собирает `HostVenueDTO` из значений формы и сохраняет (создание либо правка).
    /// Сборка/тримминг DTO живут здесь, а не во вью — форма лишь передаёт значения.
    @discardableResult
    /// Создание/правка заведения из формы. Сборку DTO делает чистый `HostForms`
    /// (там же правила «что сохраняется при правке»), здесь — только запись.
    private func saveVenueForm(existing: HostVenueDTO?, fields: HostForms.VenueFields) -> HostVenueDTO {
        let dto = HostForms.venue(existing: existing, fields: fields,
                                  newID: "hv_\(UUID().uuidString.prefix(8))")
        if existing != nil {
            updateVenue(dto)
        } else {
            venueDTOs.append(dto)
            persistVenues()
            remoteSaveVenue(dto)
        }
        return dto
    }

    private func togglePause(venueID: String) {
        if let i = venueDTOs.firstIndex(where: { $0.id == venueID }) {
            venueDTOs[i].isPaused.toggle()
            persistVenues()
            remoteSaveVenue(venueDTOs[i])
        }
    }

    private func setTodaySpecial(venueID: String, text: String) {
        if let i = venueDTOs.firstIndex(where: { $0.id == venueID }) {
            venueDTOs[i].todaySpecial = text.trimmingCharacters(in: .whitespaces)
            persistVenues()
            remoteSaveVenue(venueDTOs[i])
        }
    }

    /// Конфиг баллов САН из редактора «Лояльность». Ограничения (кэшбэк ≤ 20 %,
    /// пауза 0…1440 мин и т. д.) накладывает чистый `HostForms.applyPoints`;
    /// здесь — только запись. Остальные поля заведения не трогаются.
    private func savePointsConfig(venueID: String, fields: HostForms.PointsFields) {
        guard let i = venueDTOs.firstIndex(where: { $0.id == venueID }) else { return }
        venueDTOs[i] = HostForms.applyPoints(to: venueDTOs[i], fields: fields)
        persistVenues()
        remoteSaveVenue(venueDTOs[i])
    }

    private func deleteVenue(id: String) {
        venueDTOs.removeAll { $0.id == id }
        dealDTOs.removeAll { $0.venueID == id }
        persistVenues(); persistDeals()
        remoteDeleteVenue(id)
    }

    // MARK: Объекты для отзывов (блюда/услуги)

    private func addItem(venueID: String, name: String, emoji: String, kind: String, imageURL: String = "") {
        guard let i = venueDTOs.firstIndex(where: { $0.id == venueID }) else { return }
        let item = VenueItem(id: "it_\(UUID().uuidString.prefix(8))",
                             name: name.trimmingCharacters(in: .whitespaces),
                             emoji: emoji.isEmpty ? "🍽" : emoji, kind: kind, imageURL: imageURL)
        venueDTOs[i].items.append(item)
        persistVenues()
        remoteSaveVenue(venueDTOs[i])
    }

    private func deleteItem(venueID: String, itemID: String) {
        guard let i = venueDTOs.firstIndex(where: { $0.id == venueID }) else { return }
        venueDTOs[i].items.removeAll { $0.id == itemID }
        persistVenues()
        remoteSaveVenue(venueDTOs[i])
    }

    // MARK: Предложения

    private func saveDeal(_ dto: HostDealDTO) {
        if let i = dealDTOs.firstIndex(where: { $0.id == dto.id }) { dealDTOs[i] = dto }
        else { dealDTOs.append(dto) }
        persistDeals()
        remoteSaveDeal(dto)
    }

    /// Собирает `HostDealDTO` из значений формы и сохраняет. Сборка DTO живёт в
    /// сторе — форма только передаёт значения полей.
    /// Создание/правка акции из формы. Сборку DTO делает чистый `HostForms`.
    private func saveDealForm(existing: HostDealDTO?, fields: HostForms.DealFields) {
        saveDeal(HostForms.deal(existing: existing, fields: fields,
                                now: clock.now, newID: newDealID()))
    }

    public func newDealID() -> String { "hd_\(UUID().uuidString.prefix(8))" }

    private func setDealStatus(id: String, status: DealStatus) {
        if let i = dealDTOs.firstIndex(where: { $0.id == id }) {
            dealDTOs[i].statusRaw = status.rawValue
            persistDeals()
            remoteSaveDeal(dealDTOs[i])
        }
    }

    private func duplicateDeal(id: String) {
        guard var d = dealDTOs.first(where: { $0.id == id }) else { return }
        d.id = newDealID()
        d.title += " (копия)"
        d.statusRaw = DealStatus.draft.rawValue
        dealDTOs.append(d)
        persistDeals()
        remoteSaveDeal(d)
    }

    private func deleteDeal(id: String) {
        dealDTOs.removeAll { $0.id == id }
        persistDeals()
        remoteDeleteDeal(id)
    }

    // MARK: Кампании (Promote)

    /// Включает буст заведения в ленте до даты (пишется в Firestore → видит юзер).
    private func boostVenue(id: String, until: Date) {
        guard let i = venueDTOs.firstIndex(where: { $0.id == id }) else { return }
        venueDTOs[i].boostedUntil = until
        persistVenues()
        remoteSaveVenue(venueDTOs[i])
    }

    private func addCampaign(_ c: AdCampaign) {
        campaigns.insert(c, at: 0)
        persist(key(Key.campaigns), campaigns)
    }

    /// Push-кампания: записывает документ в Firestore (Cloud Function рассылает FCM)
    /// и добавляет кампанию в список.
    private func launchPush(headline: String, body: String, venueID: String, dealID: String? = nil) {
        guard !ownerID.isEmpty else { return }
        let owner = ownerID
        Task {
            try? await repo.queuePushCampaign(headline: headline, body: body,
                                              city: City.bishkek.id, category: nil,
                                              venueID: venueID, dealID: dealID, ownerID: owner)
        }
    }

    private func cancelCampaign(id: String) {
        if let i = campaigns.firstIndex(where: { $0.id == id }) {
            campaigns[i].status = .cancelled
            persist(key(Key.campaigns), campaigns)
        }
    }

    public func campaignID() -> String { "ad_\(UUID().uuidString.prefix(8))" }

    // MARK: Persistence

    private func persistProfile(remote: Bool = true) {
        persist(key(Key.profile), profile)
        if remote, let p = profile, !ownerID.isEmpty {
            let owner = ownerID
            Task { try? await repo.saveProfile(p, ownerID: owner) }
        }
    }
    private func persistVenues() { persist(key(Key.venues), venueDTOs); pushToAppStore() }
    private func persistDeals() { persist(key(Key.deals), dealDTOs); pushToAppStore() }

    private func pushToAppStore() {
        appStore?.setHostContent(venues: venues, deals: deals)
    }

    private func persist<T: Encodable>(_ key: String, _ value: T) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func decode<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Список из кэша, поэлементно: один битый элемент не обнуляет весь список.
    /// Раньше `decode([T].self)` был «всё или ничего» — одна запись старой схемы
    /// стирала с экрана весь кабинет.
    private func decodeList<T: Decodable>(_ key: String) -> [T] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let boxes = try? JSONDecoder().decode([Lossy<T>].self, from: data) else { return [] }
        return boxes.compactMap(\.value)
    }
}

/// Обёртка для поэлементного декодирования: элемент, который не разобрался,
/// становится `nil` вместо ошибки всего массива.
private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
