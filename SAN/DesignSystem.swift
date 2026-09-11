import SwiftUI
import UIKit
import AyantDomain   // Palette — бренд-цвета числами (один источник с Venue.defaultGradient)

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
    /// Пустая плитка сетки — та же тёплая гамма, что и канвас, но на тон плотнее.
    static let sanTileEmpty    = sanDynamic(light: 0xEFEAE2, dark: 0x272320)
    /// Фон плоской шапки хоста.
    ///
    /// Именно ДИНАМИЧЕСКИЙ. `sanCream` — статический светлый (он рисовал панель
    /// таб-бара, где это верно всегда), и на тёмной теме шапка оставалась
    /// кремовой, а заголовок поверх неё — `sanInk` — становился почти белым:
    /// «Заведения» пропадали с экрана.
    static let sanHostHeader   = sanDynamic(light: 0xFFF7F1, dark: 0x1E1C1A)
    /// Подписи счётчиков в шапке хоста. Тёплые в обеих темах.
    static let sanHostCaption  = sanDynamic(light: 0x7E4520, dark: 0xC8A48A)
    /// Капслок «Режим заведения» в шапке хоста.
    static let sanHostEyebrow  = sanDynamic(light: 0x9C3306, dark: 0xFF9F6B)
    /// «Открыто».
    static let sanOpen         = Color(hex: 0x2FA24C)
    /// Глубокий тон акцента для градиента.
    static let sanAccentDeep   = Color(hex: 0xFF3B00)
    // sanAccent определён в Models.swift (яркий оранжевый).
}

// MARK: - Редизайн 2.4 · новые токены
//
// Появились потому, что редизайн кладёт мелкий текст на тёплые подложки, где
// старые серые и сам акцент проваливались ниже WCAG AA. Контрастность в
// комментариях измерена на прототипе.
//
// ВНИМАНИЕ: тёмная тема для песочных и кремовых поверхностей ещё НЕ нарисована
// (см. раздел Accessibility в хендоффе), поэтому токены ниже — статические, без
// `sanDynamic`. Когда тёмную нарисуют, они станут динамическими здесь и в
// `Color.kt` одновременно.

extension Color {
    /// Песок: начало градиента шапки хоста / riso-панелей.
    static let sanSand           = Color(hex: 0xFFEEDF)
    /// Песок: конец градиента.
    static let sanSandDeep       = Color(hex: 0xFFDBC0)
    /// Подписи на песке. 4.6:1 на `sanSand`.
    static let sanSandInk        = Color(hex: 0x7E4520)
    /// Метки кнопок-пилюль на песке. 6.2:1.
    static let sanSandInkStrong  = Color(hex: 0x6B3A18)
    /// Акцент как МЕЛКИЙ ТЕКСТ / активная вкладка. 4.78:1 на канвасе.
    static let sanAccentText     = Color(hex: 0xC43C05)
    /// Акцентные цифры на белом. 6.25:1.
    static let sanAccentTextStrong = Color(hex: 0xB03505)
    /// Капслоковые надзаголовки на песке. 4.5:1.
    static let sanEyebrow        = Color(hex: 0x9C3306)
    /// Неактивная вкладка сегмент-контрола. 5.34:1 на светлом канвасе.
    /// Тёмная пара нужна с тех пор, как токен переехал с удалённой ручной
    /// панели на витрину хоста: #726251 на тёмном канвасе давал ~2.9:1.
    static let sanTabIdle        = sanDynamic(light: 0x726251, dark: 0xA79C90)
    /// Фон таб-бара хоста.
    static let sanCream          = Color(hex: 0xFFF7F1)
    /// Верхняя граница таб-бара хоста.
    static let sanCreamLine      = Color(hex: 0xF0DDCB)
}

// MARK: - Градиенты
//
// Углы из CSS переведены в unit-точки: направление = (sin θ, −cos θ) при оси Y
// вниз, точки разнесены от центра. 135° = .topLeading → .bottomTrailing.

extension ShapeStyle where Self == LinearGradient {
    /// Фирменный оранжевый градиент. Стопы — те же числа, что `Venue.defaultGradient`
    /// (`Palette.accent` → `Palette.orange`), чтобы бренд был из одного источника.
    static var sanAccentGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: Palette.accent), Color(hex: Palette.orange)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Песочный градиент шапки хоста и riso-панелей — CSS `155deg`.
    static var sanSandGradient: LinearGradient {
        LinearGradient(colors: [.sanSand, .sanSandDeep],
                       startPoint: UnitPoint(x: 0.289, y: 0.047),
                       endPoint: UnitPoint(x: 0.711, y: 0.953))
    }

    /// Градиент карты штампов (лояльность) — CSS `140deg`, фиолетовый.
    static var sanStampGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0x5B4CC4), Color(hex: 0x9B87F0)],
                       startPoint: UnitPoint(x: 0.179, y: 0.117),
                       endPoint: UnitPoint(x: 0.821, y: 0.883))
    }
}

// MARK: - Riso-штриховка
//
// `repeating-linear-gradient(45deg, rgba(255,255,255,.42) 0 2px, transparent 2px 16px)`
// — диагональные белые полосы поверх песочной/градиентной подложки. Период 16pt
// меряется по перпендикуляру, поэтому шаг по X = 16·√2.

/// Диагональная штриховка 45°: полосы 2pt, период 16pt.
struct SanRisoHatch: View {
    var opacity: Double = 0.42
    var stripe: CGFloat = 2
    var period: CGFloat = 16

    var body: some View {
        Canvas { context, size in
            let stepX = period * 1.4142136          // период по перпендикуляру → шаг по X
            var x = -size.height
            var path = Path()
            while x <= size.width + size.height {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                x += stepX
            }
            context.stroke(path, with: .color(.white.opacity(opacity)),
                           style: StrokeStyle(lineWidth: stripe))
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Накладывает riso-штриховку, обрезая её по форме поверхности.
    func sanRisoHatch<S: Shape>(in shape: S, opacity: Double = 0.42) -> some View {
        overlay(SanRisoHatch(opacity: opacity).clipShape(shape))
    }

    /// Песочная riso-панель: градиент + штриховка + скругление.
    func sanSandPanel(radius: CGFloat = SanRadius.panel) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(LinearGradient.sanSandGradient, in: shape)
            .sanRisoHatch(in: shape)
    }
}

// MARK: - Скругления, тени, хит-таргеты
//
// Числа из хендоффа. CSS blur → SwiftUI radius = blur / 2.

enum SanRadius {
    /// Карточки списков и результатов.
    static let card: CGFloat   = 22
    /// Крупные карточки (баллы, награды, hero).
    static let hero: CGFloat   = 26
    /// Листы и панели, накрывающие обложку.
    static let sheet: CGFloat  = 30
    /// Шапка хоста / нижние углы панели.
    static let panel: CGFloat  = 34
    /// Кнопки.
    static let button: CGFloat = 18
    /// Плитки-иконки.
    static let tile: CGFloat   = 14
    /// Пилюли и чипы.
    static let pill: CGFloat   = 999
}

/// Минимальный хит-таргет — 44pt (таб-кнопки в прототипе 55×75).
enum SanMetrics {
    static let minHitTarget: CGFloat = 44
    static let screenPadding: CGFloat = 20
    static let tabLabelSize: CGFloat = 11   // ниже 11 не опускать: провал по читаемости
    /// Высота панели вкладок (62) + запас под выступающий над ней FAB (24).
    /// Ровно на столько экраны вкладок расширяют свою безопасную зону снизу.
    static let tabBarInset: CGFloat = 86
}

/// Тени редизайна. Применяются через `.sanShadow(_:)`.
enum SanShadow {
    case card, elevated, accentCTA, hero, badge, sandPanel, qrCard

    var color: Color {
        switch self {
        case .card, .elevated, .qrCard: return .black
        case .accentCTA, .hero:         return Color(hex: 0xFF5A1F)
        case .badge:                    return Color(hex: 0xFF3B00)
        case .sandPanel:                return Color(hex: 0xC4783C)
        }
    }

    var opacity: Double {
        switch self {
        case .card: return 0.04
        case .elevated: return 0.05
        case .qrCard: return 0.08
        case .accentCTA: return 0.32
        case .hero: return 0.28
        case .badge: return 0.40
        case .sandPanel: return 0.07
        }
    }

    /// SwiftUI-радиус = CSS blur / 2.
    var radius: CGFloat {
        switch self {
        case .card: return 5
        case .elevated: return 7
        case .accentCTA: return 14
        case .hero: return 17
        case .badge: return 10
        case .sandPanel: return 11
        case .qrCard: return 20
        }
    }

    var y: CGFloat {
        switch self {
        case .card: return 2
        case .elevated: return 3
        case .accentCTA: return 12
        case .hero: return 16
        case .badge: return 8
        case .sandPanel: return -6
        case .qrCard: return 18
        }
    }
}

extension View {
    func sanShadow(_ shadow: SanShadow) -> some View {
        self.shadow(color: shadow.color.opacity(shadow.opacity),
                    radius: shadow.radius, y: shadow.y)
    }
}

// Движение живёт в `Motion.swift` — кривые, длительности, `sanScreenEnter()`,
// `sanRise(_:)`, `SanPressStyle`, `sanPop(on:)`. Здесь его специально нет,
// чтобы длительности не разъехались по двум файлам.

// MARK: - Карточка (единая сетка: скругление 20, мягкая тень, минимум рамок)

struct SanCard: ViewModifier {
    var padding: CGFloat = 14
    var radius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background { SanCardBackground(radius: radius) }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.sanHairline, lineWidth: 0.5))
    }
}

/// Подложка карточки: заливка + тень НА САМОЙ ФИГУРЕ.
///
/// Тень вешается на фигуру, а не на карточку целиком. `.shadow()` поверх
/// составного содержимого (текст + фото + обводка) заставляет систему рисовать
/// всё поддерево во внеэкранный буфер и размывать его — на каждый кадр и на
/// каждую карточку. В списке результатов, который едет вместе с листом, это
/// десяток внеэкранных проходов за кадр: ровно то, что ощущается как лаг.
/// У залитой фигуры тень берётся из её пути и почти ничего не стоит.
///
/// Числа — из макета: `box-shadow: 0 2px 10px rgba(0,0,0,.04)` (CSS blur 10 → radius 5).
struct SanCardBackground: View {
    var radius: CGFloat = 20
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.sanSurface)
            .shadow(color: .black.opacity(0.04), radius: 5, y: 2)
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

// MARK: - Роли текста редизайна
//
// Размер + начертание + трекинг из таблицы хендоффа, одним модификатором —
// чтобы редакторские заголовки не расползались по экранам разными числами.
//
// ОГОВОРКА про межстрочный интервал: в хендоффе он задан множителями 0.92–1.04,
// то есть ПЛОТНЕЕ системного (~1.19 у SF Pro). SwiftUI умеет только увеличивать
// интервал (`lineSpacing` отрицательные значения обрезает), поэтому здесь мы
// компенсируем лишь внешние отступы блока (`padding`), а сжатие между строками
// не применяется. На однострочных заголовках разницы нет; на переносах (герой
// онбординга 52pt, заголовок карточки ленты 32pt) строки будут чуть свободнее
// макета. Если понадобится точь-в-точь — понадобится UIKit-лейбл с
// `NSParagraphStyle.lineHeightMultiple`.

struct SanTextRole: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    let tracking: CGFloat
    let lineHeightMultiple: CGFloat

    func body(content: Content) -> some View {
        let uiFont = UIFont.systemFont(ofSize: size, weight: weight.uiKit)
        let delta = size * lineHeightMultiple - uiFont.lineHeight
        return content
            .font(.golos(size, weight))
            .tracking(tracking)
            .lineSpacing(max(0, delta))
            .padding(.vertical, delta / 2)   // padding принимает отрицательные значения
    }
}

extension View {
    /// Роль текста редизайна: размер/начертание/трекинг/межстрочный из хендоффа.
    func sanText(_ size: CGFloat, _ weight: Font.Weight = .regular,
                 tracking: CGFloat = 0, lineHeight: CGFloat = 1.2) -> some View {
        modifier(SanTextRole(size: size, weight: weight,
                             tracking: tracking, lineHeightMultiple: lineHeight))
    }

    /// Заголовок экрана (редакторский): 42–46/heavy.
    func sanEditorialTitle(_ size: CGFloat = 44) -> some View {
        sanText(size, .heavy, tracking: -size * 0.056, lineHeight: 0.94)
    }

    /// Надзаголовок секции: 11.5/heavy, +1.2 трекинг, капслок применять на месте.
    func sanEyebrowText() -> some View {
        sanText(11.5, .heavy, tracking: 1.2)
    }

    /// Подпись вкладки таб-бара: 11/bold (ниже не опускать).
    func sanTabLabel() -> some View {
        sanText(SanMetrics.tabLabelSize, .bold, tracking: -0.1)
    }
}

extension Font.Weight {
    /// Мост к `UIFont.Weight` — нужен, чтобы посчитать реальную высоту строки.
    var uiKit: UIFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin:       return .thin
        case .light:      return .light
        case .medium:     return .medium
        case .semibold:   return .semibold
        case .bold:       return .bold
        case .heavy:      return .heavy
        case .black:      return .black
        default:          return .regular
        }
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
            .background { SanCardBackground(radius: radius) }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.sanHairline, lineWidth: 0.5))
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
            // 0.97, а не прежние 0.99: на 0.99 нажатие не читается (ANIMATIONS.md §3).
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: SanTiming.press), value: configuration.isPressed)
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
            // Было падение прозрачности до 0.7 — редизайн везде жмёт масштабом.
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: SanTiming.press), value: configuration.isPressed)
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

// MARK: - Прибитая панель навигации

/// Панель навигации, которая ВСЕГДА видна: кнопка «назад» слева, заголовок по
/// центру, произвольное действие справа.
///
/// Ставится через `.sanNavBar(...)`, то есть как `safeAreaInset(edge: .top)`, а
/// не оверлеем: так содержимое экрана само получает верхний отступ и не
/// подныривает под кнопку. Раньше такая шапка лежала первой строкой внутри
/// `ScrollView` и уезжала вместе с содержимым — до кнопки «назад» приходилось
/// доскроллить обратно.
struct SanNavBar<Trailing: View>: View {
    var title: LocalizedStringKey?
    var onBack: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            SanCircleButton(systemName: "chevron.left", action: onBack)
                .accessibilityLabel("Назад")
            Spacer(minLength: 8)
            if let title {
                Text(title)
                    .font(.golos(17, .bold))
                    .foregroundStyle(Color.sanInk)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            // Симметрия: без правого действия резервируем ширину кнопки, иначе
            // заголовок уезжает от центра.
            trailing.frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.sanCanvas.ignoresSafeArea(edges: .top))
    }
}

extension View {
    /// Прибивает панель навигации к верху экрана.
    func sanNavBar(_ title: LocalizedStringKey? = nil,
                   onBack: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            SanNavBar(title: title, onBack: onBack) { Color.clear.frame(width: 44, height: 44) }
        }
    }

    /// Тот же бар, но с действием справа.
    func sanNavBar<Trailing: View>(_ title: LocalizedStringKey? = nil,
                                   onBack: @escaping () -> Void,
                                   @ViewBuilder trailing: () -> Trailing) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            SanNavBar(title: title, onBack: onBack, trailing: trailing)
        }
    }
}
