import SwiftUI
import AyantDomain

/// Мост «доменные числа → цвета SwiftUI».
///
/// Домен (`AyantDomain`) хранит цвета как RGB-числа (`Venue.gradient: [UInt32]`),
/// чтобы не тащить в ядро UI-фреймворк. Всё превращение в `Color` живёт здесь,
/// в UI-слое. Зеркалит `ui/theme/ModelColors.kt` на Android.

extension Color {
    static let sanAccent = Color(hex: Palette.accent)   // Ayant Refresh — яркий оранжевый акцент

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Venue {
    /// Градиент карточки заведения как цвета SwiftUI.
    var gradientColors: [Color] { gradient.map { Color(hex: $0) } }
}

extension DealType {
    var color: Color {
        switch self {
        case .discount: return .sanAccent
        case .promo: return .purple
        case .novelty: return .teal
        case .announcement: return .blue
        }
    }
}

extension DealStatus {
    var color: Color {
        switch self {
        case .active: return .green
        case .paused: return .orange
        case .expired: return .gray
        case .draft: return .blue
        }
    }
}

extension ModerationStatus {
    var color: Color {
        switch self {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .red
        }
    }
}
