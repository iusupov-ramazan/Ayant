import SwiftUI
import AyantDomain
import AyantFeatures

// Редактор карт штампов заведения — один на два входа: лист «Карта
// лояльности» с карточки заведения и вкладка «Лояльность». Правила (пределы,
// id документа, совместимость с одной картой) — в `StampCards` (домен).

/// Карты штампов в том виде, в каком их держит редактор; в `VenueFields`
/// уходят один раз, при сохранении (`apply(to:)`).
struct StampCardsDraft: Equatable {
    var enabled = false
    /// Первая карта — скалярные поля заведения (id `default`).
    var first = StampCard(id: StampCard.defaultID, title: "", goal: StampCards.defaultGoal, reward: "")
    var extras: [StampCard] = []
    /// Копия заведения знает его дополнительные карты (`stampCardsLoaded`).
    /// Пока нет — дополнительные карты не показываем и не сохраняем: пустой
    /// список здесь значит «ещё не прочитали», а не «карт нет».
    var knowsExtras = true

    init() {}

    init(_ dto: HostVenueDTO) {
        enabled = dto.loyaltyEnabled
        first = StampCard(id: StampCard.defaultID, title: dto.loyaltyTitle,
                          goal: StampCards.firstGoal(dto.loyaltyGoal), reward: dto.loyaltyReward)
        extras = dto.extraStampCards
        knowsExtras = dto.stampCardsLoaded
    }

    var canAddCard: Bool { knowsExtras && 1 + extras.count < StampCards.maxCards }

    /// Что мешает сохранить. Имена нужны, как только карт больше одной:
    /// сотрудник выбирает карту на кассе по названию, а «Карта» и «Карта»
    /// не выбрать.
    var problem: LocalizedStringKey? {
        guard enabled else { return nil }
        let all = [first] + extras
        if all.contains(where: { $0.reward.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "У каждой карты должна быть награда."
        }
        if all.count > 1, all.contains(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Когда карт несколько, дайте каждой название — по нему сотрудник выбирает карту на кассе."
        }
        return nil
    }

    func apply(to fields: inout HostForms.VenueFields, keepingReward fallback: String) {
        fields.loyaltyEnabled = enabled
        fields.loyaltyGoal = StampCards.firstGoal(first.goal)
        let reward = first.reward.trimmingCharacters(in: .whitespacesAndNewlines)
        fields.loyaltyReward = reward.isEmpty ? fallback : reward
        fields.loyaltyTitle = first.title
        // Не знаем карт — не трогаем их (`nil` в `HostForms` = «оставить как есть»).
        fields.extraStampCards = knowsExtras ? extras : nil
    }
}

/// Сам редактор: переключатель программы и по карточке на каждую карту.
struct StampCardsEditor: View {
    @Binding var draft: StampCardsDraft
    @State private var pendingDelete: StampCard?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SanGradientToggle(title: "Карта штампов",
                              subtitle: "Штамп за визит по QR карты гостя",
                              isOn: $draft.enabled)
                .padding(.horizontal, 16).padding(.vertical, 13)
                .sanGroupCard(radius: SanRadius.card)

            if draft.enabled {
                cardEditor($draft.first, number: 1, removable: false)
                // По id, а не по индексам: удаление карты при индексной
                // привязке роняло бы экран на «index out of range».
                ForEach($draft.extras) { $card in
                    let number = (draft.extras.firstIndex { $0.id == card.id } ?? 0) + 2
                    cardEditor($card, number: number, removable: true)
                }
                if draft.canAddCard {
                    Button {
                        SanHaptics.selection()
                        withAnimation(.sanStandard) {
                            draft.extras.append(StampCard(id: StampCards.newID(), title: "",
                                                          goal: StampCards.defaultGoal, reward: ""))
                        }
                    } label: {
                        Label("Добавить карту", systemImage: "plus.circle.fill")
                            .font(.golos(14.5, .semibold))
                            .foregroundStyle(Color.sanAccentText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16).padding(.vertical, 13)
                            .sanGroupCard(radius: SanRadius.card)
                    }
                    .buttonStyle(.plain)
                } else if !draft.knowsExtras {
                    Text("Загружаем остальные карты заведения — добавить новую можно будет через минуту.")
                        .font(.golos(12)).foregroundStyle(Color.sanInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Не больше \(StampCards.maxCards) карт у заведения.")
                        .font(.golos(12)).foregroundStyle(Color.sanInkSoft)
                }
                Text("Гость показывает одну и ту же карту на кассе. Если карт несколько, после скана сотрудник выбирает, какой начислить штамп.")
                    .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog("Удалить карту?",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { card in
            Button("Удалить", role: .destructive) {
                withAnimation(.sanStandard) { draft.extras.removeAll { $0.id == card.id } }
                pendingDelete = nil
            }
            Button("Отмена", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("Гости перестанут видеть эту карту и собранные на ней штампы.")
        }
    }

    /// Степпер первой карты расширяется до её текущей цели: Android пишет цель
    /// свободным числом, и правка названия не должна молча урезать 20 до 12.
    private func goalRange(for card: StampCard) -> ClosedRange<Int> {
        card.isDefault ? StampCards.goalRange.lowerBound...max(StampCards.goalRange.upperBound, card.goal)
                       : StampCards.goalRange
    }

    private func cardEditor(_ card: Binding<StampCard>, number: Int, removable: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Карта \(number)")
                    .font(.golos(13, .heavy)).foregroundStyle(Color.sanInkSoft)
                Spacer()
                if removable {
                    Button {
                        pendingDelete = card.wrappedValue
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xE8556B))
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Удалить карту")
                }
            }
            .padding(.horizontal, 16).padding(.top, removable ? 6 : 12)
            SanFieldRow(label: "Название") {
                SanFieldInput(placeholder: "Например: Кофе", text: card.title)
            }
            SanHairline(leading: 16)
            SanFieldRow(label: "Штампов до награды") {
                Stepper(value: card.goal, in: goalRange(for: card.wrappedValue)) {
                    Text("\(card.wrappedValue.goal)")
                        .font(.golos(15.5, .semibold))
                        .foregroundStyle(Color.sanInk)
                }
            }
            SanHairline(leading: 16)
            SanFieldRow(label: "Награда") {
                SanFieldInput(placeholder: "Награда (напр. Бесплатный кофе)", text: card.reward)
            }
        }
        .sanGroupCard(radius: SanRadius.card)
    }
}

/// Строка карты в сводке: «Кофе · 6 визитов → «Бесплатный кофе»».
struct StampCardSummaryRow: View {
    let card: StampCard

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "seal.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.sanAccentText)
            VStack(alignment: .leading, spacing: 2) {
                if !card.title.isEmpty {
                    Text(card.title).font(.golos(14.5, .bold)).foregroundStyle(Color.sanInk)
                }
                Text("\(card.goal) визитов → «\(card.reward)»")
                    .font(.golos(card.title.isEmpty ? 14.5 : 13, card.title.isEmpty ? .semibold : .regular))
                    .foregroundStyle(card.title.isEmpty ? Color.sanInk : Color.sanInkSoft)
            }
            Spacer(minLength: 0)
        }
    }
}
