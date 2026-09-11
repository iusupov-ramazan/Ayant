import Foundation

/*
 * Словарь диплинков: адреса для шаринга и ключи отложенных переходов.
 *
 * Чистая часть маршрутизации — её зовут и сторы (реферальная ссылка, подарок),
 * и UI. Сам `DeepLinkRouter` остался в приложении: он `ObservableObject` и
 * заодно точка входа FCM, то есть уже не домен.
 *
 * Ключи load-bearing: их читают уже установленные приложения.
 */
public enum DeepLinks {
    public static let domain = "ayant.kg"

    // Universal Links — открываются в приложении, если оно установлено.
    public static func venueURL(_ id: String) -> URL { URL(string: "https://\(domain)/venue/\(id)")! }
    public static func dealURL(_ id: String) -> URL { URL(string: "https://\(domain)/deal/\(id)")! }
    public static func referralURL(_ code: String) -> URL { URL(string: "https://\(domain)/ref/\(code)")! }
    public static func giftURL(_ code: String) -> URL { URL(string: "https://\(domain)/gift/\(code)")! }

    /// Кто пригласил — привязка и бонус происходят уже после входа.
    public static let pendingReferrerKey = "san.referrer.pending"
    /// Код подарка из ссылки — купон забирается после входа.
    public static let pendingGiftKey = "san.gift.pending"
}
