import Foundation

/// Тонкий слой персистентности пользовательских настроек-множеств и строковых
/// ключей (избранные акции, погашенные купоны, сохранённые заведения, город).
///
/// Абстрагирует `UserDefaults`, чтобы `AppStore` можно было тестировать с
/// подставным хранилищем и в перспективе сменить бэкенд (Keychain/iCloud) в
/// одном месте. Ключи и семантика сохраняются один в один с прежним кодом,
/// поэтому данные существующих пользователей не теряются.
protocol LocalPreferencesStore {
    /// Множество строк по ключу (пусто, если ничего не сохранено).
    func stringSet(forKey key: String) -> Set<String>
    /// Сохраняет множество строк по ключу.
    func setStringSet(_ value: Set<String>, forKey key: String)
    /// Строковое значение по ключу (nil, если нет).
    func string(forKey key: String) -> String?
    /// Сохраняет строковое значение по ключу.
    func setString(_ value: String, forKey key: String)
}

/// Реализация поверх `UserDefaults` (по умолчанию `.standard`).
/// Множества хранятся как массивы строк — совместимо с прежним форматом.
struct UserDefaultsPreferencesStore: LocalPreferencesStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func stringSet(forKey key: String) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    func setStringSet(_ value: Set<String>, forKey key: String) {
        defaults.set(Array(value), forKey: key)
    }

    func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func setString(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}
