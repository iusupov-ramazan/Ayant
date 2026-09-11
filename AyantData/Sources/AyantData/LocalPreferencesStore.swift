import Foundation
import AyantDomain

/// Множества хранятся как массивы строк — совместимо с прежним форматом.
public struct UserDefaultsPreferencesStore: LocalPreferencesStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func stringSet(forKey key: String) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    public func setStringSet(_ value: Set<String>, forKey key: String) {
        defaults.set(Array(value), forKey: key)
    }

    public func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func setString(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}
