import Foundation

// Доменные модели. Здесь нет SwiftUI и нет Firebase — только Foundation.
//
// Цвета намеренно хранятся как RGB-числа (`Venue.gradient`, см. ниже), а не как
// `Color`: тип из SwiftUI утянул бы за собой UI-фреймворк и закрыл бы модуль для
// тестов без симулятора. Превращение чисел в `Color` живёт в `SAN/Theme/ModelColors.swift`.
// Так же устроен Android: `List<Long>` в модели + `ui/theme/ModelColors.kt`.

// MARK: - Типы предложений (С-А-Н)

public enum DealType: String, CaseIterable, Identifiable, Sendable {
    case discount = "Скидка"
    case promo = "Акция"
    case novelty = "Новинка"
    case announcement = "Объявление"

    public var id: String { rawValue }

    /// Имя SF Symbol. Строка, а не картинка, — поэтому остаётся в домене.
    public var icon: String {
        switch self {
        case .discount: return "percent"
        case .promo: return "gift.fill"
        case .novelty: return "sparkles"
        case .announcement: return "megaphone.fill"
        }
    }
}

// MARK: - Статус предложения (по спецификации)

public enum DealStatus: String, CaseIterable, Identifiable, Codable, Sendable {
    case active, paused, expired, draft

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .active: return "Активно"
        case .paused: return "На паузе"
        case .expired: return "Завершено"
        case .draft: return "Черновик"
        }
    }
}

// MARK: - Категории заведений

/// Категория заведения. Раньше была `enum` из 6 значений; теперь — открытый
/// тип (struct), чтобы категории можно было добавлять из бэкенда (админки).
/// `rawValue` — отображаемое имя (RU), напр. «Кафе». Встроенные значения
/// остаются как статические свойства (`.cafe`, `.coffee`…), поэтому весь
/// существующий код (`== .cafe`, `?? .cafe`, `.rawValue`, `.icon`) работает.
public struct VenueCategory: RawRepresentable, Identifiable, Hashable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    public var id: String { rawValue }

    // Встроенные категории (fallback, если бэкенд недоступен).
    public static let cafe       = VenueCategory(rawValue: "Кафе")!
    public static let coffee     = VenueCategory(rawValue: "Кофейня")!
    public static let fastfood   = VenueCategory(rawValue: "Фастфуд")!
    public static let restaurant = VenueCategory(rawValue: "Ресторан")!
    public static let teahouse   = VenueCategory(rawValue: "Чайхана")!
    public static let bakery     = VenueCategory(rawValue: "Пекарня")!

    public static let allCases: [VenueCategory] = [.cafe, .coffee, .fastfood, .restaurant, .teahouse, .bakery]

    private static let builtinIcons: [String: String] = [
        "Кафе": "fork.knife", "Кофейня": "cup.and.saucer.fill",
        "Фастфуд": "takeoutbag.and.cup.and.straw.fill", "Ресторан": "wineglass.fill",
        "Чайхана": "mug.fill", "Пекарня": "birthday.cake.fill",
    ]
    /// Иконки категорий из бэкенда (имя → SF Symbol). Заполняет CategoryStore.
    public static var iconRegistry: [String: String] = [:]
    /// Код категории из бэкенда (slug → отображаемое имя). Заполняет CategoryStore.
    public static var slugRegistry: [String: String] = [:]

    /// SF Symbol категории: бэкенд → встроенная карта → универсальная иконка.
    public var icon: String {
        VenueCategory.iconRegistry[rawValue] ?? VenueCategory.builtinIcons[rawValue] ?? "tag.fill"
    }

    /// Насколько категория «в сезон» в данный локальный час, 0…1 — контекстный буст
    /// для ленты (кофе утром, рестораны к ужину), ключ — rawValue, как у `icon`.
    /// Эвристические значения, можно тюнить. Неизвестные/серверные категории →
    /// нейтральные 0.5 (не буст и не штраф). Зеркалит Android.
    public func timeRelevance(hour: Int) -> Double {
        switch rawValue {
        case "Кофейня", "Пекарня":   // утро
            switch hour { case 7...10: return 1.0; case 11...16: return 0.6; default: return 0.35 }
        case "Фастфуд":              // обед + вечер
            switch hour { case 11...14: return 1.0; case 18...22: return 0.8; default: return 0.45 }
        case "Ресторан":             // ужин
            switch hour { case 18...22: return 1.0; case 12...15: return 0.7; default: return 0.4 }
        case "Чайхана":              // день → вечер
            return (12...22).contains(hour) ? 1.0 : 0.45
        case "Кафе":                 // весь день, широкий
            return 0.7
        default:                     // неизвестная → нейтрально
            return 0.5
        }
    }

    /// Заполняет реестры иконок и слагов из серверных категорий (вызывает CategoryStore).
    public static func applyRemote(_ cats: [RemoteCategory]) {
        var icons: [String: String] = [:]
        var slugs: [String: String] = [:]
        for c in cats { icons[c.name] = c.icon; slugs[c.slug] = c.name }
        iconRegistry = icons
        slugRegistry = slugs
    }
}

// MARK: - Город (масштабирование на города Центральной Азии)

public struct City: Identifiable, Hashable, Sendable {
    public let id: String        // slug, напр. "bishkek"
    public let name: String      // отображаемое имя
    public let country: String
    public let latitude: Double   // центр города — старт карты и фолбэк координат
    public let longitude: Double
    /// Часовой пояс города (IANA). Часы работы заведений записаны по МЕСТНОМУ
    /// времени города, а телефон может стоять в любом другом поясе — без этого
    /// «открыто сейчас» считалось по часам телефона и врало на всю разницу.
    public let timeZoneID: String

    public init(id: String, name: String, country: String,
                latitude: Double, longitude: Double,
                timeZoneID: String = City.defaultTimeZoneID) {
        self.timeZoneID = timeZoneID
        self.id = id; self.name = name; self.country = country
        self.latitude = latitude; self.longitude = longitude
    }

    public static let bishkek = City(id: "bishkek", name: "Бишкек", country: "Кыргызстан",
                                     latitude: 42.8746, longitude: 74.5698,
                                     timeZoneID: "Asia/Bishkek")

    /// Пока город один; когда появятся другие — добавлять сюда, а не в UI.
    public static let all: [City] = [bishkek]

    public static let defaultTimeZoneID = "Asia/Bishkek"

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .gmt }

    /// Пояс города по его slug. Неизвестный slug — пояс каталога по умолчанию:
    /// лучше показать часы Бишкека, чем часы телефона в другой стране.
    public static func timeZone(forSlug slug: String) -> TimeZone {
        all.first { $0.id == slug }?.timeZone
            ?? TimeZone(identifier: defaultTimeZoneID) ?? .gmt
    }

    /// Календарь в поясе города — им считаются «сегодня» и время открытия.
    public static func calendar(forSlug slug: String) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone(forSlug: slug)
        return cal
    }
}

// MARK: - Объект для отзыва (блюдо / услуга внутри заведения)

public struct VenueItem: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var emoji: String
    public var kind: String   // "food" | "service" | "other"
    public var imageURL: String = ""   // фото объекта (фолбэк — эмодзи)

    public init(id: String, name: String, emoji: String, kind: String, imageURL: String = "") {
        self.id = id; self.name = name; self.emoji = emoji; self.kind = kind; self.imageURL = imageURL
    }

    public var kindTitle: String {
        switch kind {
        case "service": return "Услуга"
        case "other": return "Объект"
        default: return "Блюдо"
        }
    }
}

// MARK: - Филиал (дополнительный адрес заведения)

public struct Branch: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var address: String
    public var latitude: Double
    public var longitude: Double
    public var phone: String = ""

    public init(id: String, address: String, latitude: Double, longitude: Double, phone: String = "") {
        self.id = id; self.address = address
        self.latitude = latitude; self.longitude = longitude; self.phone = phone
    }
}

// MARK: - Бонусы САН (баллы заведения, System 1)

/// Диапазон суммы чека → баллы (режим начисления "bands").
/// Персонал жмёт кнопку нужного диапазона при сканировании (индекс = bandIndex).
public struct PointsBand: Hashable, Codable, Sendable {
    public var maxAmount: Int   // «до этой суммы, сом»; верхний диапазон = «и больше»
    public var points: Int      // сколько баллов начислить

    public init(maxAmount: Int, points: Int) {
        self.maxAmount = maxAmount; self.points = points
    }
}

/// Награда из каталога заведения, покупается за баллы.
public struct PointsReward: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var type: String      // "item" (фикс. цена) | "money" (скидка баллами)
    public var title: String
    public var cost: Int         // item: цена в баллах; money: минимум баллов к списанию
    public var ratio: Double = 1 // money: сом скидки за 1 балл (по умолчанию 1)
    public var active: Bool = true

    public init(id: String, type: String, title: String, cost: Int,
                ratio: Double = 1, active: Bool = true) {
        self.id = id; self.type = type; self.title = title
        self.cost = cost; self.ratio = ratio; self.active = active
    }
}

// MARK: - Часы работы по дням недели

/// Часы работы одного дня. Время — минуты от полуночи (напр. 9:30 = 570).
public struct DayHours: Codable, Hashable, Sendable {
    public var closed: Bool = false
    public var open: Int = 9 * 60
    public var close: Int = 22 * 60

    public init(closed: Bool = false, open: Int = 9 * 60, close: Int = 22 * 60) {
        self.closed = closed; self.open = open; self.close = close
    }

    public var label: String {
        closed ? "Выходной" : "\(DayHours.time(open)) – \(DayHours.time(close))"
    }

    public static func time(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }
}

extension Venue {
    public static let weekdayShort = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
    public static let weekdayLong = ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"]
    public static func defaultWeek() -> [DayHours] { (0..<7).map { _ in DayHours() } }

    /// 0 = Понедельник … 6 = Воскресенье — В ПОЯСЕ ГОРОДА.
    ///
    /// Считать по `Calendar.current` нельзя: у гостя из другого пояса возле
    /// полуночи это давало соседний день недели, и заведение показывалось с
    /// чужим расписанием (а по субботам — вообще «выходной»).
    public static func todayIndex(at now: Date, citySlug: String = City.bishkek.id) -> Int {
        (City.calendar(forSlug: citySlug).component(.weekday, from: now) + 5) % 7
    }
    public static var todayIndex: Int { todayIndex(at: Date()) }

    /// Часы конкретного дня (с фолбэком на legacy openHour/closeHour).
    public func hours(for index: Int) -> DayHours {
        if weekHours.count == 7 { return weekHours[index] }
        return DayHours(closed: false, open: openHour * 60, close: closeHour * 60)
    }
    public func todayHours(at now: Date) -> DayHours {
        hours(for: Venue.todayIndex(at: now, citySlug: citySlug))
    }
    public var todayHours: DayHours { todayHours(at: Date()) }

    /// Пояс заведения — из его города.
    public var timeZone: TimeZone { City.timeZone(forSlug: citySlug) }
}

// MARK: - Статус модерации заведения

public enum ModerationStatus: String, Codable, Sendable {
    case pending, approved, rejected

    public var title: String {
        switch self {
        case .pending: return "На модерации"
        case .approved: return "Одобрено"
        case .rejected: return "Отклонено"
        }
    }
}

// MARK: - Заведение

public struct Venue: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let category: VenueCategory
    public let district: String
    public let address: String
    public let phone: String
    public let emoji: String
    /// Градиент по умолчанию (RGB): им заводятся заведения, созданные хостом.
    /// Числа, а не `Color`, — цвет собирает UI (`SAN/Theme/ModelColors.swift`).
    public static let defaultGradient: [UInt32] = [0xFF5A1F, 0xFF9500]

    /// Градиент карточки как RGB-числа (0xRRGGBB) — домен не знает про `Color`.
    /// В `Color` превращает `Venue.gradientColors` в UI-слое.
    public let gradient: [UInt32]
    public let imageURL: String?

    // --- Поля по спецификации (с дефолтами, чтобы не ломать существующие инициализаторы) ---
    public var rating: Double = 0          // агрегированный рейтинг 0…5
    public var reviewCount: Int = 0
    public var isVerified: Bool = false
    public var savedByCount: Int = 0
    public var citySlug: String = City.bishkek.id
    public var latitude: Double = City.bishkek.latitude
    public var longitude: Double = City.bishkek.longitude
    public var todaySpecialText: String? = nil
    public var openHour: Int = 9           // legacy-фолбэк (одинаково по дням)
    public var closeHour: Int = 22
    public var weekHours: [DayHours] = []  // часы по дням недели (Пн…Вс); пусто = legacy
    public var pdfMenuURL: String? = nil
    public var photoEmojis: [String] = []  // галерея (для MVP — эмодзи-плейсхолдеры)
    public var ownerID: String = ""        // uid хоста-владельца ("" = площадка/seed)
    public var items: [VenueItem] = []     // блюда/услуги для отзывов
    public var statusRaw: String = ModerationStatus.approved.rawValue  // модерация
    public var isPaused: Bool = false      // на паузе — скрыто из пользовательской ленты
    public var whatsapp: String = ""       // номер для WhatsApp
    public var instagram: String = ""      // ник или ссылка Instagram
    public var telegram: String = ""       // ник или ссылка Telegram
    public var branches: [Branch] = []     // дополнительные адреса (филиалы)
    public var boostedUntil: Date? = nil   // платный буст в ленте до этой даты
    // --- Карта лояльности (настраивается заведением) ---
    public var loyaltyEnabled: Bool = false          // включена ли карта лояльности
    public var loyaltyGoal: Int = 6                   // штампов до награды
    public var loyaltyReward: String = "Награда за лояльность"  // что получает гость
    public var couponsEnabled: Bool = true            // принимает ли заведение купоны (по умолчанию да)
    // --- Бонусы САН (баллы заведения, System 1) ---
    public var pointsEnabled: Bool = false            // включены ли баллы САН
    public var pointsMode: String = "flat"            // "flat" | "bands" | "cashback"
    public var pointsFlat: Int = 0                    // баллов за визит (mode=flat)
    public var pointsBands: [PointsBand] = []         // диапазоны чек→баллы (mode=bands)
    public var cashbackPercent: Double = 0            // % кэшбэка (mode=cashback), ≤20
    public var pointsRewards: [PointsReward] = []     // каталог наград за баллы
    public var pointsExpiryMonths: Int = 6            // сгорание по неактивности
    public var redeemMode: String = "staffScan"       // "staffScan" | "customerInitiated"
    public var earnCooldownMinutes: Int = 60          // кулдаун начисления, мин.

    public init(id: String, name: String, category: VenueCategory, district: String,
                address: String, phone: String, emoji: String, gradient: [UInt32],
                imageURL: String? = nil,
                rating: Double = 0, reviewCount: Int = 0, isVerified: Bool = false,
                savedByCount: Int = 0,
                citySlug: String = City.bishkek.id,
                latitude: Double = City.bishkek.latitude,
                longitude: Double = City.bishkek.longitude,
                todaySpecialText: String? = nil, openHour: Int = 9, closeHour: Int = 22,
                weekHours: [DayHours] = [], pdfMenuURL: String? = nil,
                photoEmojis: [String] = [], ownerID: String = "", items: [VenueItem] = [],
                statusRaw: String = ModerationStatus.approved.rawValue,
                isPaused: Bool = false, whatsapp: String = "", instagram: String = "",
                telegram: String = "", branches: [Branch] = [], boostedUntil: Date? = nil,
                loyaltyEnabled: Bool = false, loyaltyGoal: Int = 6,
                loyaltyReward: String = "Награда за лояльность", couponsEnabled: Bool = true,
                pointsEnabled: Bool = false, pointsMode: String = "flat", pointsFlat: Int = 0,
                pointsBands: [PointsBand] = [], cashbackPercent: Double = 0,
                pointsRewards: [PointsReward] = [], pointsExpiryMonths: Int = 6,
                redeemMode: String = "staffScan", earnCooldownMinutes: Int = 60) {
        self.id = id; self.name = name; self.category = category; self.district = district
        self.address = address; self.phone = phone; self.emoji = emoji
        self.gradient = gradient; self.imageURL = imageURL
        self.rating = rating; self.reviewCount = reviewCount; self.isVerified = isVerified
        self.savedByCount = savedByCount; self.citySlug = citySlug
        self.latitude = latitude; self.longitude = longitude
        self.todaySpecialText = todaySpecialText
        self.openHour = openHour; self.closeHour = closeHour; self.weekHours = weekHours
        self.pdfMenuURL = pdfMenuURL; self.photoEmojis = photoEmojis
        self.ownerID = ownerID; self.items = items; self.statusRaw = statusRaw
        self.isPaused = isPaused; self.whatsapp = whatsapp; self.instagram = instagram
        self.telegram = telegram; self.branches = branches; self.boostedUntil = boostedUntil
        self.loyaltyEnabled = loyaltyEnabled; self.loyaltyGoal = loyaltyGoal
        self.loyaltyReward = loyaltyReward; self.couponsEnabled = couponsEnabled
        self.pointsEnabled = pointsEnabled; self.pointsMode = pointsMode
        self.pointsFlat = pointsFlat; self.pointsBands = pointsBands
        self.cashbackPercent = cashbackPercent; self.pointsRewards = pointsRewards
        self.pointsExpiryMonths = pointsExpiryMonths; self.redeemMode = redeemMode
        self.earnCooldownMinutes = earnCooldownMinutes
    }

    /// Активен ли платный буст в момент `now`.
    public func isBoosted(at now: Date) -> Bool { boostedUntil.map { $0 > now } ?? false }
    /// Системное «сейчас». Ниже слоя UI используйте `isBoosted(at:)` — иначе
    /// логика не воспроизводится в тесте (см. `Clock`).
    public var isBoosted: Bool { isBoosted(at: Date()) }

    /// Ссылка WhatsApp (wa.me) или nil.
    public var whatsappURL: URL? {
        let digits = whatsapp.filter(\.isNumber)
        return digits.isEmpty ? nil : URL(string: "https://wa.me/\(digits)")
    }
    /// Ссылка Instagram или nil.
    public var instagramURL: URL? {
        guard !instagram.isEmpty else { return nil }
        if instagram.hasPrefix("http") { return URL(string: instagram) }
        return URL(string: "https://instagram.com/\(instagram.replacingOccurrences(of: "@", with: ""))")
    }
    /// Ссылка Telegram или nil.
    public var telegramURL: URL? {
        guard !telegram.isEmpty else { return nil }
        if telegram.hasPrefix("http") { return URL(string: telegram) }
        return URL(string: "https://t.me/\(telegram.replacingOccurrences(of: "@", with: ""))")
    }

    public var moderation: ModerationStatus { ModerationStatus(rawValue: statusRaw) ?? .approved }
    public var isApproved: Bool { moderation == .approved }

    /// Открыто ли заведение в момент `now` (по часам текущего дня недели).
    ///
    /// Всё считается в поясе ГОРОДА заведения: часы работы записаны по местному
    /// времени, а `now` — абсолютный момент. Телефон в другом поясе больше не
    /// сдвигает открытие/закрытие на разницу часов.
    public func isOpen(at now: Date) -> Bool {
        let d = todayHours(at: now)
        guard !d.closed else { return false }
        let cal = City.calendar(forSlug: citySlug)
        let cur = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        if d.close > d.open { return cur >= d.open && cur < d.close }
        return cur >= d.open || cur < d.close   // через полночь
    }
    public var isOpenNow: Bool { isOpen(at: Date()) }

    /// «Открыто · до 22:00» / «Сегодня закрыто» / «Закрыто».
    public var hoursStatusText: String {
        let d = todayHours(at: Date())
        if d.closed { return "Сегодня выходной" }
        return isOpenNow ? "Открыто · до \(DayHours.time(d.close))" : "Закрыто"
    }

    public var hasTodaySpecial: Bool {
        (todaySpecialText?.trimmingCharacters(in: .whitespaces).isEmpty == false)
    }
}

// MARK: - Предложение

public struct Deal: Identifiable, Hashable {
    public let id: String
    public let venueID: String
    public let type: DealType
    public let title: String
    public let details: String
    public let emoji: String
    public let oldPrice: Int?
    public let newPrice: Int?
    public let discountPercent: Int?
    public let validUntil: Date

    // --- Поля по спецификации ---
    /// Ключ партиционирования по городам. Пока константа «bishkek» — заведён
    /// заранее: доставить его в живой каталог задним числом дороже, чем нести
    /// неиспользуемое поле. Совпадает с `Venue.citySlug`.
    public var citySlug: String = City.bishkek.id
    public var status: DealStatus = .active
    public var startDate: Date? = nil
    public var imageEmojis: [String] = []   // до 5 изображений (плейсхолдеры)
    public var imageURL: String? = nil      // главное фото предложения
    public var imageURLs: [String] = []     // галерея фото (карусель)
    /// Условия акции — по строке на пункт («Каждый день до 12:00»).
    ///
    /// Отдельно от `details`: описание продаёт, условия ограничивают. Сложенные
    /// в один текст, ограничения либо теряются в абзаце, либо превращают его в
    /// юридическую сноску. Пусто — блока условий в ленте просто нет.
    public var terms: [String] = []

    public init(id: String, venueID: String, type: DealType, title: String, details: String,
                emoji: String, oldPrice: Int? = nil, newPrice: Int? = nil,
                discountPercent: Int? = nil, validUntil: Date,
                citySlug: String = City.bishkek.id,
                status: DealStatus = .active, startDate: Date? = nil,
                imageEmojis: [String] = [], imageURL: String? = nil, imageURLs: [String] = [],
                terms: [String] = []) {
        self.id = id; self.venueID = venueID; self.type = type; self.title = title
        self.details = details; self.emoji = emoji; self.oldPrice = oldPrice
        self.newPrice = newPrice; self.discountPercent = discountPercent
        self.validUntil = validUntil; self.citySlug = citySlug
        self.status = status; self.startDate = startDate
        self.imageEmojis = imageEmojis; self.imageURL = imageURL; self.imageURLs = imageURLs
        self.terms = terms
    }

    /// Все фото предложения (для карусели): imageURLs, иначе одно imageURL.
    public var allImages: [String] {
        let extra = imageURLs.filter { !$0.isEmpty }
        if !extra.isEmpty { return extra }
        if let u = imageURL, !u.isEmpty { return [u] }
        return []
    }

    /// Протухшие/на паузе/черновики не показываются в пользовательской ленте.
    public func isActive(at now: Date) -> Bool { status == .active && validUntil >= now }
    /// Системное «сейчас». Ниже слоя UI используйте `isActive(at:)`.
    public var isActive: Bool { isActive(at: Date()) }

    /// Можно ли предъявить купон сотруднику. Новинки и объявления — это просто
    /// новости/информация, купона у них нет.
    public var isRedeemable: Bool { type == .discount || type == .promo }

    /// Часов до конца действия.
    public var hoursLeft: Int { max(0, Int(validUntil.timeIntervalSinceNow / 3600)) }

    /// Бейдж срочности для активных предложений (или nil).
    public var urgencyText: String? {
        guard isActive else { return nil }
        // «Сегодня» — день ГОРОДА, а не телефона: акция заканчивается по
        // местному времени заведения.
        if City.calendar(forSlug: citySlug).isDateInToday(validUntil) {
            return "Заканчивается сегодня"
        }
        let h = hoursLeft
        if h > 0 && h <= 48 { return "Осталось \(h) ч" }
        return nil
    }

    /// Добавлено в последние 48ч до `now` — буст в ранжировании.
    public func isFresh(at now: Date) -> Bool {
        guard let start = startDate else { return false }
        return start >= now.addingTimeInterval(-48 * 3600)
    }
    public var isFresh: Bool { isFresh(at: Date()) }

    /// Эффективный процент скидки для ранжирования: явный `discountPercent`, иначе
    /// выводим из старой/новой цены. nil, если ни то ни другое не задано.
    public var effectiveDiscountPercent: Int? {
        if let p = discountPercent { return p }
        guard let old = oldPrice, let new = newPrice, old > 0, new < old else { return nil }
        return Int((Double(old - new) / Double(old) * 100).rounded())
    }
}

// MARK: - Отзыв и ответ владельца

public struct HostReply: Hashable, Codable, Sendable {
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(text: String, createdAt: Date, updatedAt: Date) {
        self.text = text; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct Review: Identifiable, Hashable, Codable {
    public let id: String
    public let venueID: String
    public var authorID: String
    public var authorName: String
    public var rating: Int            // 1…5
    public var text: String
    public var photoEmojis: [String]  // до 3 (для MVP — эмодзи)
    public var createdAt: Date
    public var updatedAt: Date
    public var hostReply: HostReply?
    public var itemID: String? = nil    // объект отзыва (блюдо/услуга), если выбран
    public var itemName: String? = nil
    public var photos: [String] = []    // реальные фото (URL); photoEmojis — легаси-фолбэк
    public var verifiedVisit: Bool = false   // автор реально гасил купон в этом заведении
    /// Ключ партиционирования по городам (см. `Deal.citySlug`).
    public var citySlug: String = City.bishkek.id

    public init(id: String, venueID: String, authorID: String, authorName: String,
                rating: Int, text: String, photoEmojis: [String],
                createdAt: Date, updatedAt: Date, hostReply: HostReply? = nil,
                itemID: String? = nil, itemName: String? = nil,
                photos: [String] = [], verifiedVisit: Bool = false,
                citySlug: String = City.bishkek.id) {
        self.id = id; self.venueID = venueID; self.authorID = authorID
        self.authorName = authorName; self.rating = rating; self.text = text
        self.photoEmojis = photoEmojis; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.hostReply = hostReply; self.itemID = itemID; self.itemName = itemName
        self.photos = photos; self.verifiedVisit = verifiedVisit
        self.citySlug = citySlug
    }

    public var initial: String { String(authorName.prefix(1)).uppercased() }

    public var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: createdAt)
    }
}
