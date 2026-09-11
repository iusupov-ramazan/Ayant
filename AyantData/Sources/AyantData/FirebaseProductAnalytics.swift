import Foundation
import FirebaseAnalytics
import AyantDomain

/// Отправка продуктовых событий в Firebase Analytics.
///
/// Единственное место в приложении, где импортируется `FirebaseAnalytics`:
/// таксономия событий (`AnalyticsEvent`) и вызовы из экранов о SDK не знают.
public struct FirebaseProductAnalytics: ProductAnalytics {
    /// Пустой инициализатор нужен явно: синтезированный — internal.
    public init() {}

    public func log(_ event: AnalyticsEvent, _ params: [String: Any]) {
        Analytics.logEvent(event.rawValue, parameters: params)
    }
}
