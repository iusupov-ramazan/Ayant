import Foundation
import AyantDomain

/// Оффлайн-режим: печатаем в консоль в DEBUG и ничего не отправляем.
public struct ConsoleProductAnalytics: ProductAnalytics {
    public init() {}

    public func log(_ event: AnalyticsEvent, _ params: [String: Any]) {
        #if DEBUG
        print("📊 analytics: \(event.rawValue) \(params)")
        #endif
    }
}
