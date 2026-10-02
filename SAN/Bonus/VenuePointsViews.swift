import SwiftUI
import AyantDomain
import AyantFeatures

// Экраны «Баллы САН». Читают одно значение `points.state` и отправляют намерения —
// собственного состояния загрузки/ошибки у вьюх нет.
//
// Циклов `Task.sleep(4s)` здесь больше нет: подписка на живой поток заводится
// один раз в `SANApp` (`.observe`), а обновления приходят snapshot-листенером.

// MARK: - Экран «Баллы САН» (список карт из вкладки Бонусы)

struct VenuePointsListView: View {
    @EnvironmentObject private var points: PointsStore

    var body: some View {
        Group {
            switch points.state.cards {
            case .idle, .loading:
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failed(let error):
                ContentUnavailableView(
                    "Не удалось загрузить баллы",
                    systemImage: "exclamationmark.triangle",
                    description: Text(PointsMessages.text(for: error)))

            case .loaded(let cards) where cards.isEmpty:
                ContentUnavailableView(
                    "Пока нет баллов",
                    systemImage: "star.circle",
                    description: Text("Показывайте свой QR при оплате в заведениях с баллами САН — за визиты копятся баллы, которые можно потратить на награды этого заведения. Награды — на странице заведения."))

            case .loaded:
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(points.state.sortedCards) {
                            VenuePointsCardView(card: $0, userID: points.state.userID)
                        }
                    }
                    .padding(16)
                }
                .sanScreenBackground()
            }
        }
        .navigationTitle("Баллы САН")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Карта баллов (баланс + QR начисления)

struct VenuePointsCardView: View {
    let card: VenuePointsCard
    let userID: String
    @State private var showQR = false

    private var earnCode: String { GuestQR.code(userID: userID) }
    private var canScan: Bool { !userID.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.92))
                    .frame(width: 46, height: 46)
                    .overlay(
                        Text(String(card.venueName.prefix(1)).uppercased())
                            .font(.golos(20, .heavy)).foregroundStyle(Color.sanAccentDeep))
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.venueName).font(.golos(20, .heavy)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("Ваши баллы").font(.golos(13, .medium)).foregroundStyle(.white.opacity(0.92))
                }
                Spacer(minLength: 4)
                Text(card.balance.sanThousands)
                    .font(.golos(22, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.black.opacity(0.22), in: Capsule())
                    // Баланс меняется сам, когда сотрудник просканировал QR.
                    .contentTransition(.numericText())
                    .animation(.snappy, value: card.balance)
            }
            if showQR && canScan {
                VStack(spacing: 8) {
                    QRCodeView(text: earnCode, size: 168)
                        .accessibilityLabel("QR-код для сотрудника")
                        .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16))
                    Text("Покажите сотруднику — он начислит баллы")
                        .font(.golos(12, .medium)).foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            Button { withAnimation(.snappy) { showQR.toggle() } } label: {
                Label(showQR ? "Скрыть QR" : "Показать QR для начисления", systemImage: "qrcode")
                    .font(.golos(15, .bold)).foregroundStyle(Color.sanAccentDeep)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain).disabled(!canScan)
            if !canScan {
                Text("Войдите в аккаунт, чтобы копить баллы.")
                    .font(.golos(12, .medium)).foregroundStyle(.white.opacity(0.92))
            }
        }
        .padding(20)
        .background(
            LinearGradient.sanAccentGradient,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.sanAccent.opacity(0.28), radius: 22, y: 12)
    }
}

// MARK: - Экран баллов конкретного заведения (со страницы заведения)

struct VenuePointsScreen: View {
    let venue: Venue
    @EnvironmentObject private var points: PointsStore
    @Environment(\.dismiss) private var dismiss
    @State private var pendingReward: PointsReward?

    private var activeRewards: [PointsReward] { venue.pointsRewards.filter { $0.active } }

    var body: some View {
        let balance = points.state.balance(for: venue.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                let card = points.state.card(for: venue.id)
                    ?? VenuePointsCard(venueID: venue.id, venueName: venue.name)
                VenuePointsCardView(card: card, userID: points.state.userID)

                if !activeRewards.isEmpty { rewardsSection(balance: balance) }
                historySection
                explainer
            }
            .padding(16)
        }
        .refreshable { await reloadHistoryAndSettle() }
        .sanNavBar("Баллы САН") { dismiss() }
        .sanScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { reloadHistory() }
        .sheet(item: $pendingReward) { reward in
            // Баланс лист читает сам из стора — живой, а не снимок на момент открытия.
            RedeemSheet(venue: venue, reward: reward, userID: points.state.userID)
                .environmentObject(points)
        }
    }

    // MARK: История

    private var history: LoadState<[PointsLedgerEntry]> { points.state.history(for: venue.id) }

    private func reloadHistory() { points.send(.loadHistory(venueID: venue.id)) }

    /// См. `PointsHistoryView.reloadAndSettle` — стор не сообщает о завершении.
    private func reloadHistoryAndSettle() async {
        reloadHistory()
        try? await Task.sleep(for: .milliseconds(600))
    }

    /// Пять последних операций и ссылка на полный журнал.
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("История").font(.golos(17, .bold)).foregroundStyle(Color.sanInk)
                Spacer(minLength: 8)
                if let entries = history.value, !entries.isEmpty {
                    NavigationLink {
                        PointsHistoryView(venue: venue)
                    } label: {
                        HStack(spacing: 3) {
                            Text("Вся история")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .font(.golos(14, .semibold))
                        .foregroundStyle(Color.sanAccentText)
                    }
                    .buttonStyle(.plain)
                }
            }
            switch history {
            case .idle, .loading:
                PointsHistorySkeleton(rows: 3)
            case .failed(let error):
                PointsHistoryFailed(error: error) { reloadHistory() }
            case .loaded(let entries) where entries.isEmpty:
                PointsHistoryEmpty()
            case .loaded(let entries):
                PointsLedgerCard(entries: Array(entries.prefix(5)), venue: venue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rewardsSection(balance: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Награды").font(.golos(17, .bold)).foregroundStyle(Color.sanInk)
            ForEach(activeRewards) { reward in
                let affordable = balance >= reward.cost
                Button { pendingReward = reward } label: {
                    HStack(spacing: 12) {
                        Text(reward.type == "money" ? "💸" : "🎁").font(.system(size: 22))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reward.title).font(.golos(15, .semibold)).foregroundStyle(Color.sanInk)
                                .lineLimit(2)
                            Text(reward.type == "money" ? "Скидка баллами · от \(reward.cost) б."
                                                        : "\(reward.cost) баллов")
                                .font(.golos(12, .medium)).foregroundStyle(Color.sanInkSoft)
                            // Недоступная награда — не только замок: сколько не хватает.
                            if !affordable {
                                Text("Не хватает \(reward.cost - balance) баллов.")
                                    .font(.golos(12, .semibold)).foregroundStyle(Color.sanAccentText)
                            }
                        }
                        Spacer()
                        Image(systemName: affordable ? "chevron.right" : "lock.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(affordable ? Color.sanInkSoft : Color.sanInkSoft.opacity(0.5))
                    }
                    .padding(12)
                    .sanCard(padding: 0)
                    .opacity(affordable ? 1 : 0.55)
                }
                .buttonStyle(.plain)
                .disabled(!affordable)
                .accessibilityElement(children: .combine)
                .accessibilityHint(affordable ? Text("Открыть награду")
                                              : Text("Не хватает \(reward.cost - balance) баллов."))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Как это работает", systemImage: "info.circle")
                .font(.golos(17, .bold)).foregroundStyle(Color.sanInk)
            Text("Показывайте QR при оплате — сотрудник сканирует его и начисляет баллы. Накопленные баллы тратьте на награды из списка выше.")
                .font(.golos(15, .regular)).foregroundStyle(Color.sanInkSoft)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(houseRules, id: \.self) { rule in
                Text(rule)
                    .font(.golos(14, .regular)).foregroundStyle(Color.sanInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sanCard(padding: 0)
    }

    /// Два правила заведения, которые гость иначе не узнаёт НИОТКУДА: почему
    /// второе сканирование подряд ничего не дало и что баллы не вечные.
    ///
    /// Про кулдаун сейчас знает только сотрудник — сканер показывает ему
    /// «этому гостю уже начисляли недавно», а гость видит просто ничего и
    /// решает, что приложение сломалось.
    ///
    /// Цифры берутся у заведения, а не зашиты: у каждого свой кулдаун и свой
    /// срок сгорания, и расхождение подписи с реальным правилом хуже её
    /// отсутствия.
    private var houseRules: [String] {
        var rules: [String] = []

        let cooldown = PointsMath.effectiveCooldownMinutes(venue.earnCooldownMinutes)
        if cooldown > 0 {
            // Склонение («минуту / минуты / минут») — плюральными формами
            // ключа в каталоге, а не руками: иначе на английском оставалось
            // русское слово.
            rules.append(LF("Начисляют не чаще раза в %lld минут: показать код второй раз подряд не получится.", cooldown))
        }

        // Ноль здесь значит «не настроено», а не «не сгорают»: у поля есть
        // серверный дефолт, и гостю нужно видеть именно его.
        let months = venue.pointsExpiryMonths > 0 ? venue.pointsExpiryMonths : PointsMath.defaultExpiryMonths
        // Плюральные формы ключа в каталоге —
        // «месяца / месяцев / месяцев», а не «месяц / месяца / месяцев»: после
        // предлога «после» слово идёт в родительном падеже — «после 1 месяца»,
        // «после 2 месяцев», «после 5 месяцев». Выглядит как опечатка, но
        // обычный счётный ряд здесь дал бы «после 1 месяц».
        rules.append(LF("Баллы сгорают после %lld месяцев без начислений и трат.", months))
        return rules
    }
}

// MARK: - Лист списания баллов на награду

/// «Награда»: подтверждение списания в фирменном стиле.
///
/// Машина состояний прежняя — `points.state.redeem` (`idle / working / done /
/// failed`), `send(.redeem)` и `send(.dismissRedeem)`; лист только рисует фазу.
/// Баланс читается из стора живьём: если сотрудник просканировал QR, пока лист
/// открыт, «Останется» пересчитается само.
///
/// В режиме «гасит сотрудник» ответа сервера у гостя нет — списание делает
/// сканер хоста. Поэтому лист следит за балансом карты: упал не меньше чем на
/// цену награды, пока показан QR, — значит, сотрудник списал, и вместо QR
/// показываем чек. «Останется» в этом режиме не показываем: после списания
/// баланс уже уменьшен, и плитка вычла бы цену второй раз (уходила в минус).
struct RedeemSheet: View {
    let venue: Venue
    let reward: PointsReward
    let userID: String
    @EnvironmentObject private var points: PointsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Сколько списать (только для `money`-награды); шаг 10.
    @State private var spend: Int
    @State private var waitingPulse = false
    /// Одноразовая метка QR списания: новая на каждое открытие листа и стабильна,
    /// пока лист показывает этот QR, — сервер отличает повторный скан того же
    /// кода от новой попытки. Новая и при смене суммы: сервер воспроизводит
    /// списание по nonce, и QR «…:200» с nonce уже отсканированного «…:100»
    /// вернул бы те 100 вместо списания 200.
    @State private var nonce = RedeemQR.newNonce()
    /// Суммы, чьи QR лист показывал: списание сотрудником засчитываем, только
    /// если баланс упал ровно на одну из них (`StaffRedeemWatch`).
    @State private var shownAmounts: Set<Int>
    /// Баланс, от которого считаем «сотрудник списал» (растёт вместе с
    /// начислениями под открытым листом, но не опускается).
    @State private var staffBaseline: Int?
    /// Сколько списал сотрудник — когда списание замечено.
    @State private var staffRedeemed: Int?
    /// Одноразовый токен для QR сотрудника (`AYANT-RDT:`): QR больше не несёт
    /// uid гостя. Стор сам обновляет токен до истечения.
    @StateObject private var tokens: RedeemTokenStore

    private static let step = 10

    init(venue: Venue, reward: PointsReward, userID: String) {
        self.venue = venue; self.reward = reward; self.userID = userID
        _spend = State(initialValue: reward.cost)
        _shownAmounts = State(initialValue: [reward.cost])
        let coupons = AppConfig.makeCouponService()
        let auth = AppConfig.makeAuthService()
        _tokens = StateObject(wrappedValue: RedeemTokenStore { venueID, rewardID, points in
            guard let idToken = await auth.idToken(), !idToken.isEmpty else { throw AppError.unauthenticated }
            return try await coupons.issueRedeemToken(venueID: venueID, rewardId: rewardID,
                                                      pointsToSpend: points, idToken: idToken)
        })
    }

    // MARK: Производные

    private var isMoney: Bool { reward.type == "money" }
    private var balance: Int { points.state.balance(for: venue.id) }
    private var cost: Int { isMoney ? spend : reward.cost }
    private var remaining: Int { balance - cost }
    private var affordable: Bool { remaining >= 0 }
    private var staffScan: Bool { venue.redeemMode != "customerInitiated" }
    private var somOff: Int {
        PointsMath.somOff(reward: reward, cost: spend,
                          pointsMode: venue.pointsMode, cashbackPercent: venue.cashbackPercent) ?? 0
    }
    private var maxSpend: Int { max(reward.cost, balance) }
    private var phase: RedeemPhase { points.state.redeem }
    private var isWorking: Bool { phase.isWorking }
    private var isDone: Bool { if case .done = phase { return true }; return false }
    /// Старый QR с uid — только когда сервер ещё без токенов (`legacy`).
    private var legacyRedeemCode: String {
        RedeemQR.code(userID: userID, rewardID: reward.id,
                      points: isMoney ? spend : 0, nonce: nonce)
    }
    /// Списание сотрудником замечено — лист показывает чек.
    private var isStaffDone: Bool { staffRedeemed != nil }
    private var showsReceipt: Bool { isDone || isStaffDone }

    // MARK: Тело

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    if isMoney && !showsReceipt { amountPicker }
                    actionCard
                }
                .padding(.horizontal, SanMetrics.screenPadding)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            SanStickyFooter {
                Button(showsReceipt ? "Готово" : "Отмена", action: close)
                    .buttonStyle(SanPillButton(accent: showsReceipt))
            }
        }
        .sanScreenBackground()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Баланс мог измениться под открытым листом — выбранная сумма не должна
        // выйти за новые границы.
        .onChange(of: balance) { _, new in
            if !isStaffDone { spend = clamped(spend) }
            watchStaffRedeem(balance: new)
        }
        .onAppear {
            if staffBaseline == nil { staffBaseline = balance }
            if staffScan && !isStaffDone && !isDone { requestToken() }
        }
        // Сумма изменилась, пока показан QR сотрудника, — новый QR, новый
        // токен (у токена своя сумма) и новый nonce для старого формата.
        .onChange(of: spend) { _, new in
            guard staffScan, !isStaffDone, !isDone else { return }
            nonce = RedeemQR.newNonce()
            shownAmounts.insert(new)
            requestToken()
        }
        // Списание замечено — токен больше не нужен.
        .onChange(of: staffRedeemed) { _, new in if new != nil { tokens.stop() } }
        .onChange(of: phase) { _, new in
            if case .done = new { SanHaptics.success() }
        }
        // Смахнули лист — фаза не должна пережить его и всплыть в другом заведении.
        .onDisappear {
            points.send(.dismissRedeem)
            tokens.stop()
        }
    }

    private var header: some View {
        HStack {
            Text("Награда")
                .textCase(.uppercase)
                .font(.golos(12, .heavy)).tracking(1.0)
                .foregroundStyle(Color.sanInkSoft)
            Spacer(minLength: 8)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.sanInk)
                    .frame(width: 34, height: 34)
                    .background(Color.sanSurfaceMuted, in: Circle())
            }
            .buttonStyle(.sanPress(0.9))
            .accessibilityLabel("Закрыть")
        }
        .padding(.horizontal, SanMetrics.screenPadding)
        .padding(.top, 18).padding(.bottom, 10)
    }

    // MARK: Герой

    private var heroCard: some View {
        VStack(spacing: 10) {
            Text(isMoney ? "💸" : "🎁")
                .font(.system(size: 52))
                .padding(.top, 2)
            Text(reward.title)
                .font(.golos(22, .bold)).foregroundStyle(Color.sanInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(venue.name)
                .font(.golos(14, .medium)).foregroundStyle(Color.sanInkSoft)
                .lineLimit(1)
            HStack(spacing: 10) {
                statTile(label: "Баланс", value: balance, negative: false)
                // У сотрудника «Останется» считать нечем: после его скана баланс
                // уже уменьшен, и плитка вычла бы цену второй раз.
                if !staffScan && !isDone {
                    statTile(label: "Останется", value: remaining, negative: remaining < 0)
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .sanCard(padding: 20, radius: SanRadius.hero)
    }

    private func statTile(label: LocalizedStringKey, value: Int, negative: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .textCase(.uppercase)
                .font(.golos(10.5, .heavy)).tracking(0.8)
                .foregroundStyle(negative ? Color.red : Color.sanInkSoft)
            Text(value.sanThousands)
                .font(.golos(22, .heavy)).tracking(-0.6)
                .foregroundStyle(negative ? Color.red : Color.sanInk)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(negative ? Color.red.opacity(0.10) : Color.sanSurfaceMuted,
                    in: RoundedRectangle(cornerRadius: SanRadius.tile, style: .continuous))
        .animation(.sanStandard, value: negative)
    }

    // MARK: Выбор суммы (money)

    private var amountPicker: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                stepButton("minus", enabled: spend - Self.step >= reward.cost) { adjust(-Self.step) }
                // Подпись — над числом и без согласования с ним («Баллы»):
                // «21 баллов» под крупной цифрой читалось с ошибкой.
                VStack(spacing: 2) {
                    Text("Баллы")
                        .textCase(.uppercase)
                        .font(.golos(10.5, .heavy)).tracking(0.8)
                        .foregroundStyle(Color.sanInkSoft)
                    Text("\(spend)")
                        .font(.golos(40, .heavy)).tracking(-1.8)
                        .foregroundStyle(Color.sanInk)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: spend)
                }
                .frame(maxWidth: .infinity)
                .lineLimit(1).minimumScaleFactor(0.6)
                stepButton("plus", enabled: spend + Self.step <= maxSpend) { adjust(Self.step) }
            }

            // Ползунок есть только когда есть куда двигать: при `min == max`
            // у Slider нулевой диапазон и деление на ноль.
            if maxSpend > reward.cost {
                VStack(spacing: 4) {
                    Slider(value: sliderValue,
                           in: Double(reward.cost)...Double(maxSpend),
                           step: Double(Self.step))
                        .tint(Color.sanAccent)
                    HStack {
                        Text("мин. \(reward.cost)")
                        Spacer()
                        Text("макс. \(maxSpend)")
                    }
                    .font(.golos(11.5, .medium)).foregroundStyle(Color.sanInkSoft)
                }
            }

            Text("= \(somOff) сом скидки")
                .font(.golos(14, .semibold)).foregroundStyle(Color.sanAccentText)
                .contentTransition(.numericText())
                .animation(.snappy, value: somOff)
        }
        .sanCard(padding: 18, radius: SanRadius.card)
    }

    private var sliderValue: Binding<Double> {
        Binding(get: { Double(spend) },
                set: { spend = clamped(Int($0.rounded())) })
    }

    private func stepButton(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.sanInk)
                .frame(width: SanMetrics.minHitTarget, height: SanMetrics.minHitTarget)
                .background(Color.sanSurfaceMuted, in: Circle())
        }
        .buttonStyle(.sanPress(0.9))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    private func adjust(_ delta: Int) {
        SanHaptics.selection()
        spend = clamped(spend + delta)
    }

    private func clamped(_ value: Int) -> Int { min(max(value, reward.cost), maxSpend) }

    // MARK: Действие — одна карточка, меняется по фазе

    private var actionCard: some View {
        Group {
            switch phase {
            case .done(let receipt):
                receiptView(receipt)
            case .failed(let error):
                failedView(error)
            case .idle, .working:
                if let redeemed = staffRedeemed {
                    staffReceipt(redeemed)
                } else if staffScan {
                    staffQR
                } else {
                    selfRedeem
                }
            }
        }
        .frame(maxWidth: .infinity)
        .sanCard(padding: 20, radius: SanRadius.hero)
        .animation(.sanStandard, value: phase)
    }

    @ViewBuilder
    private var staffQR: some View {
        switch tokens.phase {
        case .ready(let token):
            staffQRCard(text: RedeemQR.tokenCode(token.token), expiresAt: token.expiresAt)
        case .legacy:
            staffQRCard(text: legacyRedeemCode, expiresAt: nil)
        case .failed(let error):
            tokenFailedView(error)
        case .idle, .loading:
            tokenLoadingView
        }
    }

    private func requestToken() {
        tokens.start(venueID: venue.id, rewardID: reward.id, points: isMoney ? spend : 0)
    }

    /// Пока сервер выдаёт токен — место под QR того же размера, чтобы лист не прыгал.
    private var tokenLoadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .frame(width: 204, height: 204)
                .background(Color.sanSurfaceMuted, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("Готовим QR…")
                .font(.golos(14, .medium)).foregroundStyle(Color.sanInkSoft)
        }
    }

    private func tokenFailedView(_ error: AppError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: error == .network ? "wifi.slash" : "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.red)
            Text(Self.tokenErrorText(error))
                .font(.golos(14, .semibold)).foregroundStyle(Color.red)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Повторить", action: requestToken)
                .buttonStyle(SanPrimaryButton())
        }
    }

    /// Отказ выдать токен — человеческим языком.
    static func tokenErrorText(_ error: AppError) -> String {
        switch error.code {
        case "network":
            return LS("Нет связи — QR для списания не получить. Проверьте интернет и повторите.")
        case "insufficient":
            return LS("Недостаточно баллов.")
        case "unauthenticated", "no_token", "bad_token", "anonymous_not_allowed":
            return LS("Войдите в аккаунт, чтобы списать баллы.")
        case "reward_not_found", "points_off":
            return LS("Награда недоступна.")
        case "below_min":
            return LS("Слишком мало баллов для этой награды.")
        case "app_check_failed":
            return LS("Обновите приложение — эта версия не прошла проверку")
        default:
            return LS("Не удалось получить QR. Повторите.")
        }
    }

    private func staffQRCard(text: String, expiresAt: Date?) -> some View {
        VStack(spacing: 14) {
            // 180 + 8·2 (внутренний отступ QRCodeView) + 12·2 = 220pt белой карточки.
            QRCodeView(text: text, size: 180)
                .accessibilityLabel("QR-код для сотрудника")
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .sanShadow(.qrCard)
            if let expiresAt {
                // Код живёт 3 минуты и обновляется сам за 20 с до конца —
                // отсчёт показывает, что это живой код, а не скриншот.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(LF("Код обновится через %lld с",
                            max(0, RedeemQR.secondsLeft(expiresAt: expiresAt, now: context.date)
                                    - Int(RedeemQR.refreshLead))))
                        .font(.golos(12, .semibold)).foregroundStyle(Color.sanInkSoft)
                        .monospacedDigit()
                }
            }
            Text("Покажите QR сотруднику — он спишет баллы и выдаст награду")
                .font(.golos(14, .medium)).foregroundStyle(Color.sanInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Circle().fill(Color.sanAccent).frame(width: 6, height: 6)
                Text("Ожидаем сканирование…")
            }
            .font(.golos(12.5, .semibold)).foregroundStyle(Color.sanInkSoft)
            .opacity(waitingPulse ? 1 : 0.4)
            .onAppear {
                guard !reduceMotion else { waitingPulse = true; return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    waitingPulse = true
                }
            }
            .onDisappear { withoutAnimation { waitingPulse = false } }
        }
    }

    private var selfRedeem: some View {
        VStack(spacing: 12) {
            Button(action: sendRedeem) {
                HStack(spacing: 10) {
                    if isWorking { ProgressView().tint(.white) }
                    Text(isWorking ? "Списываем…" : "Списать \(cost) баллов")
                        .contentTransition(.numericText())
                }
            }
            .buttonStyle(SanPrimaryButton())
            .disabled(isWorking || !affordable)
            .opacity(affordable || isWorking ? 1 : 0.55)
            Text(affordable ? "Баллы спишутся сразу — покажите этот экран сотруднику и заберите награду."
                            : "Не хватает \(-remaining) баллов.")
                .font(.golos(12.5, .medium))
                .foregroundStyle(affordable ? Color.sanInkSoft : Color.red)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func receiptView(_ receipt: RedeemReceipt) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.sanOpen.opacity(0.14)).frame(width: 72, height: 72)
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Color.sanOpen)
            }
            .padding(.bottom, 6)
            Text("Списано \(receipt.redeemed) баллов")
                .font(.golos(20, .bold)).foregroundStyle(Color.sanInk)
            if let som = receipt.somOff, som > 0 {
                Text("Скидка \(som) сом")
                    .font(.golos(14, .semibold)).foregroundStyle(Color.sanAccentText)
            }
            Text("Остаток: \(receipt.balance)")
                .font(.golos(14, .semibold)).foregroundStyle(Color.sanInkSoft)
            Text("Заберите награду у сотрудника")
                .font(.golos(14, .medium)).foregroundStyle(Color.sanInk)
                .padding(.top, 4)
            LiveRedeemStamp(receipt: receipt)
                .padding(.top, 10)
            if receipt.replayed {
                // Сервер узнал повтор по ключу идемпотентности — второй раз не списали.
                Text("Это повтор предыдущего запроса — баллы списаны один раз.")
                    .font(.golos(12, .medium)).foregroundStyle(Color.sanInkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }

    /// Чек после списания сотрудником: сервер гостю не отвечает, а баланс
    /// карты уже уменьшился — это и есть подтверждение.
    private func staffReceipt(_ redeemed: Int) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.sanOpen.opacity(0.14)).frame(width: 72, height: 72)
                Image(systemName: "checkmark")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Color.sanOpen)
            }
            .padding(.bottom, 6)
            Text("Списано \(redeemed) баллов — заберите награду")
                .font(.golos(19, .bold)).foregroundStyle(Color.sanInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Остаток: \(balance.sanThousands)")
                .font(.golos(14, .semibold)).foregroundStyle(Color.sanInkSoft)
        }
    }

    private func failedView(_ error: AppError) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.red)
            Text(PointsMessages.text(for: error))
                .font(.golos(14, .semibold)).foregroundStyle(Color.red)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // Тот же intent: стор держит ключ идемпотентности до успеха, поэтому
            // повтор не спишет баллы дважды.
            Button("Повторить", action: sendRedeem)
                .buttonStyle(SanPrimaryButton())
        }
    }

    // MARK: Действия

    private func sendRedeem() {
        points.send(.redeem(venueID: venue.id, rewardID: reward.id,
                            pointsToSpend: isMoney ? spend : 0))
    }

    private func close() {
        points.send(.dismissRedeem)
        dismiss()
    }

    /// Сотрудник списал баллы по QR: баланс упал РОВНО на сумму одного из
    /// показанных QR (у item-награды — на её цену). Падение на другую сумму —
    /// не наше списание (другая награда, сгорание), «Списано» не показываем.
    /// Рост баланса (начисление под открытым листом) поднимает точку отсчёта,
    /// чтобы потом не принять его откат за списание.
    private func watchStaffRedeem(balance new: Int) {
        guard staffScan, !isStaffDone, !isDone else { return }
        let expected: Set<Int> = isMoney ? shownAmounts : [reward.cost]
        switch StaffRedeemWatch.observe(baseline: staffBaseline, balance: new, expected: expected) {
        case .rebase(let base):
            staffBaseline = base
        case .redeemed(let amount):
            withAnimation(.sanStandard) { staffRedeemed = amount }
            SanHaptics.success()
        case .none:
            break
        }
    }
}

/// Чистое правило «сотрудник списал баллы по QR» — вынесено из листа, чтобы
/// закрепить тестом (`GuestBonusUITests`).
enum StaffRedeemWatch: Equatable {
    /// Ничего не случилось.
    case none
    /// Баланс вырос (начисление) — новая точка отсчёта.
    case rebase(Int)
    /// Баланс упал не меньше чем на цену награды — списано столько.
    case redeemed(Int)

    static func observe(baseline: Int?, balance: Int, minCost: Int) -> StaffRedeemWatch {
        let base = baseline ?? balance
        if balance > base { return .rebase(balance) }
        let dropped = base - balance
        return dropped >= max(1, minCost) ? .redeemed(dropped) : .none
    }

    /// Строгий вариант, которым пользуется лист: списание засчитывается, только
    /// если баланс упал ровно на одну из ожидаемых сумм (цена награды / суммы
    /// показанных QR). Иначе другое списание или сгорание под открытым листом
    /// выглядело как «Списано — заберите награду».
    static func observe(baseline: Int?, balance: Int, expected: Set<Int>) -> StaffRedeemWatch {
        let base = baseline ?? balance
        if balance > base { return .rebase(balance) }
        let dropped = base - balance
        return dropped > 0 && expected.contains(dropped) ? .redeemed(dropped) : .none
    }
}

// MARK: - Тексты ошибок

/// Один словарь кодов на всю фичу: тот же код приходит и от клиентской проверки
/// (`PointsMath`), и от сервера, поэтому текст должен быть один.
enum PointsMessages {
    static func text(for error: AppError) -> String {
        switch error.code {
        case "insufficient":       return LS("Недостаточно баллов.")
        case "reward_not_found":   return LS("Награда недоступна.")
        case "redeem_not_allowed": return LS("Списание доступно только у сотрудника.")
        case "below_min":          return LS("Слишком мало баллов для этой награды.")
        case "key_reused":         return LS("Не получилось. Попробуйте ещё раз — баллы дважды не спишутся.")
        case "unauthenticated", "no_token", "bad_token":
            return LS("Войдите в аккаунт, чтобы списать баллы.")
        case "permission_denied":  return LS("Нет доступа к баллам этого аккаунта.")
        case "network":            return LS("Нет связи. Проверьте интернет и повторите.")
        case "app_check_failed":   return LS("Обновите приложение — эта версия не прошла проверку")
        case "venue_not_found":    return LS("Заведение не найдено — возможно, оно больше не работает с баллами.")
        case "bad_reward":         return LS("Награда изменилась. Закройте экран и выберите её заново.")
        default:                   return LS("Не удалось списать баллы. Попробуйте ещё раз.")
        }
    }

    /// Ошибка загрузки журнала — коротко, под кнопкой «Повторить».
    static func historyText(for error: AppError) -> String {
        switch error.code {
        case "network":            return LS("Нет связи. Проверьте интернет и повторите.")
        case "unauthenticated", "no_token", "bad_token":
            return LS("Войдите в аккаунт, чтобы видеть историю.")
        case "permission_denied":  return LS("Нет доступа к истории этого аккаунта.")
        default:                   return LS("Не удалось загрузить историю.")
        }
    }
}

// MARK: - Живая отметка погашения

/// Отметка на экране «погашено», которую нельзя подделать скриншотом.
///
/// В режиме «гость гасит сам» сотрудник видит только экран телефона, и
/// старый скриншот выглядел так же, как свежее списание. Здесь три вещи,
/// которых у скриншота нет: идущие секунды, «N мин назад» от момента списания
/// на сервере и бегущая полоса. Код чека совпадает с записью в истории карты
/// (`ledger.receiptCode`), так что спорный случай можно проверить.
struct LiveRedeemStamp: View {
    let receipt: RedeemReceipt
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 6) {
                if !receipt.receiptCode.isEmpty {
                    Text(receipt.receiptCode)
                        .font(.system(size: 34, weight: .heavy, design: .monospaced))
                        .tracking(6)
                        .foregroundStyle(Color.sanInk)
                }
                Text(context.date.formatted(Date.FormatStyle(locale: AppLanguage.locale)
                    .hour().minute().second()))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.sanAccentText)
                    .contentTransition(.numericText())
                if let at = receipt.redeemedAt {
                    Text(Self.ago(from: at, now: context.date))
                        .font(.golos(12.5, .medium))
                        .foregroundStyle(Color.sanInkSoft)
                }
                sweep
            }
            .padding(.vertical, 12).padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(Color.sanOpen.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }

    /// Полоса, которая проходит слева направо каждые 2 секунды.
    ///
    /// Своя `TimelineView(.animation)`: внешняя тикает раз в секунду, и полоса
    /// на ней прыгала скачками вместо бега. С «Уменьшением движения» — стоит
    /// посередине (сама отметка живая и без неё: часы и «N мин назад»).
    private var sweep: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
            GeometryReader { geo in
                let phase = reduceMotion
                    ? 0.5
                    : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2
                Capsule().fill(Color.sanOpen.opacity(0.18))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.sanOpen)
                            .frame(width: geo.size.width * 0.25)
                            .offset(x: geo.size.width * 0.75 * phase)
                    }
            }
        }
        .frame(height: 4)
        .padding(.top, 4)
        .accessibilityHidden(true)
    }

    static func ago(from at: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(at) / 60))
        if minutes == 0 { return LS("Списано только что") }
        return LF("Списано %lld мин назад", minutes)
    }
}
