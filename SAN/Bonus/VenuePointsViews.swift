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
                    description: Text("Показывайте свой QR при оплате в заведениях с бонусами САН — за визиты копятся баллы, которые можно потратить на награды. Награды — на странице заведения."))

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

    private var earnCode: String { "AYANT-PTS:\(userID)" }
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
                Text("\(card.balance)")
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
                                .lineLimit(1)
                            Text(reward.type == "money" ? "Скидка баллами · от \(reward.cost) б."
                                                        : "\(reward.cost) баллов")
                                .font(.golos(12, .medium)).foregroundStyle(Color.sanInkSoft)
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
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sanCard(padding: 0)
    }
}

// MARK: - Лист списания баллов на награду

/// «Награда»: подтверждение списания в фирменном стиле.
///
/// Машина состояний прежняя — `points.state.redeem` (`idle / working / done /
/// failed`), `send(.redeem)` и `send(.dismissRedeem)`; лист только рисует фазу.
/// Баланс читается из стора живьём: если сотрудник просканировал QR, пока лист
/// открыт, «Останется» пересчитается само.
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

    private static let step = 10

    init(venue: Venue, reward: PointsReward, userID: String) {
        self.venue = venue; self.reward = reward; self.userID = userID
        _spend = State(initialValue: reward.cost)
    }

    // MARK: Производные

    private var isMoney: Bool { reward.type == "money" }
    private var balance: Int { points.state.balance(for: venue.id) }
    private var cost: Int { isMoney ? spend : reward.cost }
    private var remaining: Int { balance - cost }
    private var affordable: Bool { remaining >= 0 }
    private var staffScan: Bool { venue.redeemMode != "customerInitiated" }
    private var somOff: Int { PointsMath.somOff(reward: reward, cost: spend) ?? 0 }
    private var maxSpend: Int { max(reward.cost, balance) }
    private var phase: RedeemPhase { points.state.redeem }
    private var isWorking: Bool { phase.isWorking }
    private var isDone: Bool { if case .done = phase { return true }; return false }
    private var redeemCode: String {
        isMoney ? "AYANT-RDM:\(userID):\(reward.id):\(spend)" : "AYANT-RDM:\(userID):\(reward.id)"
    }

    // MARK: Тело

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    heroCard
                    if isMoney && !isDone { amountPicker }
                    actionCard
                }
                .padding(.horizontal, SanMetrics.screenPadding)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            SanStickyFooter {
                Button(isDone ? "Готово" : "Отмена", action: close)
                    .buttonStyle(SanPillButton(accent: isDone))
            }
        }
        .sanScreenBackground()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Баланс мог измениться под открытым листом — выбранная сумма не должна
        // выйти за новые границы.
        .onChange(of: balance) { _, _ in spend = clamped(spend) }
        .onChange(of: phase) { _, new in
            if case .done = new { SanHaptics.success() }
        }
        // Смахнули лист — фаза не должна пережить его и всплыть в другом заведении.
        .onDisappear { points.send(.dismissRedeem) }
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
                statTile(label: "Останется", value: remaining, negative: remaining < 0)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .sanCard(padding: 20, radius: SanRadius.hero)
    }

    private func statTile(label: String, value: Int, negative: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .textCase(.uppercase)
                .font(.golos(10.5, .heavy)).tracking(0.8)
                .foregroundStyle(negative ? Color.red : Color.sanInkSoft)
            Text("\(value)")
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
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(spend)")
                        .font(.golos(40, .heavy)).tracking(-1.8)
                        .foregroundStyle(Color.sanInk)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: spend)
                    Text("баллов")
                        .font(.golos(15, .semibold)).foregroundStyle(Color.sanInkSoft)
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
                if staffScan { staffQR } else { selfRedeem }
            }
        }
        .frame(maxWidth: .infinity)
        .sanCard(padding: 20, radius: SanRadius.hero)
        .animation(.sanStandard, value: phase)
    }

    private var staffQR: some View {
        VStack(spacing: 14) {
            // 180 + 8·2 (внутренний отступ QRCodeView) + 12·2 = 220pt белой карточки.
            QRCodeView(text: redeemCode, size: 180)
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .sanShadow(.qrCard)
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
            if receipt.replayed {
                // Сервер узнал повтор по ключу идемпотентности — второй раз не списали.
                Text("Это повтор предыдущего запроса — баллы списаны один раз.")
                    .font(.golos(12, .medium)).foregroundStyle(Color.sanInkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
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
}

// MARK: - Тексты ошибок

/// Один словарь кодов на всю фичу: тот же код приходит и от клиентской проверки
/// (`PointsMath`), и от сервера, поэтому текст должен быть один.
enum PointsMessages {
    static func text(for error: AppError) -> String {
        switch error.code {
        case "insufficient":       return "Недостаточно баллов."
        case "reward_not_found":   return "Награда недоступна."
        case "redeem_not_allowed": return "Списание доступно только у сотрудника."
        case "below_min":          return "Слишком мало баллов для этой награды."
        case "key_reused":         return "Этот запрос уже выполнялся. Обновите экран."
        case "unauthenticated", "no_token", "bad_token":
            return "Войдите в аккаунт, чтобы списать баллы."
        case "permission_denied":  return "Нет доступа к баллам этого аккаунта."
        case "network":            return "Нет связи. Проверьте интернет и повторите."
        default:                   return "Не удалось списать баллы. Попробуйте ещё раз."
        }
    }

    /// Ошибка загрузки журнала — коротко, под кнопкой «Повторить».
    static func historyText(for error: AppError) -> String {
        switch error.code {
        case "network":            return "Нет связи. Проверьте интернет и повторите."
        case "unauthenticated", "no_token", "bad_token":
            return "Войдите в аккаунт, чтобы видеть историю."
        case "permission_denied":  return "Нет доступа к истории этого аккаунта."
        default:                   return "Не удалось загрузить историю."
        }
    }
}
