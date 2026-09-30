import Foundation

/*
 * Модели бонусной части: награда каталога, купон и карта лояльности.
 *
 * Раньше лежали рядом со своими экранами (`CouponStore.swift`,
 * `LoyaltyStore.swift`) и тянули за собой SwiftUI. Здесь они — обычные
 * значения, поэтому их видят и слой данных, и слой фич, и тесты.
 *
 * Зеркалит `android/domain/.../domain/model/BonusModels.kt`.
 */

/// Награда из каталога (что можно купить за бонусы).
public struct Reward: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let cost: Int
    public let emoji: String
    /// Заведение-партнёр, которое гасит награду.
    ///
    /// Без него награда бесполезна: `scanCoupon` сверяет `coupon.venueID` с
    /// заведением сканера и отвечает `wrong_venue`, то есть сотрудник не сможет
    /// погасить купон. Поэтому награды без партнёра не показываются
    /// (см. `isRedeemable`), а не выдают купон в никуда.
    public let venueID: String
    public let venueName: String

    public init(id: String, title: String, cost: Int, emoji: String,
                venueID: String = "", venueName: String = "") {
        self.id = id
        self.title = title
        self.cost = cost
        self.emoji = emoji
        self.venueID = venueID
        self.venueName = venueName
    }

    /// Награду можно предъявить в заведении. Без партнёра — нельзя.
    public var isRedeemable: Bool { !venueID.isEmpty }

}

/// Купон, полученный пользователем за бонусы (показывается сотруднику).
public struct Coupon: Identifiable, Codable, Hashable {
    public var id: String
    public var title: String
    public var code: String
    public var createdAt: Date
    public var used: Bool = false
    // --- Привязка к заведению (для бэкенд-трекинга и сканера) ---
    public var venueID: String = ""        // "" = общий бонус-купон (не сканируется у заведения)
    public var venueName: String = ""
    public var kind: String = "bonus"      // bonus | loyalty | deal | gift
    public var dealID: String = ""

    /// Сканируется ли купон у заведения (даёт штамп): только привязанные к venue.
    public var isVenueBound: Bool { !venueID.isEmpty }

    public init(
        id: String, title: String, code: String, createdAt: Date, used: Bool = false,
        venueID: String = "", venueName: String = "", kind: String = "bonus", dealID: String = ""
    ) {
        self.id = id
        self.title = title
        self.code = code
        self.createdAt = createdAt
        self.used = used
        self.venueID = venueID
        self.venueName = venueName
        self.kind = kind
        self.dealID = dealID
    }
}

// MARK: - Модель карты лояльности

/// «Сотрудник поставил штамп»: рост уже известной карты в живом потоке.
/// Показывается экраном «Начислено» и снимается только рукой гостя.
public struct LoyaltyStampEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let venueID: String
    public let venueName: String
    /// Штампов на карте после скана (0 — круг только что собран).
    public let stamps: Int
    public let goal: Int
    public let rewardIssued: Bool
    public let reward: String
    /// Имя карты штампов (пусто у безымянной первой).
    public let cardTitle: String

    public init(id: String, venueID: String, venueName: String, stamps: Int, goal: Int,
                rewardIssued: Bool, reward: String, cardTitle: String = "") {
        self.cardTitle = cardTitle
        self.id = id; self.venueID = venueID; self.venueName = venueName
        self.stamps = stamps; self.goal = goal; self.rewardIssued = rewardIssued; self.reward = reward
    }
}

/// Карта штампов гостя в одном заведении.
///
/// У заведения может быть несколько карт (`StampCards`), поэтому `id` — это
/// заведение плюс карта. У первой карты `id` по-прежнему равен `venueID`:
/// так его знают кэш на устройстве и экраны, писавшиеся до нескольких карт.
public struct LoyaltyCard: Identifiable, Codable, Hashable {
    public var id: String { Self.id(venueID: venueID, cardID: cardID) }
    public var venueID: String
    public var venueName: String
    public var stamps: Int = 0            // штампы в текущем круге
    public var completedRounds: Int = 0   // сколько наград уже получено
    public var goal: Int = 6              // штампов до награды (задаёт заведение)
    public var reward: String = "Награда за лояльность"  // что получает гость
    public var cardID: String = StampCard.defaultID
    /// Имя карты («Кофе»); пусто — у безымянной первой.
    public var title: String = ""

    public static func id(venueID: String, cardID: String) -> String {
        cardID.isEmpty || cardID == StampCard.defaultID ? venueID : "\(venueID)#\(cardID)"
    }

    public init(
        venueID: String, venueName: String, stamps: Int = 0, completedRounds: Int = 0,
        goal: Int = 6, reward: String = "Награда за лояльность",
        cardID: String = StampCard.defaultID, title: String = ""
    ) {
        self.venueID = venueID
        self.venueName = venueName
        self.stamps = stamps
        self.completedRounds = completedRounds
        self.goal = goal
        self.reward = reward
        self.cardID = cardID.isEmpty ? StampCard.defaultID : cardID
        self.title = title
    }

    /// Кэш прежних версий не знает `cardID`/`title` — это первая карта.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        venueID = try c.decode(String.self, forKey: .venueID)
        venueName = try c.decodeIfPresent(String.self, forKey: .venueName) ?? ""
        stamps = try c.decodeIfPresent(Int.self, forKey: .stamps) ?? 0
        completedRounds = try c.decodeIfPresent(Int.self, forKey: .completedRounds) ?? 0
        goal = try c.decodeIfPresent(Int.self, forKey: .goal) ?? 6
        reward = try c.decodeIfPresent(String.self, forKey: .reward) ?? "Награда за лояльность"
        cardID = try c.decodeIfPresent(String.self, forKey: .cardID) ?? StampCard.defaultID
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
    }
}


/// Встроенный список наград глобального кошелька.
///
/// Это ШАБЛОН, а не то, что видит пользователь: у наград здесь нет партнёра,
/// поэтому показывать их нельзя (см. `Reward.isRedeemable`). Реальный каталог
/// приходит из `config/globalRewards`, где у каждой награды проставлено
/// заведение; админ-панель заполняет его этими же заготовками.
public enum CouponCatalog {
    public static let builtIn: [Reward] = [
        Reward(id: "disc10", title: "−10% к любой акции", cost: 100, emoji: "🏷️"),
        Reward(id: "coffee", title: "Бесплатный кофе у партнёра", cost: 300, emoji: "☕️"),
        Reward(id: "dessert", title: "Десерт в подарок", cost: 400, emoji: "🍰"),
        Reward(id: "vip", title: "VIP-доступ к новинкам", cost: 500, emoji: "⭐️"),
    ]
}
