import SwiftUI

// MARK: - Слой движения (ANIMATIONS.md)
//
// Все длительности и кривые редизайна живут ЗДЕСЬ и только здесь. Если число
// появится во втором файле — оно разъедется (ANIMATIONS.md §17).
//
// Две кривые на всё приложение:
//   · «стандартная» cubic-bezier(.22,1,.36,1) — вход, переходы, прогресс;
//   · «поп» cubic-bezier(.2,1.4,.4,1) — с перелётом: сердечко, галочка, штампы.

extension Animation {
    /// Стандартная кривая рефреша — вход, переходы, прогресс.
    static let sanStandard = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.42)
    static func sanStandard(_ duration: Double) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }
    /// Кривая «поп» — с перелётом.
    static let sanPop = Animation.spring(response: 0.45, dampingFraction: 0.55)
    /// Счётчик: ease-out cubic, 1 с.
    static let sanCounter = Animation.timingCurve(0.33, 1, 0.68, 1, duration: 1.0)
}

/// Именованные длительности и шаги — чтобы не рассыпать магические числа.
enum SanTiming {
    static let screenEnter = 0.42
    static let press = 0.18

    /// Выезд элементов списка: длительность и шаг задержки.
    static let feedRise = (duration: 0.72, stagger: 0.09)
    static let dealRowRise = (duration: 0.55, stagger: 0.08)
    static let gridTileRise = (duration: 0.50, stagger: 0.06)
    static let resultRowRise = (duration: 0.50, stagger: 0.07)
    /// Витрина хоста: плитки мельче и их втрое больше в ряду, поэтому шаг короче.
    static let hostGridRise = (duration: 0.50, stagger: 0.05)

    /// Задержку получают только элементы первого экрана: иначе 12-я карточка
    /// ждёт секунду, а прокрученные позже появляются «с опозданием».
    static let staggerCap = 4
    /// То же правило для сетки 3×N: первый экран — это девять плиток.
    static let gridStaggerCap = 9
    /// Лента постов: на экран влезает один пост, но задержку получают первые
    /// четыре — их видно при быстрой прокрутке сразу после входа.
    static let feedStaggerCap = 4

    static let progressBar = 1.0
    static let qrSweep = 2.6
    static let scannerSweep = 2.2
    static let shimmer = 3.4
    static let fabPulse = 2.8
    static let skeletonPulse = 1.2
}

// MARK: - §1 Появление экрана

/// +14pt снизу и проявление, 420 мс. Вешается на корень каждого экрана и
/// проигрывается заново при каждом переходе.
struct SanScreenEnter: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            // При «уменьшении движения» оставляем только проявление.
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                withAnimation(.sanStandard(SanTiming.screenEnter)) { shown = true }
            }
    }
}

// MARK: - §2 Ступенчатый выезд списка

/// +28pt и scale 0.985 с задержкой по индексу. Задержка обрезается
/// `SanTiming.staggerCap` — см. комментарий там.
struct SanRise: ViewModifier {
    let index: Int
    var stagger: Double = SanTiming.feedRise.stagger
    var duration: Double = SanTiming.feedRise.duration
    /// Сколько первых элементов получают задержку.
    var cap: Int = SanTiming.staggerCap
    /// Выключено — элемент просто на месте, без выезда.
    ///
    /// Нужно там, где список перестраивается не при входе на экран, а по
    /// переключателю: выезд, проигранный второй раз, читается как новая
    /// загрузка, хотя пользователь всего лишь сменил фильтр.
    var enabled: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private var visible: Bool { shown || !enabled }

    private var delay: Double {
        index < cap ? Double(index) * stagger : 0
    }

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible || reduceMotion ? 1 : 0.985)
            .offset(y: visible || reduceMotion ? 0 : 28)
            .onAppear {
                withAnimation(.sanStandard(duration).delay(delay)) { shown = true }
            }
    }
}

extension View {
    /// Появление экрана (§1).
    func sanScreenEnter() -> some View { modifier(SanScreenEnter()) }

    /// Выезд i-го элемента списка (§2).
    func sanRise(_ index: Int,
                 stagger: Double = SanTiming.feedRise.stagger,
                 duration: Double = SanTiming.feedRise.duration,
                 cap: Int = SanTiming.staggerCap,
                 enabled: Bool = true) -> some View {
        modifier(SanRise(index: index, stagger: stagger, duration: duration,
                         cap: cap, enabled: enabled))
    }
}

// MARK: - §3 Отклик на нажатие

/// Масштаб 0.86…0.98 за 180 мс. Самая заметная часть слоя движения — она
/// чувствуется на каждом тапе.
struct SanPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: SanTiming.press), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SanPressStyle {
    /// Крупные элементы: карточки, основные кнопки.
    static var sanPress: SanPressStyle { SanPressStyle() }
    /// Мелкие: чипы, иконки, вкладки (0.94/0.88), сердечко (0.86).
    static func sanPress(_ scale: CGFloat) -> SanPressStyle { SanPressStyle(scale: scale) }
}

// MARK: - §4 «Поп» на сохранении

/// Пружина 0.6 → 1.18 → 1. Срабатывает, когда элемент СТАНОВИТСЯ выбранным,
/// и молчит на снятии — иначе снятие лайка читается как ещё один лайк.
struct SanPopOnSet: ViewModifier {
    let isSet: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: isSet) { _, nowSet in
                guard nowSet, !reduceMotion else { return }
                scale = 0.6
                withAnimation(.sanPop) { scale = 1 }
            }
    }
}

extension View {
    func sanPop(on isSet: Bool) -> some View { modifier(SanPopOnSet(isSet: isSet)) }
}

// MARK: - Тактильная отдача
//
// «Сохранение без хаптики ощущается мёртвым» (ANIMATIONS.md §4). Держим рядом
// с движением, а не вместо него.

enum SanHaptics {
    static func save() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - Шапка под статус-баром
//
// Экраны редизайна скроллятся во всю высоту, и без этой полосы под часами
// проезжает контент. Полоса с запасом и сдвиг на неё же — верх уходит за экран,
// реальный инсет читать не нужно.

extension View {
    func sanStatusBarCap(_ color: Color = .sanCanvas) -> some View {
        overlay(alignment: .top) {
            color.frame(height: 120).offset(y: -120).allowsHitTesting(false)
        }
    }
}
