import SwiftUI
import AyantDomain
import AyantFeatures

// «Бонусы»: карусель карт «Баллы САН» и карт штампов (SCREENS.md G6).
//
// Три валюты в одном месте: баллы заведения (главное), карта штампов и
// глобальные бонусы (нарочно подчинённые — они почти ничего не стоят).

// MARK: - Карусель кошелька

/// Страница карусели: карта баллов заведения или карта штампов.
///
/// У одного заведения действует ровно одна механика (`LoyaltyKind`), но
/// локальный кэш штампов переживает переключение на баллы, поэтому id
/// страницы несёт префикс — иначе две страницы одного заведения совпали бы.
enum WalletPage: Identifiable, Hashable {
    case points(VenuePointsCard)
    case stamps(LoyaltyCard)

    var id: String {
        switch self {
        case .points(let card): return "points-\(card.venueID)"
        // `card.id`, а не заведение: у заведения бывает несколько карт штампов.
        case .stamps(let card): return "stamps-\(card.id)"
        }
    }
}

/// Горизонтальная карусель с прилипанием к карте: сначала все карты баллов,
/// потом карты штампов. Следующая карта выглядывает справа — так сразу видно,
/// что есть ещё. Раньше это была стопка со смещением, и её приходилось
/// «прокручивать» тапами по выглядывающим краям — на ощупь это не читалось.
struct WalletCarousel: View {
    let pages: [WalletPage]
    let venues: [String: Venue]
    var onOpenPoints: (VenuePointsCard) -> Void
    var onOpenStamps: (LoyaltyCard) -> Void

    /// id текущей страницы — им живут точки под каруселью.
    @State private var current: String?
    /// Подсказка «проведите» показывается до первого реального свайпа и больше
    /// не возвращается — ключ переживает переустановку экрана, но не приложения.
    @AppStorage("san.wallet.swipeHintSeen") private var swipeHintSeen = false

    /// Доля ширины контейнера под карту; остаток — «подглядывание» следующей.
    private static let cardFraction: CGFloat = 0.86
    private static let spacing: CGFloat = 12

    private var currentIndex: Int {
        pages.firstIndex { $0.id == current } ?? 0
    }

    private var showsHint: Bool { pages.count > 1 && !swipeHintSeen }

    var body: some View {
        VStack(spacing: 14) {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Self.spacing) {
                    ForEach(pages) { page in
                        pageView(page)
                            .containerRelativeFrame(.horizontal) { length, _ in
                                length * Self.cardFraction
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $current)
            .scrollClipDisabled()
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, SanMetrics.screenPadding)

            if pages.count > 1 {
                pageDots
            }
            if showsHint {
                Text("Проведите, чтобы увидеть остальные карты")
                    .font(.golos(12)).foregroundStyle(Color.sanInkSoft)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
        }
        .onChange(of: current) { old, new in
            // Первое прилипание к первой карте — ещё не свайп: подсказку
            // прячем, только когда пользователь долистал до другой страницы.
            guard let new else { return }
            if old != nil, old != new { SanHaptics.selection() }
            if new != pages.first?.id, !swipeHintSeen {
                withAnimation(.sanStandard(0.3)) { swipeHintSeen = true }
            }
        }
    }

    @ViewBuilder
    private func pageView(_ page: WalletPage) -> some View {
        switch page {
        case .points(let card):
            Button { onOpenPoints(card) } label: {
                WalletPointsCard(card: card, venue: venues[card.venueID])
            }
            .buttonStyle(.sanPress(0.97))
        case .stamps(let card):
            Button { onOpenStamps(card) } label: {
                WalletStampCard(card: card)
            }
            .buttonStyle(.sanPress(0.97))
        }
    }

    /// Точки-страницы: текущая — вытянутая акцентная капсула.
    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(pages.indices, id: \.self) { i in
                Capsule()
                    .fill(i == currentIndex ? Color.sanAccent : Color.sanInk.opacity(0.18))
                    .frame(width: i == currentIndex ? 18 : 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.sanStandard(0.3), value: currentIndex)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Карта \(currentIndex + 1) из \(pages.count)")
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

    /// Высота карты растёт с «Размером текста» (как у `WalletStampCard`, чтобы
    /// карусель оставалась ровной) — фиксированные 198 pt обрезали текст на
    /// крупных настройках.
    @ScaledMetric(relativeTo: .body) private var scaledHeight: CGFloat = WalletStampCard.height

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

            // Подпись над числом, а не «баллов» под ним: голое «баллов» не
            // согласуется с «1 / 3 / 21» и не переводится по числу.
            Text("Баллы")
                .font(.golos(12, .semibold)).foregroundStyle(.white.opacity(0.82))
                .padding(.top, 16)
            Text(verbatim: card.balance.sanThousands)
                .font(.golos(46, .heavy)).tracking(-2.4)
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.snappy, value: card.balance)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            SanProgressBar(fraction: progress, height: 6)
                .padding(.top, 18)

            // `String` из `map` в `Text` не локализовался — строим через каталог.
            Text(verbatim: nextReward.map { LF("Ещё %lld до «%@»", $0.cost - card.balance, $0.title) }
                 ?? LS("Награды доступны"))
                .font(.golos(11.5, .semibold)).foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: WalletStampCard.cappedHeight(scaledHeight), alignment: .top)
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

    /// Ровно `goal` кружков (2…12) в один ряд: карта живёт в карусели рядом с
    /// картой баллов и обязана быть той же высоты — сетка 5×2 делала её выше
    /// и она наезжала на то, что под каруселью.
    private var goal: Int { max(card.goal, 1) }

    /// Та же высота, что у `WalletPointsCard` (при стандартном размере текста).
    static let height: CGFloat = 198
    @ScaledMetric(relativeTo: .body) private var scaledHeight: CGFloat = WalletStampCard.height

    /// Минимальная высота карты: растёт с Dynamic Type, но не бесконечно —
    /// дальше карта просто вытягивается под содержимое.
    static func cappedHeight(_ scaled: CGFloat) -> CGFloat { min(max(scaled, height), 340) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.venueName)
                        .font(.golos(14.5, .heavy)).tracking(-0.3)
                        .foregroundStyle(.white).lineLimit(1)
                    // Имя карты («Кофе», «Пицца») — когда их у заведения несколько.
                    Text(card.title.isEmpty ? LS("штамп за каждый визит") : card.title)
                        .font(.golos(12)).foregroundStyle(.white.opacity(0.82))
                }
                Spacer(minLength: 8)
                Text(verbatim: "\(card.stamps) / \(goal)")
                    .font(.golos(11.5, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(.white.opacity(0.2), in: Capsule())
                    .fixedSize()
                    .accessibilityLabel(LF("%lld из %lld штампов", card.stamps, goal))
            }

            // Больше 12 штампов — перенос на следующую строку (цель первой
            // карты сверху не ограничена), не больше `StampLayout.maxShown`.
            StampRows(goal: goal, perRow: 12, spacing: goal > 8 ? 5 : 8) { i in
                stamp(index: i, filled: i < card.stamps)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 16)

            Spacer(minLength: 0)

            Text(stampHint)
                .font(.golos(12, .semibold)).foregroundStyle(.white.opacity(0.94))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: Self.cappedHeight(scaledHeight))
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
                    .font(.system(size: goal > 8 ? 9 : 11.5, weight: .heavy))
                    .foregroundStyle(.white)
            } else {
                // Внутри кружка ≤ 36 pt — размер фиксированный, иначе на
                // крупном тексте цифра вылезает за кружок.
                Text(verbatim: "\(index + 1)")
                    .font(.golosFixed(goal > 8 ? 9 : 11.5, .heavy))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 36)
        // Каждый кружок «выстреливает» с шагом 50 мс (ANIMATIONS.md §4).
        .scaleEffect(appeared ? 1 : 0.6)
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? nil : .sanPop.delay(Double(index) * 0.05), value: appeared)
    }

    private var stampHint: String {
        let left = max(0, goal - card.stamps)
        // Коротко — под подсказку две строки.
        if left == 0 { return LF("Круг собран — купон «%@» уже в «Мои купоны».", card.reward) }
        return LF("Ещё %lld штампов — и «%@» в подарок.", left, card.reward)
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
            // `LS`, а не `String(localized:)`: последняя смотрит на язык системы.
            return LF("кэшбэк %@%%", cashbackPercent.sanPercentText)
        case "bands":
            return LS("по сумме чека")
        default:
            guard pointsFlat > 0 else { return nil }
            return LF("%lld за визит", pointsFlat)
        }
    }
}
