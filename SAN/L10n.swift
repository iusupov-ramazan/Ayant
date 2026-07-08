import SwiftUI

/// Локализует ДИНАМИЧЕСКУЮ строку (enum rawValue, серверные значения-ключи,
/// статусы и т. п.) через строковый каталог.
///
/// Почему это нужно: `Text("литерал")` локализуется автоматически, а
/// `Text(переменная)` — НЕТ (берётся init(_: String), а не LocalizedStringKey).
/// Поэтому для категорий, типов акций, статусов и прочих значений-переменных
/// оборачиваем строку в `LocalizedStringKey`, чтобы перевод из каталога
/// подхватывался и уважал выбранный в приложении язык (\.locale).
func L(_ s: String) -> LocalizedStringKey { LocalizedStringKey(s) }

extension VenueCategory {
    /// Локализованное имя категории для показа в Text/Label.
    var locKey: LocalizedStringKey { LocalizedStringKey(rawValue) }
}

extension DealType {
    var locKey: LocalizedStringKey { LocalizedStringKey(rawValue) }
}
