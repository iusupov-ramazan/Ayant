import SwiftUI

/// Вкладка «Бонусы» (рефреш): акцент на кошельке и наградах, игры — ниже и тише.
/// Обёртка URL+название для .sheet(item:).
struct ShareURL: Identifiable { let id = UUID(); let url: URL; let title: String }

struct BonusHubView: View {
    @EnvironmentObject private var bonus: BonusEngine
    @EnvironmentObject private var coupons: CouponStore
    @EnvironmentObject private var store: AppStore

    @State private var showSnake = false
    @State private var showTetris = false
    @State private var justClaimed: Coupon?
    @State private var pendingReward: Reward?
    @State private var pendingGift: Reward?
    @State private var giftShare: ShareURL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SanScreenTitle("Бонусы")
                    walletCard
                    rewardsSection
                    loyaltyLink
                    gamesSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .sanScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) { rewardToast }
            .alert("Купон получен 🎉", isPresented: Binding(
                get: { justClaimed != nil }, set: { if !$0 { justClaimed = nil } })) {
                Button("Отлично") {}
            } message: {
                Text("Найди его в «Мои купоны» и покажи сотруднику заведения.")
            }
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
    }

    // MARK: Кошелёк

    private var walletCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Твой баланс")
                        .font(.golos(15, .medium)).foregroundStyle(.white.opacity(0.9))
                    Text("\(bonus.balance)")
                        .font(.golos(52, .heavy)).foregroundStyle(.white)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text(Self.plural(bonus.balance))
                        .font(.golos(15, .medium)).foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                NavigationLink { MyCouponsView() } label: {
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
            }
            progressBar
        }
        .padding(22)
        .background(
            LinearGradient.sanAccentGradient,
            in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color.sanAccent.opacity(0.28), radius: 22, y: 12)
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Полоска без наложенного текста — заполнение и подпись не перекрываются.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.28))
                    Capsule().fill(.white)
                        .frame(width: max(10, geo.size.width * CGFloat(min(bonus.progress, 1))))
                }
            }
            .frame(height: 12)
            .animation(.easeInOut, value: bonus.progress)
            // Подпись — отдельной строкой, всегда белая на оранжевой карточке.
            Text("ещё \(bonus.remaining) до награды")
                .font(.golos(13, .bold)).foregroundStyle(.white)
        }
    }

    // MARK: Потратить бонусы

    private var rewardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Потратить бонусы").font(.golos(20, .bold)).foregroundStyle(Color.sanInk)
                Spacer()
                NavigationLink { MyCouponsView() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "creditcard.fill")
                        Text("Мои купоны\(coupons.activeCount > 0 ? " (\(coupons.activeCount))" : "")")
                    }
                    .font(.golos(14, .bold)).foregroundStyle(Color.sanAccent)
                }
                .buttonStyle(.plain)
            }
            ForEach(CouponStore.catalog) { reward in
                rewardRow(reward)
            }
        }
    }

    private func rewardRow(_ reward: Reward) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.sanAccent.opacity(0.10))
                .frame(width: 54, height: 54)
                .overlay(Text(reward.emoji).font(.system(size: 24)))
            VStack(alignment: .leading, spacing: 2) {
                Text(L(reward.title)).font(.golos(16, .bold)).foregroundStyle(Color.sanInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(Self.subtitle(reward)).font(.golos(13, .medium)).foregroundStyle(Color.sanInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Menu {
                Button { pendingReward = reward } label: { Label("Обменять себе", systemImage: "ticket") }
                Button { pendingGift = reward } label: { Label("Подарить другу", systemImage: "gift") }
            } label: {
                Text("\(reward.cost)")
                    .font(.golos(15, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(bonus.balance >= reward.cost
                                ? AnyShapeStyle(LinearGradient.sanAccentGradient)
                                : AnyShapeStyle(Color.sanInkSoft.opacity(0.5)),
                                in: Capsule())
            }
            .disabled(bonus.balance < reward.cost)
        }
        .padding(12)
        .sanCard(padding: 0)
    }

    // MARK: Карты лояльности

    private var loyaltyLink: some View {
        NavigationLink { LoyaltyView() } label: {
            HStack(spacing: 14) {
                SanIconTile(systemName: "creditcard.fill")
                Text("Карты лояльности").font(.golos(16, .semibold)).foregroundStyle(Color.sanInk)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sanInkSoft)
            }
            .padding(12)
            .sanCard(padding: 0)
        }
        .buttonStyle(.plain)
    }

    // MARK: Игры (тише, ниже)

    private var gamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SanSectionHeader("Играй и копи бонусы")
                SanHairline().frame(maxWidth: .infinity)
            }
            HStack(spacing: 12) {
                Button { showSnake = true } label: {
                    gameTile(emoji: "🐍", title: "Змейка", subtitle: "+1 / яблоко",
                             gradient: [Color(hex: 0x1FBF75), Color(hex: 0x0E9E86)])
                }
                .buttonStyle(.plain)
                .fullScreenCover(isPresented: $showSnake) { SnakeGameView() }

                Button { showTetris = true } label: {
                    gameTile(emoji: "🧱", title: "Тетрис", subtitle: "+5 / линия",
                             gradient: [Color(hex: 0x8A5CF6), Color(hex: 0x6D3BE0)])
                }
                .buttonStyle(.plain)
                .fullScreenCover(isPresented: $showTetris) { TetrisGameView() }
            }
        }
        .padding(.top, 4)
    }

    private func gameTile(emoji: String, title: String, subtitle: String,
                          gradient: [Color]) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 44)
                .overlay(Text(emoji).font(.system(size: 22)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.golos(15, .bold)).foregroundStyle(Color.sanInk)
                Text(subtitle).font(.golos(12, .medium)).foregroundStyle(Color.sanInkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sanSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.sanHairline, lineWidth: 0.5))
    }

    // MARK: Тост «+N»

    @ViewBuilder private var rewardToast: some View {
        if let reward = bonus.lastReward {
            Text("+\(reward) бонусов 🎉")
                .font(.golos(15, .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(Color.sanOpen, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task {
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    bonus.clearRewardFlag()
                }
        }
    }

    // MARK: Помощники

    private static func subtitle(_ r: Reward) -> String {
        switch r.id {
        case "disc10":  return "Действует в любом заведении Ayant"
        case "coffee":  return "У партнёров сети"
        case "dessert": return "У партнёров сети"
        case "vip":     return "Ранний доступ к новинкам"
        default:        return "\(r.cost) бонусов"
        }
    }

    private static func plural(_ n: Int) -> String {
        let n10 = n % 10, n100 = n % 100
        if n10 == 1 && n100 != 11 { return "бонус" }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return "бонуса" }
        return "бонусов"
    }
}

#Preview {
    BonusHubView()
        .environmentObject(BonusEngine())
        .environmentObject(CouponStore())
        .environmentObject(AppStore())
        .tint(.sanAccent)
}
