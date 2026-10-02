import Foundation

/// Чистая математика **баллов САН** (System 1) — зеркало серверных правил из
/// `functions/src/index.ts` (`scanCoupon` ветка C и `redeemVenuePoints`).
///
/// Сервер остаётся авторитетным: он всё равно пересчитывает начисление и списание
/// сам. Клиенту эти же функции нужны, чтобы **показать результат до скана**
/// («вам начислят 100 баллов», «не хватает 20», «ещё 42 мин до начисления») и не
/// отправлять заведомо провальный запрос.
///
/// Поэтому расхождение клиента с сервером = обещание в UI, которое не сбудется, —
/// и ловится оно только общим фикстуром `specs/fixtures/points-fixtures.json`,
/// который гоняют все три реализации (iOS, Android, Functions). Новый кейс идёт
/// в фикстур, а не в тесты одной платформы.
///
/// Зеркалит `android/domain/.../PointsMath.kt` на Android 1:1 (имена, порядок проверок, коды ошибок).
public enum PointsMath {

    // MARK: - Константы (совпадают с functions/src/index.ts)

    /// Потолок за одно начисление — страховка от опечатки в конфиге заведения.
    public static let maxPointsPerEarn = 10_000
    /// Потолок кэшбэка, % — защита от «50%» вместо «5%».
    public static let maxCashbackPercent: Double = 20
    /// Кулдаун начисления по умолчанию, мин.
    public static let defaultEarnCooldownMinutes = 60
    /// Кулдаун штампа карты лояльности, мин. (отдельная от баллов система).
    public static let defaultStampCooldownMinutes = 15
    /// Сгорание баллов по неактивности, мес.
    public static let defaultExpiryMonths = 6

    // MARK: - Начисление

    /// Сколько баллов начислит сервер за этот скан.
    ///
    /// Порядок проверок повторяет серверный: сначала режим и его входные данные,
    /// затем кап `maxPointsPerEarn`, затем «нечего начислять». Кулдаун сервер
    /// проверяет **после** расчёта суммы — здесь он вынесен в `canEarn(...)`.
    ///
    /// - Parameters:
    ///   - billAmount: сумма чека (режим `cashback`); отрицательная приводится к нулю.
    ///   - bandIndex: индекс нажатой кнопки-диапазона (режим `bands`).
    public static func award(config: PointsConfig, billAmount: Int?, bandIndex: Int?) -> Result<Int, PointsError> {
        guard config.pointsEnabled else { return .failure(.pointsOff) }

        let bill = max(0, billAmount ?? 0)
        var awarded: Int

        switch config.pointsMode {
        case "cashback":
            let pct = min(max(config.cashbackPercent.isFinite ? config.cashbackPercent : 0, 0), maxCashbackPercent)
            guard bill > 0 else { return .failure(.missingAmount) }
            // Порядок умножения/деления повторяет сервер (bill * pct / 100), иначе
            // на дробных процентах платформы разойдутся в последнем разряде.
            awarded = Int((Double(bill) * pct / 100).rounded())
        case "bands":
            guard let index = bandIndex, index >= 0, index < config.pointsBands.count else {
                return .failure(.badBand)
            }
            awarded = config.pointsBands[index].points
        default:
            // "flat" и любой незнакомый режим.
            awarded = config.pointsFlat
        }

        awarded = min(max(awarded, 0), maxPointsPerEarn)
        guard awarded > 0 else { return .failure(.noPoints) }
        return .success(awarded)
    }

    /// Эффективный кулдаун, мин.
    ///
    /// **`0` отключает кулдаун** (начислять можно хоть каждый скан) — как и любое
    /// отрицательное значение, которое приводится к нулю. Отсутствующего значения
    /// здесь не бывает: слой разбора (`FirebaseServices`) подставляет дефолтные
    /// 60 мин, ровно как сервер для документа без поля.
    ///
    /// Зеркалит `functions/src/index.ts` (ветка C, `intOrDefault`) — разойтись
    /// нельзя: клиент разрешил бы скан, а сервер ответил бы 429.
    public static func effectiveCooldownMinutes(_ configured: Int) -> Int {
        max(configured, 0)
    }

    /// Прошёл ли кулдаун с прошлого начисления.
    /// - Parameter lastEarnAt: `nil` — баллы этому гостю здесь ещё не начисляли.
    public static func canEarn(lastEarnAt: Date?, cooldownMinutes: Int, now: Date) -> Bool {
        let cooldown = effectiveCooldownMinutes(cooldownMinutes)
        guard cooldown > 0 else { return true }
        guard let last = lastEarnAt else { return true }
        return now.timeIntervalSince(last) >= Double(cooldown) * 60
    }

    /// Сколько секунд осталось до следующего начисления (`0` — можно уже сейчас).
    public static func cooldownRemainingSeconds(lastEarnAt: Date?, cooldownMinutes: Int, now: Date) -> Int {
        let cooldown = effectiveCooldownMinutes(cooldownMinutes)
        guard cooldown > 0, let last = lastEarnAt else { return 0 }
        let left = Double(cooldown) * 60 - now.timeIntervalSince(last)
        return left > 0 ? clampedInt(left.rounded(.up)) : 0
    }

    // MARK: - Списание

    /// Найти награду в каталоге заведения. Снятая с публикации — как отсутствующая.
    public static func findReward(in rewards: [PointsReward], id: String) -> Result<PointsReward, PointsError> {
        guard let reward = rewards.first(where: { $0.id == id }), reward.active else {
            return .failure(.rewardNotFound)
        }
        return .success(reward)
    }

    /// Сколько баллов спишется за награду.
    ///
    /// `item`  — фиксированная цена `reward.cost`.
    /// `money` — скидка баллами: `reward.cost` это **минимум** к списанию,
    ///           списывается ровно `pointsToSpend`.
    public static func redeemCost(reward: PointsReward, pointsToSpend: Int, balance: Int) -> Result<Int, PointsError> {
        let spend = max(0, pointsToSpend)
        let cost: Int

        if reward.type == "money" {
            let minRedeem = max(reward.cost, 1)
            guard spend >= minRedeem else { return .failure(.belowMin(minRedeem: minRedeem)) }
            cost = spend
        } else {
            cost = max(reward.cost, 0)
            guard cost > 0 else { return .failure(.badReward) }
        }

        guard balance >= cost else { return .failure(.insufficient) }
        return .success(cost)
    }

    /// Сумма скидки в сомах для награды типа `money` (`nil` для `item`).
    /// Нулевой/отрицательный курс трактуется как 1 сом за балл — как на сервере.
    public static func somOff(reward: PointsReward, cost: Int) -> Int? {
        guard reward.type == "money" else { return nil }
        let ratio = (reward.ratio.isFinite && reward.ratio > 0) ? reward.ratio : 1
        return clampedInt((Double(cost) * ratio).rounded())
    }

    /// То же, но с серверной страховкой курса (`effectiveMoneyRatio` в
    /// `functions/src/index.ts`): так гость видит ровно ту скидку, что даст сервер.
    public static func somOff(reward: PointsReward, cost: Int,
                              pointsMode: String, cashbackPercent: Double) -> Int? {
        guard reward.type == "money" else { return nil }
        let ratio = effectiveRatio(reward.ratio, pointsMode: pointsMode, cashbackPercent: cashbackPercent)
        return clampedInt((Double(cost) * ratio).rounded())
    }

    /// `Int(_: Double)` падает на бесконечности, NaN и значениях за пределами
    /// `Int`. Курс и цена приходят из документа заведения (админка, Android),
    /// так что «1e300 сомов за балл» — данные, а не невозможность: экран
    /// должен показать большое число, а не уронить приложение.
    static func clampedInt(_ x: Double) -> Int {
        guard x.isFinite else { return x.isNaN ? 0 : (x > 0 ? Int.max : Int.min) }
        if x >= Double(Int.max) { return Int.max }
        if x <= Double(Int.min) { return Int.min }
        return Int(x)
    }

    /// Курс денежной награды (сомов за балл) после страховки.
    ///
    /// Потолок кэшбэка 20% иначе обходился курсом: «20% баллами + 1 балл =
    /// 5 сом» — это скидка 100%. В режиме cashback эффективная скидка —
    /// процент × курс, поэтому курс не выше `maxCashbackPercent / процент` (и
    /// не ниже 1). В flat/bands курс — лишь масштаб числа баллов за визит,
    /// которое заведение и так задаёт, и не режется.
    public static func effectiveRatio(_ ratio: Double, pointsMode: String, cashbackPercent: Double) -> Double {
        let r = (ratio.isFinite && ratio > 0) ? ratio : 1
        guard pointsMode == "cashback" else { return r }
        let pct = min(max(cashbackPercent.isFinite ? cashbackPercent : 0, 0), maxCashbackPercent)
        guard pct > 0 else { return r }
        return min(r, maxMoneyRatio(cashbackPercent: pct))
    }

    /// Самый щедрый курс, при котором кэшбэк не превышает потолок.
    public static func maxMoneyRatio(cashbackPercent: Double) -> Double {
        guard cashbackPercent > 0 else { return .infinity }
        return max(1, maxCashbackPercent / cashbackPercent)
    }
}

// MARK: - Конфиг заведения

/// Настройки начисления баллов, вырезанные из `Venue`.
///
/// Отдельный тип, а не сам `Venue`, чтобы математику можно было прогнать на голых
/// данных фикстура — без сборки полноценного заведения.
/// Имена полей = имена полей в документе `venues/{id}` (их пишет админка).
public struct PointsConfig: Equatable {
    public var pointsEnabled: Bool = false
    /// `"flat"` | `"bands"` | `"cashback"`; незнакомое значение = `flat`.
    public var pointsMode: String = "flat"
    public var pointsFlat: Int = 0
    public var pointsBands: [PointsBand] = []
    public var cashbackPercent: Double = 0
    public var earnCooldownMinutes: Int = PointsMath.defaultEarnCooldownMinutes

    public init(pointsEnabled: Bool = false,
         pointsMode: String = "flat",
         pointsFlat: Int = 0,
         pointsBands: [PointsBand] = [],
         cashbackPercent: Double = 0,
         earnCooldownMinutes: Int = PointsMath.defaultEarnCooldownMinutes) {
        self.pointsEnabled = pointsEnabled
        self.pointsMode = pointsMode
        self.pointsFlat = pointsFlat
        self.pointsBands = pointsBands
        self.cashbackPercent = cashbackPercent
        self.earnCooldownMinutes = earnCooldownMinutes
    }

    public init(venue: Venue) {
        self.init(pointsEnabled: venue.pointsEnabled,
                  pointsMode: venue.pointsMode,
                  pointsFlat: venue.pointsFlat,
                  pointsBands: venue.pointsBands,
                  cashbackPercent: venue.cashbackPercent,
                  earnCooldownMinutes: venue.earnCooldownMinutes)
    }
}

// MARK: - Ошибки

/// Отказы математики баллов. `code` — строка ошибки **ровно как её отдаёт сервер**
/// (тело ответа `{"error": ...}`), чтобы клиент мог показывать один и тот же текст
/// и на предсказании, и на реальном ответе.
public enum PointsError: Error, Equatable {
    /// Баллы выключены у заведения.
    case pointsOff
    /// Режим `cashback`, но сумма чека не введена.
    case missingAmount
    /// Режим `bands`, но кнопка диапазона не выбрана / её нет в каталоге.
    case badBand
    /// Конфиг даёт ноль баллов — начислять нечего.
    case noPoints
    /// `money`-награда: списываемых баллов меньше минимума.
    case belowMin(minRedeem: Int)
    /// `item`-награда с нулевой ценой — сломанный конфиг.
    case badReward
    /// Награды нет в каталоге или она снята с публикации.
    case rewardNotFound
    /// Не хватает баллов на балансе.
    case insufficient

    public var code: String {
        switch self {
        case .pointsOff:      return "points_off"
        case .missingAmount:  return "missing_amount"
        case .badBand:        return "bad_band"
        case .noPoints:       return "no_points"
        case .belowMin:       return "below_min"
        case .badReward:      return "bad_reward"
        case .rewardNotFound: return "reward_not_found"
        case .insufficient:   return "insufficient"
        }
    }
}
