import Foundation

/*
 * Палитра и разбор HEX — числами, без UI.
 *
 * Домен хранит цвета как `UInt32` (`Venue.gradient`), поэтому и палитра, и
 * парсер "#RRGGBB" живут здесь: их зовёт маппер Firestore из слоя данных,
 * которому SwiftUI недоступен. Превращение чисел в `Color` осталось в
 * UI-слое (`SAN/Theme/ModelColors.swift`).
 */

/// Палитра в виде чисел — то, что может лежать в домене и приходить с бэкенда.
public enum Palette {
    /// Те же числа, что и `Venue.defaultGradient` в домене — один источник.
    public static let accent: UInt32 = Venue.defaultGradient[0]
    public static let orange: UInt32 = Venue.defaultGradient[1]
    public static let purple: UInt32 = 0xAF52DE
    public static let teal: UInt32   = 0x30B0C7
    public static let blue: UInt32   = 0x007AFF
    public static let green: UInt32  = 0x34C759
    public static let gray: UInt32   = 0x8E8E93
    public static let red: UInt32    = 0xFF3B30
}

extension UInt32 {
    /// Парсит "#RRGGBB" или "RRGGBB". Используется маппером Firestore.
    public init?(hexString: String?) {
        guard var s = hexString else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self = v
    }
}
