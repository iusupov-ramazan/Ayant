import SwiftUI
import AyantDomain
import AyantFeatures

/// Вкладка «Бонусы» (рефреш): акцент на кошельке и наградах, игры — ниже и тише.
/// Обёртка URL+название для .sheet(item:).
struct ShareURL: Identifiable { let id = UUID(); let url: URL; let title: String }

/// «Бонусы» (SCREENS.md G6) — один дом для всех трёх валют лояльности:
/// карусель карт «Баллы САН» и штампов, и глобальные бонусы (нарочно
/// подчинённые: их почти невозможно накопить, и это by design).
struct BonusHubView: View {
    @EnvironmentObject private var bonus: BonusEngine
    @EnvironmentObject private var coupons: CouponStore
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var points: PointsStore
    @EnvironmentObject private var loyalty: LoyaltyStore
    @EnvironmentObject private var session: SessionStore

    @State private var showGuestAlert = false
    @State private var showSnake = false
    @State private var showTetris = false
    @State private var justClaimed: Coupon?
    @State private var pendingReward: Reward?
    @State private var pendingGift: Reward?
    @State private var giftShare: ShareURL?
    @State private var openedCard: VenuePointsCard?
    @State private var openedStampCard: LoyaltyCard?

    /// Заведения по id — картам нужны градиент, категория и конфиг наград.
    private var venuesByID: [String: Venue] {
        Dictionary(store.venues.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var pointsCards: [VenuePointsCard] { points.state.sortedCards }
    /// Карты штампов, которым есть что показать: со штампами или заведения,
    /// где штампы — действующая механика. Пустые карты заведений, которые
    /// перешли на баллы, остаются в «Все карты», но карусель не засоряют.
    private var stampCards: [LoyaltyCard] {
        loyalty.cards.filter { card in
            card.stamps > 0 || (venuesByID[card.venueID]?.stampsActive ?? false)
        }
    }
    /// Порядок карусели: сначала баллы (главное), потом штампы.
    private var walletPages: [WalletPage] {
        pointsCards.map(WalletPage.points) + stampCards.map(WalletPage.stamps)
    }

    var body: some View {
        NavigationStack {
            walletFlow(hubContent)
        }
    }

    private var hubContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                headerRow
                if walletPages.isEmpty {
                    emptyPointsCard
                } else {
                    WalletCarousel(pages: walletPages, venues: venuesByID,
                                   onOpenPoints: { openedCard = $0 },
                                   onOpenStamps: { openedStampCard = $0 })
                        // Карусель на всю ширину экрана — отступ возвращает
                        // `contentMargins` внутри, чтобы следующая карта выглядывала.
                        .padding(.horizontal, -SanMetrics.screenPadding)
                }
                // Глобальный кошелёк (награды, подарки, игры) выключен на
                // релиз: он локальный и без записи в Firestore. Без него
                // хаб — карусель баллов и штампов и строка в купоны.
                if ReleaseFlags.globalBonusWallet {
                    rewardsSection
                    gamesSection
                } else {
                    couponsSection
                }
            }
            .padding(.horizontal, SanMetrics.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .sanScreenEnter()
        }
        .sanScreenBackground()
        .sanStatusBarCap()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $openedCard) { card in
            if let venue = venuesByID[card.venueID] {
                VenuePointsScreen(venue: venue)
            } else {
                VenuePointsListView()
            }
        }
        // Карта штампов ведёт туда же, куда и баннер на странице заведения;
        // если заведения нет в каталоге — в общий список карт.
        .navigationDestination(item: $openedStampCard) { card in
            if let venue = venuesByID[card.venueID] {
                VenueLoyaltyScreen(venue: venue)
            } else {
                LoyaltyView()
            }
        }
    }

    /// Тост, алерты и листы глобального кошелька — только с включённым
    /// флагом: без него ни одно из этих состояний не наступает.
    @ViewBuilder
    private func walletFlow<Content: View>(_ content: Content) -> some View {
        if ReleaseFlags.globalBonusWallet {
            walletModals(content)
        } else {
            content
        }
    }

    private func walletModals<Content: View>(_ content: Content) -> some View {
        content
            .overlay(alignment: .top) { rewardToast }
            .guestAlert(isPresented: $showGuestAlert, message: GuestGate.game)
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

    // MARK: Шапка

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Бонусы")
                    .sanEditorialTitle(44)
                    .foregroundStyle(Color.sanInk)
                Text("Баллы САН в каждом заведении")
                    .font(.golos(14)).foregroundStyle(Color.sanInkSoft)
                    .padding(.top, 9)
            }
            Spacer(minLength: 8)
            // Глобальный кошелёк BonusEngine — визуально подчинённый: он
            // зарабатывается почти в ноль и не должен спорить с баллами САН.
            // Скрыт вместе с кошельком (`ReleaseFlags.globalBonusWallet`).
            if ReleaseFlags.globalBonusWallet {
                NavigationLink { MyCouponsView() } label: {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("БОНУСЫ")
                            .font(.golos(10.5, .heavy)).tracking(0.4)
                            .foregroundStyle(Color(hex: 0x9A9188))
                        Text("\(bonus.balance)")
                            .font(.golos(16, .heavy)).tracking(-0.5)
                            .foregroundStyle(Color.sanInk)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: bonus.balance)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.sanSurface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.sanHairline, lineWidth: 0.5))
                }
                .buttonStyle(.sanPress(0.94))
            }
        }
    }

    // MARK: Купоны без глобального кошелька

    /// «Мои купоны» + ссылки на полные списки. Раньше в купоны вели только
    /// капсула «БОНУСЫ» и заголовок наград — оба спрятаны вместе с кошельком,
    /// а купоны на акции заведений выдаются и без него.
    private var couponsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink { MyCouponsView() } label: {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(LinearGradient.sanAccentGradient)
                        .frame(width: 46, height: 46)
                        .overlay(Image(systemName: "ticket.fill")
                            .font(.system(size: 19, weight: .semibold)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Мои купоны").font(.golos(14.5, .bold)).tracking(-0.2)
                            .foregroundStyle(Color.sanInk)
                        Text(coupons.activeCount > 0
                             ? "Активных: \(coupons.activeCount)"
                             : "Купоны на акции заведений")
                            .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x9A9188))
                }
                .padding(15)
                .sanCard(padding: 0, radius: SanRadius.card)
            }
            .buttonStyle(.sanPress(0.97))
            // Карусель показывает не все карты штампов — ссылки на полные списки остаются.
            HStack(spacing: 10) {
                listLink("Все баллы", "star.circle.fill") { VenuePointsListView() }
                listLink("Все карты", "creditcard.fill") { LoyaltyView() }
            }
            .padding(.top, 2)
        }
    }

    private var emptyPointsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Здесь появятся ваши баллы")
                .font(.golos(16, .bold)).foregroundStyle(Color.sanInk)
            Text("Показывайте свой QR на кассе в заведениях с баллами САН — карта заведения появится в кошельке после первого начисления.")
                .font(.golos(13)).foregroundStyle(Color.sanInkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .sanCard(padding: 0, radius: SanRadius.hero)
    }

    // MARK: Потратить бонусы

    private var rewardsSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Награды")
                    .textCase(.uppercase)
                    .sanEyebrowText()
                    .foregroundStyle(Color(hex: 0x9A9188))
                Spacer()
                NavigationLink { MyCouponsView() } label: {
                    Text(coupons.activeCount > 0 ? "Мои купоны · \(coupons.activeCount)" : "Мои купоны")
                        .font(.golos(12.5, .bold))
                        // Акцент мелким текстом — только контрастный вариант.
                        .foregroundStyle(Color.sanAccentText)
                }
                .buttonStyle(.sanPress(0.94))
            }
            ForEach(Array(CouponStore.catalog.enumerated()), id: \.element.id) { index, reward in
                rewardRow(reward).sanRise(index, stagger: 0.07, duration: 0.5)
            }
            // Ссылки на полные списки остаются — карусель показывает не все карты штампов.
            HStack(spacing: 10) {
                listLink("Все баллы", "star.circle.fill") { VenuePointsListView() }
                listLink("Все карты", "creditcard.fill") { LoyaltyView() }
            }
            .padding(.top, 2)
        }
    }

    private func listLink<Destination: View>(_ title: LocalizedStringKey, _ icon: String,
                                             @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(title).font(.golos(13.5, .bold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.sanInk)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.sanSurfaceMuted, in: RoundedRectangle(cornerRadius: SanRadius.tile, style: .continuous))
        }
        .buttonStyle(.sanPress(0.97))
    }

    private func rewardRow(_ reward: Reward) -> some View {
        let affordable = bonus.balance >= reward.cost
        return HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(LinearGradient.sanAccentGradient)
                .frame(width: 46, height: 46)
                .overlay(Image(systemName: "star.fill")
                    .font(.system(size: 19, weight: .semibold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text(L(reward.title)).font(.golos(14.5, .bold)).tracking(-0.2)
                    .foregroundStyle(Color.sanInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(reward.cost) бонусов").font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
            }
            Spacer(minLength: 8)
            Menu {
                Button { pendingReward = reward } label: { Label("Обменять себе", systemImage: "ticket") }
                Button { pendingGift = reward } label: { Label("Подарить другу", systemImage: "gift") }
            } label: {
                Text(affordable ? "Обменять" : "Не хватает")
                    .font(.golos(13, .bold))
                    .foregroundStyle(affordable ? Color.white : Color(hex: 0x9A9188))
                    .padding(.horizontal, 15).padding(.vertical, 10)
                    .background(affordable ? AnyShapeStyle(LinearGradient.sanAccentGradient)
                                           : AnyShapeStyle(Color.sanSurfaceMuted),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(!affordable)
        }
        .padding(15)
        .opacity(affordable ? 1 : 0.55)
        .sanCard(padding: 0, radius: SanRadius.card)
    }

    // MARK: Игры (тише, ниже)

    private var gamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SanSectionHeader("Играй и копи бонусы")
                SanHairline().frame(maxWidth: .infinity)
            }
            // Игры начисляют бонусы в кошелёк аккаунта, поэтому гостю закрыты —
            // иначе он «зарабатывает» в запись, которая исчезнет вместе с выходом.
            Button { if session.isGuest { showGuestAlert = true } else { showSnake = true } } label: {
                gameTile(emoji: "🐍", title: "Змейка", subtitle: "+1 / яблоко",
                         gradient: [Color(hex: 0x1FBF75), Color(hex: 0x0E9E86)])
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showSnake) { SnakeGameView() }

            Button { if session.isGuest { showGuestAlert = true } else { showTetris = true } } label: {
                gameTile(emoji: "🧱", title: "Тетрис",
                         subtitle: "+\(Tetris.bonusPerLine) / линия",
                         gradient: [Color(hex: 0x7C6BE8), Color(hex: 0xB39CF0)])
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showTetris) { TetrisGameView() }
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

}

#Preview {
    BonusHubView()
        .environmentObject(AyantStores.bonus())
        .environmentObject(AyantStores.coupons())
        .environmentObject(AyantStores.app())
        .environmentObject(AyantStores.points())
        .environmentObject(AyantStores.loyalty())
        .tint(.sanAccent)
}
