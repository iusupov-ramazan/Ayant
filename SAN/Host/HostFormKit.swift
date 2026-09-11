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
            Button("Отмена", action: onCancel)
                .font(.golos(15, .semibold))
                .foregroundStyle(Color.sanAccentText)
            Spacer(minLength: 8)
            Text(title)
                .font(.golos(16, .bold)).foregroundStyle(Color.sanInk)
                .lineLimit(1).fixedSize()
            Spacer(minLength: 8)
            // Балансирующая пустота той же ширины, что и «Отмена».
            Text("Отмена").font(.golos(15, .semibold)).opacity(0)
        }
        .padding(.horizontal, SanMetrics.screenPadding)
        .padding(.vertical, 12)
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
