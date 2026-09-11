import Foundation

// Модели хост-стороны (бизнес-кабинет): профиль, DTO заведений и предложений,
// рекламные кампании.
//
// Раньше они жили внутри `SAN/Host/HostStore.swift` — то есть доменные типы
// лежали в файле со стором и SwiftUI. Android держал их в домене с самого
// начала (`domain/model/HostModels.kt`); теперь обе платформы совпадают.

// MARK: - Статус верификации

public enum VerificationStatus: String, Codable, Equatable {
    case none, pending, verified, rejected

    public var title: String {
        switch self {
        case .none: return "Не запрошена"
        case .pending: return "На рассмотрении"
        case .verified: return "Подтверждено ✓"
        case .rejected: return "Отклонено"
        }
    }
}

// MARK: - Профиль хоста

public struct HostProfile: Codable, Equatable {
    public var businessName: String
    public var categoryRaw: String
    public var phone: String
    public var email: String
    public var verification: VerificationStatus = .none
    // Реквизиты / расширенная информация о бизнесе
    public var legalForm: String = ""            // ИП / ООО / Самозанятый
    public var legalName: String = ""            // ФИО ИП или название юрлица
    public var inn: String = ""                  // ИНН / ОГРНИП
    public var registrationAddress: String = ""  // юридический адрес
    public var website: String = ""
    public var about: String = ""                // описание бизнеса

    public var category: VenueCategory { VenueCategory(rawValue: categoryRaw) ?? .cafe }

    public init(businessName: String, categoryRaw: String, phone: String, email: String,
         verification: VerificationStatus = .none,
         legalForm: String = "", legalName: String = "", inn: String = "",
         registrationAddress: String = "", website: String = "", about: String = "") {
        self.businessName = businessName; self.categoryRaw = categoryRaw
        self.phone = phone; self.email = email; self.verification = verification
        self.legalForm = legalForm; self.legalName = legalName; self.inn = inn
        self.registrationAddress = registrationAddress; self.website = website; self.about = about
    }

    // Обратная совместимость: старые сохранённые профили без новых полей.
    public init(from decoder: Decoder) throws {
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

public struct HostVenueDTO: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var categoryRaw: String
    public var district: String
    public var address: String
    public var phone: String
    public var emoji: String
    public var latitude: Double
    public var longitude: Double
    public var openHour: Int
    public var closeHour: Int
    public var todaySpecial: String?
    public var isPaused: Bool
    public var isVerified: Bool
    public var status: String = ModerationStatus.pending.rawValue   // модерация
    public var items: [VenueItem] = []                              // блюда/услуги
    public var imageURL: String = ""                                // ссылка на обложку
    public var weekHours: [DayHours] = Venue.defaultWeek()          // часы по дням недели
    public var pdfMenuURL: String = ""                              // прайс-лист / каталог (PDF)
    public var whatsapp: String = ""
    public var instagram: String = ""
    public var telegram: String = ""
    public var branches: [Branch] = []                              // дополнительные адреса
    public var boostedUntil: Date? = nil                            // буст в ленте до даты
    public var loyaltyEnabled: Bool = false                         // карта лояльности вкл/выкл
    public var loyaltyGoal: Int = 6                                 // штампов до награды
    public var loyaltyReward: String = "Награда за лояльность"      // текст награды
    public var couponsEnabled: Bool = true                          // принимать купоны (по умолчанию да)
    // --- Бонусы САН (баллы); конфиг задаётся в админ-панели, читается для сканера ---
    public var pointsEnabled: Bool = false
    public var pointsMode: String = "flat"                          // "flat" | "bands" | "cashback"
    public var pointsFlat: Int = 0
    public var pointsBands: [PointsBand] = []
    public var cashbackPercent: Double = 0
    public var pointsRewards: [PointsReward] = []
    public var pointsExpiryMonths: Int = 6
    public var redeemMode: String = "staffScan"                     // "staffScan" | "customerInitiated"
    public var earnCooldownMinutes: Int = 60


    public init(id: String, name: String, categoryRaw: String, district: String,
                address: String, phone: String, emoji: String,
                latitude: Double, longitude: Double, openHour: Int, closeHour: Int,
                todaySpecial: String?, isPaused: Bool, isVerified: Bool,
                status: String = ModerationStatus.pending.rawValue,
                items: [VenueItem] = [], imageURL: String = "",
                weekHours: [DayHours] = Venue.defaultWeek(), pdfMenuURL: String = "",
                whatsapp: String = "", instagram: String = "", telegram: String = "",
                branches: [Branch] = [], boostedUntil: Date? = nil,
                loyaltyEnabled: Bool = false, loyaltyGoal: Int = 6,
                loyaltyReward: String = "Награда за лояльность", couponsEnabled: Bool = true,
                pointsEnabled: Bool = false, pointsMode: String = "flat", pointsFlat: Int = 0,
                pointsBands: [PointsBand] = [], cashbackPercent: Double = 0,
                pointsRewards: [PointsReward] = [], pointsExpiryMonths: Int = 6,
                redeemMode: String = "staffScan", earnCooldownMinutes: Int = 60) {
        self.id = id; self.name = name; self.categoryRaw = categoryRaw
        self.district = district; self.address = address; self.phone = phone; self.emoji = emoji
        self.latitude = latitude; self.longitude = longitude
        self.openHour = openHour; self.closeHour = closeHour
        self.todaySpecial = todaySpecial; self.isPaused = isPaused; self.isVerified = isVerified
        self.status = status; self.items = items; self.imageURL = imageURL
        self.weekHours = weekHours; self.pdfMenuURL = pdfMenuURL
        self.whatsapp = whatsapp; self.instagram = instagram; self.telegram = telegram
        self.branches = branches; self.boostedUntil = boostedUntil
        self.loyaltyEnabled = loyaltyEnabled; self.loyaltyGoal = loyaltyGoal
        self.loyaltyReward = loyaltyReward; self.couponsEnabled = couponsEnabled
        self.pointsEnabled = pointsEnabled; self.pointsMode = pointsMode
        self.pointsFlat = pointsFlat; self.pointsBands = pointsBands
        self.cashbackPercent = cashbackPercent; self.pointsRewards = pointsRewards
        self.pointsExpiryMonths = pointsExpiryMonths; self.redeemMode = redeemMode
        self.earnCooldownMinutes = earnCooldownMinutes
    }

    public var category: VenueCategory { VenueCategory(rawValue: categoryRaw) ?? .cafe }
    public var moderation: ModerationStatus { ModerationStatus(rawValue: status) ?? .pending }

    public var asVenue: Venue {
        Venue(
            id: id, name: name, category: category, district: district,
            address: address, phone: phone, emoji: emoji,
            gradient: Venue.defaultGradient, imageURL: imageURL.isEmpty ? nil : imageURL,
            rating: 0, reviewCount: 0, isVerified: isVerified, savedByCount: 0,
            citySlug: City.bishkek.id, latitude: latitude, longitude: longitude,
            todaySpecialText: (todaySpecial?.isEmpty == false) ? todaySpecial : nil,
            openHour: openHour, closeHour: closeHour, weekHours: weekHours,
            pdfMenuURL: pdfMenuURL.isEmpty ? nil : pdfMenuURL,
            photoEmojis: [emoji], items: items, statusRaw: status, isPaused: isPaused,
            whatsapp: whatsapp, instagram: instagram, telegram: telegram, branches: branches,
            boostedUntil: boostedUntil,
            loyaltyEnabled: loyaltyEnabled, loyaltyGoal: loyaltyGoal, loyaltyReward: loyaltyReward,
            couponsEnabled: couponsEnabled,
            pointsEnabled: pointsEnabled, pointsMode: pointsMode, pointsFlat: pointsFlat,
            pointsBands: pointsBands, cashbackPercent: cashbackPercent, pointsRewards: pointsRewards,
            pointsExpiryMonths: pointsExpiryMonths, redeemMode: redeemMode,
            earnCooldownMinutes: earnCooldownMinutes
        )
    }
}

// MARK: - DTO предложения хоста

public struct HostDealDTO: Codable, Identifiable, Equatable {
    public var id: String
    public var venueID: String
    public var typeRaw: String
    public var title: String
    public var details: String
    public var emoji: String
    public var newPrice: Int?
    public var discountPercent: Int?
    public var startDate: Date
    public var endDate: Date?
    public var statusRaw: String
    public var imageURL: String = ""
    public var imageURLs: [String] = []      // галерея фото (карусель)
    public var terms: [String] = []          // условия акции, по строке на пункт


    public init(id: String, venueID: String, typeRaw: String, title: String, details: String,
                emoji: String, newPrice: Int? = nil, discountPercent: Int? = nil,
                startDate: Date, endDate: Date? = nil, statusRaw: String,
                imageURL: String = "", imageURLs: [String] = [], terms: [String] = []) {
        self.id = id; self.venueID = venueID; self.typeRaw = typeRaw
        self.title = title; self.details = details; self.emoji = emoji
        self.newPrice = newPrice; self.discountPercent = discountPercent
        self.startDate = startDate; self.endDate = endDate; self.statusRaw = statusRaw
        self.imageURL = imageURL; self.imageURLs = imageURLs; self.terms = terms
    }

    public var type: DealType { DealType(rawValue: typeRaw) ?? .discount }
    public var status: DealStatus { DealStatus(rawValue: statusRaw) ?? .active }

    public var asDeal: Deal {
        Deal(
            id: id, venueID: venueID, type: type, title: title, details: details,
            emoji: emoji, oldPrice: nil, newPrice: newPrice,
            discountPercent: discountPercent,
            validUntil: endDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now)!,
            status: status, startDate: startDate, imageEmojis: [emoji],
            imageURL: imageURL.isEmpty ? nil : imageURL,
            imageURLs: imageURLs,
            terms: terms
        )
    }
}

// MARK: - Рекламная кампания (Promote, mock)

public struct AdCampaign: Codable, Identifiable, Equatable {
    public enum Kind: String, Codable { case boost, push
        public var title: String { self == .boost ? "Буст заведения" : "Push-уведомление" }
    }
    public enum Status: String, Codable { case scheduled, active, sent, completed, cancelled
        public var title: String {
            switch self {
            case .scheduled: return "Запланирована"
            case .active: return "Активна"
            case .sent: return "Отправлено"
            case .completed: return "Завершена"
            case .cancelled: return "Отменена"
            }
        }
        /// Зелёным подсвечиваем «живые» статусы.
        public var isLive: Bool { self == .active || self == .sent }
    }
    public var id: String
    public var kind: Kind
    public var venueID: String
    public var status: Status
    public var startAt: Date
    public var endAt: Date
    public var impressions: Int
    public var taps: Int
    public var spend: Int


    public init(id: String, kind: Kind, venueID: String, status: Status,
                startAt: Date, endAt: Date, impressions: Int = 0, taps: Int = 0, spend: Int = 0) {
        self.id = id; self.kind = kind; self.venueID = venueID; self.status = status
        self.startAt = startAt; self.endAt = endAt
        self.impressions = impressions; self.taps = taps; self.spend = spend
    }

    /// Какая доля кампании прошла — от 0 до 1. Считается из её собственных дат,
    /// поэтому полоса расхода в UI не выдумывает данные.
    /// Ниже UI используйте `elapsedFraction(at:)`;нуль-аргументная — удобство вьюх.
    public func elapsedFraction(at now: Date) -> Double {
        let total = endAt.timeIntervalSince(startAt)
        guard total > 0 else { return status == .cancelled ? 0 : 1 }
        return min(1, max(0, now.timeIntervalSince(startAt) / total))
    }
    public var elapsedFraction: Double { elapsedFraction(at: Date()) }

    /// Фактический статус с учётом времени: истёкший буст → «Завершена».
    /// Push — разовая отправка, остаётся «Отправлено».
    public var effectiveStatus: Status {
        if status == .cancelled { return .cancelled }
        if kind == .push { return status }
        return endAt < Date() ? .completed : status
    }
}

