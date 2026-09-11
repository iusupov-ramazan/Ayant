import Foundation

// Доменные модели переехали в пакет `AyantDomain` (Venue, Deal, Review,
// VenueCategory, DayHours…) — там они компилируются без SwiftUI и тестируются
// без симулятора. Цвета моделей живут в `SAN/Theme/ModelColors.swift`.
//
// Здесь остались только форматтеры представления: им нужен русский Locale,
// и в ядре они были бы лишними.

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
