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

    public init(id: String, title: String, cost: Int, emoji: String) {
        self.id = id
        self.title = title
        self.cost = cost
        self.emoji = emoji
    }
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

    public init(id: String, venueID: String, venueName: String, stamps: Int, goal: Int,
                rewardIssued: Bool, reward: String) {
        self.id = id; self.venueID = venueID; self.venueName = venueName
        self.stamps = stamps; self.goal = goal; self.rewardIssued = rewardIssued; self.reward = reward
    }
}

public struct LoyaltyCard: Identifiable, Codable, Hashable {
    public var id: String { venueID }
    public var venueID: String
    public var venueName: String
    public var stamps: Int = 0            // штампы в текущем круге
    public var completedRounds: Int = 0   // сколько наград уже получено
    public var goal: Int = 6              // штампов до награды (задаёт заведение)
    public var reward: String = "Награда за лояльность"  // что получает гость

    public init(
        venueID: String, venueName: String, stamps: Int = 0, completedRounds: Int = 0,
        goal: Int = 6, reward: String = "Награда за лояльность"
    ) {
        self.venueID = venueID
        self.venueName = venueName
        self.stamps = stamps
        self.completedRounds = completedRounds
        self.goal = goal
        self.reward = reward
    }
}
