import Foundation
import SwiftUI
import AyantDomain

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
        // Локаль — язык приложения (Профиль → Язык), а не жёстко русская:
        // иначе в английском интерфейсе оставалось «23 сентября».
        f.locale = AppLanguage.locale
        f.dateFormat = "d MMMM"
        return f.string(from: self)
    }
}

extension Int {
    // `LF`, а не `String(localized:)`: последняя смотрит на язык системы.
    var som: String { LF("%lld сом", self) }
}

extension Venue {
    /// Локализованный статус часов работы. Доменный `hoursStatusText` —
    /// русская строка; здесь тот же смысл через ключи каталога, чтобы в
    /// английском интерфейсе не оставалось «Открыто · до 23:00».
    var hoursStatusKey: LocalizedStringKey {
        let now = Date()
        // Хвост вчерашней ночной смены идёт и в «выходной» день — как в
        // доменном `hoursStatusText`.
        if let close = openShiftClose(at: now) { return "Открыто · до \(DayHours.time(close))" }
        return todayHours(at: now).closed ? "Сегодня выходной" : "Закрыто"
    }
}
