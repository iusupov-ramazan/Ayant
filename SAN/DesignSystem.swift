import SwiftUI
import UIKit

// MARK: - Ayant Refresh · дизайн-система
//
// Принципы: больше воздуха, меньше рамок · единая сетка карточек ·
// цвет приглушён, акцент яркий. Палитра: Accent · Gradient · Ink · Canvas · Open.

extension UIColor {
    fileprivate convenience init(rgb: UInt) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    /// Динамический цвет: разные значения для светлой и тёмной темы.
    static func sanDynamic(light: UInt, dark: UInt) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }

    /// Тёплый фон приложения (Canvas).
    static let sanCanvas       = sanDynamic(light: 0xF6F4F0, dark: 0x121110)
    /// Поверхность карточек.
    static let sanSurface      = sanDynamic(light: 0xFFFFFF, dark: 0x1E1C1A)
    /// Приглушённая подложка (чипы, вторичные плашки).
    static let sanSurfaceMuted = sanDynamic(light: 0xEFEDE7, dark: 0x2A2724)
    /// Основной текст (Ink).
    static let sanInk          = sanDynamic(light: 0x17130F, dark: 0xF3F1EC)
    /// Вторичный текст.
    static let sanInkSoft      = sanDynamic(light: 0x6E655C, dark: 0xB4ADA3)
    /// Тонкая линия / обводка.
    static let sanHairline     = sanDynamic(light: 0xE7E3DC, dark: 0x322E2A)
    /// «Открыто».
    static let sanOpen         = Color(hex: 0x2FA24C)
    /// Глубокий тон акцента для градиента.
    static let sanAccentDeep   = Color(hex: 0xFF3B00)
    // sanAccent определён в Models.swift (яркий оранжевый).
}

// MARK: - Градиент акцента (для шапок, баланса, кнопок)

extension ShapeStyle where Self == LinearGradient {
    /// Фирменный оранжевый градиент (как в исходной версии: оранжевый → янтарный).
    static var sanAccentGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xFF4D29), Color(hex: 0xFFB300)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Карточка (единая сетка: скругление 20, мягкая тень, минимум рамок)

struct SanCard: ViewModifier {
    var padding: CGFloat = 14
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.sanSurface,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.sanHairline, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.05), radius: 12, y: 6)
    }
}

extension View {
    /// Оборачивает контент в карточку рефреша.
    func sanCard(padding: CGFloat = 14, radius: CGFloat = 20) -> some View {
        modifier(SanCard(padding: padding, radius: radius))
    }

    /// Тёплый фон-канвас на весь экран (для ScrollView-экранов).
    func sanScreenBackground() -> some View {
        background(Color.sanCanvas.ignoresSafeArea())
    }

    /// Канвас-фон под Form/List (белые карточки-группы на тёплом фоне).
    func sanFormBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.sanCanvas.ignoresSafeArea())
    }
}

// MARK: - Типографика · системный шрифт SF Pro
//
// Используем нативный San Francisco (SF Pro): чёткая иерархия по размеру и весу,
// поддержка кириллицы и Dynamic Type «из коробки». Историческое имя `golos(_:_:)`
// сохранено, чтобы не менять сотни вызовов по экранам — оно возвращает SF.

extension Font {
    /// SF Pro заданного размера и начертания (Text/Display подбирается автоматически).
    static func golos(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Общие компоненты рефреша
//
// Единый набор для всех экранов: заголовки, плитки-иконки, карточки-группы,
// статистика, кнопки. Меньше рамок, больше воздуха, акцент — только на действии.

/// Крупный заголовок экрана (SF Pro, bold).
struct SanScreenTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.golos(32, .heavy))
            .foregroundStyle(Color.sanInk)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Приглушённый капс-заголовок секции.
struct SanSectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.golos(12, .bold))
            .tracking(1.0)
            .foregroundStyle(Color.sanInkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Плитка-иконка: мягкая тонированная подложка + акцентный глиф,
/// либо `filled` — градиентная плитка с белым глифом.
struct SanIconTile: View {
    let systemName: String
    var tint: Color = .sanAccent
    var filled: Bool = false
    var size: CGFloat = 44
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
            .fill(filled ? AnyShapeStyle(LinearGradient.sanAccentGradient)
                          : AnyShapeStyle(tint.opacity(0.14)))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(filled ? Color.white : tint)
            )
    }
}

/// Карточка со значением-цифрой (для сеток статистики).
struct SanStatCard: View {
    let value: String
    let label: String
    var accent: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.golos(30, .heavy))
                .foregroundStyle(accent ? Color.sanAccent : Color.sanInk)
            Text(label)
                .font(.golos(13, .medium))
                .foregroundStyle(Color.sanInkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .sanCard(padding: 16)
    }
}

/// Тонкая разделительная линия для строк внутри карточки-группы.
struct SanHairline: View {
    var leading: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(Color.sanHairline)
            .frame(height: 0.5)
            .padding(.leading, leading)
    }
}

extension View {
    /// Оборачивает VStack строк в карточку-группу без внутренних отступов
    /// (строки задают отступы сами; между ними — SanHairline).
    func sanGroupCard(radius: CGFloat = 20) -> some View {
        self
            .background(Color.sanSurface,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.sanHairline, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.05), radius: 12, y: 6)
    }
}

// MARK: - Кнопки

/// Основная кнопка: акцентный градиент с мягким свечением.
struct SanPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.golos(17, .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(LinearGradient.sanAccentGradient,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.sanAccent.opacity(configuration.isPressed ? 0.15 : 0.32),
                    radius: 16, y: 8)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

/// Вторичная «пилюля»: приглушённая подложка или лёгкий акцентный тон.
struct SanPillButton: ButtonStyle {
    var accent: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.golos(15, .semibold))
            .foregroundStyle(accent ? Color.sanAccent : Color.sanInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(accent ? Color.sanAccent.opacity(0.12) : Color.sanSurfaceMuted,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Круглая мягкая кнопка панели навигации (напр. «назад», сканер).
struct SanCircleButton: View {
    let systemName: String
    var filled: Bool = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(filled ? Color.white : Color.sanInk)
                .frame(width: 44, height: 44)
                .background(filled ? AnyShapeStyle(LinearGradient.sanAccentGradient)
                                   : AnyShapeStyle(Color.sanSurface),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }
}
