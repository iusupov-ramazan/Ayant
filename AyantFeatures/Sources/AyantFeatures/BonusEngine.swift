import SwiftUI
import AyantDomain

/// Начисляет бонусы за АКТИВНОЕ время в приложении.
///
/// Логика «активные 30 минут»:
/// - секунда засчитывается только если приложение на переднем плане
///   И пользователь взаимодействовал недавно (тап/скролл за последние `idleTimeout` сек);
/// - простой (открыл и отложил телефон) не копит время;
/// - за каждые `goalSeconds` активного времени — начисление `rewardPerGoal` бонусов.
/// Баланс и прогресс сохраняются между запусками.
@MainActor
public final class BonusEngine: ObservableObject {

    // Глобальный кошелёк минтит медленно — настоящая ценность живёт в per-venue
    // баллах САН. Дневного потолка у игр больше НЕТ: сколько наиграл, столько и
    // получил. Значит, единственный тормоз — цена бонуса внутри самой игры
    // (яблоко, линия, двенадцать совпадений), и менять её теперь нельзя «на
    // глазок»: это прямая ставка обмена игрового времени на купоны заведений.
    //
    // Все ставки — из `gameRates` (Remote Config, `GameRates.Key`); по
    // умолчанию: цикл 30 минут, 1 бонус за цикл, не больше 4 циклов в день.
    public var goalSeconds: Int { gameRates.timeGoalSeconds }
    public var rewardPerGoal: Int { gameRates.timeRewardPerGoal }
    public var dailyGoalCap: Int { gameRates.timeGoalsPerDay }

    /// Курс игр и времени. Меняет Remote Config сразу после загрузки
    /// (`RemoteSettingsEffects` в приложении); игры берут снимок в начале партии.
    @Published public private(set) var gameRates: GameRates = .defaults

    public func setGameRates(_ rates: GameRates) {
        if gameRates != rates { gameRates = rates }
    }
    private let idleTimeout: TimeInterval = 25  // сек без действий = простой

    // Состояние (персистентное)
    @AppStorage("san.bonus.balance") public var balance: Int = 0
    @AppStorage("san.bonus.activeSeconds") private var storedActive: Int = 0
    @AppStorage("san.bonus.cycles") public var completedCycles: Int = 0
    @AppStorage("san.bonus.lastAwardAt") private var lastAwardAt: Double = 0
    // Дневные счётчики (сбрасываются по смене календарного дня).
    @AppStorage("san.bonus.counterDate") private var counterDate: String = ""
    @AppStorage("san.bonus.awardsToday") private var awardsToday: Int = 0
    // Ключ прежний: на устройствах уже лежит счётчик под этим именем.
    @AppStorage("san.bonus.gameEarnedToday") private var gameEarnedTodayStored: Int = 0
    /// Сколько принесли за сегодня бесконечные игры — для их дневного потолка.
    @AppStorage("san.bonus.endlessEarnedToday") private var endlessEarnedTodayStored: Int = 0

    @Published public var activeSeconds: Int = 0
    @Published public var isCounting = false
    @Published public var lastReward: Int? = nil   // для анимации «+50»

    private let clock: Clock
    private var lastInteraction: Date
    private var timer: Timer?

    // MARK: Серверный кошелёк

    /// Кошелёк на сервере (`bonusWallets/{uid}`). Есть — баланс ведёт сервер:
    /// начисления уходят в `earnBonus`, покупки — в `buyCoupon`, а `balance`
    /// только показывает `подтверждённое + ещё не отправленное`. Нет (мок,
    /// тесты) — всё считается на устройстве, как раньше.
    private let wallet: BonusWalletService?
    public var usesServerWallet: Bool { wallet != nil }
    private var walletUserID = ""
    private var walletTask: Task<Void, Never>?
    private var flushing = false
    /// Поколение кошелька: растёт при подключении и сбросе. Каждая задача
    /// запоминает своё и проверяет его после КАЖДОГО `await` — выход из
    /// аккаунта посреди запроса иначе ронял `removeFirst()` на пустой
    /// очереди и переносил баланс/гранты пользователя A в кошелёк B.
    private var walletGeneration = 0
    private var serverBalance: Int?
    /// Баланс устройства на момент подключения — его сервер один раз
    /// перенесёт в кошелёк (с потолком). Всё заработанное после — в очереди.
    private var migrationBalance = 0
    private var walletSynced = false
    private var syncInFlight = false

    // MARK: Повторы очереди

    /// Подряд неудачных попыток досылки — для паузы между повторами.
    private var flushFailures = 0
    /// Неудач у конкретного начисления: застрявшее (сервер раз за разом
    /// отвечает ошибкой) уходит в конец очереди, чтобы не держать остальные.
    private var entryFailures: [String: Int] = [:]
    private var retryTask: Task<Void, Never>?
    /// Сколько повторов делаем сами; дальше — по следующему поводу
    /// (начисление, возврат в приложение, кнопка «Повторить»).
    public static let maxAutoRetries = 6
    public static let rotateAfterFailures = 3

    public static func backoffSeconds(failures: Int) -> TimeInterval {
        min(300, pow(2, Double(max(1, failures))))
    }

    private func resetBackoff() {
        flushFailures = 0
        retryTask?.cancel()
        retryTask = nil
    }

    /// Неудача досылки: пауза растёт (2, 4, 8 … 300 с), после
    /// `maxAutoRetries` сами больше не пробуем. Бонусы остаются в очереди.
    private func noteFlushFailure(problem: SyncProblem, entryKey: String?) {
        setSyncProblem(problem)
        flushFailures += 1
        if let key = entryKey {
            let n = (entryFailures[key] ?? 0) + 1
            entryFailures[key] = n
            if n >= Self.rotateAfterFailures, pending.count > 1,
               let i = pending.firstIndex(where: { $0.key == key }) {
                let stuck = pending.remove(at: i)
                pending.append(stuck)
                entryFailures[key] = 0
            }
        }
        // Обновление приложения или вход повтор не заменит — ждём повода.
        guard problem == .network, flushFailures <= Self.maxAutoRetries else { return }
        let delay = Self.backoffSeconds(failures: flushFailures)
        let gen = walletGeneration
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self, gen == self.walletGeneration else { return }
            await self.flush()
        }
    }

    /// Начисление, ещё не принятое сервером. Ключ — один на начисление:
    /// ретрай после обрыва сети не начислит дважды.
    private struct PendingEarn: Codable {
        let key: String
        let amount: Int
        let source: String
        /// Уходило ли на сервер. Отправленное могло быть зачислено (ответ
        /// потерялся), поэтому сливать его с соседями нельзя — только с тем же
        /// ключом. `nil` — очередь старой сборки: считаем отправленным.
        var sent: Bool?
    }
    /// Потолок одного начисления на сервере (`BONUS_EARN_MAX_PER_CALL`):
    /// слитое начисление крупнее сервер урезал бы.
    static let maxEarnPerCall = 100
    /// Очередь хранится ПО ПОЛЬЗОВАТЕЛЮ (`san.bonus.pendingEarns.<uid>`):
    /// выход из аккаунта без сети не должен стирать неотправленное «+N» —
    /// оно дойдёт, когда этот же человек войдёт снова. Ключ без uid — очередь
    /// старой сборки и начисления до подключения кошелька; её забирает первый
    /// подключённый пользователь.
    private static let legacyPendingKey = "san.bonus.pendingEarns"
    static func pendingKey(userID: String) -> String { "san.bonus.pendingEarns.\(userID)" }
    /// Чья очередь сейчас в памяти: uid, `""` — общий ключ, `nil` — никуда
    /// не пишем (сразу после выхода, пока очередь прежнего пользователя
    /// снимается из памяти).
    private var pendingOwner: String?
    private var pending: [PendingEarn] = [] {
        didSet {
            if let owner = pendingOwner, let data = try? JSONEncoder().encode(pending) {
                UserDefaults.standard.set(data, forKey: owner.isEmpty ? Self.legacyPendingKey
                                                                      : Self.pendingKey(userID: owner))
            }
            let total = pendingTotal
            if syncingAmount != total { syncingAmount = total }
        }
    }

    private static func loadPending(forKey key: String) -> [PendingEarn] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([PendingEarn].self, from: data) else { return [] }
        return saved
    }
    private var pendingTotal: Int { pending.reduce(0) { $0 + $1.amount } }

    /// Заработано, но сервер ещё не подтвердил (очередь `earnBonus`, нет сети).
    /// Экран показывает это отдельно: такие бонусы видны в балансе, но
    /// потратить их нельзя, пока они не дошли, — и сервер на покупку ответил
    /// бы «не хватает», что выглядело как ошибка приложения.
    @Published public private(set) var syncingAmount: Int = 0

    /// Сколько можно потратить прямо сейчас: подтверждённое сервером. Без
    /// серверного кошелька (мок, тесты) — весь баланс, как раньше.
    public var spendableBalance: Int {
        usesServerWallet ? max(0, balance - syncingAmount) : balance
    }

    /// «Сейчас» приходит из [clock] — иначе счётчик активных минут и дневной
    /// лимит нельзя проверить тестом, не дожидаясь реального времени.
    public init(clock: Clock = SystemClock(), wallet: BonusWalletService? = nil) {
        self.clock = clock
        self.wallet = wallet
        self.lastInteraction = clock.now
        activeSeconds = storedActive
        if wallet != nil {
            pendingOwner = ""
            let saved = Self.loadPending(forKey: Self.legacyPendingKey)
            if !saved.isEmpty { pending = saved }
        }
        // Прежняя сборка писала `san.bonus.serverCapDay` на ЛЮБОЙ урезанный
        // источник, и после перезапуска потолок Diamond становился общим.
        // Ключ больше не читаем — общий потолок живёт под своим.
        UserDefaults.standard.removeObject(forKey: "san.bonus.serverCapDay")
        restoreServerCaps()
    }

    /// «Сейчас» по часам движка — для напоминания и экранов, которым нужен
    /// тот же день, что и счётчикам.
    public var now: Date { clock.now }

    // MARK: Честный итог начисления

    /// Сервер зачислил меньше, чем показала игра (дневной потолок, потолок
    /// источника). Экран обязан сказать об этом, а не молча убрать «+N».
    /// Публикуется ТОЛЬКО для урезанных начислений — `granted < requested`
    /// всегда; итог одного источника, а не сумма по разным играм.
    public struct EarnNotice: Equatable, Identifiable {
        public let id: UUID
        public let requested: Int
        public let granted: Int
        public let source: String
        /// Общий потолок кошелька (сегодня не платит ничто), а не потолок источника.
        public let daily: Bool

        public init(id: UUID = UUID(), requested: Int, granted: Int, source: String, daily: Bool = false) {
            self.id = id; self.requested = requested; self.granted = granted
            self.source = source; self.daily = daily
        }
    }

    /// Последнее урезанное начисление — пока экран его не снял (`clearEarnNotice`).
    @Published public private(set) var earnNotice: EarnNotice?

    public func clearEarnNotice() { earnNotice = nil }

    // MARK: Итог захода в игру

    /// Сколько принёс текущий/последний заход в игру — по ответам СЕРВЕРА:
    /// зачисленное плюс ещё не подтверждённое, минус то, что сервер урезал или
    /// отклонил. Хаб показывает «+N» по нему, а не по тому, что насчитала игра:
    /// иначе после «Начислено 3 из 10» всплывало «+10 🎉». Время в приложении
    /// сюда не входит — оно не часть партии.
    @Published public private(set) var sessionEarned: Int = 0
    private var sessionKeys: Set<String> = []

    /// Открыли игру: новый отсчёт.
    public func beginGameSession() {
        sessionEarned = 0
        sessionKeys = []
    }

    private func noteSessionShortfall(key: String, by amount: Int) {
        guard amount > 0, sessionKeys.contains(key) else { return }
        sessionEarned = max(0, sessionEarned - amount)
    }

    /// Сервер больше не зачисляет сегодня (общий дневной потолок). Игры в
    /// этот день ничего не обещают и ничего не ставят в очередь; сбрасывается
    /// сменой суток по Бишкеку и сменой пользователя.
    @Published public private(set) var serverDailyCapReached: Bool = false
    /// День общего потолка. Пишется ТОЛЬКО когда сервер ответил `capReason:
    /// "daily"` — потолок Diamond или времени сюда не попадает, иначе после
    /// перезапуска он превращался бы в запрет для всех игр.
    @AppStorage("san.bonus.serverGlobalCapDay") private var serverGlobalCapDay: String = ""
    /// Источники, упёршиеся в свой серверный потолок сегодня. Персистентны
    /// вместе с днём: перезапуск не должен снова обещать «+N» за Diamond.
    @Published public private(set) var cappedSourcesToday: Set<String> = []
    private static let cappedSourcesKey = "san.bonus.serverCappedSources"
    private static let cappedSourcesDayKey = "san.bonus.serverCappedSourcesDay"
    /// Остаток потолка источника по последнему ответу сервера (тот же день).
    private var serverSourceLeft: [String: Int] = [:]
    private var serverSourceLeftDay = ""
    /// Запасной путь для старого сервера без `capReason`: эти источники имеют
    /// свой потолок, урезание остальных — общий потолок.
    private static let legacySourceCappedSources: Set<String> = ["time", BonusGame.diamond.source]

    private func restoreServerCaps() {
        let today = Self.dayKey(clock.now)
        serverDailyCapReached = serverGlobalCapDay == today
        let d = UserDefaults.standard
        if d.string(forKey: Self.cappedSourcesDayKey) == today {
            cappedSourcesToday = Set(d.stringArray(forKey: Self.cappedSourcesKey) ?? [])
        } else {
            cappedSourcesToday = []
        }
    }

    private func persistCappedSources(day: String) {
        let d = UserDefaults.standard
        d.set(day, forKey: Self.cappedSourcesDayKey)
        d.set(Array(cappedSourcesToday).sorted(), forKey: Self.cappedSourcesKey)
    }

    /// Снимает отметки потолков, если сутки сменились.
    private func refreshServerCapDay() {
        let today = Self.dayKey(clock.now)
        if serverDailyCapReached, serverGlobalCapDay != today { serverDailyCapReached = false }
        if !cappedSourcesToday.isEmpty,
           UserDefaults.standard.string(forKey: Self.cappedSourcesDayKey) != today {
            cappedSourcesToday = []
        }
        if serverSourceLeftDay != today { serverSourceLeft = [:]; serverSourceLeftDay = today }
    }

    /// Упёрся ли источник в серверный потолок сегодня (общий или свой).
    public func isServerCapped(_ source: String) -> Bool {
        guard usesServerWallet else { return false }
        refreshServerCapDay()
        return serverDailyCapReached || cappedSourcesToday.contains(source)
    }

    private func noteGlobalCap() {
        serverGlobalCapDay = Self.dayKey(clock.now)
        if !serverDailyCapReached { serverDailyCapReached = true }
    }

    private func noteSourceCap(_ source: String) {
        refreshServerCapDay()
        cappedSourcesToday.insert(source)
        persistCappedSources(day: Self.dayKey(clock.now))
    }

    /// Применяет ответ `earnBonus`: остатки и — при урезании — чей потолок.
    /// Причину называет сервер (`capReason`); угадывание по имени источника
    /// осталось только для сервера без этого поля.
    private func applyEarnOutcome(_ r: BonusEarnOutcome, requested: Int, source: String, key: String) {
        refreshServerCapDay()
        if let left = r.sourceLeft { serverSourceLeft[source] = left }
        let shortfall = max(0, requested - r.granted)
        noteSessionShortfall(key: key, by: shortfall)
        // Остаток источника исчерпан — дальше он не платит, даже без урезания.
        if r.sourceLeft == 0 { noteSourceCap(source) }
        if r.dailyLeft == 0 { noteGlobalCap() }
        guard shortfall > 0 else { return }
        let reason: BonusEarnCapReason
        if let given = r.capReason {
            reason = given
        } else if r.dailyLeft != nil {
            // Новый сервер, но причины нет: урезания по его мнению не было.
            return
        } else {
            reason = Self.legacySourceCappedSources.contains(source) ? .source : .daily
        }
        switch reason {
        case .daily: noteGlobalCap()
        case .source: noteSourceCap(source)
        // Слишком крупный вызов — не потолок дня. Очередь сама держит ≤ 100,
        // так что сюда попадает только ошибка; потолков не ставим и плашку
        // «дневной лимит» не показываем — это была бы неправда.
        case .perCall: return
        }
        let daily = reason == .daily
        if let prev = earnNotice, prev.source == source, prev.daily == daily {
            earnNotice = EarnNotice(requested: prev.requested + requested,
                                    granted: prev.granted + r.granted, source: source, daily: daily)
        } else {
            earnNotice = EarnNotice(requested: requested, granted: r.granted, source: source, daily: daily)
        }
    }

    /// Подключает кошелёк вошедшего пользователя: заводит его на сервере
    /// (первый раз — с переносом баланса устройства), слушает баланс и
    /// досылает начисления из очереди. Повторный вызов для того же
    /// пользователя ничего не делает.
    public func attach(userID: String) {
        guard let wallet, !userID.isEmpty, userID != walletUserID else { return }
        walletTask?.cancel()
        walletGeneration += 1
        flushing = false
        let gen = walletGeneration
        walletUserID = userID
        walletSynced = false
        syncInFlight = false
        resetBackoff()
        // Очередь этого пользователя (оставшаяся с прошлого входа) плюс общая
        // (старая сборка, начисления до подключения) — общую забирает он один.
        let mine = Self.loadPending(forKey: Self.pendingKey(userID: userID))
        let shared = pendingOwner == "" ? pending : []
        pendingOwner = userID
        pending = mine + shared.filter { e in !mine.contains { $0.key == e.key } }
        UserDefaults.standard.removeObject(forKey: Self.legacyPendingKey)
        migrationBalance = max(0, balance - pendingTotal)
        restoreDayCounters(userID: userID)
        recomputeBalance()
        walletTask = Task { [weak self] in
            await self?.syncWallet()
            await self?.flush()
            for await b in wallet.balance(userID: userID) {
                guard let self, !Task.isCancelled, gen == self.walletGeneration else { return }
                self.applyServerBalance(b)
            }
        }
    }

    /// Досылает очередь начислений. Зовётся при возврате в приложение: сеть
    /// могла появиться. Кошелёк заводится один раз за сессию (`attach`);
    /// повторный `bonusWalletSync` — только если он тогда не прошёл, а не на
    /// каждый выход на передний план.
    public func retryPending() {
        guard usesServerWallet, !walletUserID.isEmpty else { return }
        refreshDay()
        resetBackoff()
        let needsSync = !walletSynced
        guard needsSync || !pending.isEmpty else { return }
        Task {
            if needsSync { await syncWallet() }
            await flush()
        }
    }

    /// Забрать новые гранты (приглашённый друг) — явным действием экрана, а
    /// не на каждом возврате в приложение.
    public func refreshGrants() {
        guard usesServerWallet, !walletUserID.isEmpty else { return }
        lastGrantsRefresh = clock.now
        Task { await syncWallet(force: true) }
    }

    /// То же, но не чаще раза в `minInterval` — для появления экрана бонусов:
    /// приветственный бонус приглашённого иначе приходил только со следующей
    /// сессией.
    public func refreshGrantsIfStale(minInterval: TimeInterval = 60) {
        if let last = lastGrantsRefresh, clock.now.timeIntervalSince(last) < minInterval { return }
        refreshGrants()
    }
    private var lastGrantsRefresh: Date?

    /// Снимает вчерашние отметки (потолки, дневные счётчики), не дожидаясь
    /// следующего начисления: после полуночи по Бишкеку плашка «лимит на
    /// сегодня» иначе висела до первой награды. Зовётся при возврате в
    /// приложение и при появлении экрана бонусов.
    public func refreshDay() {
        resetDailyIfNeeded()
        refreshServerCapDay()
    }

    /// Баланс, подтверждённый сервером (ответ покупки или снапшот кошелька).
    public func applyServerBalance(_ value: Int) {
        guard usesServerWallet else { return }
        serverBalance = value
        balance = value + pendingTotal
    }

    /// Отказы `earnBonus`, после которых повтор бессмысленен.
    /// `anonymous_not_allowed` сюда НЕ входит: после входа в аккаунт тот же
    /// uid получит кошелёк, и молча выбросить заработанное «+N» было бы
    /// кражей у игрока. Такие начисления ждут в очереди (`syncProblem`).
    private static let permanentEarnErrors: Set<String> = [
        "key_reused", "bad_amount", "bad_source", "missing_key",
    ]

    /// Почему очередь начислений стоит. Бонусы при этом НЕ теряются — они
    /// ждут в очереди; экран говорит, что делать.
    public enum SyncProblem: Equatable, Sendable {
        /// Нет сети или сбой сервера: повторим сами.
        case network
        /// Сервер не принимает эту сборку (App Check): помогает только обновление.
        case appUpdateNeeded
        /// Анонимный аккаунт: кошелёк заведётся после входа.
        case signInRequired
    }

    /// Причина, по которой начисления не доходят; `nil` — очередь в порядке.
    @Published public private(set) var syncProblem: SyncProblem?

    private func setSyncProblem(_ p: SyncProblem?) {
        if syncProblem != p { syncProblem = p }
    }

    static func syncProblem(forEarnError code: String?) -> SyncProblem {
        switch code {
        case "app_check_failed": return .appUpdateNeeded
        case "anonymous_not_allowed": return .signInRequired
        default: return .network
        }
    }

    /// `force` — повторный sync уже заведённого кошелька: переноса он не
    /// делает (сервер переносит один раз), но забирает новые гранты —
    /// награду за приглашённого, приветственный бонус.
    private func syncWallet(force: Bool = false) async {
        // Холодный старт звал sync двумя-тремя путями сразу (attach,
        // retryPending, возврат в приложение) — один запрос за раз.
        guard let wallet, !walletUserID.isEmpty, force || !walletSynced, !syncInFlight else { return }
        let gen = walletGeneration
        let migrate = migrationBalance
        syncInFlight = true
        let b = try? await wallet.sync(localBalance: migrate)
        // Пока ждали ответа, пользователь вышел или сменился — ответ чужой.
        guard gen == walletGeneration else { return }
        syncInFlight = false
        guard let b else { return }
        walletSynced = true
        applyServerBalance(b)
    }

    /// Начисление в режиме серверного кошелька: сразу на экран, в очередь, на сервер.
    private func credit(_ amount: Int, source: String) {
        let key = UUID().uuidString
        if source != "time" {
            sessionKeys.insert(key)
            sessionEarned += amount
        }
        pending.append(PendingEarn(key: key, amount: amount, source: source, sent: false))
        recomputeBalance()
        Task { await flush() }
    }

    /// Баланс на экране = подтверждённое сервером + ещё не отправленное.
    private func recomputeBalance() {
        balance = (serverBalance ?? migrationBalance) + pendingTotal
    }

    /// Сливает подряд идущие НЕотправленные начисления одного источника в
    /// одно (до `maxEarnPerCall`): яблоко за яблоком иначе были бы запросом
    /// за запросом. Отправленное не трогаем — его ключ мог уже сработать.
    private func coalescePending() {
        guard pending.count > 1 else { return }
        var out: [PendingEarn] = []
        for e in pending {
            if let last = out.last, last.sent == false, e.sent == false,
               last.source == e.source, last.amount + e.amount <= Self.maxEarnPerCall,
               // Итог захода считается по ключам: не сливаем начисление партии
               // с начислением до неё.
               sessionKeys.contains(last.key) == sessionKeys.contains(e.key) {
                out[out.count - 1] = PendingEarn(key: last.key, amount: last.amount + e.amount,
                                                 source: last.source, sent: false)
            } else {
                out.append(e)
            }
        }
        if out.count != pending.count { pending = out }
    }

    /// Досылает очередь по одному. Обрыв сети — стоп до следующего раза
    /// (начисление, вход, возврат в приложение); ответ-отказ, который не
    /// исправить повтором, — выкидываем, чтобы не застрять навсегда.
    private func flush() async {
        guard let wallet, !walletUserID.isEmpty, !flushing else { return }
        let gen = walletGeneration
        flushing = true
        // Сброс посреди запроса сам снял `flushing` и начал новое поколение —
        // чужой флаг не трогаем.
        defer { if gen == walletGeneration { flushing = false } }
        while gen == walletGeneration {
            coalescePending()
            guard var next = pending.first else { setSyncProblem(nil); return }
            if next.sent != true {
                next.sent = true
                pending[0] = next          // до отправки: ключ «засвечен», сливать нельзя
            }
            let r = try? await wallet.earn(amount: next.amount, source: next.source,
                                           idempotencyKey: next.key)
            guard gen == walletGeneration else { return }
            guard let r else {
                noteFlushFailure(problem: .network, entryKey: next.key)
                return
            }
            if r.errorCode == "no_wallet" {
                // Кошелёк ещё не заведён (sync не дошёл) — заводим и повторяем.
                walletSynced = false
                await syncWallet()
                guard gen == walletGeneration, walletSynced else { return }
                continue
            }
            // Отказ, который повтор не исправит, — выкидываем. Сбой сервера
            // (earn_failed и т.п.) — оставляем в очереди: это бонусы игрока.
            if !r.ok, !Self.permanentEarnErrors.contains(r.errorCode ?? "") {
                noteFlushFailure(problem: Self.syncProblem(forEarnError: r.errorCode),
                                 entryKey: next.key)
                return
            }
            setSyncProblem(nil)
            flushFailures = 0
            entryFailures[next.key] = nil
            // По ключу, а не `removeFirst()`: очередь могла поменяться за время запроса.
            pending.removeAll { $0.key == next.key }
            if r.ok {
                applyEarnOutcome(r, requested: next.amount, source: next.source, key: next.key)
                applyServerBalance(r.balance)
            } else {
                // Отказ навсегда: показанные «+N» убираем из баланса и из итога захода.
                noteSessionShortfall(key: next.key, by: next.amount)
                recomputeBalance()
            }
        }
    }

    public var progress: Double { Double(activeSeconds) / Double(goalSeconds) }

    /// Получил ли пользователь бонус за 30 минут сегодня.
    /// Если нет — шлём напоминания каждые 4 часа.
    /// День — тот же, что у дневных счётчиков и сервера: по Бишкеку и по
    /// часам движка, а не по `Date()` и календарю телефона.
    public var reachedGoalToday: Bool {
        lastAwardAt > 0 &&
        Self.dayKey(Date(timeIntervalSince1970: lastAwardAt)) == Self.dayKey(clock.now)
    }

    // MARK: Удалённый выключатель начисления за время

    /// Время в приложении не платит (Remote Config `ios_bonus_time_enabled`).
    @Published public private(set) var timeEarningPaused = false

    public func setTimeEarningPaused(_ paused: Bool) {
        if timeEarningPaused != paused { timeEarningPaused = paused }
        if paused { isCounting = false }
    }

    public var remaining: String {
        let left = max(0, goalSeconds - activeSeconds)
        return String(format: "%02d:%02d", left / 60, left % 60)
    }

    // Любое взаимодействие продлевает «активность»
    public func registerInteraction() {
        lastInteraction = clock.now
    }

    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    public func pause() {
        timer?.invalidate()
        timer = nil
        isCounting = false
        storedActive = activeSeconds
    }

    private func tick() {
        resetDailyIfNeeded()
        // Достигнут дневной лимит активности — больше не копим (анти-фарм).
        // Выключено удалённо или сервер сегодня больше не зачисляет — тоже.
        guard awardsToday < dailyGoalCap, !timeEarningPaused,
              !isServerCapped("time") else { isCounting = false; return }

        let active = clock.now.timeIntervalSince(lastInteraction) < idleTimeout
        isCounting = active
        guard active else { return }

        activeSeconds += 1
        if activeSeconds >= goalSeconds {
            award()
        }
        if activeSeconds % 15 == 0 { storedActive = activeSeconds }   // периодически сохраняем
    }

    private func award() {
        resetDailyIfNeeded()
        activeSeconds = 0
        storedActive = 0
        guard awardsToday < dailyGoalCap, !timeEarningPaused else { return }   // дневной лимит — без начисления
        if usesServerWallet { credit(rewardPerGoal, source: "time") } else { balance += rewardPerGoal }
        awardsToday += 1
        completedCycles += 1
        lastReward = rewardPerGoal
        lastAwardAt = clock.now.timeIntervalSince1970
        // имитация лёгкой вибрации
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // цель достигнута — снимаем напоминание на сегодня
        NotificationManager.cancelReminder()
    }

    /// Бонусы за мини-игру. Начисляет всё, что заработано: дневного потолка нет.
    ///
    /// Возвращаемое значение осталось — вью показывает «+N» именно по нему, и
    /// врать пользователю нельзя. Сейчас оно всегда равно `amount`, но подпись
    /// сохранена: вернуть любой тормоз (ступенька, лимит за сессию) можно, не
    /// переписывая четыре экрана.
    @discardableResult
    public func awardGameplay(_ amount: Int, source: String = "game") -> Int {
        guard amount > 0, earnsBonus(source: source) else { return 0 }
        resetDailyIfNeeded()
        // Сервер сегодня больше не зачисляет — «+N» был бы неправдой, а
        // очередь — запросами, которые вернутся нулём.
        if isServerCapped(source) { return 0 }
        var grant = amount
        // Дневной лимит игры (Remote Config `ios_bonus_<game>_daily_cap`):
        // выдаём только остаток до лимита.
        if let game = BonusGame(source: source), let cap = bonusDailyCaps[game] {
            grant = min(amount, max(0, cap - earnedToday(game)))
            guard grant > 0 else { return 0 }
            addEarnedToday(game, grant)
        }
        gameEarnedTodayStored += grant
        // Новое начисление — прежняя плашка о чужом потолке устарела.
        if let n = earnNotice, n.source != source { earnNotice = nil }
        if usesServerWallet {
            credit(grant, source: source)
        } else {
            balance += grant
            sessionEarned += grant
        }
        lastReward = grant
        AnalyticsLog.log(.bonusEarned, ["source": source, "amount": grant])
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return grant
    }

    // MARK: Удалённый выключатель начисления по играм

    /// Игры, за которые начисление выключено удалённо (Remote Config
    /// `ios_bonus_<game>_enabled`). Применяется сразу, не со следующего
    /// запуска: игра не исчезает, только перестаёт платить — а если её
    /// фармят, ждать перезапуска нельзя.
    @Published public private(set) var bonusPausedGames: Set<BonusGame> = []

    public func setBonusPaused(_ games: Set<BonusGame>) {
        if bonusPausedGames != games { bonusPausedGames = games }
    }

    public func earnsBonus(_ game: BonusGame) -> Bool { !bonusPausedGames.contains(game) }

    /// Источник, не являющийся игрой («game», время в приложении), не
    /// выключается этим переключателем.
    func earnsBonus(source: String) -> Bool {
        guard let game = BonusGame(source: source) else { return true }
        return earnsBonus(game)
    }

    // MARK: Дневные лимиты по играм

    /// Лимиты по играм; игры нет — без лимита. По умолчанию только Diamond
    /// (30 в день); консоль меняет их сразу, без перезапуска.
    @Published public private(set) var bonusDailyCaps: [BonusGame: Int] = BonusCaps.defaults

    public func setBonusDailyCaps(_ caps: [BonusGame: Int]) {
        if bonusDailyCaps != caps { bonusDailyCaps = caps }
    }

    /// Сколько игра ещё может принести сегодня; `nil` — без лимита.
    /// Сервер сегодня больше не зачисляет эту игру (её потолок или общий) —
    /// `0`, даже если местный счётчик думает иначе: «ещё 12» при закрытом
    /// сервере было бы обещанием, которое не сбудется. Остаток источника из
    /// ответа сервера тоже учитывается — он точнее местного счётчика.
    public func remainingToday(_ game: BonusGame) -> Int? {
        if isServerCapped(game.source) { return 0 }
        let local: Int? = bonusDailyCaps[game].map { cap in
            let spent = counterDate == Self.dayKey(clock.now) ? earnedToday(game) : 0
            return max(0, cap - spent)
        }
        guard let server = serverSourceLeft[game.source] else { return local }
        return min(local ?? server, server)
    }

    /// Начислено сегодня по играм: `[rawValue: бонусы]` в UserDefaults.
    private static let earnedByGameKey = "san.bonus.earnedTodayByGame"

    private func earnedToday(_ game: BonusGame) -> Int {
        let dict = UserDefaults.standard.dictionary(forKey: Self.earnedByGameKey) as? [String: Int] ?? [:]
        if let value = dict[game.rawValue] { return value }
        // Счётчик Diamond жил под своим ключом: перенос сегодняшнего прогресса,
        // чтобы обновление приложения не выдало ещё 30 бонусов в тот же день.
        return game == .diamond ? endlessEarnedTodayStored : 0
    }

    private func addEarnedToday(_ game: BonusGame, _ amount: Int) {
        var dict = UserDefaults.standard.dictionary(forKey: Self.earnedByGameKey) as? [String: Int] ?? [:]
        dict[game.rawValue] = earnedToday(game) + amount
        UserDefaults.standard.set(dict, forKey: Self.earnedByGameKey)
        objectWillChange.send()
    }

    private func clearEarnedToday() {
        UserDefaults.standard.removeObject(forKey: Self.earnedByGameKey)
        endlessEarnedTodayStored = 0
    }

    /// Сколько бонусов игры принесли сегодня. Уже не лимит, а счётчик: экран
    /// показывает по нему «сегодня +N», и он обнуляется сменой суток.
    public var gameEarnedToday: Int { gameEarnedTodayStored }

    /// Прямое начисление без дневного лимита — только для реферальных/серверных
    /// наград (разовые, не фармятся). Мини-игры используют `awardGameplay`.
    ///
    /// С серверным кошельком ничего не делает: такие награды сервер зачисляет
    /// сам (`bonusWalletSync` забирает `bonusGrants`), а клиентское
    /// начисление было бы вторым.
    public func addFromGame(_ amount: Int) {
        guard amount > 0, !usesServerWallet else { return }
        balance += amount
        lastReward = amount
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: Дневные счётчики по пользователю

    private static func dayCountersKey(userID: String) -> String { "san.bonus.dayCounters.\(userID)" }

    /// Снимок сегодняшних счётчиков пользователя — при выходе. Хранилище
    /// счётчиков общее для устройства, и без снимка выход-вход обнулял бы
    /// лимиты Diamond и времени.
    private func saveDayCounters(userID: String) {
        let today = Self.dayKey(clock.now)
        guard counterDate == today else { return }
        var byGame: [String: Int] = [:]
        for game in BonusGame.allCases { byGame[game.rawValue] = earnedToday(game) }
        let snapshot: [String: Any] = [
            "day": today, "awards": awardsToday, "games": gameEarnedTodayStored, "byGame": byGame,
            "globalCap": serverGlobalCapDay == today,
            "cappedSources": Array(cappedSourcesToday).sorted(),
        ]
        UserDefaults.standard.set(snapshot, forKey: Self.dayCountersKey(userID: userID))
    }

    /// Возвращает сегодняшние счётчики пользователя при входе (вчерашние не нужны).
    private func restoreDayCounters(userID: String) {
        let key = Self.dayCountersKey(userID: userID)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let today = Self.dayKey(clock.now)
        guard let snap = UserDefaults.standard.dictionary(forKey: key),
              snap["day"] as? String == today else { return }
        resetDailyIfNeeded()
        awardsToday = max(awardsToday, snap["awards"] as? Int ?? 0)
        gameEarnedTodayStored = max(gameEarnedTodayStored, snap["games"] as? Int ?? 0)
        if let byGame = snap["byGame"] as? [String: Int] {
            var dict = UserDefaults.standard.dictionary(forKey: Self.earnedByGameKey) as? [String: Int] ?? [:]
            for (k, v) in byGame { dict[k] = max(dict[k] ?? 0, v) }
            UserDefaults.standard.set(dict, forKey: Self.earnedByGameKey)
        }
        if snap["globalCap"] as? Bool == true { noteGlobalCap() }
        let sources = snap["cappedSources"] as? [String] ?? []
        if !sources.isEmpty {
            cappedSourcesToday.formUnion(sources)
            persistCappedSources(day: today)
        }
        objectWillChange.send()
    }

    /// Сбрасывает дневные счётчики при смене календарного дня.
    private func resetDailyIfNeeded() {
        let key = Self.dayKey(clock.now)
        if counterDate != key {
            counterDate = key
            awardsToday = 0
            refreshServerCapDay()
            gameEarnedTodayStored = 0
            clearEarnedToday()
        }
    }

    /// Ключ дня — из переданного времени: статический метод часов не видит,
    /// а брать их из системы значило бы вернуть скрытую зависимость.
    /// Сутки — по Бишкеку, как у сервера (`bishkekDayKey` в `earnBonus`).
    /// По часам телефона дневные лимиты (Diamond, время) сбрасывались в другой
    /// момент, чем на сервере: гость в другом поясе видел «+N», а сервер
    /// резал их как вчерашние/сегодняшние по-своему.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Bishkek") ?? TimeZone(secondsFromGMT: 6 * 3600)
        return f
    }()

    static func dayKey(_ now: Date) -> String {
        dayFormatter.string(from: now)
    }

    /// Локальное списание — только без серверного кошелька. С ним покупки
    /// идут через `CouponStore` → `buyCoupon`: списанное на устройстве сервер
    /// тут же вернул бы снапшотом, и купон достался бы бесплатно.
    public func spend(_ amount: Int) -> Bool {
        guard !usesServerWallet else { return false }
        guard balance >= amount else { return false }
        balance -= amount
        return true
    }

    public func clearRewardFlag() { lastReward = nil }

    /// Обнуляет кошелёк при смене пользователя (выход, удаление аккаунта).
    ///
    /// Хранилище здесь — `@AppStorage`, то есть УСТРОЙСТВО, а не аккаунт:
    /// без этого сброса гость выходил, заходил снова — и видел чужой (свой
    /// прежний) баланс, дневные лимиты и прогресс. Дневные счётчики тоже
    /// сбрасываем, иначе анти-фарм обходится простым перезаходом.
    public func resetForNewUser() {
        pause()
        // Дневные счётчики прежнего пользователя — под его uid: перезаход в
        // тот же аккаунт не должен обнулять дневные лимиты (анти-фарм).
        if !walletUserID.isEmpty { saveDayCounters(userID: walletUserID) }
        // Кошелёк прежнего пользователя: отписываемся, его неотправленные
        // начисления не должны уйти в кошелёк следующего. Они остаются на
        // диске под его uid и дойдут при его следующем входе.
        walletTask?.cancel()
        walletTask = nil
        walletGeneration += 1     // задачи прежнего пользователя выйдут после своего await
        flushing = false
        syncInFlight = false
        resetBackoff()
        entryFailures = [:]
        walletUserID = ""
        walletSynced = false
        serverBalance = nil
        migrationBalance = 0
        pendingOwner = nil        // очистка памяти не стирает его очередь на диске
        pending = []
        if usesServerWallet { pendingOwner = "" }
        earnNotice = nil
        serverDailyCapReached = false
        serverGlobalCapDay = ""
        cappedSourcesToday = []
        UserDefaults.standard.removeObject(forKey: Self.cappedSourcesKey)
        UserDefaults.standard.removeObject(forKey: Self.cappedSourcesDayKey)
        serverSourceLeft = [:]
        sessionEarned = 0
        sessionKeys = []
        syncProblem = nil
        balance = 0
        storedActive = 0
        activeSeconds = 0
        completedCycles = 0
        lastAwardAt = 0
        counterDate = ""
        awardsToday = 0
        gameEarnedTodayStored = 0
        clearEarnedToday()
        lastReward = nil
    }
}
