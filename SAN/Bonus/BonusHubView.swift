import SwiftUI

/// Вкладка «Бонусы»: кошелёк, прогресс активного времени, игры, обмен на скидки.
/// Обёртка URL+название для .sheet(item:).
struct ShareURL: Identifiable { let id = UUID(); let url: URL; let title: String }

struct BonusHubView: View {
    @EnvironmentObject private var bonus: BonusEngine
    @EnvironmentObject private var coupons: CouponStore
    @EnvironmentObject private var store: AppStore

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
                        subtitle: "1 яблоко = 1 бонус", gradient: [.green, .teal])
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showSnake) {
                SnakeGameView()
            }

            Button { showTetris = true } label: {
                gameRow(emoji: "🧱", title: "Тетрис",
                        subtitle: "1 линия = 5 бонусов", gradient: [.purple, .indigo])
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
            HStack {
                Text("Потратить бонусы").font(.headline)
                Spacer()
                NavigationLink {
                    MyCouponsView()
                } label: {
                    Label("Мои купоны\(coupons.activeCount > 0 ? " (\(coupons.activeCount))" : "")",
                          systemImage: "ticket.fill")
                        .font(.subheadline.weight(.semibold))
                }
            }
            ForEach(CouponStore.catalog) { reward in
                rewardRow(reward)
            }
            NavigationLink {
                LoyaltyView()
            } label: {
                HStack {
                    Label("Карты лояльности", systemImage: "creditcard.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
        .alert("Купон получен 🎉", isPresented: Binding(
            get: { justClaimed != nil }, set: { if !$0 { justClaimed = nil } })) {
            Button("Отлично") {}
        } message: {
            Text("Найди его в «Мои купоны» и покажи сотруднику заведения.")
        }
        // Подтверждение перед обменом бонусов.
        .alert("Обменять бонусы?", isPresented: Binding(
            get: { pendingReward != nil }, set: { if !$0 { pendingReward = nil } }),
            presenting: pendingReward) { reward in
            Button("Обменять за \(reward.cost)", role: .destructive) {
                if let c = coupons.redeem(reward, bonus: bonus) { justClaimed = c }
            }
            Button("Отмена", role: .cancel) {}
        } message: { reward in
            Text("«\(reward.title)» за \(reward.cost) бонусов. Купон нельзя вернуть после обмена.")
        }
    }

    @State private var justClaimed: Coupon?
    @State private var pendingReward: Reward?
    @State private var pendingGift: Reward?
    @State private var giftShare: ShareURL?

    private func rewardRow(_ reward: Reward) -> some View {
        HStack(spacing: 12) {
            Text(reward.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(reward.title)).font(.subheadline.weight(.medium))
                Text("\(reward.cost) бонусов").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button { pendingReward = reward } label: { Label("Обменять себе", systemImage: "ticket") }
                Button { pendingGift = reward } label: { Label("Подарить другу", systemImage: "gift") }
            } label: {
                Text("Обменять").font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(bonus.balance >= reward.cost ? Color.sanAccent : Color.gray, in: Capsule())
                    .foregroundStyle(.white)
            }
            .disabled(bonus.balance < reward.cost)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .alert("Подарить купон?", isPresented: Binding(
            get: { pendingGift != nil }, set: { if !$0 { pendingGift = nil } }),
            presenting: pendingGift) { r in
            Button("Подарить за \(r.cost)", role: .destructive) {
                if let url = store.createGift(r, bonus: bonus) {
                    giftShare = ShareURL(url: url, title: r.title)
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: { r in
            Text("Спишется \(r.cost) бонусов. Отправь ссылку другу — он заберёт «\(r.title)».")
        }
        .sheet(item: $giftShare) { item in
            GiftShareSheet(url: item.url, title: item.title)
        }
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
    BonusHubView()
        .environmentObject(BonusEngine())
        .environmentObject(CouponStore())
        .environmentObject(AppStore())
        .tint(.sanAccent)
}
