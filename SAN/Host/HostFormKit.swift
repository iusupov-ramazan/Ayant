import SwiftUI
import AyantDomain
import AyantFeatures

// Общие детали хост-форм (SCREENS.md H1, H3–H5, H8).
//
// В макете все формы устроены одинаково: карточка с рядами «капслоковая метка
// сверху, значение снизу», кремовая заметка и липкий футер. Раньше это были
// системные `Form` — их вид не совпадал ни с чем в редизайне.

/// Ряд формы: метка-капслок + значение.
struct SanFieldRow<Value: View>: View {
    let label: LocalizedStringKey
    /// Пояснение под полем — там, где из одного названия правило не понятно.
    var hint: LocalizedStringKey? = nil
    @ViewBuilder var value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .textCase(.uppercase)
                .font(.golos(11, .heavy)).tracking(0.9)
                .foregroundStyle(Color(hex: 0x9A9188))
            value
            if let hint {
                Text(hint)
                    .font(.golos(11.5))
                    .foregroundStyle(Color.sanInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 13)
    }
}

/// Текстовое поле формы. Пустое значение показывается плейсхолдером `#C0B8AE`.
struct SanFieldInput: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var axis: Axis = .horizontal

    var body: some View {
        TextField("", text: $text, axis: axis)
            .keyboardType(keyboard)
            .font(.golos(15.5, .semibold))
            .foregroundStyle(Color.sanInk)
            .tint(Color.sanAccent)
            .overlay(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.golos(15.5, .semibold))
                        .foregroundStyle(Color(hex: 0xC0B8AE))
                        .allowsHitTesting(false)
                }
            }
    }
}

/// Карточка-группа для рядов формы (разделители рисуются между рядами).
struct SanFieldCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .sanGroupCard(radius: SanRadius.card)
    }
}

/// Кремовая заметка-предупреждение («уйдёт на модерацию» и т. п.).
struct SanNoteCard: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text)
            .font(.golos(13)).foregroundStyle(Color(hex: 0xC24A12))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(hex: 0xFFF3EC),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Прогресс из отрезков: первый активный — акцентный градиент.
struct SanStepProgress: View {
    let step: Int          // 0-based
    var total: Int = 2

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? AnyShapeStyle(LinearGradient.sanAccentGradient)
                                    : AnyShapeStyle(Color(hex: 0xE0DAD1)))
                    .frame(height: 4)
            }
        }
    }
}

/// Липкий футер формы: основная кнопка и подпись под ней.
struct SanStickyFooter<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 8) { content }
            .padding(.horizontal, 18)
            .padding(.top, 12).padding(.bottom, 14)
            .background {
                ZStack(alignment: .top) {
                    Color.sanCanvas.opacity(0.92).background(.ultraThinMaterial)
                    Rectangle().fill(Color.sanHairline).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
            }
    }
}

/// Заголовок формы: «Отмена · Название · пусто» одной строкой без переносов.
struct SanFormHeader: View {
    let title: LocalizedStringKey
    var onCancel: () -> Void

    var body: some View {
        HStack {
            // Цель нажатия — не только буквы. Голый текст 15pt у самой
            // верхней кромки листа давал попадание размером с палец наполовину:
            // касание чуть выше уходило жесту перетаскивания листа, и
            // «Отмена» «не работала». Теперь зона — полные 44pt по высоте.
            Button(action: onCancel) {
                Text("Отмена")
                    .font(.golos(15, .semibold))
                    .foregroundStyle(Color.sanAccentText)
                    .frame(minHeight: 44)
                    .padding(.trailing, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Text(title)
                .font(.golos(16, .bold)).foregroundStyle(Color.sanInk)
                .lineLimit(1).fixedSize()
            Spacer(minLength: 8)
            // Балансирующая пустота той же ширины, что и «Отмена».
            Text("Отмена").font(.golos(15, .semibold)).padding(.leading, 12).opacity(0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, SanMetrics.screenPadding)
        // Высота шапки прежняя: 44pt кнопки вместо 12 + текст + 12.
        .padding(.top, 6).padding(.bottom, 2)
    }
}

/// Ряд-переключатель с градиентной дорожкой (системный Toggle не умеет градиент).
struct SanGradientToggle: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.golos(14.5, .bold)).foregroundStyle(Color.sanInk)
                if let subtitle {
                    Text(subtitle).font(.golos(12)).foregroundStyle(Color(hex: 0x9A9188))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Button {
                SanHaptics.selection()
                withAnimation(.sanStandard(0.25)) { isOn.toggle() }
            } label: {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? AnyShapeStyle(LinearGradient.sanAccentGradient)
                                   : AnyShapeStyle(Color(hex: 0xDDD7CE)))
                        .frame(width: 46, height: 28)
                    Circle().fill(.white).frame(width: 22, height: 22).padding(3)
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn ? [.isSelected] : [])
        }
    }
}

/// Сегментированный выбор из строк (режимы баллов, типы акций).
struct SanSegmented<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                let isOn = item == selection
                Button {
                    SanHaptics.selection()
                    withAnimation(.sanStandard) { selection = item }
                } label: {
                    Text(title(item))
                        .font(.golos(13.5, isOn ? .bold : .semibold))
                        .foregroundStyle(isOn ? Color.sanInk : Color.sanInkSoft)
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: 13, style: .continuous)
                                    .fill(Color.sanSurface)
                                    .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.sanSurfaceMuted,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Несохранённые изменения

extension View {
    /// Лист с черновиком не закрывается молча: пока `isDirty`, свайп вниз
    /// не закрывает лист, а зовёт `onAttempt` — там форма спрашивает
    /// «Сохранить изменения?». Без этого правка заведения терялась от
    /// случайного свайпа.
    ///
    /// Одного `interactiveDismissDisabled` мало: лист просто пружинит, и
    /// хозяин не понимает, почему он не закрывается. Попытку закрыть видит
    /// только UIKit (`presentationControllerDidAttemptToDismiss`), поэтому
    /// здесь мост к нему.
    func sanConfirmDismiss(isDirty: Bool, onAttempt: @escaping () -> Void) -> some View {
        self
            .interactiveDismissDisabled(isDirty)
            .background(DismissAttemptBridge(onAttempt: onAttempt).frame(width: 0, height: 0))
    }
}

/// Подключается к `presentationController` листа и ловит попытку закрыть его.
///
/// SwiftUI сам держит делегата этого контроллера (через него он узнаёт о
/// закрытии свайпом и сбрасывает `isPresented`). Заменить его нельзя —
/// лист перестал бы сбрасывать привязку, — поэтому `DismissAttemptProxy`
/// встаёт перед ним и передаёт ему все остальные вызовы.
private struct DismissAttemptBridge: UIViewControllerRepresentable {
    let onAttempt: () -> Void

    func makeUIViewController(context: Context) -> BridgeController { BridgeController() }

    func updateUIViewController(_ controller: BridgeController, context: Context) {
        controller.onAttempt = onAttempt
    }

    final class BridgeController: UIViewController {
        var onAttempt: () -> Void = {}
        private var proxy: DismissAttemptProxy?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }

        private func install() {
            // Корень цепочки `parent` — контроллер, который показан листом
            // (у дочерних `presentingViewController` унаследован, по нему не найти).
            var root: UIViewController = self
            while let parent = root.parent { root = parent }
            guard root.presentingViewController != nil,
                  let pc = root.presentationController,
                  !(pc.delegate is DismissAttemptProxy) else { return }
            let proxy = DismissAttemptProxy(original: pc.delegate) { [weak self] in self?.onAttempt() }
            self.proxy = proxy          // делегат слабый — держим сами
            pc.delegate = proxy
        }
    }
}

private final class DismissAttemptProxy: NSObject, UIAdaptivePresentationControllerDelegate {
    weak var original: UIAdaptivePresentationControllerDelegate?
    let onAttempt: () -> Void

    init(original: UIAdaptivePresentationControllerDelegate?, onAttempt: @escaping () -> Void) {
        self.original = original
        self.onAttempt = onAttempt
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        onAttempt()
        original?.presentationControllerDidAttemptToDismiss?(presentationController)
    }

    // Всё остальное — делегату SwiftUI, как если бы нас не было.
    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        (original?.responds(to: aSelector) ?? false) ? original : super.forwardingTarget(for: aSelector)
    }
}
