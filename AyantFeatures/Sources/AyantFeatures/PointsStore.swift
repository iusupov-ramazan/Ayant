import SwiftUI
import AyantDomain

/// Стор фичи «Баллы САН».
///
/// Форма новая и намеренно отличается от остальных сторов: наружу торчит **одно
/// значение состояния** и **один вход** — `send(_:)`. Вьюха не дёргает методы по
/// одному и не хранит собственных флагов «грузим / ошибка / готово»; она читает
/// `state` и отправляет намерения. Зеркалит `PointsViewModel.kt` на Android.
///
/// Что изменилось по сравнению со старым `VenuePointsStore`:
///  • баланс приходит живым потоком (snapshot-листенер) вместо опроса раз в 4 с;
///  • ключ идемпотентности генерируется один раз на попытку списания, поэтому
///    повторная отправка (ретрай, второй тап) не спишет баллы дважды;
///  • загрузка и ошибка — часть состояния, а не отдельные `@State` во вьюхе.
@MainActor
public final class PointsStore: ObservableObject {
    @Published public private(set) var state = PointsState()

    private let repository: PointsRepository
    private let clock: Clock
    private var observation: Task<Void, Never>?
    /// Ключ живёт, пока попытка не завершилась успехом: любой повтор уйдёт с тем же
    /// ключом, и сервер вернёт первый результат вместо второго списания.
    private var pendingRedeemKey: [String: String] = [:]

    public init(repository: PointsRepository,
         clock: Clock = SystemClock()) {
        self.repository = repository
        self.clock = clock
    }

    deinit { observation?.cancel() }

    public func send(_ intent: PointsIntent) {
        switch intent {
        case .observe(let userID):   observe(userID: userID)
        case .stop:                  stopObserving()
        case .redeem(let venueID, let rewardID, let points):
            redeem(venueID: venueID, rewardID: rewardID, pointsToSpend: points)
        case .dismissRedeem:         state.redeem = .idle
        case .loadHistory(let venueID): loadHistory(venueID: venueID)
        }
    }

    // MARK: - История

    /// Сколько записей журнала тянем за раз: хватает на месяцы визитов, а
    /// пагинации у экрана пока нет.
    public static let historyLimit = 100

    private func loadHistory(venueID: String) {
        guard state.isSignedIn else { state.history[venueID] = .loaded([]); return }
        if state.history(for: venueID).value == nil { state.history[venueID] = .loading }
        let userID = state.userID
        Task { [repository] in
            let result = await repository.ledger(userID: userID, venueID: venueID, limit: Self.historyLimit)
            switch result {
            case .success(let entries): state.history[venueID] = .loaded(entries)
            case .failure(let error):
                // Уже показанную историю не стираем из-за моргнувшей сети.
                if let known = state.history(for: venueID).value {
                    state.history[venueID] = .loaded(known)
                } else {
                    state.history[venueID] = .failed(error)
                }
            }
        }
    }

    // MARK: - Чтение

    private func observe(userID: String) {
        // Повторный вызов с тем же гостем — уже подписаны, второй листенер не нужен.
        guard state.userID != userID || observation == nil else { return }
        observation?.cancel()
        state.userID = userID

        guard !userID.isEmpty else {
            state.cards = .loaded([])
            return
        }
        if state.cards.value == nil { state.cards = .loading }

        observation = Task { [repository] in
            for await result in repository.cards(userID: userID) {
                if Task.isCancelled { return }
                switch result {
                case .success(let cards): state.cards = .loaded(cards)
                case .failure(let error):
                    // Уже показанные карты не стираем: сеть моргнула — пусть
                    // гость видит последний известный баланс, а не пустой экран.
                    if let known = state.cards.value {
                        state.cards = .loaded(known)
                    } else {
                        state.cards = .failed(error)
                    }
                }
            }
        }
    }

    private func stopObserving() {
        observation?.cancel()
        observation = nil
    }

    // MARK: - Списание

    private func redeem(venueID: String, rewardID: String, pointsToSpend: Int) {
        guard state.isSignedIn else { state.redeem = .failed(.unauthenticated); return }
        guard !state.redeem.isWorking else { return }   // второй тап игнорируем

        let attemptID = "\(venueID)|\(rewardID)"
        let key = pendingRedeemKey[attemptID] ?? newIdempotencyKey()
        pendingRedeemKey[attemptID] = key

        state.redeem = .working(rewardID: rewardID)
        let userID = state.userID
        Task { [repository] in
            let result = await repository.redeem(venueID: venueID, userID: userID, rewardID: rewardID,
                                                 pointsToSpend: pointsToSpend, idempotencyKey: key)
            switch result {
            case .success(let receipt):
                pendingRedeemKey[attemptID] = nil      // попытка закрыта, дальше — новая
                state.redeem = .done(receipt)
                // Баланс приедет сам snapshot-листенером; журнал — по запросу,
                // поэтому его обновляем, если экран его уже показывал.
                if state.history(for: venueID).value != nil { loadHistory(venueID: venueID) }
            case .failure(let error):
                // Ключ НЕ сбрасываем: повтор должен уйти с тем же ключом.
                state.redeem = .failed(error)
            }
        }
    }

    /// Уникальный ключ попытки. Время берём из `Clock`, чтобы тест был воспроизводим.
    private func newIdempotencyKey() -> String {
        "\(UUID().uuidString)-\(Int(clock.now.timeIntervalSince1970))"
    }
}
