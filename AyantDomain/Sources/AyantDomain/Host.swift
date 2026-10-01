import Foundation

// Фича «Бизнес-кабинет»: состояние и намерения.
// Имена полей совпадают с `Host.kt` в `android/domain`.

/// Всё состояние хост-стороны одним значением.
///
/// Кэш заведений/акций читается с диска сразу, поэтому «загрузки» как таковой
/// нет — есть фаза синхронизации с сервером поверх уже показанных данных
/// (`sync`). Это отличается от ленты, где до первой загрузки показывать нечего.
public struct HostState: Equatable {
    /// uid владельца. Пусто — пользователь не вошёл; кэш тогда общий (легаси).
    public var ownerID: String = ""
    public var profile: HostProfile?
    public var venues: [HostVenueDTO] = []
    public var deals: [HostDealDTO] = []
    public var campaigns: [AdCampaign] = []
    /// Купоны, которые заведения этого владельца продают за бонусы.
    public var couponOffers: [CouponOffer] = []
    public var sync: SyncPhase = .idle
    /// Сколько успешных сканов сделано за сессию. Экраны со статистикой
    /// перезагружаются, когда счётчик меняется: «Погашено купонов» должно
    /// вырасти сразу после скана, а не после ручного обновления.
    public var scansCompleted: Int = 0
    /// Instagram по заведениям: ключ — venueID. Пусто — аккаунт не подключён.
    public var instagram: [String: InstagramVenueState] = [:]

    public init(ownerID: String = "", profile: HostProfile? = nil,
                venues: [HostVenueDTO] = [], deals: [HostDealDTO] = [],
                campaigns: [AdCampaign] = [], sync: SyncPhase = .idle,
                scansCompleted: Int = 0,
                instagram: [String: InstagramVenueState] = [:],
                couponOffers: [CouponOffer] = []) {
        self.ownerID = ownerID; self.profile = profile
        self.venues = venues; self.deals = deals
        self.campaigns = campaigns; self.sync = sync
        self.scansCompleted = scansCompleted
        self.instagram = instagram
        self.couponOffers = couponOffers
    }

    /// Кабинет заведён — профиль создан.
    public var hasAccount: Bool { profile != nil }

    public var ownedVenueIDs: Set<String> { Set(venues.map(\.id)) }

    public func venue(id: String) -> HostVenueDTO? { venues.first { $0.id == id } }

    /// Заведение, которое открыто на первой вкладке кабинета.
    ///
    /// Выбор хранится на устройстве по id, а заведение за это время могли
    /// удалить (здесь или с другого телефона) — тогда показываем первое, а не
    /// пустой экран: пустой экран означал бы «у вас нет заведений», что неправда.
    /// `nil` — только когда заведений нет вовсе.
    public func currentVenue(preferredID: String?) -> HostVenueDTO? {
        if let preferredID, let v = venue(id: preferredID) { return v }
        return venues.first
    }

    /// Какое заведение появилось с момента `before` — чтобы сразу открыть
    /// только что созданное. Ровно одно новое или ничего: несколько новых
    /// приходят не из формы, а с синхронизацией, и угадывать среди них
    /// «то самое» значило бы перескакивать на случайное.
    public func addedVenueID(since before: Set<String>) -> String? {
        let added = venues.map(\.id).filter { !before.contains($0) }
        return added.count == 1 ? added[0] : nil
    }

    public func instagram(venueID: String) -> InstagramVenueState {
        instagram[venueID] ?? InstagramVenueState()
    }

    /// Посты, уже превращённые в акции. Считается из самих акций, а не хранится
    /// отдельно: два источника правды тут разъедутся на первом же удалении.
    public var importedPostIDs: Set<String> { Set(deals.compactMap(\.sourcePostID)) }

    /// Купоны заведения, дорогие сверху — так их и сравнивают.
    public func couponOffers(forVenue id: String) -> [CouponOffer] {
        couponOffers.filter { $0.venueID == id }.sorted { $0.cost > $1.cost }
    }

    /// Акции заведения, новые сверху.
    public func deals(forVenue id: String) -> [HostDealDTO] {
        deals.filter { $0.venueID == id }.sorted { $0.startDate > $1.startDate }
    }

    /// Контент хоста в виде пользовательских моделей — им он накладывается на ленту.
    public var publicVenues: [Venue] { venues.map(\.asVenue) }
    public var publicDeals: [Deal] { deals.map(\.asDeal) }
}

/// Фаза синхронизации с сервером. Ошибка не стирает кэш — он остаётся видимым.
public enum SyncPhase: Equatable {
    case idle
    case syncing
    case failed(AppError)

    public var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }
}

/// Реквизиты бизнеса — отдельная структура, чтобы не тащить 10 аргументов в намерение.
public struct BusinessInfo: Equatable {
    public var businessName: String
    public var category: VenueCategory
    public var phone: String
    public var email: String
    public var legalForm: String
    public var legalName: String
    public var inn: String
    public var registrationAddress: String
    public var website: String
    public var about: String

    public init(businessName: String, category: VenueCategory, phone: String, email: String,
                legalForm: String = "", legalName: String = "", inn: String = "",
                registrationAddress: String = "", website: String = "", about: String = "") {
        self.businessName = businessName; self.category = category
        self.phone = phone; self.email = email
        self.legalForm = legalForm; self.legalName = legalName; self.inn = inn
        self.registrationAddress = registrationAddress; self.website = website; self.about = about
    }
}

/// Единственный вход в стор бизнес-кабинета.
public enum HostIntent: Equatable {
    /// Сменить владельца (вход/выход/другой аккаунт) — перечитывает его кэш.
    case configure(ownerID: String?)
    /// Подтянуть заведения/акции/профиль с сервера поверх кэша.
    case sync

    // Аккаунт
    case createAccount(businessName: String, category: VenueCategory, phone: String, email: String)
    case updateProfile(businessName: String, phone: String, email: String)
    case updateBusinessInfo(BusinessInfo)
    case requestVerification

    // Заведения
    case saveVenue(existing: HostVenueDTO?, fields: HostForms.VenueFields)
    case togglePause(venueID: String)
    case setTodaySpecial(venueID: String, text: String)
    case deleteVenue(id: String)
    /// Новое блюдо вручную — те же поля, что у правки (раздел, цена,
    /// описание, фото). `id` присваивает стор.
    case addItem(venueID: String, item: VenueItem)
    case deleteItem(venueID: String, itemID: String)
    /// Правка одного блюда (название, цена, описание, раздел, фото).
    case updateItem(venueID: String, item: VenueItem)
    /// Проверенные хозяином блюда из разбора PDF — слияние по `MenuImport.merge`.
    case importMenu(venueID: String, drafts: [MenuDraftItem])
    case boostVenue(id: String, until: Date)
    /// Конфиг баллов САН заведения из редактора «Лояльность». Значения режутся
    /// до серверных ограничений в `HostForms.applyPoints`.
    case savePointsConfig(venueID: String, fields: HostForms.PointsFields)

    // Акции
    case saveDeal(existing: HostDealDTO?, fields: HostForms.DealFields)
    case setDealStatus(id: String, status: DealStatus)
    case duplicateDeal(id: String)
    case deleteDeal(id: String)

    // Купоны заведения (продаются за бонусы)
    case saveCouponOffer(existing: CouponOffer?, fields: HostForms.CouponFields)
    /// Снять с продажи / вернуть. Отдельно от модерации: пауза — решение
    /// заведения, статус — администратора.
    case toggleCouponPause(id: String)
    case deleteCouponOffer(id: String)

    // Продвижение
    case addCampaign(AdCampaign)
    case launchPush(headline: String, body: String, venueID: String, dealID: String?)
    case cancelCampaign(id: String)
    /// Сканер успешно начислил/погасил — статистику пора перечитать.
    case noteScanSucceeded

    // Instagram
    /// Запросить ссылку входа — вью откроет её в системном браузере.
    case connectInstagram(venueID: String)
    /// Вернулись из браузера: перечитать подключение и погасить `authURL`.
    case instagramConnected(venueID: String)
    /// Кнопка «Синхронизировать»: перечитать последние посты.
    case syncInstagram(venueID: String)
    /// Перезалить фото поста на наш CDN — дальше хост правит форму акции.
    case importInstagramPost(venueID: String, postID: String)
    case disconnectInstagram(venueID: String)
}
