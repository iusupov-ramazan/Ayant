import SwiftUI

// MARK: - Статус верификации

enum VerificationStatus: String, Codable {
    case none, pending, verified, rejected

    var title: String {
        switch self {
        case .none: return "Не запрошена"
        case .pending: return "На рассмотрении"
        case .verified: return "Подтверждено ✓"
        case .rejected: return "Отклонено"
        }
    }
}

// MARK: - Профиль хоста

struct HostProfile: Codable {
    var businessName: String
    var categoryRaw: String
    var phone: String
    var email: String
    var verification: VerificationStatus = .none
    // Реквизиты / расширенная информация о бизнесе
    var legalForm: String = ""            // ИП / ООО / Самозанятый
    var legalName: String = ""            // ФИО ИП или название юрлица
    var inn: String = ""                  // ИНН / ОГРНИП
    var registrationAddress: String = ""  // юридический адрес
    var website: String = ""
    var about: String = ""                // описание бизнеса

    var category: VenueCategory { VenueCategory(rawValue: categoryRaw) ?? .cafe }

    init(businessName: String, categoryRaw: String, phone: String, email: String,
         verification: VerificationStatus = .none,
         legalForm: String = "", legalName: String = "", inn: String = "",
         registrationAddress: String = "", website: String = "", about: String = "") {
        self.businessName = businessName; self.categoryRaw = categoryRaw
        self.phone = phone; self.email = email; self.verification = verification
        self.legalForm = legalForm; self.legalName = legalName; self.inn = inn
        self.registrationAddress = registrationAddress; self.website = website; self.about = about
    }

    // Обратная совместимость: старые сохранённые профили без новых полей.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        businessName = try c.decodeIfPresent(String.self, forKey: .businessName) ?? ""
        categoryRaw = try c.decodeIfPresent(String.self, forKey: .categoryRaw) ?? VenueCategory.cafe.rawValue
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        verification = try c.decodeIfPresent(VerificationStatus.self, forKey: .verification) ?? .none
        legalForm = try c.decodeIfPresent(String.self, forKey: .legalForm) ?? ""
        legalName = try c.decodeIfPresent(String.self, forKey: .legalName) ?? ""
        inn = try c.decodeIfPresent(String.self, forKey: .inn) ?? ""
        registrationAddress = try c.decodeIfPresent(String.self, forKey: .registrationAddress) ?? ""
        website = try c.decodeIfPresent(String.self, forKey: .website) ?? ""
        about = try c.decodeIfPresent(String.self, forKey: .about) ?? ""
    }
}

// MARK: - DTO заведения хоста (Codable; конвертируется в Venue)

struct HostVenueDTO: Codable, Identifiable {
    var id: String
    var name: String
    var categoryRaw: String
    var district: String
    var address: String
    var phone: String
    var emoji: String
    var latitude: Double
    var longitude: Double
    var openHour: Int
    var closeHour: Int
    var todaySpecial: String?
    var isPaused: Bool
    var isVerified: Bool
    var status: String = ModerationStatus.pending.rawValue   // модерация
    var items: [VenueItem] = []                              // блюда/услуги
    var imageURL: String = ""                                // ссылка на обложку
    var weekHours: [DayHours] = Venue.defaultWeek()          // часы по дням недели
    var pdfMenuURL: String = ""                              // прайс-лист / каталог (PDF)
    var whatsapp: String = ""
    var instagram: String = ""
    var telegram: String = ""
    var branches: [Branch] = []                              // дополнительные адреса
    var boostedUntil: Date? = nil                            // буст в ленте до даты
    var loyaltyEnabled: Bool = false                         // карта лояльности вкл/выкл
    var loyaltyGoal: Int = 6                                 // штампов до награды
    var loyaltyReward: String = "Награда за лояльность"      // текст награды
    var couponsEnabled: Bool = true                          // принимать купоны (по умолчанию да)

    var category: VenueCategory { VenueCategory(rawValue: categoryRaw) ?? .cafe }
    var moderation: ModerationStatus { ModerationStatus(rawValue: status) ?? .pending }

    var asVenue: Venue {
        Venue(
            id: id, name: name, category: category, district: district,
            address: address, phone: phone, emoji: emoji,
            gradient: [.sanAccent, .orange], imageURL: imageURL.isEmpty ? nil : imageURL,
            rating: 0, reviewCount: 0, isVerified: isVerified, savedByCount: 0,
            citySlug: City.bishkek.id, latitude: latitude, longitude: longitude,
            todaySpecialText: (todaySpecial?.isEmpty == false) ? todaySpecial : nil,
            openHour: openHour, closeHour: closeHour, weekHours: weekHours,
            pdfMenuURL: pdfMenuURL.isEmpty ? nil : pdfMenuURL,
            photoEmojis: [emoji], items: items, statusRaw: status, isPaused: isPaused,
            whatsapp: whatsapp, instagram: instagram, telegram: telegram, branches: branches,
            boostedUntil: boostedUntil,
            loyaltyEnabled: loyaltyEnabled, loyaltyGoal: loyaltyGoal, loyaltyReward: loyaltyReward,
            couponsEnabled: couponsEnabled
        )
    }
}

// MARK: - DTO предложения хоста

struct HostDealDTO: Codable, Identifiable {
    var id: String
    var venueID: String
    var typeRaw: String
    var title: String
    var details: String
    var emoji: String
    var newPrice: Int?
    var discountPercent: Int?
    var startDate: Date
    var endDate: Date?
    var statusRaw: String
    var imageURL: String = ""
    var imageURLs: [String] = []      // галерея фото (карусель)

    var type: DealType { DealType(rawValue: typeRaw) ?? .discount }
    var status: DealStatus { DealStatus(rawValue: statusRaw) ?? .active }

    var asDeal: Deal {
        Deal(
            id: id, venueID: venueID, type: type, title: title, details: details,
            emoji: emoji, oldPrice: nil, newPrice: newPrice,
            discountPercent: discountPercent,
            validUntil: endDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now)!,
            status: status, startDate: startDate, imageEmojis: [emoji],
            imageURL: imageURL.isEmpty ? nil : imageURL,
            imageURLs: imageURLs
        )
    }
}

// MARK: - Рекламная кампания (Promote, mock)

struct AdCampaign: Codable, Identifiable {
    enum Kind: String, Codable { case boost, push
        var title: String { self == .boost ? "Буст заведения" : "Push-уведомление" }
    }
    enum Status: String, Codable { case scheduled, active, sent, completed, cancelled
        var title: String {
            switch self {
            case .scheduled: return "Запланирована"
            case .active: return "Активна"
            case .sent: return "Отправлено"
            case .completed: return "Завершена"
            case .cancelled: return "Отменена"
            }
        }
        /// Зелёным подсвечиваем «живые» статусы.
        var isLive: Bool { self == .active || self == .sent }
    }
    var id: String
    var kind: Kind
    var venueID: String
    var status: Status
    var startAt: Date
    var endAt: Date
    var impressions: Int
    var taps: Int
    var spend: Int

    /// Фактический статус с учётом времени: истёкший буст → «Завершена».
    /// Push — разовая отправка, остаётся «Отправлено».
    var effectiveStatus: Status {
        if status == .cancelled { return .cancelled }
        if kind == .push { return status }
        return endAt < Date() ? .completed : status
    }
}

// MARK: - HostStore

@MainActor
final class HostStore: ObservableObject {

    @Published var profile: HostProfile?
    @Published private(set) var venueDTOs: [HostVenueDTO] = []
    @Published private(set) var dealDTOs: [HostDealDTO] = []
    @Published private(set) var campaigns: [AdCampaign] = []

    private weak var appStore: AppStore?
    private let repo: HostRepository
    private(set) var ownerID = ""   // uid текущего пользователя-владельца

    private enum Key {
        static let profile = "san.host.profile"
        static let venues = "san.host.venues"
        static let deals = "san.host.deals"
        static let campaigns = "san.host.campaigns"
    }

    init(repo: HostRepository = AppConfig.makeHostRepository()) {
        self.repo = repo
        profile = decode(Key.profile)
        venueDTOs = decode(Key.venues) ?? []
        dealDTOs = decode(Key.deals) ?? []
        campaigns = decode(Key.campaigns) ?? []
    }

    var hasAccount: Bool { profile != nil }

    // Привязка к AppStore: контент хоста виден и на пользовательской стороне.
    func bind(_ store: AppStore) {
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
    func configure(ownerID id: String?) {
        let newOwner = id ?? ""
        guard newOwner != ownerID else { return }
        ownerID = newOwner
        reloadFromCache()
    }

    /// Перечитывает заведения/предложения/профиль текущего владельца из кэша.
    private func reloadFromCache() {
        profile = decode(key(Key.profile))
        venueDTOs = decode(key(Key.venues)) ?? []
        dealDTOs = decode(key(Key.deals)) ?? []
        campaigns = decode(key(Key.campaigns)) ?? []

        // Миграция: у авторизованного пользователя ещё нет своего кэша, но есть
        // легаси-глобальный (созданный до привязки к аккаунту) — усыновляем его
        // один раз, до-сохраняем в Firestore под ownerID и чистим глобальные ключи,
        // чтобы данные не утекли в другой аккаунт.
        if !ownerID.isEmpty, venueDTOs.isEmpty, dealDTOs.isEmpty,
           let legacyV: [HostVenueDTO] = decode(Key.venues), !legacyV.isEmpty {
            venueDTOs = legacyV
            dealDTOs = decode(Key.deals) ?? []
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
    func sync() async {
        guard !ownerID.isEmpty else { return }
        do {
            async let v = repo.fetchOwnedVenues(ownerID: ownerID)
            async let d = repo.fetchOwnedDeals(ownerID: ownerID)
            let (remoteV, remoteD) = try await (v, d)
            venueDTOs = Self.merge(remote: remoteV, local: venueDTOs)
            dealDTOs = Self.merge(remote: remoteD, local: dealDTOs)
            persist(key(Key.venues), venueDTOs)
            persist(key(Key.deals), dealDTOs)
            pushToAppStore()
            // Профиль (включая статус верификации, выставленный админом).
            if let remoteProfile = try await repo.fetchProfile(ownerID: ownerID) {
                profile = remoteProfile
                persistProfile(remote: false)
            }
        } catch {
            print("⚠️ host sync failed, using local cache: \(error.localizedDescription)")
        }
    }

    /// Remote — источник истины; локальные элементы без удалённой копии сохраняются.
    private static func merge<T: Identifiable>(remote: [T], local: [T]) -> [T] where T.ID == String {
        var byID: [String: T] = [:]
        for x in local { byID[x.id] = x }
        for x in remote { byID[x.id] = x }
        return Array(byID.values)
    }

    private func remoteSaveVenue(_ dto: HostVenueDTO) {
        guard !ownerID.isEmpty else { return }
        Task { try? await repo.saveVenue(dto, ownerID: ownerID) }
    }
    private func remoteSaveDeal(_ dto: HostDealDTO) {
        guard !ownerID.isEmpty else { return }
        Task { try? await repo.saveDeal(dto, ownerID: ownerID) }
    }
    private func remoteDeleteVenue(_ id: String) { Task { try? await repo.deleteVenue(id: id) } }
    private func remoteDeleteDeal(_ id: String) { Task { try? await repo.deleteDeal(id: id) } }

    // MARK: Конверсии

    var venues: [Venue] { venueDTOs.map(\.asVenue) }
    var deals: [Deal] { dealDTOs.map(\.asDeal) }
    var ownedVenueIDs: Set<String> { Set(venueDTOs.map(\.id)) }

    func deals(forVenue id: String) -> [HostDealDTO] {
        dealDTOs.filter { $0.venueID == id }.sorted { $0.startDate > $1.startDate }
    }

    func venueDTO(id: String) -> HostVenueDTO? { venueDTOs.first { $0.id == id } }

    // MARK: Аккаунт хоста

    func createAccount(businessName: String, category: VenueCategory, phone: String, email: String) {
        profile = HostProfile(businessName: businessName, categoryRaw: category.rawValue,
                              phone: phone, email: email, verification: .none)
        persistProfile()
    }

    func updateProfile(businessName: String, phone: String, email: String) {
        profile?.businessName = businessName
        profile?.phone = phone
        profile?.email = email
        persistProfile()
    }

    /// Полное обновление информации о бизнесе (экран «Информация о бизнесе»).
    func updateBusinessInfo(businessName: String, category: VenueCategory, phone: String, email: String,
                            legalForm: String, legalName: String, inn: String,
                            registrationAddress: String, website: String, about: String) {
        if profile == nil {
            profile = HostProfile(businessName: businessName, categoryRaw: category.rawValue,
                                  phone: phone, email: email)
        }
        profile?.businessName = businessName
        profile?.categoryRaw = category.rawValue
        profile?.phone = phone
        profile?.email = email
        profile?.legalForm = legalForm
        profile?.legalName = legalName
        profile?.inn = inn
        profile?.registrationAddress = registrationAddress
        profile?.website = website
        profile?.about = about
        persistProfile()
    }

    func requestVerification() {
        profile?.verification = .pending
        persistProfile()
    }

    // MARK: Заведения
    // Создание/правка заведения из формы — единая точка `saveVenueForm` ниже
    // (сборка DTO живёт в сторе, не во вью).

    func updateVenue(_ dto: HostVenueDTO) {
        if let i = venueDTOs.firstIndex(where: { $0.id == dto.id }) { venueDTOs[i] = dto }
        persistVenues()
        remoteSaveVenue(dto)
    }

    /// Собирает `HostVenueDTO` из значений формы и сохраняет (создание либо правка).
    /// Сборка/тримминг DTO живут здесь, а не во вью — форма лишь передаёт значения.
    @discardableResult
    func saveVenueForm(existing: HostVenueDTO?,
                       name: String, category: VenueCategory, district: String, address: String,
                       phone: String, emoji: String, latitude: Double, longitude: Double,
                       openHour: Int, closeHour: Int, imageURL: String, weekHours: [DayHours],
                       pdfMenuURL: String, whatsapp: String, instagram: String, telegram: String,
                       branches: [Branch], loyaltyEnabled: Bool, loyaltyGoal: Int,
                       loyaltyReward: String, couponsEnabled: Bool) -> HostVenueDTO {
        func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
        // Правка — поверх существующего DTO (сохраняем id/status/todaySpecial);
        // создание — новый DTO со статусом «на модерации» по умолчанию.
        var dto = existing ?? HostVenueDTO(
            id: "hv_\(UUID().uuidString.prefix(8))", name: name, categoryRaw: category.rawValue,
            district: district, address: address, phone: phone, emoji: emoji,
            latitude: latitude, longitude: longitude, openHour: openHour, closeHour: closeHour,
            todaySpecial: nil, isPaused: false, isVerified: false)
        dto.name = name; dto.categoryRaw = category.rawValue; dto.district = district
        dto.address = address; dto.phone = phone; dto.emoji = emoji
        dto.latitude = latitude; dto.longitude = longitude
        dto.openHour = openHour; dto.closeHour = closeHour
        dto.imageURL = trim(imageURL)
        dto.weekHours = weekHours
        dto.pdfMenuURL = trim(pdfMenuURL)
        dto.whatsapp = trim(whatsapp)
        dto.instagram = trim(instagram)
        dto.telegram = trim(telegram)
        dto.branches = branches
        dto.loyaltyEnabled = loyaltyEnabled
        dto.loyaltyGoal = loyaltyGoal
        dto.loyaltyReward = trim(loyaltyReward)
        dto.couponsEnabled = couponsEnabled

        if existing != nil {
            updateVenue(dto)
        } else {
            venueDTOs.append(dto)
            persistVenues()
            remoteSaveVenue(dto)
        }
        return dto
    }

    func togglePause(venueID: String) {
        if let i = venueDTOs.firstIndex(where: { $0.id == venueID }) {
            venueDTOs[i].isPaused.toggle()
            persistVenues()
            remoteSaveVenue(venueDTOs[i])
        }
    }

    func setTodaySpecial(venueID: String, text: String) {
        if let i = venueDTOs.firstIndex(where: { $0.id == venueID }) {
            venueDTOs[i].todaySpecial = text.trimmingCharacters(in: .whitespaces)
            persistVenues()
            remoteSaveVenue(venueDTOs[i])
        }
    }

    func deleteVenue(id: String) {
        venueDTOs.removeAll { $0.id == id }
        dealDTOs.removeAll { $0.venueID == id }
        persistVenues(); persistDeals()
        remoteDeleteVenue(id)
    }

    // MARK: Объекты для отзывов (блюда/услуги)

    func addItem(venueID: String, name: String, emoji: String, kind: String, imageURL: String = "") {
        guard let i = venueDTOs.firstIndex(where: { $0.id == venueID }) else { return }
        let item = VenueItem(id: "it_\(UUID().uuidString.prefix(8))",
                             name: name.trimmingCharacters(in: .whitespaces),
                             emoji: emoji.isEmpty ? "🍽" : emoji, kind: kind, imageURL: imageURL)
        venueDTOs[i].items.append(item)
        persistVenues()
        remoteSaveVenue(venueDTOs[i])
    }

    func deleteItem(venueID: String, itemID: String) {
        guard let i = venueDTOs.firstIndex(where: { $0.id == venueID }) else { return }
        venueDTOs[i].items.removeAll { $0.id == itemID }
        persistVenues()
        remoteSaveVenue(venueDTOs[i])
    }

    // MARK: Предложения

    func saveDeal(_ dto: HostDealDTO) {
        if let i = dealDTOs.firstIndex(where: { $0.id == dto.id }) { dealDTOs[i] = dto }
        else { dealDTOs.append(dto) }
        persistDeals()
        remoteSaveDeal(dto)
    }

    /// Собирает `HostDealDTO` из значений формы и сохраняет. Сборка DTO живёт в
    /// сторе — форма только передаёт значения полей.
    func saveDealForm(existing: HostDealDTO?, venueID: String, type: DealType, title: String,
                      details: String, emoji: String, newPrice: Int?, discountPercent: Int?,
                      endDate: Date?, isDraft: Bool, imageURLs: [String]) {
        let dto = HostDealDTO(
            id: existing?.id ?? newDealID(),
            venueID: venueID, typeRaw: type.rawValue, title: title, details: details, emoji: emoji,
            newPrice: newPrice, discountPercent: discountPercent,
            startDate: existing?.startDate ?? .now,
            endDate: endDate,
            statusRaw: (isDraft ? DealStatus.draft : .active).rawValue,
            imageURL: imageURLs.first ?? "",
            imageURLs: imageURLs)
        saveDeal(dto)
    }

    func newDealID() -> String { "hd_\(UUID().uuidString.prefix(8))" }

    func setDealStatus(id: String, status: DealStatus) {
        if let i = dealDTOs.firstIndex(where: { $0.id == id }) {
            dealDTOs[i].statusRaw = status.rawValue
            persistDeals()
            remoteSaveDeal(dealDTOs[i])
        }
    }

    func duplicateDeal(id: String) {
        guard var d = dealDTOs.first(where: { $0.id == id }) else { return }
        d.id = newDealID()
        d.title += " (копия)"
        d.statusRaw = DealStatus.draft.rawValue
        dealDTOs.append(d)
        persistDeals()
        remoteSaveDeal(d)
    }

    func deleteDeal(id: String) {
        dealDTOs.removeAll { $0.id == id }
        persistDeals()
        remoteDeleteDeal(id)
    }

    // MARK: Кампании (Promote)

    /// Включает буст заведения в ленте до даты (пишется в Firestore → видит юзер).
    func boostVenue(id: String, until: Date) {
        guard let i = venueDTOs.firstIndex(where: { $0.id == id }) else { return }
        venueDTOs[i].boostedUntil = until
        persistVenues()
        remoteSaveVenue(venueDTOs[i])
    }

    func addCampaign(_ c: AdCampaign) {
        campaigns.insert(c, at: 0)
        persist(key(Key.campaigns), campaigns)
    }

    /// Push-кампания: записывает документ в Firestore (Cloud Function рассылает FCM)
    /// и добавляет кампанию в список.
    func launchPush(headline: String, body: String, venueID: String, dealID: String? = nil) {
        guard !ownerID.isEmpty else { return }
        let owner = ownerID
        Task {
            try? await repo.queuePushCampaign(headline: headline, body: body,
                                              city: City.bishkek.id, category: nil,
                                              venueID: venueID, dealID: dealID, ownerID: owner)
        }
    }

    func cancelCampaign(id: String) {
        if let i = campaigns.firstIndex(where: { $0.id == id }) {
            campaigns[i].status = .cancelled
            persist(key(Key.campaigns), campaigns)
        }
    }

    func campaignID() -> String { "ad_\(UUID().uuidString.prefix(8))" }

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
}
