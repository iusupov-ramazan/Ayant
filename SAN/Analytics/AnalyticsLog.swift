import Foundation
#if canImport(FirebaseAnalytics)
import FirebaseAnalytics
#endif

/// Продуктовая аналитика (DAU, удержание, воронки) — события для Firebase Analytics.
///
/// Чтобы включить реальную отправку: в Xcode добавь пакет Firebase и продукт
/// **FirebaseAnalytics** в target приложения. До этого момента события просто
/// печатаются в консоль (в DEBUG) и ничего не ломают.
enum AnalyticsEvent: String {
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

enum AnalyticsLog {
    static func log(_ event: AnalyticsEvent, _ params: [String: Any] = [:]) {
        #if canImport(FirebaseAnalytics)
        Analytics.logEvent(event.rawValue, parameters: params)
        #else
        #if DEBUG
        print("📊 analytics: \(event.rawValue) \(params)")
        #endif
        #endif
    }
}
