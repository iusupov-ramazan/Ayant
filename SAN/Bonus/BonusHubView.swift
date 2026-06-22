import SwiftUI

/// Вкладка «Бонусы»: кошелёк, прогресс активного времени, игры, обмен на скидки.
struct BonusHubView: View {
    @EnvironmentObject private var bonus: BonusEngine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    walletCard
                    activeTimeCard
                    gamesSection
                    rewardsSection
                }
                .padding(16)
            }
            .navigationTitle("Бонусы")
            .overlay(alignment: .top) { rewardToast }
        }
    }

    // MARK: Кошелёк

    private var walletCard: some View {
        VStack(spacing: 6) {
            Text("Твой баланс").font(.subheadline).foregroundStyle(.white.opacity(0.9))
            Text("\(bonus.balance)")
                .font(.system(size: 52, weight: .heavy))
                .foregroundStyle(.white)
            Text("бонусов").font(.caption).foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            LinearGradient(colors: [Color(hex: 0xFF4D29), Color(hex: 0xFFB300)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }

    // MARK: Активное время

    private var activeTimeCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color(.systemGray5), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: bonus.progress)
                    .stroke(Color.sanAccent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: bonus.progress)
                Image(systemName: bonus.isCounting ? "bolt.fill" : "pause.fill")
                    .foregroundStyle(bonus.isCounting ? Color.sanAccent : .secondary)
            }
            .frame(width: 78, height: 78)

            VStack(alignment: .leading, spacing: 4) {
                Text("Активные 30 минут")
                    .font(.subheadline.weight(.semibold))
                Text("Осталось \(bonus.remaining) до +\(bonus.rewardPerGoal)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(bonus.isCounting ? "Идёт отсчёт" : "На паузе — листай ленту")
                    .font(.caption2)
                    .foregroundStyle(bonus.isCounting ? Color.green : .orange)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: Игры

    @State private var showSnake = false
    @State private var showTetris = false

    private var gamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Игры").font(.headline)
            // Открываем как полноэкранную модалку: у неё нет свайпа «назад»,
            // поэтому горизонтальные свайпы управляют только игрой.
            Button { showSnake = true } label: {
                gameRow(emoji: "🐍", title: "Змейка",
                        subtitle: "1 яблоко = 2 бонуса", gradient: [.green, .teal])
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showSnake) {
                SnakeGameView()
            }

            Button { showTetris = true } label: {
                gameRow(emoji: "🧱", title: "Тетрис",
                        subtitle: "1 линия = 20 бонусов", gradient: [.purple, .indigo])
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showTetris) {
                TetrisGameView()
            }
        }
    }

    private func gameRow(emoji: String, title: String, subtitle: String,
                         gradient: [Color]) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: gradient,
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(emoji).font(.title)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: Обмен бонусов

    private var rewardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Потратить бонусы").font(.headline)
            rewardRow(title: "−10% к любой акции", cost: 100)
            rewardRow(title: "Бесплатный кофе у партнёра", cost: 300)
            rewardRow(title: "VIP-доступ к новинкам", cost: 500)
        }
    }

    @State private var redeemed: String?

    private func rewardRow(title: String, cost: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text("\(cost) бонусов").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(redeemed == title ? "Готово" : "Обменять") {
                if bonus.spend(cost) { redeemed = title }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.borderedProminent)
            .tint(bonus.balance >= cost ? .sanAccent : .gray)
            .disabled(bonus.balance < cost || redeemed == title)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Тост «+N»

    @ViewBuilder private var rewardToast: some View {
        if let reward = bonus.lastReward {
            Text("+\(reward) бонусов 🎉")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Color.green, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task {
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    bonus.clearRewardFlag()
                }
        }
    }
}

#Preview {
    BonusHubView().environmentObject(BonusEngine()).tint(.sanAccent)
}
