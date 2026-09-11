import SwiftUI
import AyantDomain

/// Локализует ДИНАМИЧЕСКУЮ строку (enum rawValue, серверные значения-ключи,
/// статусы и т. п.) через строковый каталог.
///
/// Почему это нужно: `Text("литерал")` локализуется автоматически, а
/// `Text(переменная)` — НЕТ (берётся init(_: String), а не LocalizedStringKey).
/// Поэтому для категорий, типов акций, статусов и прочих значений-переменных
/// оборачиваем строку в `LocalizedStringKey`, чтобы перевод из каталога
/// подхватывался и уважал выбранный в приложении язык (\.locale).
func L(_ s: String) -> LocalizedStringKey { LocalizedStringKey(s) }

/// То же, но возвращает `String` — для мест, где `Text` не годится: подписи на
/// UIKit-пинах карты, тексты для шаринга, Apple Wallet.
///
/// `String(localized:)` смотрит на язык СИСТЕМЫ и не видит `\.locale`, который
/// приложение подменяет своей настройкой. Поэтому достаём бандл нужного языка
/// руками, иначе на английском интерфейсе такие подписи остались бы русскими.
func LS(_ key: String) -> String {
    let lang = UserDefaults.standard.string(forKey: "san.language") ?? "ru"
    guard let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
          let bundle = Bundle(path: path) else {
        return NSLocalizedString(key, comment: "")
    }
    return bundle.localizedString(forKey: key, value: key, table: nil)
}

extension VenueCategory {
    /// Локализованное имя категории для показа в Text/Label.
    var locKey: LocalizedStringKey { LocalizedStringKey(rawValue) }
}

extension DealType {
    var locKey: LocalizedStringKey { LocalizedStringKey(rawValue) }
}
