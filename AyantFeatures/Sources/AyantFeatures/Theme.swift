import SwiftUI

/// Тема оформления. Хранится в UserDefaults, применяется на корне приложения.
public enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    public var icon: String {
        switch self {
        case .system: return "iphone"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// nil = следовать системе
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Лёгкий стор для темы. Используется на корне и в профиле.
@MainActor
public final class ThemeStore: ObservableObject {
    /// Явный public init: синтезированный — internal.
    public init() {}

    @AppStorage("san.theme") private var raw: String = AppTheme.system.rawValue

    public var theme: AppTheme {
        get { AppTheme(rawValue: raw) ?? .system }
        set { raw = newValue.rawValue; objectWillChange.send() }
    }
}
