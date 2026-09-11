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
                explainer
            }
            .padding(16)
        }
        .sanNavBar("Баллы САН") { dismiss() }
        .sanScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $pendingReward) { reward in
            RedeemSheet(venue: venue, reward: reward, balance: balance,
                        userID: points.state.userID)
                .environmentObject(points)
        }
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

struct RedeemSheet: View {
    let venue: Venue
    let reward: PointsReward
    let balance: Int
    let userID: String
    @EnvironmentObject private var points: PointsStore
    @Environment(\.dismiss) private var dismiss

    @State private var spend: Int

    init(venue: Venue, reward: PointsReward, balance: Int, userID: String) {
        self.venue = venue; self.reward = reward; self.balance = balance; self.userID = userID
        _spend = State(initialValue: reward.cost)
    }

    private var isMoney: Bool { reward.type == "money" }
    private var cost: Int { isMoney ? spend : reward.cost }
    private var staffScan: Bool { venue.redeemMode != "customerInitiated" }
    private var somOff: Int { PointsMath.somOff(reward: reward, cost: spend) ?? 0 }
    private var redeemCode: String {
        isMoney ? "AYANT-RDM:\(userID):\(reward.id):\(spend)" : "AYANT-RDM:\(userID):\(reward.id)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Text(reward.title).font(.golos(20, .bold)).foregroundStyle(Color.sanInk)
                        .multilineTextAlignment(.center)

                    if isMoney {
                        VStack(spacing: 6) {
                            Stepper("К списанию: \(spend) б.", value: $spend,
                                    in: reward.cost...max(reward.cost, balance), step: 10)
                                .font(.golos(15, .semibold))
                            Text("Скидка: \(somOff) сом").font(.golos(13, .medium))
                                .foregroundStyle(Color.sanInkSoft)
                        }
                        .padding(14).sanCard(padding: 0)
                    } else {
                        Text("Стоимость: \(reward.cost) баллов")
                            .font(.golos(15, .medium)).foregroundStyle(Color.sanInkSoft)
                    }

                    // Всё, что показывается ниже, — функция от одной фазы списания.
                    switch points.state.redeem {
                    case .done(let receipt):
                        receiptView(receipt)
                    case .idle, .working, .failed:
                        if staffScan { staffQR } else { selfRedeemButton }
                    }

                    if case .failed(let error) = points.state.redeem {
                        Text(PointsMessages.text(for: error))
                            .font(.golos(13, .medium)).foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(20)
            }
            .sanScreenBackground()
            .navigationTitle("Списание баллов").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isDone ? "Готово" : "Отмена") {
                        points.send(.dismissRedeem)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var isDone: Bool { if case .done = points.state.redeem { return true }; return false }

    private func receiptView(_ receipt: RedeemReceipt) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 40))
                .foregroundStyle(Color.sanOpen)
            Text("Списано \(receipt.redeemed) баллов").font(.golos(16, .bold))
                .foregroundStyle(Color.sanInk)
            Text("Остаток: \(receipt.balance). Заберите награду у сотрудника.")
                .font(.golos(13, .regular)).foregroundStyle(Color.sanInkSoft)
                .multilineTextAlignment(.center)
            if receipt.replayed {
                // Сервер узнал повтор по ключу идемпотентности — второй раз не списали.
                Text("Это повтор предыдущего запроса — баллы списаны один раз.")
                    .font(.golos(12, .medium)).foregroundStyle(Color.sanInkSoft)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var staffQR: some View {
        VStack(spacing: 8) {
            QRCodeView(text: redeemCode, size: 200)
                .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 16))
            Text("Покажите этот QR сотруднику — он спишет баллы и выдаст награду.")
                .font(.golos(12, .medium)).foregroundStyle(Color.sanInkSoft)
                .multilineTextAlignment(.center)
        }
    }

    private var selfRedeemButton: some View {
        Button {
            points.send(.redeem(venueID: venue.id, rewardID: reward.id,
                                pointsToSpend: isMoney ? spend : 0))
        } label: {
            Text(points.state.redeem.isWorking ? "Списываем…" : "Списать \(cost) баллов")
        }
        .buttonStyle(SanPrimaryButton())
        .disabled(points.state.redeem.isWorking || cost > balance)
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
}
