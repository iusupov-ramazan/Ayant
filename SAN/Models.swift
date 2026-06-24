import SwiftUI

// MARK: - Типы предложений (С-А-Н)

enum DealType: String, CaseIterable, Identifiable {
    case discount = "Скидка"
    case promo = "Акция"
    case novelty = "Новинка"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .discount: return .sanAccent
        case .promo: return .purple
        case .novelty: return .teal
        }
    }

    var icon: String {
        switch self {
        case .discount: return "percent"
        case .promo: return "gift.fill"
        case .novelty: return "sparkles"
        }
    }
}

// MARK: - Статус предложения (по спецификации)

enum DealStatus: String, CaseIterable, Identifiable, Codable {
    case active, paused, expired, draft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "Активно"
        case .paused: return "На паузе"
        case .expired: return "Завершено"
        case .draft: return "Черновик"
        }
    }

    var color: Color {
        switch self {
        case .active: return .green
        case .paused: return .orange
        case .expired: return .gray
        case .draft: return .blue
        }
    }
}

// MARK: - Категории заведений

enum VenueCategory: String, CaseIterable, Identifiable {
    case cafe = "Кафе"
    case coffee = "Кофейня"
    case fastfood = "Фастфуд"
    case restaurant = "Ресторан"
    case teahouse = "Чайхана"
    case bakery = "Пекарня"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cafe: return "fork.knife"
        case .coffee: return "cup.and.saucer.fill"
        case .fastfood: return "takeoutbag.and.cup.and.straw.fill"
        case .restaurant: return "wineglass.fill"
        case .teahouse: return "mug.fill"
        case .bakery: return "birthday.cake.fill"
        }
    }
}

// MARK: - Город (масштабирование на города Центральной Азии)

struct City: Identifiable, Hashable {
    let id: String        // slug, напр. "bishkek"
    let name: String      // отображаемое имя
    let country: String
    let latitude: Double   // центр города — старт карты и фолбэк координат
    let longitude: Double

    static let bishkek = City(id: "bishkek", name: "Бишкек", country: "Кыргызстан",
                              latitude: 42.8746, longitude: 74.5698)
}

// MARK: - Объект для отзыва (блюдо / услуга внутри заведения)

struct VenueItem: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var emoji: String
    var kind: String   // "food" | "service" | "other"
    var imageURL: String = ""   // фото объекта (фолбэк — эмодзи)

    var kindTitle: String {
        switch kind {
        case "service": return "Услуга"
        case "other": return "Объект"
        default: return "Блюдо"
        }
    }
}

// MARK: - Филиал (дополнительный адрес заведения)

struct Branch: Identifiable, Hashable, Codable {
    var id: String
    var address: String
    var latitude: Double
    var longitude: Double
    var phone: String = ""
}

// MARK: - Часы работы по дням недели

/// Часы работы одного дня. Время — минуты от полуночи (напр. 9:30 = 570).
struct DayHours: Codable, Hashable {
    var closed: Bool = false
    var open: Int = 9 * 60
    var close: Int = 22 * 60

    var label: String {
        closed ? "Выходной" : "\(DayHours.time(open)) – \(DayHours.time(close))"
    }

    static func time(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }
}

extension Venue {
    static let weekdayShort = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
    static let weekdayLong = ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"]
    static func defaultWeek() -> [DayHours] { (0..<7).map { _ in DayHours() } }

    /// 0 = Понедельник … 6 = Воскресенье.
    static var todayIndex: Int { (Calendar.current.component(.weekday, from: .now) + 5) % 7 }

    /// Часы конкретного дня (с фолбэком на legacy openHour/closeHour).
    func hours(for index: Int) -> DayHours {
        if weekHours.count == 7 { return weekHours[index] }
        return DayHours(closed: false, open: openHour * 60, close: closeHour * 60)
    }
    var todayHours: DayHours { hours(for: Venue.todayIndex) }
}

// MARK: - Статус модерации заведения

enum ModerationStatus: String, Codable {
    case pending, approved, rejected

    var title: String {
        switch self {
        case .pending: return "На модерации"
        case .approved: return "Одобрено"
        case .rejected: return "Отклонено"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .red
        }
    }
}

// MARK: - Заведение

struct Venue: Identifiable, Hashable {
    let id: String
    let name: String
    let category: VenueCategory
    let district: String
    let address: String
    let phone: String
    let emoji: String
    let gradient: [Color]
    let imageURL: String?

    // --- Поля по спецификации (с дефолтами, чтобы не ломать существующие инициализаторы) ---
    var rating: Double = 0          // агрегированный рейтинг 0…5
    var reviewCount: Int = 0
    var isVerified: Bool = false
    var savedByCount: Int = 0
    var citySlug: String = City.bishkek.id
    var latitude: Double = City.bishkek.latitude
    var longitude: Double = City.bishkek.longitude
    var todaySpecialText: String? = nil
    var openHour: Int = 9           // legacy-фолбэк (одинаково по дням)
    var closeHour: Int = 22
    var weekHours: [DayHours] = []  // часы по дням недели (Пн…Вс); пусто = legacy
    var pdfMenuURL: String? = nil
    var photoEmojis: [String] = []  // галерея (для MVP — эмодзи-плейсхолдеры)
    var ownerID: String = ""        // uid хоста-владельца ("" = площадка/seed)
    var items: [VenueItem] = []     // блюда/услуги для отзывов
    var statusRaw: String = ModerationStatus.approved.rawValue  // модерация
    var isPaused: Bool = false      // на паузе — скрыто из пользовательской ленты
    var whatsapp: String = ""       // номер для WhatsApp
    var instagram: String = ""      // ник или ссылка Instagram
    var telegram: String = ""       // ник или ссылка Telegram
    var branches: [Branch] = []     // дополнительные адреса (филиалы)

    /// Ссылка WhatsApp (wa.me) или nil.
    var whatsappURL: URL? {
        let digits = whatsapp.filter(\.isNumber)
        return digits.isEmpty ? nil : URL(string: "https://wa.me/\(digits)")
    }
    /// Ссылка Instagram или nil.
    var instagramURL: URL? {
        guard !instagram.isEmpty else { return nil }
        if instagram.hasPrefix("http") { return URL(string: instagram) }
        return URL(string: "https://instagram.com/\(instagram.replacingOccurrences(of: "@", with: ""))")
    }
    /// Ссылка Telegram или nil.
    var telegramURL: URL? {
        guard !telegram.isEmpty else { return nil }
        if telegram.hasPrefix("http") { return URL(string: telegram) }
        return URL(string: "https://t.me/\(telegram.replacingOccurrences(of: "@", with: ""))")
    }

    var moderation: ModerationStatus { ModerationStatus(rawValue: statusRaw) ?? .approved }
    var isApproved: Bool { moderation == .approved }

    /// Открыто ли заведение прямо сейчас (по часам текущего дня недели).
    var isOpenNow: Bool {
        let d = todayHours
        guard !d.closed else { return false }
        let now = Calendar.current
        let cur = now.component(.hour, from: .now) * 60 + now.component(.minute, from: .now)
        if d.close > d.open { return cur >= d.open && cur < d.close }
        return cur >= d.open || cur < d.close   // через полночь
    }

    /// «Открыто · до 22:00» / «Сегодня закрыто» / «Закрыто».
    var hoursStatusText: String {
        let d = todayHours
        if d.closed { return "Сегодня выходной" }
        return isOpenNow ? "Открыто · до \(DayHours.time(d.close))" : "Закрыто"
    }

    var hasTodaySpecial: Bool {
        (todaySpecialText?.trimmingCharacters(in: .whitespaces).isEmpty == false)
    }
}

// MARK: - Предложение

struct Deal: Identifiable, Hashable {
    let id: String
    let venueID: String
    let type: DealType
    let title: String
    let details: String
    let emoji: String
    let oldPrice: Int?
    let newPrice: Int?
    let discountPercent: Int?
    let validUntil: Date

    // --- Поля по спецификации ---
    var status: DealStatus = .active
    var startDate: Date? = nil
    var imageEmojis: [String] = []   // до 5 изображений (плейсхолдеры)
    var imageURL: String? = nil      // ссылка на фото предложения

    /// Протухшие/на паузе/черновики не показываются в пользовательской ленте.
    var isActive: Bool { status == .active && validUntil >= .now }

    /// Добавлено в последние 48ч — буст в ранжировании.
    var isFresh: Bool {
        guard let start = startDate else { return false }
        return start >= Calendar.current.date(byAdding: .hour, value: -48, to: .now)!
    }
}

// MARK: - Отзыв и ответ владельца

struct HostReply: Hashable, Codable {
    var text: String
    var createdAt: Date
    var updatedAt: Date
}

struct Review: Identifiable, Hashable, Codable {
    let id: String
    let venueID: String
    var authorID: String
    var authorName: String
    var rating: Int            // 1…5
    var text: String
    var photoEmojis: [String]  // до 3 (для MVP — эмодзи)
    var createdAt: Date
    var updatedAt: Date
    var hostReply: HostReply?
    var itemID: String? = nil    // объект отзыва (блюдо/услуга), если выбран
    var itemName: String? = nil
    var photos: [String] = []    // реальные фото (URL); photoEmojis — легаси-фолбэк

    var initial: String { String(authorName.prefix(1)).uppercased() }

    var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM yyyy"
        return f.string(from: createdAt)
    }
}

// MARK: - Хелперы

extension Color {
    static let sanAccent = Color(red: 1.0, green: 0.30, blue: 0.16)

    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Date {
    /// «15 июня»
    var sanShort: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        return f.string(from: self)
    }
}

extension Int {
    var som: String { "\(self) сом" }
}
