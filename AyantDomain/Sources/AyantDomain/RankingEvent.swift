import Foundation

/// Схема событий ранжирования — журнал для обучения весов выдачи (learning-to-rank).
///
/// Пишется в append-only коллекцию Firestore `rankingEvents` (правила: только
/// `create` для авторизованных, ни read/update/delete — см. firestore.rules). Каждый
/// документ — одно событие. Ключевая идея: **фичи логируются на момент ранжирования**,
/// потому что потом их не восстановить (расстояние меняется, рейтинг растёт, акция
/// протухает). Это то, из чего позже учатся веса `Ranking` вместо ручного подбора.
///
/// 1:1 зеркалит Android `data/RankingEvent.kt` — имена полей в документе совпадают,
/// иначе экспорт для обучения смешает две схемы. При изменении правь ОБЕ стороны и
/// правило `rankingEvents` в firestore.rules.
///
/// Форма документа:
/// ```
/// {
///   type: "impression" | "tap" | "redeem",
///   userID, sessionID, renderID,        // renderID связывает impression → tap/redeem
///   platform: "ios" | "android",
///   citySlug, category,                  // фильтр ленты (null = все)
///   hour, weekday,                       // локальный контекст (0…23, 0=Пн)
///   clientTs,                            // epoch ms клиента (порядок внутри сессии)
///   createdAt,                           // серверное время (авторитетное)
///   // только для impression:
///   items: [{ dealID, venueID, position, kind, score, features: {…} }],
///   // только для tap/redeem:
///   dealID, venueID, position
/// }
/// ```
public enum RankingEventType: String {
    case impression   // показан слейт ленты (кандидаты + позиции + фичи)
    case tap          // пользователь открыл предложение
    case redeem       // купон погашен (главная целевая метка)
}

/// Снимок фич предложения на момент ранжирования — вход для обучения весов.
/// Каждое поле соответствует слагаемому `Ranking.dealScore`/`feedScore`.
public struct RankingItemFeatures {
    public let dealID: String
    public let venueID: String
    public let position: Int           // ранг в слейте (0 — верх)
    public let kind: String            // "deal" | "ad"
    public let score: Double           // итоговый dealScore на момент показа

    // Сырые сигналы (то, из чего считается score):
    public let bayesRating: Double
    public let reviewCount: Int
    public let savedByCount: Int
    public let isVerified: Bool
    public let hasTodaySpecial: Bool
    public let activeDealCount: Int
    public let isFresh: Bool
    public let daysSinceStart: Double?
    public let discountPercent: Int?
    public let hoursUntilExpiry: Double?
    public let distanceKm: Double?
    public let timeRelevance: Double

    public init(dealID: String, venueID: String, position: Int, kind: String, score: Double,
                bayesRating: Double, reviewCount: Int, savedByCount: Int, isVerified: Bool,
                hasTodaySpecial: Bool, activeDealCount: Int, isFresh: Bool,
                daysSinceStart: Double?, discountPercent: Int?, hoursUntilExpiry: Double?,
                distanceKm: Double?, timeRelevance: Double) {
        self.dealID = dealID; self.venueID = venueID; self.position = position
        self.kind = kind; self.score = score; self.bayesRating = bayesRating
        self.reviewCount = reviewCount; self.savedByCount = savedByCount
        self.isVerified = isVerified; self.hasTodaySpecial = hasTodaySpecial
        self.activeDealCount = activeDealCount; self.isFresh = isFresh
        self.daysSinceStart = daysSinceStart; self.discountPercent = discountPercent
        self.hoursUntilExpiry = hoursUntilExpiry; self.distanceKm = distanceKm
        self.timeRelevance = timeRelevance
    }

    public var asDict: [String: Any] {
        var m: [String: Any] = [
            "dealID": dealID, "venueID": venueID, "position": position, "kind": kind,
            "score": score, "bayesRating": bayesRating, "reviewCount": reviewCount,
            "savedByCount": savedByCount, "isVerified": isVerified,
            "hasTodaySpecial": hasTodaySpecial, "activeDealCount": activeDealCount,
            "isFresh": isFresh, "timeRelevance": timeRelevance,
        ]
        if let d = daysSinceStart { m["daysSinceStart"] = d }
        if let d = discountPercent { m["discountPercent"] = d }
        if let h = hoursUntilExpiry { m["hoursUntilExpiry"] = h }
        if let km = distanceKm { m["distanceKm"] = km }
        return m
    }
}

/// Одно событие журнала ранжирования (конверт + полезная нагрузка по типу).
public struct RankingEvent {
    public let type: RankingEventType
    public let userID: String
    public let sessionID: String
    public let renderID: String
    public let citySlug: String
    public let category: String?
    public let hour: Int
    public let weekday: Int
    public let clientTs: Double

    // impression: весь показанный слейт; tap/redeem: одиночная позиция.
    public var items: [RankingItemFeatures] = []
    public var dealID: String? = nil
    public var venueID: String? = nil
    public var position: Int? = nil

    public init(type: RankingEventType, userID: String, sessionID: String, renderID: String,
                citySlug: String, category: String?, hour: Int, weekday: Int, clientTs: Double,
                items: [RankingItemFeatures] = [], dealID: String? = nil,
                venueID: String? = nil, position: Int? = nil) {
        self.type = type; self.userID = userID; self.sessionID = sessionID
        self.renderID = renderID; self.citySlug = citySlug; self.category = category
        self.hour = hour; self.weekday = weekday; self.clientTs = clientTs
        self.items = items; self.dealID = dealID; self.venueID = venueID; self.position = position
    }

    public var asFirestore: [String: Any] {
        var m: [String: Any] = [
            "type": type.rawValue, "userID": userID, "sessionID": sessionID,
            "renderID": renderID, "platform": "ios", "citySlug": citySlug,
            "hour": hour, "weekday": weekday, "clientTs": clientTs,
            "createdAt": Date(),
        ]
        if let c = category { m["category"] = c }
        if type == .impression {
            m["items"] = items.map(\.asDict)
        } else {
            if let d = dealID { m["dealID"] = d }
            if let v = venueID { m["venueID"] = v }
            if let p = position { m["position"] = p }
        }
        return m
    }
}
