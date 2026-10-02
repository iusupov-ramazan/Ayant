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
    @State private var showMatch3 = false
    @State private var show2048 = false
    @State private var openedCard: VenuePointsCard?
    @State private var openedStampCard: LoyaltyCard?
    /// Показать итог захода в игру после её закрытия. Само число — живое
    /// `bonus.sessionEarned`: то, что зачислил СЕРВЕР за эту партию, а не то,
    /// что насчитала игра, — урезанный ответ, пришедший уже после закрытия,
    /// уменьшает его на экране.
    @State private var sessionToast = false
    @State private var showSyncInfo = false

    /// Открыта ли какая-нибудь игра: пока да, тосты хаба молчат — игра
    /// показывает начисления сама.
    private var gameOpen: Bool { showSnake || showTetris || showMatch3 || show2048 }

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
            // Дополнительную карту заведение удалило или выключило — её больше
            // не показываем: собрать её всё равно нельзя (сервер ответит
            // `card_not_found`).
            if let venue = venuesByID[card.venueID], !venue.offersStampCard(card.cardID) { return false }
            return card.stamps > 0 || (venuesByID[card.venueID]?.stampsActive ?? false)
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

    /// Сверху вниз — от «сколько у меня» к «на что потратить» и «где взять»:
    /// баланс бонусов → магазин купонов (лентой) → игры → баллы и карты
    /// заведений (отдельная валюта — в самом низу).
    ///
    /// Раньше экран открывался большой картой заведения с «320 баллов», а
    /// бонусы жили в маленькой капсуле в углу — и люди принимали баллы
    /// заведения за свои бонусы. Теперь бонусы — первая и самая крупная
    /// цифра, а баллы заведений — отдельный раздел со своим заголовком.
    private var hubContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    headerRow
                    if ReleaseFlags.globalBonusWallet {
                        // Новый email-аккаунт без подтверждения: сервер не начисляет и не
                        // продаёт (email_not_verified) — говорим об этом над балансом.
                        EmailVerificationBanner()
                        balanceCard { withAnimation { proxy.scrollTo(Self.gamesAnchor, anchor: .top) } }
                        BonusStoreSection()
                        gamesSection.id(Self.gamesAnchor)
                        venuePointsSection
                    } else {
                        // Без глобального кошелька экран — баллы и карты
                        // заведений и строка в купоны.
                        venuePointsSection
                        couponsSection
                    }
                }
                .padding(.horizontal, SanMetrics.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .sanScreenEnter()
            }
        }
        .sanScreenBackground()
        .sanStatusBarCap()
        .toolbar(.hidden, for: .navigationBar)
        .task { if ReleaseFlags.globalBonusWallet { await coupons.loadRewards() } }
        // Вчерашний «лимит на сегодня» снимаем сразу, а приветственный бонус
        // приглашённого забираем при входе на экран (не чаще раза в минуту).
        .onAppear {
            guard ReleaseFlags.globalBonusWallet else { return }
            bonus.refreshDay()
            bonus.refreshGrantsIfStale()
        }
        // Потянуть вниз — свежая витрина: заведение могло выпустить купон,
        // модерация — одобрить, остаток — кончиться.
        .refreshable {
            guard ReleaseFlags.globalBonusWallet else { return }
            await coupons.loadShopOffers()
            await coupons.loadRewards()
        }
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
            .animation(.snappy, value: toastKey)
            .guestAlert(isPresented: $showGuestAlert, message: GuestGate.game)
            .onChange(of: gameOpen) { _, open in gameSession(open: open) }
            .alert("Бонусы отправляются", isPresented: $showSyncInfo) {
                Button("Повторить") { bonus.retryPending() }
                Button("OK", role: .cancel) {}
            } message: {
                Text(syncInfoMessage)
            }
    }

    /// Почему «+N отправляются». Без паники: бонусы не пропадают, повтор —
    /// наша забота. Только если сервер не принимает сборку, помочь может
    /// лишь обновление — так и говорим.
    private var syncInfoMessage: LocalizedStringKey {
        switch bonus.syncProblem {
        case .appUpdateNeeded:
            return "Обновите приложение, чтобы бонусы дошли. Заработанное не пропадёт."
        case .signInRequired:
            return "Войдите в аккаунт, чтобы бонусы дошли. Заработанное не пропадёт."
        case .network, nil:
            return "Бонусы ещё не дошли до сервера. Мы повторим отправку сами — заработанное не пропадёт."
        }
    }

    // MARK: Шапка

    private static let gamesAnchor = "games"

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Бонусы")
                .sanEditorialTitle(44)
                .foregroundStyle(Color.sanInk)
            Text(ReleaseFlags.globalBonusWallet
                 ? "Копите в играх — меняйте на купоны заведений"
                 : "Баллы САН в каждом заведении")
                .font(.golos(14)).foregroundStyle(Color.sanInkSoft)
                .padding(.top, 9)
        }
    }

    /// Баланс бонусов — главная цифра экрана. Отсюда же — «Мои купоны» и
    /// «Как заработать» (прокрутка к играм).
    private func balanceCard(onEarn: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ваши бонусы")
                        .font(.golos(13.5, .semibold)).foregroundStyle(.white.opacity(0.9))
                    Text(verbatim: bonus.balance.sanThousands)
                        .sanText(46, .heavy, tracking: -2)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: bonus.balance)
                    if bonus.syncingAmount > 0 {
                        // Заработанное без сети — видно, но ещё не потратить.
                        // Нажатие объясняет, что это, и повторяет отправку.
                        Button {
                            bonus.retryPending()
                            showSyncInfo = true
                        } label: {
                            Label("+\(bonus.syncingAmount) отправляются", systemImage: "arrow.triangle.2.circlepath")
                                .font(.golos(12, .semibold)).foregroundStyle(.white.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text(syncInfoMessage))
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Text("Общий счёт приложения: меняйте на купоны заведений-партнёров в магазине ниже.")
                .font(.golos(12.5)).foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            // Крупный шрифт не помещает две плашки в строку — тогда столбиком.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { balanceChips(onEarn: onEarn) }
                VStack(alignment: .leading, spacing: 8) { balanceChips(onEarn: onEarn) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.sanAccentGradient,
                    in: RoundedRectangle(cornerRadius: SanRadius.hero, style: .continuous))
        .sanShadow(.hero)
    }

    @ViewBuilder
    private func balanceChips(onEarn: @escaping () -> Void) -> some View {
        NavigationLink { MyCouponsView() } label: {
            balanceChip(coupons.activeCount > 0 ? "Мои купоны · \(coupons.activeCount)" : "Мои купоны",
                        icon: "ticket.fill")
        }
        .buttonStyle(.sanPress(0.95))
        Button(action: onEarn) { balanceChip("Как заработать", icon: "gamecontroller.fill") }
            .buttonStyle(.sanPress(0.95))
    }

    private func balanceChip(_ title: LocalizedStringKey, icon: String) -> some View {
        Label { Text(title) } icon: { Image(systemName: icon) }
            .font(.golos(13, .bold)).foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.white.opacity(0.2), in: Capsule())
    }

    // MARK: Баллы и карты заведений

    /// Карусель карт заведений — отдельным разделом и с объяснением: это не
    /// бонусы, а счёт в конкретном заведении, и потратить его можно только там.
    private var venuePointsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Баллы и карты заведений")
                    .font(.golos(20, .heavy)).tracking(-0.5)
                    .foregroundStyle(Color.sanInk)
                Text("Свои в каждом заведении: начисляет заведение за покупки, тратятся только там же.")
                    .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            // Карусель показывает не все карты — ссылки на полные списки.
            HStack(spacing: 10) {
                listLink("Все баллы", "star.circle.fill") { VenuePointsListView() }
                listLink("Все карты", "creditcard.fill") { LoyaltyView() }
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
        }
    }

    private var emptyPointsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Здесь появятся ваши баллы")
                .font(.golos(16, .bold)).foregroundStyle(Color.sanInk)
            Text("Показывайте свой QR на кассе в заведениях с баллами САН — карта заведения появится здесь после первого начисления.")
                .font(.golos(13)).foregroundStyle(Color.sanInkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .sanCard(padding: 0, radius: SanRadius.hero)
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

    // MARK: Игры

    /// Четыре игры сеткой 2×2 — все видны сразу, без прокрутки через список.
    private var gamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Играйте и копите бонусы")
                    .font(.golos(20, .heavy)).tracking(-0.5)
                    .foregroundStyle(Color.sanInk)
                Spacer(minLength: 8)
                // Потолка больше нет, поэтому и обещать «сегодня ещё N» нечего.
                // Показываем заработанное за день: это единственная цифра,
                // которая здесь что-то значит, — и молчим, пока она нулевая.
                if bonus.gameEarnedToday > 0 {
                    Text("+\(bonus.gameEarnedToday) сегодня в играх")
                        .font(.golos(11.5, .semibold))
                        .foregroundStyle(Color.sanInkSoft)
                        .fixedSize()
                }
            }
            // Игры начисляют бонусы в кошелёк аккаунта, поэтому гостю закрыты —
            // иначе он «зарабатывает» в запись, которая исчезнет вместе с выходом.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
            Button { if session.isGuest { showGuestAlert = true } else { showSnake = true } } label: {
                gameTile(emoji: "🐍", title: "Змейка",
                         subtitle: capped("\(bonus.gameRates.applesPerBonus) 🍎 = 1 бонус", .snake),
                         gradient: [Color(hex: 0x1FBF75), Color(hex: 0x0E9E86)])
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showSnake) { SnakeGameView() }

            Button { if session.isGuest { showGuestAlert = true } else { showTetris = true } } label: {
                gameTile(emoji: "🧱", title: "Блоки",
                         subtitle: capped("\(bonus.gameRates.linesPerBonus) линий = 1 бонус", .tetris),
                         gradient: [Color(hex: 0x7C6BE8), Color(hex: 0xB39CF0)])
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showTetris) { TetrisGameView() }

            Button { if session.isGuest { showGuestAlert = true } else { showMatch3 = true } } label: {
                gameTile(icon: GemView(kind: .ruby, power: .none).padding(6),
                         title: "Diamond",
                         // Партия бесконечная — дневной потолок виден ещё до входа.
                         subtitle: capped("\(bonus.gameRates.matchesPerBonus) совпадений = 1 бонус", .diamond),
                         gradient: [Color(hex: 0xF2A03D), Color(hex: 0xE8556B)])
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showMatch3) { Match3GameView() }

            Button { if session.isGuest { showGuestAlert = true } else { show2048 = true } } label: {
                // Иконка — само число: у игры нет ни эмодзи, ни фишки, по
                // которой её узнают, узнают её именно по «2048».
                // Фиксированный кегль: иконка — плашка 48×48, крупный шрифт
                // выдавил бы «2048» за её края.
                gameTile(icon: Text("2048").font(.golosFixed(12, .heavy)).tracking(-0.4)
                            .foregroundStyle(.white),
                         title: "2048",
                         subtitle: capped("Плитка от \(bonus.gameRates.game2048FirstTile) = 1 бонус", .game2048),
                         gradient: [Color(hex: 0xC92E76), Color(hex: 0x8B3BC9)])
            }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $show2048) { Game2048View() }
            }
        }
    }

    /// Курс игры и, если есть, дневной лимит (Remote Config) — второй
    /// строкой: упереться в невидимый лимит значит решить, что игра сломалась.
    private func capped(_ rate: LocalizedStringKey, _ game: BonusGame) -> Text {
        guard bonus.earnsBonus(game) else { return Text(rate) + Text(verbatim: "\n") + Text("сейчас без бонусов") }
        // Сервер сегодня эту игру больше не зачисляет (её потолок или общий) —
        // «до 30 в день» обещало бы то, чего не будет.
        if bonus.remainingToday(game) == 0 {
            return Text(rate) + Text(verbatim: "\n") + Text("бонусы на сегодня собраны")
        }
        guard let cap = bonus.bonusDailyCaps[game] else { return Text(rate) }
        return Text(rate) + Text(verbatim: "\n") + Text("до \(cap) в день")
    }

    private func gameTile(emoji: String, title: LocalizedStringKey, subtitle: Text,
                          gradient: [Color]) -> some View {
        gameTile(icon: Text(emoji).font(.system(size: 22)),
                 title: title, subtitle: subtitle, gradient: gradient)
    }

    /// Та же плитка, но со своей картинкой вместо эмодзи: «Три в ряд» показывает
    /// настоящий камень с поля, а не символ из шрифта.
    private func gameTile<Icon: View>(icon: Icon, title: LocalizedStringKey,
                                      subtitle: Text,
                                      gradient: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 48, height: 48)
                .overlay(icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.golos(15.5, .bold)).foregroundStyle(Color.sanInk)
                // Без потолка строк: «до 30 в день» второй строкой на крупном
                // шрифте обрезалось — а это и есть то, что надо прочитать.
                subtitle.font(.golos(12, .medium)).foregroundStyle(Color.sanInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sanSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.sanHairline, lineWidth: 0.5))
    }

    // MARK: Тост «+N»

    /// Что сейчас показывает тост — для анимации появления/смены.
    private var toastKey: String {
        if gameOpen { return "" }
        if let n = bonus.earnNotice { return "cap-\(n.id)" }
        if sessionToast, bonus.sessionEarned > 0 { return "session-\(bonus.sessionEarned)" }
        if let r = bonus.lastReward { return "reward-\(r)" }
        return ""
    }

    /// Порядок важности: урезанное сервером начисление (честно сказать, что
    /// упёрлись в лимит) → итог захода в игру → разовая награда (время в
    /// приложении). Пока открыта игра, хаб молчит: начисления видны в ней.
    @ViewBuilder private var rewardToast: some View {
        if gameOpen {
            EmptyView()
        } else if let notice = bonus.earnNotice {
            toastPill(Text("Начислено \(notice.granted) из \(notice.requested) — дневной лимит бонусов"),
                      color: Color(hex: 0xC26A00))
                .task(id: notice.id) {
                    AccessibilityNotification.Announcement(
                        LF("Начислено %lld из %lld — дневной лимит бонусов", notice.granted, notice.requested)).post()
                    try? await Task.sleep(nanoseconds: 2_600_000_000)
                    bonus.clearEarnNotice()
                }
        } else if sessionToast, bonus.sessionEarned > 0 {
            toastPill(Text("+\(bonus.sessionEarned) бонусов") + Text(verbatim: " 🎉"), color: .sanOpen)
                .task {
                    announceBonus(bonus.sessionEarned)
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    sessionToast = false
                }
        } else if let reward = bonus.lastReward {
            toastPill(Text("+\(reward) бонусов") + Text(verbatim: " 🎉"), color: .sanOpen)
                .task(id: reward) {
                    announceBonus(reward)
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    bonus.clearRewardFlag()
                }
        }
    }

    private func toastPill(_ text: Text, color: Color) -> some View {
        text
            .font(.golos(15, .bold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(color, in: Capsule())
            .padding(.horizontal, SanMetrics.screenPadding)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Открыли игру — новый отсчёт в движке; закрыли — показываем итог
    /// захода. Итог считает движок по ответам сервера (`sessionEarned`), а не
    /// по разнице счётчиков: после «Начислено 3 из 10» тост «+10 🎉» был бы
    /// неправдой, а смена суток посреди игры больше не теряет итог.
    private func gameSession(open: Bool) {
        bonus.clearRewardFlag()
        if open {
            bonus.beginGameSession()
            sessionToast = false
        } else {
            sessionToast = bonus.sessionEarned > 0
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
