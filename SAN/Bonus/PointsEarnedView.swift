import SwiftUI
import AyantDomain
import AyantFeatures

/// «Начисление» (SCREENS.md G5) — момент, ради которого гость сканирует снова.
///
/// ВАЖНО: ни одно число здесь не считается на клиенте. Экран показывается, когда
/// snapshot-листенер `venuePoints` принёс новый баланс, и анимирует счётчик
/// *к* тому значению, которое записал сервер (`scanCoupon`).
/// Что именно начислили: баллы или штамп. Экран один — язык у обоих один.
enum EarnedContent: Equatable {
    case points(delta: Int, newBalance: Int)
    case stamp(stamps: Int, goal: Int, rewardIssued: Bool, reward: String)
}

struct PointsEarnedView: View {
    let earned: EarnedContent
    let venueName: String
    let venueSubtitle: String
    var onDone: () -> Void
    /// «Оставить отзыв» — только когда у гостя ещё нет отзыва об этом заведении.
    var onReview: (() -> Void)? = nil

    init(delta: Int, venueName: String, venueSubtitle: String, newBalance: Int,
         onDone: @escaping () -> Void, onReview: (() -> Void)? = nil) {
        self.init(content: .points(delta: delta, newBalance: newBalance), venueName: venueName,
                  venueSubtitle: venueSubtitle, onDone: onDone, onReview: onReview)
    }

    init(content: EarnedContent, venueName: String, venueSubtitle: String,
         onDone: @escaping () -> Void, onReview: (() -> Void)? = nil) {
        self.earned = content; self.venueName = venueName; self.venueSubtitle = venueSubtitle
        self.onDone = onDone; self.onReview = onReview
    }

    private var delta: Int {
        switch earned {
        case .points(let d, _): return d
        case .stamp: return 1
        }
    }
    private var newBalance: Int {
        switch earned {
        case .points(_, let b): return b
        case .stamp(let s, _, _, _): return s
        }
    }
    private var headline: String {
        switch earned {
        case .points: return "Баллы начислены"
        case .stamp(_, _, let issued, _): return issued ? "Карта заполнена!" : "Штамп получен"
        }
    }
    private var footnote: String {
        switch earned {
        case .points: return "Баллы копятся у этого заведения и тратятся у него же."
        case .stamp(_, let goal, let issued, let reward):
            return issued ? "Купон «\(reward)» уже в «Мои купоны» — покажите его сотруднику."
                          : "Ещё \(goal) \(Self.stampsWord(goal)) — и «\(reward)» в подарок."
        }
    }
    private var balanceLabel: String {
        switch earned {
        case .points: return "Новый баланс"
        case .stamp(_, let goal, _, _): return "Штампов из \(goal)"
        }
    }

    private static func stampsWord(_ n: Int) -> String {
        let n10 = n % 10, n100 = n % 100
        if n10 == 1 && n100 != 11 { return "штамп" }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return "штампа" }
        return "штампов"
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringsRunning = false
    @State private var discShown = false
    @State private var confettiFalling = false
    @State private var shownDelta = 0
    @State private var shownBalance = 0

    private static let confettiCount = 14
    private static let confettiColors: [Color] = [
        Color(hex: 0xFF5A1F), Color(hex: 0xFF9500), Color(hex: 0xFF3B00), Color(hex: 0xFFD166),
    ]

    var body: some View {
        ZStack {
            Color.sanCanvas.ignoresSafeArea()
            confetti
            content
        }
        .onAppear(perform: start)
        // Бесконечные кольца не крутятся за закрытым экраном (ANIMATIONS.md §17).
        .onDisappear { withoutAnimation { ringsRunning = false } }
    }

    private var content: some View {
        VStack(spacing: 0) {
            burst
            Text("+\(shownDelta)")
                .sanText(70, .heavy, tracking: -3.6, lineHeight: 1)
                .foregroundStyle(LinearGradient.sanAccentGradient)
                .contentTransition(.numericText())
                .padding(.top, 28)

            Text(headline)
                .sanText(24, .heavy, tracking: -1)
                .foregroundStyle(Color.sanInk)
                .padding(.top, 12)

            Text("\(venueName) · \(venueSubtitle)")
                .font(.golos(14.5)).foregroundStyle(Color.sanInkSoft)
                .padding(.top, 8)

            balanceCard.padding(.top, 26)

            Text(footnote)
                .font(.golos(13)).foregroundStyle(Color(hex: 0x9A9188))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .padding(.top, 14)
                .sanRise(4, stagger: 0.09, duration: 0.6)

            Button("Отлично", action: onDone)
                .buttonStyle(SanPrimaryButton())
                .frame(maxWidth: 300)
                .padding(.top, 26)
                .sanRise(5, stagger: 0.09, duration: 0.6)

            // Момент, когда гость доволен, — лучший для отзыва: он только что
            // побывал в заведении и получил за это награду.
            if let onReview {
                Button(action: onReview) {
                    Label("Оставить отзыв о заведении", systemImage: "star.bubble")
                }
                .buttonStyle(SanPillButton(accent: true))
                .padding(.top, 12)
                .sanRise(6, stagger: 0.09, duration: 0.6)
            }
        }
        .padding(30)
    }

    // MARK: Кольца + галочка

    private var burst: some View {
        ZStack {
            if !reduceMotion {
                ring(color: .sanAccent, delay: 0)
                ring(color: Color(hex: Palette.orange), delay: 0.6)
            }
            Circle()
                .fill(LinearGradient.sanAccentGradient)
                .frame(width: 104, height: 104)
                .overlay(Image(systemName: "checkmark")
                    .font(.system(size: 46, weight: .heavy))
                    .foregroundStyle(.white))
                .shadow(color: Color.sanAccent.opacity(0.4), radius: 20, y: 18)
                .scaleEffect(discShown ? 1 : 0.6)
                .opacity(discShown ? 1 : 0)
        }
        .frame(width: 120, height: 120)
    }

    private func ring(color: Color, delay: Double) -> some View {
        Circle()
            .strokeBorder(color, lineWidth: 2)
            .frame(width: 120, height: 120)
            .scaleEffect(ringsRunning ? 2.6 : 0.35)
            .opacity(ringsRunning ? 0 : 0.55)
            .animation(.easeOut(duration: 1.9).repeatForever(autoreverses: false).delay(delay),
                       value: ringsRunning)
    }

    // MARK: Новый баланс

    private var balanceCard: some View {
        HStack {
            Text(balanceLabel)
                .font(.golos(14, .semibold)).foregroundStyle(Color.sanInkSoft)
            Spacer(minLength: 12)
            Text("\(shownBalance)")
                .font(.golos(24, .heavy)).tracking(-0.9)
                .foregroundStyle(Color.sanInk)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .frame(maxWidth: 300)
        .background(Color.sanSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.sanHairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.05), radius: 12, y: 8)
        .sanRise(3, stagger: 0.09, duration: 0.6)
    }

    // MARK: Конфетти

    @ViewBuilder private var confetti: some View {
        if !reduceMotion {
            GeometryReader { geo in
                ForEach(0..<Self.confettiCount, id: \.self) { i in
                    let x = geo.size.width * (Double(i) + 0.5) / Double(Self.confettiCount)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.confettiColors[i % Self.confettiColors.count])
                        .frame(width: 9, height: 9)
                        .position(x: x, y: geo.size.height * 0.34)
                        .offset(y: confettiFalling ? 220 : 0)
                        .rotationEffect(.degrees(confettiFalling ? 320 : 0))
                        .opacity(confettiFalling ? 0 : 1)
                        .animation(.timingCurve(0.2, 0.7, 0.4, 1, duration: 1.5)
                            .delay(Double(i) * 0.045), value: confettiFalling)
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: Запуск

    private func start() {
        SanHaptics.success()
        guard !reduceMotion else {
            discShown = true
            shownDelta = delta
            shownBalance = newBalance
            return
        }
        withAnimation(.sanPop) { discShown = true }
        ringsRunning = true
        confettiFalling = true
        // Счётчик — ease-out cubic, 1 с (ANIMATIONS.md §9).
        withAnimation(.sanCounter) {
            shownDelta = delta
            shownBalance = newBalance
        }
    }
}
