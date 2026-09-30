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
    public let goalSeconds: Int = 30 * 60          // цель: 30 минут
    public let rewardPerGoal: Int = 1              // бонусов за цикл (почти ноль)
    public let dailyGoalCap: Int = 4               // не больше 4 циклов активности в день (≤4/день)
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
    private var serverBalance: Int?
    /// Баланс устройства на момент подключения — его сервер один раз
    /// перенесёт в кошелёк (с потолком). Всё заработанное после — в очереди.
    private var migrationBalance = 0
    private var walletSynced = false

    /// Начисление, ещё не принятое сервером. Ключ — один на начисление:
    /// ретрай после обрыва сети не начислит дважды.
    private struct PendingEarn: Codable {
        let key: String
        let amount: Int
        let source: String
    }
    private static let pendingKey = "san.bonus.pendingEarns"
    private var pending: [PendingEarn] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(pending) {
                UserDefaults.standard.set(data, forKey: Self.pendingKey)
            }
        }
    }
    private var pendingTotal: Int { pending.reduce(0) { $0 + $1.amount } }

    /// «Сейчас» приходит из [clock] — иначе счётчик активных минут и дневной
    /// лимит нельзя проверить тестом, не дожидаясь реального времени.
    public init(clock: Clock = SystemClock(), wallet: BonusWalletService? = nil) {
        self.clock = clock
        self.wallet = wallet
        self.lastInteraction = clock.now
        activeSeconds = storedActive
        if wallet != nil,
           let data = UserDefaults.standard.data(forKey: Self.pendingKey),
           let saved = try? JSONDecoder().decode([PendingEarn].self, from: data) {
            pending = saved
        }
    }

    /// Подключает кошелёк вошедшего пользователя: заводит его на сервере
    /// (первый раз — с переносом баланса устройства), слушает баланс и
    /// досылает начисления из очереди. Повторный вызов для того же
    /// пользователя ничего не делает.
    public func attach(userID: String) {
        guard let wallet, !userID.isEmpty, userID != walletUserID else { return }
        walletTask?.cancel()
        walletUserID = userID
        walletSynced = false
        migrationBalance = max(0, balance - pendingTotal)
        walletTask = Task { [weak self] in
            await self?.syncWallet()
            await self?.flush()
            for await b in wallet.balance(userID: userID) {
                guard let self, !Task.isCancelled else { return }
                self.applyServerBalance(b)
            }
        }
    }

    /// Досылает очередь начислений (и заводит кошелёк, если в прошлый раз не
    /// вышло). Зовётся при возврате в приложение: сеть могла появиться.
    public func retryPending() {
        guard usesServerWallet, !walletUserID.isEmpty else { return }
        Task { await syncWallet(force: true); await flush() }
    }

    /// Баланс, подтверждённый сервером (ответ покупки или снапшот кошелька).
    public func applyServerBalance(_ value: Int) {
        guard usesServerWallet else { return }
        serverBalance = value
        balance = value + pendingTotal
    }

    /// Отказы `earnBonus`, после которых повтор бессмысленен.
    private static let permanentEarnErrors: Set<String> = [
        "key_reused", "bad_amount", "bad_source", "missing_key", "anonymous_not_allowed",
    ]

    /// `force` — повторный sync уже заведённого кошелька: переноса он не
    /// делает (сервер переносит один раз), но забирает новые гранты —
    /// награду за приглашённого, приветственный бонус.
    private func syncWallet(force: Bool = false) async {
        guard let wallet, force || !walletSynced else { return }
        guard let b = try? await wallet.sync(localBalance: migrationBalance) else { return }
        walletSynced = true
        applyServerBalance(b)
    }

    /// Начисление в режиме серверного кошелька: сразу на экран, в очередь, на сервер.
    private func credit(_ amount: Int, source: String) {
        pending.append(PendingEarn(key: UUID().uuidString, amount: amount, source: source))
        balance = (serverBalance ?? migrationBalance) + pendingTotal
        Task { await flush() }
    }

    /// Досылает очередь по одному. Обрыв сети — стоп до следующего раза
    /// (начисление, вход, возврат в приложение); ответ-отказ, который не
    /// исправить повтором, — выкидываем, чтобы не застрять навсегда.
    private func flush() async {
        guard let wallet, !walletUserID.isEmpty, !flushing else { return }
        flushing = true
        defer { flushing = false }
        while let next = pending.first {
            guard let r = try? await wallet.earn(amount: next.amount, source: next.source,
                                                 idempotencyKey: next.key) else { return }
            if r.errorCode == "no_wallet" {
                // Кошелёк ещё не заведён (sync не дошёл) — заводим и повторяем.
                walletSynced = false
                await syncWallet()
                guard walletSynced else { return }
                continue
            }
            // Отказ, который повтор не исправит, — выкидываем. Сбой сервера
            // (earn_failed и т.п.) — оставляем в очереди: это бонусы игрока.
            if !r.ok, !Self.permanentEarnErrors.contains(r.errorCode ?? "") { return }
            pending.removeFirst()
            if r.ok { applyServerBalance(r.balance) }
        }
    }

    public var progress: Double { Double(activeSeconds) / Double(goalSeconds) }

    /// Получил ли пользователь бонус за 30 минут сегодня.
    /// Если нет — шлём напоминания каждые 4 часа.
    public var reachedGoalToday: Bool {
        lastAwardAt > 0 &&
        Calendar.current.isDateInToday(Date(timeIntervalSince1970: lastAwardAt))
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
        guard awardsToday < dailyGoalCap else { isCounting = false; return }

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
        guard awardsToday < dailyGoalCap else { return }   // дневной лимит — без начисления
        if usesServerWallet { credit(rewardPerGoal, source: "time") } else { balance += rewardPerGoal }
        awardsToday += 1
        completedCycles += 1
        lastReward = rewardPerGoal
        lastAwardAt = clock.now.timeIntervalSince1970
        // имитация лёгкой вибрации
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // цель достигнута — снимаем напоминания на сегодня
        NotificationManager.refresh(reachedGoalToday: true)
    }

    /// Бонусы за мини-игру. Начисляет всё, что заработано: дневного потолка нет.
    ///
    /// Возвращаемое значение осталось — вью показывает «+N» именно по нему, и
    /// врать пользователю нельзя. Сейчас оно всегда равно `amount`, но подпись
    /// сохранена: вернуть любой тормоз (ступенька, лимит за сессию) можно, не
    /// переписывая четыре экрана.
    @discardableResult
    public func awardGameplay(_ amount: Int, source: String = "game") -> Int {
        guard amount > 0 else { return 0 }
        resetDailyIfNeeded()
        gameEarnedTodayStored += amount
        if usesServerWallet { credit(amount, source: source) } else { balance += amount }
        lastReward = amount
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return amount
    }

    /// Начисление за БЕСКОНЕЧНУЮ игру — с дневным потолком.
    ///
    /// Обычные игры потолка не имеют: их партия кончается сама. Бесконечная не
    /// кончается никогда, и без потолка это был бы станок для бонусов.
    /// Возвращает реально начисленное — вью показывает именно его.
    @discardableResult
    public func awardEndlessGameplay(_ amount: Int,
                                     dailyCap: Int = GameEconomy.endlessDailyBonusCap,
                                     source: String = "game") -> Int {
        guard amount > 0 else { return 0 }
        resetDailyIfNeeded()
        let grant = min(amount, max(0, dailyCap - endlessEarnedTodayStored))
        guard grant > 0 else { return 0 }
        endlessEarnedTodayStored += grant
        return awardGameplay(grant, source: source)
    }

    /// Сколько бесконечная игра ещё может принести сегодня.
    ///
    /// Чистое чтение, без сброса счётчиков: его зовёт `body` вью, а менять
    /// опубликованное состояние посреди отрисовки SwiftUI запрещает. Смену
    /// суток учитываем сравнением ключа дня.
    public func remainingEndlessToday(dailyCap: Int = GameEconomy.endlessDailyBonusCap) -> Int {
        let spent = counterDate == Self.dayKey(clock.now) ? endlessEarnedTodayStored : 0
        return max(0, dailyCap - spent)
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

    /// Сбрасывает дневные счётчики при смене календарного дня.
    private func resetDailyIfNeeded() {
        let key = Self.dayKey(clock.now)
        if counterDate != key {
            counterDate = key
            awardsToday = 0
            gameEarnedTodayStored = 0
            endlessEarnedTodayStored = 0
        }
    }

    /// Ключ дня — из переданного времени: статический метод часов не видит,
    /// а брать их из системы значило бы вернуть скрытую зависимость.
    private static func dayKey(_ now: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: now)
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
        // Кошелёк прежнего пользователя: отписываемся, его неотправленные
        // начисления не должны уйти в кошелёк следующего.
        walletTask?.cancel()
        walletTask = nil
        walletUserID = ""
        walletSynced = false
        serverBalance = nil
        migrationBalance = 0
        pending = []
        balance = 0
        storedActive = 0
        activeSeconds = 0
        completedCycles = 0
        lastAwardAt = 0
        counterDate = ""
        awardsToday = 0
        gameEarnedTodayStored = 0
        endlessEarnedTodayStored = 0
        lastReward = nil
    }
}
