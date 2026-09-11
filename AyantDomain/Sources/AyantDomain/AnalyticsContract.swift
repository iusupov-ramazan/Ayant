import Foundation

/// Продуктовая аналитика (DAU, удержание, воронки).
///
/// Таксономия событий и точка вызова живут здесь и НЕ знают про Firebase:
/// отправкой занимается реализация `ProductAnalytics` из слоя данных
/// (`SAN/Firebase/FirebaseProductAnalytics.swift`). Так экраны и сторы,
/// логирующие события, не тянут за собой SDK.
public enum AnalyticsEvent: String {
    case appOpen        = "app_open"
    case dealView       = "deal_view"
    case venueView      = "venue_view"
    case search         = "search"
    case dealRedeem     = "deal_redeem"      // ключевая метрика: купон погашен
    case saveDeal       = "save_deal"
    case reviewPosted   = "review_posted"
    case referralInvite = "referral_invite"  // пользователь поделился ссылкой
    case referralJoin   = "referral_join"    // пришёл по чужой ссылке
    case couponClaim    = "coupon_claim"     // обменял бонусы на купон
    case loyaltyStamp   = "loyalty_stamp"    // штамп в карте лояльности
}

/// Куда уходят продуктовые события. Зеркалит `ProductAnalytics` на Android.
public protocol ProductAnalytics {
    func log(_ event: AnalyticsEvent, _ params: [String: Any])
}


/// Оффлайн-заглушка по умолчанию: пока приложение не подставило реальную
/// реализацию, события просто некуда отправлять.
public struct NoopProductAnalytics: ProductAnalytics {
    public init() {}
    public func log(_ event: AnalyticsEvent, _ params: [String: Any]) {}
}

/// Статический фасад — его зовут десятки экранов и сторов, менять их подпись
/// незачем. Реальную реализацию подставляет композиционный корень приложения
/// (`AyantStores.installAnalytics()`), тест — свою.
public enum AnalyticsLog {
    public nonisolated(unsafe) static var backend: ProductAnalytics = NoopProductAnalytics()

    public static func log(_ event: AnalyticsEvent, _ params: [String: Any] = [:]) {
        backend.log(event, params)
    }
}
