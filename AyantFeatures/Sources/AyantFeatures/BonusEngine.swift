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

    /// «Сейчас» приходит из [clock] — иначе счётчик активных минут и дневной
    /// лимит нельзя проверить тестом, не дожидаясь реального времени.
    public init(clock: Clock = SystemClock()) {
        self.clock = clock
        self.lastInteraction = clock.now
        activeSeconds = storedActive
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
        balance += rewardPerGoal
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
    public func awardGameplay(_ amount: Int) -> Int {
        guard amount > 0 else { return 0 }
        resetDailyIfNeeded()
        gameEarnedTodayStored += amount
        balance += amount
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
                                     dailyCap: Int = GameEconomy.endlessDailyBonusCap) -> Int {
        guard amount > 0 else { return 0 }
        resetDailyIfNeeded()
        let grant = min(amount, max(0, dailyCap - endlessEarnedTodayStored))
        guard grant > 0 else { return 0 }
        endlessEarnedTodayStored += grant
        return awardGameplay(grant)
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
    public func addFromGame(_ amount: Int) {
        guard amount > 0 else { return }
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

    public func spend(_ amount: Int) -> Bool {
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
