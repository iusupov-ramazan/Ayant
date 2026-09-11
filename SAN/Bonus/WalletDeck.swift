import SwiftUI
import AyantDomain
import AyantFeatures

// «Бонусы»: колода карт «Баллы САН» и карта штампов (SCREENS.md G6).
//
// Три валюты в одном месте: баллы заведения (главное), карта штампов и
// глобальные бонусы (нарочно подчинённые — они почти ничего не стоят).

// MARK: - Колода карт баллов

/// Стопка карт: верхняя развёрнута, остальные выглядывают снизу.
/// `rel = (index - top + n) % n` — так колода «прокручивается» по кругу.
struct WalletDeck: View {
    let cards: [VenuePointsCard]
    let venues: [String: Venue]
    var onOpen: (VenuePointsCard) -> Void

    @State private var top = 0

    private static let step: CGFloat = 44
    private static let scaleStep: CGFloat = 0.055
    /// Показываем не больше четырёх — глубже стопка нечитаема, а высота сцены фиксирована.
    private static let maxVisible = 4

    private var stageHeight: CGFloat {
        198 + Self.step * CGFloat(min(cards.count, Self.maxVisible) - 1)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                let rel = (index - top + cards.count) % cards.count
                if rel < Self.maxVisible {
                    WalletPointsCard(card: card, venue: venues[card.venueID], isFront: rel == 0)
                        .offset(y: Self.step * CGFloat(rel))
                        .scaleEffect(1 - Self.scaleStep * CGFloat(rel), anchor: .top)
                        .zIndex(Double(cards.count - rel))
                        .onTapGesture {
                            if rel == 0 {
                                onOpen(card)
                            } else {
                                SanHaptics.selection()
                                withAnimation(.sanStandard(0.55)) { top = index }
                            }
                        }
                }
            }
        }
        .frame(height: stageHeight)
        .padding(.horizontal, 24)
        .animation(.sanStandard(0.55), value: top)
    }
}

/// Одна карта баллов заведения.
struct WalletPointsCard: View {
    let card: VenuePointsCard
    let venue: Venue?
    var isFront: Bool = true

    /// Ближайшая награда — она задаёт цель прогресса.
    private var nextReward: PointsReward? {
        (venue?.pointsRewards ?? [])
            .filter { $0.active && $0.cost > card.balance }
            .min { $0.cost < $1.cost }
    }

    private var progress: Double {
        guard let next = nextReward, next.cost > 0 else { return 1 }
        return min(1, Double(card.balance) / Double(next.cost))
    }

    private var gradient: [Color] { venue?.gradientColors ?? [.sanAccent, Color(hex: Palette.orange)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.venueName)
                        .font(.golos(13, .bold)).tracking(-0.1)
                        .foregroundStyle(.white).lineLimit(1)
                    if let venue {
                        Text(venue.category.locKey)
                            .font(.golos(11.5)).foregroundStyle(.white.opacity(0.72))
                    }
                }
                Spacer(minLength: 8)
                if let mode = venue?.pointsModeLabel {
                    Text(mode)
                        .font(.golos(11, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(.white.opacity(0.2), in: Capsule())
                        .lineLimit(1).fixedSize()
                }
            }

            Text("\(card.balance)")
                .font(.golos(46, .heavy)).tracking(-2.4)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.snappy, value: card.balance)
                .padding(.top, 20)
            Text("баллов")
                .font(.golos(12, .semibold)).foregroundStyle(.white.opacity(0.82))

            SanProgressBar(fraction: progress, height: 6)
                .padding(.top, 18)

            Text(nextReward.map { "Ещё \($0.cost - card.balance) до «\($0.title)»" }
                 ?? "Награды доступны")
                .font(.golos(11.5, .semibold)).foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .padding(.top, 9)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 198)
        .background(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(isFront ? 0.20 : 0.12),
                radius: isFront ? 22 : 12, y: isFront ? 22 : 10)
    }
}

// MARK: - Карта штампов

/// Карта лояльности `loyaltyCards/{userID}_{venueID}` — до редизайна у неё не
/// было своего места на экране.
struct WalletStampCard: View {
    let card: LoyaltyCard
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// Сетка 5×2 по макету; если цель другая — рисуем ровно `goal` кружков.
    private var goal: Int { max(card.goal, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.venueName)
                        .font(.golos(14.5, .heavy)).tracking(-0.3)
                        .foregroundStyle(.white).lineLimit(1)
                    Text("штамп за каждый визит")
                        .font(.golos(12)).foregroundStyle(.white.opacity(0.82))
                }
                Spacer(minLength: 8)
                Text("\(card.stamps) / \(goal)")
                    .font(.golos(11.5, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(.white.opacity(0.2), in: Capsule())
                    .fixedSize()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 5), spacing: 9) {
                ForEach(0..<goal, id: \.self) { i in
                    stamp(index: i, filled: i < card.stamps)
                }
            }
            .padding(.top, 18)

            Text(stampHint)
                .font(.golos(12.5, .semibold)).foregroundStyle(.white.opacity(0.94))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: SanRadius.hero, style: .continuous)
            shape.fill(LinearGradient.sanStampGradient)
                .overlay(SanRisoHatch(opacity: 0.10).clipShape(shape))
        }
        .shadow(color: Color(hex: 0x5B4CC4).opacity(0.26), radius: 15, y: 14)
        .onAppear {
            guard !reduceMotion else { appeared = true; return }
            appeared = true
        }
    }

    private func stamp(index: Int, filled: Bool) -> some View {
        ZStack {
            Circle().fill(filled ? AnyShapeStyle(LinearGradient.sanAccentGradient)
                                 : AnyShapeStyle(Color.white.opacity(0.26)))
            if filled {
                Image(systemName: "checkmark")
                    .font(.system(size: 12.5, weight: .heavy))
                    .foregroundStyle(.white)
            } else {
                Text("\(index + 1)")
                    .font(.golos(12.5, .heavy))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        // Каждый кружок «выстреливает» с шагом 50 мс (ANIMATIONS.md §4).
        .scaleEffect(appeared ? 1 : 0.6)
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .sanPop.delay(Double(index) * 0.05), value: appeared)
    }

    private var stampHint: String {
        let left = max(0, goal - card.stamps)
        if left == 0 { return "Круг собран — покажите карту сотруднику и заберите «\(card.reward)»." }
        return "Ещё \(left) \(Self.visits(left)) — и «\(card.reward)» в подарок. Штампы ставит сотрудник, сканируя ваш QR."
    }

    private static func visits(_ n: Int) -> String {
        let n10 = n % 10, n100 = n % 100
        if n10 == 1 && n100 != 11 { return "визит" }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return "визита" }
        return "визитов"
    }
}

// MARK: - Прогресс-бар
//
// Растёт от нуля один раз при появлении (ANIMATIONS.md §5). Дальнейшие
// изменения баланса анимируются коротко — иначе полоска перезаливалась бы
// каждый раз, когда snapshot-листенер приносит новый баланс.

struct SanProgressBar: View {
    let fraction: Double
    var height: CGFloat = 8
    var track: Color = .white.opacity(0.26)
    var fill: Color = .white

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill)
                    .frame(width: max(0, geo.size.width * shown))
            }
        }
        .frame(height: height)
        .onAppear {
            guard !reduceMotion else { shown = fraction; return }
            withAnimation(.sanStandard(SanTiming.progressBar).delay(0.2)) { shown = fraction }
        }
        .onChange(of: fraction) { _, new in
            withAnimation(.sanStandard(0.4)) { shown = new }
        }
    }
}

// MARK: - Подпись режима начисления

extension Venue {
    /// «кэшбэк 5%» / «30 за визит» — читает конфиг, ничего не считает.
    var pointsModeLabel: String? {
        guard pointsEnabled else { return nil }
        switch pointsMode {
        case "cashback":
            guard cashbackPercent > 0 else { return nil }
            return "кэшбэк \(cashbackPercent.sanPercentText)%"
        case "bands":
            return "по сумме чека"
        default:
            guard pointsFlat > 0 else { return nil }
            return "\(pointsFlat) за визит"
        }
    }
}
