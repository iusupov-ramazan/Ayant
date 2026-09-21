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

/// Язык интерфейса (Профиль → Язык): `ru` | `en` | `ky`. Хранится в
/// UserDefaults под ключом `san.language` — ключ load-bearing, не переименовывать.
enum AppLanguage {
    static let defaultsKey = "san.language"

    static var current: String { UserDefaults.standard.string(forKey: defaultsKey) ?? "ru" }

    /// Локаль для дат и чисел — язык ПРИЛОЖЕНИЯ, а не системы. Кыргызский
    /// раньше выпадал из этой ветки и форматировался по-русски.
    static var localeIdentifier: String {
        switch current {
        case "en": return "en_US"
        case "ky": return "ky_KG"
        default:   return "ru_RU"
        }
    }

    static var locale: Locale { Locale(identifier: localeIdentifier) }
}

/// Русское слово по числу («1 отзыв / 2 отзыва / 5 отзывов»), уже переведённое
/// через каталог: формы — ключи, английские значения у них совпадают. Без этого
/// в английском интерфейсе оставались русские хвосты вроде «2 отзыва».
func LPlural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
    let n10 = n % 10, n100 = n % 100
    let key: String
    if n10 == 1 && n100 != 11 { key = one }
    else if (2...4).contains(n10) && !(12...14).contains(n100) { key = few }
    else { key = many }
    return LS(key)
}

/// То же, но возвращает `String` — для мест, где `Text` не годится: подписи на
/// UIKit-пинах карты, тексты для шаринга, Apple Wallet, `String`-возвращающие
/// хелперы (тексты ошибок по кодам сервера и т. п.).
///
/// `String(localized:)` смотрит на язык СИСТЕМЫ и не видит `\.locale`, который
/// приложение подменяет своей настройкой. Поэтому достаём бандл нужного языка
/// руками, иначе на английском интерфейсе такие подписи остались бы русскими.
///
/// Ключи, которые проходят только через `LS`/`LF`, компилятор в каталог не
/// вытаскивает — их надо добавить в `Localizable.xcstrings` руками.
func LS(_ key: String) -> String {
    let lang = AppLanguage.current
    guard let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
          let bundle = Bundle(path: path) else {
        // Язык-источник (ru) в отдельный `.lproj` не компилируется — его текст
        // и есть ключ. Раньше здесь был `NSLocalizedString`, который на
        // английском устройстве отдавал английскую строку при выбранном русском.
        return key
    }
    return bundle.localizedString(forKey: key, value: key, table: nil)
}

/// Форматная строка из каталога: `LF("Ещё %lld до «%@»", n, title)`.
/// Ключ пишется с теми же спецификаторами, что генерирует Xcode для
/// интерполяций (`%lld` для Int, `%@` для String), чтобы переводы можно было
/// переиспользовать между `Text("…\(n)…")` и `LF`.
func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: LS(key), arguments: args)
}

extension VenueCategory {
    /// Локализованное имя категории для показа в Text/Label.
    var locKey: LocalizedStringKey { LocalizedStringKey(rawValue) }
}

extension DealType {
    var locKey: LocalizedStringKey { LocalizedStringKey(rawValue) }
}
