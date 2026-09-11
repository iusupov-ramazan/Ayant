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
    public var sync: SyncPhase = .idle
    /// Сколько успешных сканов сделано за сессию. Экраны со статистикой
    /// перезагружаются, когда счётчик меняется: «Погашено купонов» должно
    /// вырасти сразу после скана, а не после ручного обновления.
    public var scansCompleted: Int = 0

    public init(ownerID: String = "", profile: HostProfile? = nil,
                venues: [HostVenueDTO] = [], deals: [HostDealDTO] = [],
                campaigns: [AdCampaign] = [], sync: SyncPhase = .idle,
                scansCompleted: Int = 0) {
        self.ownerID = ownerID; self.profile = profile
        self.venues = venues; self.deals = deals
        self.campaigns = campaigns; self.sync = sync
        self.scansCompleted = scansCompleted
    }

    /// Кабинет заведён — профиль создан.
    public var hasAccount: Bool { profile != nil }

    public var ownedVenueIDs: Set<String> { Set(venues.map(\.id)) }

    public func venue(id: String) -> HostVenueDTO? { venues.first { $0.id == id } }

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
    case addItem(venueID: String, name: String, emoji: String, kind: String, imageURL: String)
    case deleteItem(venueID: String, itemID: String)
    case boostVenue(id: String, until: Date)
    /// Конфиг баллов САН заведения из редактора «Лояльность». Значения режутся
    /// до серверных ограничений в `HostForms.applyPoints`.
    case savePointsConfig(venueID: String, fields: HostForms.PointsFields)

    // Акции
    case saveDeal(existing: HostDealDTO?, fields: HostForms.DealFields)
    case setDealStatus(id: String, status: DealStatus)
    case duplicateDeal(id: String)
    case deleteDeal(id: String)

    // Продвижение
    case addCampaign(AdCampaign)
    case launchPush(headline: String, body: String, venueID: String, dealID: String?)
    case cancelCampaign(id: String)
    /// Сканер успешно начислил/погасил — статистику пора перечитать.
    case noteScanSucceeded
}
