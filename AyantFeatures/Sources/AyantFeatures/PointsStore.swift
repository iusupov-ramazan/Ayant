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
    ///
    /// Хранится в UserDefaults по uid: приложение убили после списания, но до
    /// ответа — после перезапуска повтор уйдёт с тем же ключом. Но не вечно:
    /// через `PersistedAttemptKeys.retryWindow` попытка считается брошенной, и
    /// следующее списание — новое, а не воспроизведение квитанции недельной давности.
    private var redeemKeys: PersistedAttemptKeys? {
        state.userID.isEmpty ? nil
            : PersistedAttemptKeys(storageKey: "san.points.redeemKeys.\(state.userID)")
    }

    /// Списание, ответ на которое ещё не пришёл (по `venueID|rewardID`), и
    /// жетон попытки, чей ответ сейчас ждёт экран. Шторку закрыли посреди
    /// запроса — жетон снят, и опоздавший ответ не всплывает «Готово»/ошибкой
    /// в СЛЕДУЮЩЕЙ шторке; а второе списание той же награды, пока первое в
    /// пути, не уходит параллельно — экран просто снова ждёт первое.
    private var inFlight: [String: UUID] = [:]
    private var shownAttempt: UUID?

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
        case .dismissRedeem:
            shownAttempt = nil
            state.redeem = .idle
        case .loadHistory(let venueID): loadHistory(venueID: venueID)
        case .dismissEarn:           state.pendingEarn = nil
        }
    }

    // MARK: - Начисление

    /// Балансы из ПРЕДЫДУЩЕГО снимка. `nil` до первого снимка: первая загрузка —
    /// не начисление, а просто карты, которые уже были.
    private var knownBalances: [String: Int]?

    /// Сравнивает снимок с предыдущим и поднимает событие на рост баланса.
    /// Раньше это делал экран «Мой QR» своим `@State`: событие жило в нём и
    /// пропадало вместе с перерисовкой вкладки. Теперь оно в состоянии стора
    /// и снимается только `dismissEarn`; второе начисление, пришедшее пока
    /// экран открыт, не затирает первое.
    ///
    /// Точка отсчёта — только серверный снимок (`fromCache == false`): первый
    /// снимок из пустого или неполного кэша SDK иначе становился «было», и
    /// следующий серверный показывал «Начислено +<весь баланс>».
    /// Событие воронки «впервые на этом устройстве» — один раз за установку.
    static func logFirstOnce(_ key: String, _ event: AnalyticsEvent) {
        let d = UserDefaults.standard
        guard !d.bool(forKey: key) else { return }
        d.set(true, forKey: key)
        AnalyticsLog.log(event)
    }

    private func detectEarn(in cards: [VenuePointsCard], fromCache: Bool = false) {
        let now = Dictionary(cards.map { ($0.venueID, $0.balance) }, uniquingKeysWith: { a, _ in a })
        guard let known = knownBalances else {
            if !fromCache { knownBalances = now }
            return
        }
        defer { knownBalances = now }
        guard state.pendingEarn == nil else { return }
        for card in cards {
            // Карты не было в прошлом снимке — первое начисление в этом
            // заведении: «было» = 0. Раньше такую карту пропускали, и первый
            // скан гостя оставался без экрана «Начислено».
            let was = known[card.venueID] ?? 0
            guard card.balance > was else { continue }
            state.pendingEarn = PointsEarnEvent(
                id: "\(card.venueID)-\(card.balance)-\(Int(clock.now.timeIntervalSince1970))",
                venueID: card.venueID, venueName: card.venueName,
                delta: card.balance - was, newBalance: card.balance)
            Self.logFirstOnce("san.analytics.firstPointsLogged", .firstPointsEarned)
            return
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
            guard state.userID == userID else { return }      // вышел/сменился — журнал чужой
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

        knownBalances = nil
        state.pendingEarn = nil
        guard !userID.isEmpty else {
            state.cards = .loaded([])
            return
        }
        if state.cards.value == nil { state.cards = .loading }

        observation = Task { [repository] in
            for await result in repository.liveCards(userID: userID) {
                if Task.isCancelled || state.userID != userID { return }
                switch result {
                case .success(let snapshot):
                    state.cards = .loaded(snapshot.value)
                    detectEarn(in: snapshot.value, fromCache: snapshot.isFromCache)
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

    /// Выход/смена пользователя: снимаем слушатель И стираем всё, что
    /// принадлежало прежнему гостю, — карты, историю, незакрытое списание,
    /// экран «Начислено». Ключи списаний остаются под его uid.
    private func stopObserving() {
        observation?.cancel()
        observation = nil
        knownBalances = nil
        inFlight = [:]
        shownAttempt = nil
        state = PointsState()
    }

    // MARK: - Списание

    private func redeem(venueID: String, rewardID: String, pointsToSpend: Int) {
        guard state.isSignedIn else { state.redeem = .failed(.unauthenticated); return }
        guard !state.redeem.isWorking else { return }   // второй тап игнорируем

        let attemptID = "\(venueID)|\(rewardID)"
        // Эта награда уже списывается (шторку закрыли и открыли снова) — не
        // шлём второй запрос, а снова ждём ответ первого.
        if let running = inFlight[attemptID] {
            shownAttempt = running
            state.redeem = .working(rewardID: rewardID)
            return
        }
        guard let keys = redeemKeys else { return }
        let now = clock.now
        let key = keys.key(for: attemptID, now: now) ?? newIdempotencyKey()
        keys.set(key, for: attemptID, now: now)

        let token = UUID()
        inFlight[attemptID] = token
        shownAttempt = token
        state.redeem = .working(rewardID: rewardID)
        let userID = state.userID
        Task { [repository] in
            let result = await repository.redeem(venueID: venueID, userID: userID, rewardID: rewardID,
                                                 pointsToSpend: pointsToSpend, idempotencyKey: key)
            // Пользователь сменился за время запроса: ключ остаётся под прежним
            // uid, состояние нового не трогаем.
            guard state.userID == userID else { return }
            if inFlight[attemptID] == token { inFlight[attemptID] = nil }
            // Экран ждёт ЭТУ попытку? Нет — шторку закрыли: итог не показываем.
            let shown = shownAttempt == token
            if shown { shownAttempt = nil }
            switch result {
            case .success(let receipt):
                keys.set(nil, for: attemptID, now: clock.now)   // попытка закрыта, дальше — новая
                if shown { state.redeem = .done(receipt) }
                // Баланс приедет сам snapshot-листенером; журнал — по запросу,
                // поэтому его обновляем, если экран его уже показывал.
                if state.history(for: venueID).value != nil { loadHistory(venueID: venueID) }
            case .failure(let error):
                // Ключ НЕ сбрасываем: повтор должен уйти с тем же ключом. Кроме
                // `key_reused`: сервер узнал ключ ДРУГОГО запроса и этот не
                // выполнил — с тем же ключом «Повторить» получал бы отказ вечно.
                if error == .server(code: "key_reused") { keys.set(nil, for: attemptID, now: clock.now) }
                if shown { state.redeem = .failed(error) }
            }
        }
    }

    /// Уникальный ключ попытки. Время берём из `Clock`, чтобы тест был воспроизводим.
    private func newIdempotencyKey() -> String {
        "\(UUID().uuidString)-\(Int(clock.now.timeIntervalSince1970))"
    }
}

// MARK: - Ключи незавершённых попыток

/// Ключи идемпотентности незавершённых попыток (списание баллов, покупка
/// купона) в UserDefaults: словарь `ссылка → ключ` под прежним именем
/// (`storageKey` — его читают уже установленные приложения) и рядом —
/// `storageKey + ".at"` с моментом выдачи ключа.
///
/// Ключ переживает перезапуск, чтобы повтор после потерянного ответа ушёл с
/// тем же ключом. Но через `retryWindow` попытка считается брошенной: иначе
/// забытый ключ через дни «воспроизводил» старую покупку или квитанцию вместо
/// новой. Ключ из прежней версии (без времени) получает окно с момента
/// первого чтения.
struct PersistedAttemptKeys {
    static let retryWindow: TimeInterval = 30 * 60

    let storageKey: String
    var ttl: TimeInterval = PersistedAttemptKeys.retryWindow
    private var stampsKey: String { storageKey + ".at" }
    private var defaults: UserDefaults { .standard }

    init(storageKey: String, ttl: TimeInterval = PersistedAttemptKeys.retryWindow) {
        self.storageKey = storageKey
        self.ttl = ttl
    }

    /// Живой ключ попытки или `nil` (нет / окно истекло — тогда он стёрт).
    func key(for ref: String, now: Date) -> String? {
        guard let key = keys[ref] else { return nil }
        var stamps = self.stamps
        guard let issued = stamps[ref] else {
            stamps[ref] = now.timeIntervalSince1970
            self.stamps = stamps
            return key
        }
        if now.timeIntervalSince1970 - issued > ttl {
            set(nil, for: ref, now: now)
            return nil
        }
        return key
    }

    /// Запомнить ключ (время выдачи — только для нового ключа) или стереть (`nil`).
    func set(_ key: String?, for ref: String, now: Date) {
        var keys = self.keys
        var stamps = self.stamps
        if let key {
            if keys[ref] != key { stamps[ref] = now.timeIntervalSince1970 }
            keys[ref] = key
        } else {
            keys[ref] = nil
            stamps[ref] = nil
        }
        self.keys = keys
        self.stamps = stamps
    }

    /// Стереть все ключи этого хранилища.
    func clear() {
        keys = [:]
        stamps = [:]
    }

    private var keys: [String: String] {
        get { defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:] }
        nonmutating set {
            if newValue.isEmpty { defaults.removeObject(forKey: storageKey) }
            else { defaults.set(newValue, forKey: storageKey) }
        }
    }

    private var stamps: [String: Double] {
        get { defaults.dictionary(forKey: stampsKey) as? [String: Double] ?? [:] }
        nonmutating set {
            if newValue.isEmpty { defaults.removeObject(forKey: stampsKey) }
            else { defaults.set(newValue, forKey: stampsKey) }
        }
    }
}

// MARK: - Токен списания для QR гостя (AYANT-RDT)

/// QR списания «гасит сотрудник» несёт одноразовый токен с сервера
/// (`issueRedeemToken`), а не uid гостя — см. `RedeemQR`. Стор держит токен
/// на открытый лист награды: просит его при показе QR и при смене суммы,
/// сам обновляет за `RedeemQR.refreshLead` до истечения и останавливается,
/// когда лист закрыт или списание замечено.
///
/// Без сети — `failed(.network)` и честное сообщение вместо QR, который
/// сотрудник всё равно не сможет погасить. Сервер без `issueRedeemToken`
/// (`not_deployed`: приложение вышло раньше деплоя функций) — `legacy`: экран
/// показывает старый QR, сервер по умолчанию его ещё принимает.
@MainActor
public final class RedeemTokenStore: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case loading
        case ready(RedeemToken)
        /// Сервер ещё без токенов — показать старый QR (с uid).
        case legacy
        case failed(AppError)
    }

    public typealias Issuer = (_ venueID: String, _ rewardID: String, _ points: Int) async throws -> RedeemToken

    @Published public private(set) var phase: Phase = .idle

    private let issue: Issuer
    private let clock: Clock
    private let sleep: (TimeInterval) async -> Void
    private var task: Task<Void, Never>?
    /// Поколение запроса: ответ на устаревший запрос (сумму уже поменяли,
    /// лист закрыли) не должен перезаписать актуальный.
    private var generation = 0

    public init(clock: Clock = SystemClock(),
                sleep: @escaping (TimeInterval) async -> Void = { seconds in
                    try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                },
                issue: @escaping Issuer) {
        self.clock = clock
        self.sleep = sleep
        self.issue = issue
    }

    deinit { task?.cancel() }

    /// Текст QR, когда токен готов.
    public var qrText: String? {
        if case .ready(let t) = phase { return RedeemQR.tokenCode(t.token) }
        return nil
    }

    /// Запросить токен на награду (и держать его свежим, пока не `stop()`).
    public func start(venueID: String, rewardID: String, points: Int) {
        task?.cancel()
        generation += 1
        let gen = generation
        phase = .loading
        task = Task { [weak self] in
            await self?.run(gen: gen, venueID: venueID, rewardID: rewardID, points: points)
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        generation += 1
        phase = .idle
    }

    private func run(gen: Int, venueID: String, rewardID: String, points: Int) async {
        while !Task.isCancelled && gen == generation {
            do {
                let token = try await issue(venueID, rewardID, points)
                guard !Task.isCancelled, gen == generation else { return }
                phase = .ready(token)
                await sleep(RedeemQR.refreshDelay(expiresAt: token.expiresAt, now: clock.now))
            } catch {
                guard !Task.isCancelled, gen == generation else { return }
                let appError = (error as? AppError) ?? .network
                phase = appError == .server(code: "not_deployed") ? .legacy : .failed(appError)
                return
            }
        }
    }
}
