package kg.ayant.app.domain

import kg.ayant.app.domain.model.PointsBand
import kg.ayant.app.domain.model.PointsReward
import kg.ayant.app.domain.model.Venue
import kotlin.math.floor

/**
 * Чистая математика **баллов САН** (System 1) — зеркало серверных правил из
 * `functions/src/index.ts` (`scanCoupon` ветка C и `redeemVenuePoints`).
 *
 * Сервер остаётся авторитетным: он всё равно пересчитывает начисление и списание
 * сам. Клиенту эти же функции нужны, чтобы **показать результат до скана**
 * («вам начислят 100 баллов», «не хватает 20», «ещё 42 мин до начисления») и не
 * отправлять заведомо провальный запрос.
 *
 * Поэтому расхождение клиента с сервером = обещание в UI, которое не сбудется, —
 * и ловится оно только общим фикстуром `specs/fixtures/points-fixtures.json`,
 * который гоняют все три реализации (iOS, Android, Functions). Новый кейс идёт
 * в фикстур, а не в тесты одной платформы.
 *
 * Зеркалит `Domain/PointsMath.swift` на iOS 1:1 (имена, порядок проверок, коды ошибок).
 */
object PointsMath {

    // ── Константы (совпадают с functions/src/index.ts) ────────────────────────

    /** Потолок за одно начисление — страховка от опечатки в конфиге заведения. */
    const val MAX_POINTS_PER_EARN = 10_000
    /** Потолок кэшбэка, % — защита от «50%» вместо «5%». */
    const val MAX_CASHBACK_PERCENT = 20.0
    /** Кулдаун начисления по умолчанию, мин. */
    const val DEFAULT_EARN_COOLDOWN_MINUTES = 60
    /** Кулдаун штампа карты лояльности, мин. (отдельная от баллов система). */
    const val DEFAULT_STAMP_COOLDOWN_MINUTES = 15
    /** Сгорание баллов по неактивности, мес. */
    const val DEFAULT_EXPIRY_MONTHS = 6

    // ── Начисление ───────────────────────────────────────────────────────────

    /**
     * Сколько баллов начислит сервер за этот скан.
     *
     * Порядок проверок повторяет серверный: сначала режим и его входные данные,
     * затем кап [MAX_POINTS_PER_EARN], затем «нечего начислять». Кулдаун сервер
     * проверяет **после** расчёта суммы — здесь он вынесен в [canEarn].
     *
     * @param billAmount сумма чека (режим `cashback`); отрицательная приводится к нулю.
     * @param bandIndex индекс нажатой кнопки-диапазона (режим `bands`).
     */
    fun award(config: PointsConfig, billAmount: Int?, bandIndex: Int?): PointsResult<Int> {
        if (!config.pointsEnabled) return PointsResult.Err(PointsError.PointsOff)

        val bill = maxOf(0, billAmount ?: 0)
        var awarded: Int

        when (config.pointsMode) {
            "cashback" -> {
                val raw = if (config.cashbackPercent.isFinite()) config.cashbackPercent else 0.0
                val pct = minOf(maxOf(raw, 0.0), MAX_CASHBACK_PERCENT)
                if (bill <= 0) return PointsResult.Err(PointsError.MissingAmount)
                // Порядок умножения/деления повторяет сервер (bill * pct / 100), иначе
                // на дробных процентах платформы разойдутся в последнем разряде.
                awarded = roundHalfUp(bill.toDouble() * pct / 100.0)
            }
            "bands" -> {
                val index = bandIndex ?: return PointsResult.Err(PointsError.BadBand)
                if (index < 0 || index >= config.pointsBands.size) {
                    return PointsResult.Err(PointsError.BadBand)
                }
                awarded = config.pointsBands[index].points
            }
            else -> {
                // "flat" и любой незнакомый режим.
                awarded = config.pointsFlat
            }
        }

        awarded = minOf(maxOf(awarded, 0), MAX_POINTS_PER_EARN)
        if (awarded <= 0) return PointsResult.Err(PointsError.NoPoints)
        return PointsResult.Ok(awarded)
    }

    /**
     * Эффективный кулдаун, мин.
     *
     * **`0` отключает кулдаун** (начислять можно хоть каждый скан) — как и любое
     * отрицательное значение, которое приводится к нулю. Отсутствующего значения
     * здесь не бывает: слой разбора (`FirebaseDataRepository`) подставляет дефолтные
     * 60 мин, ровно как сервер для документа без поля.
     *
     * Зеркалит `functions/src/index.ts` (ветка C, `intOrDefault`) — разойтись
     * нельзя: клиент разрешил бы скан, а сервер ответил бы 429.
     */
    fun effectiveCooldownMinutes(configured: Int): Int =
        maxOf(configured, 0)

    /**
     * Прошёл ли кулдаун с прошлого начисления.
     * @param lastEarnAtMs `null` — баллы этому гостю здесь ещё не начисляли.
     */
    fun canEarn(lastEarnAtMs: Long?, cooldownMinutes: Int, nowMs: Long): Boolean {
        val cooldown = effectiveCooldownMinutes(cooldownMinutes)
        if (cooldown <= 0) return true
        val last = lastEarnAtMs ?: return true
        return nowMs - last >= cooldown * 60_000L
    }

    /** Сколько секунд осталось до следующего начисления (`0` — можно уже сейчас). */
    fun cooldownRemainingSeconds(lastEarnAtMs: Long?, cooldownMinutes: Int, nowMs: Long): Int {
        val cooldown = effectiveCooldownMinutes(cooldownMinutes)
        if (cooldown <= 0) return 0
        val last = lastEarnAtMs ?: return 0
        val leftMs = cooldown * 60_000L - (nowMs - last)
        return if (leftMs > 0) ((leftMs + 999) / 1000).toInt() else 0
    }

    // ── Списание ─────────────────────────────────────────────────────────────

    /** Найти награду в каталоге заведения. Снятая с публикации — как отсутствующая. */
    fun findReward(rewards: List<PointsReward>, id: String): PointsResult<PointsReward> {
        val reward = rewards.firstOrNull { it.id == id }
        if (reward == null || !reward.active) return PointsResult.Err(PointsError.RewardNotFound)
        return PointsResult.Ok(reward)
    }

    /**
     * Сколько баллов спишется за награду.
     *
     * `item`  — фиксированная цена `reward.cost`.
     * `money` — скидка баллами: `reward.cost` это **минимум** к списанию,
     *           списывается ровно [pointsToSpend].
     */
    fun redeemCost(reward: PointsReward, pointsToSpend: Int, balance: Int): PointsResult<Int> {
        val spend = maxOf(0, pointsToSpend)
        val cost: Int

        if (reward.type == "money") {
            val minRedeem = maxOf(reward.cost, 1)
            if (spend < minRedeem) return PointsResult.Err(PointsError.BelowMin(minRedeem))
            cost = spend
        } else {
            cost = maxOf(reward.cost, 0)
            if (cost <= 0) return PointsResult.Err(PointsError.BadReward)
        }

        if (balance < cost) return PointsResult.Err(PointsError.Insufficient)
        return PointsResult.Ok(cost)
    }

    /**
     * Сумма скидки в сомах для награды типа `money` (`null` для `item`).
     * Нулевой/отрицательный курс трактуется как 1 сом за балл — как на сервере.
     */
    fun somOff(reward: PointsReward, cost: Int): Int? {
        if (reward.type != "money") return null
        val ratio = if (reward.ratio.isFinite() && reward.ratio > 0) reward.ratio else 1.0
        return roundHalfUp(cost.toDouble() * ratio)
    }

    /**
     * Округление «половина вверх» — ровно как JS `Math.round` на сервере.
     * `kotlin.math.round` округляет половину к чётному, поэтому не подходит:
     * на 50.5 сервер дал бы 51, а клиент — 50.
     */
    private fun roundHalfUp(value: Double): Int = floor(value + 0.5).toInt()
}

// ── Конфиг заведения ─────────────────────────────────────────────────────────

/**
 * Настройки начисления баллов, вырезанные из [Venue].
 *
 * Отдельный тип, а не сам [Venue], чтобы математику можно было прогнать на голых
 * данных фикстура — без сборки полноценного заведения.
 * Имена полей = имена полей в документе `venues/{id}` (их пишет админка).
 */
data class PointsConfig(
    val pointsEnabled: Boolean = false,
    /** `"flat"` | `"bands"` | `"cashback"`; незнакомое значение = `flat`. */
    val pointsMode: String = "flat",
    val pointsFlat: Int = 0,
    val pointsBands: List<PointsBand> = emptyList(),
    val cashbackPercent: Double = 0.0,
    val earnCooldownMinutes: Int = PointsMath.DEFAULT_EARN_COOLDOWN_MINUTES,
) {
    companion object {
        fun of(venue: Venue) = PointsConfig(
            pointsEnabled = venue.pointsEnabled,
            pointsMode = venue.pointsMode,
            pointsFlat = venue.pointsFlat,
            pointsBands = venue.pointsBands,
            cashbackPercent = venue.cashbackPercent,
            earnCooldownMinutes = venue.earnCooldownMinutes,
        )
    }
}

// ── Результат ────────────────────────────────────────────────────────────────

/** Зеркало Swift `Result<T, PointsError>` — успех либо типизированный отказ. */
sealed interface PointsResult<out T> {
    data class Ok<T>(val value: T) : PointsResult<T>
    data class Err(val error: PointsError) : PointsResult<Nothing>

    /** Значение либо `null` — для мест, где отказ обрабатывается отдельно. */
    fun valueOrNull(): T? = (this as? Ok)?.value
    /** Ошибка либо `null`. */
    fun errorOrNull(): PointsError? = (this as? Err)?.error
}

// ── Ошибки ───────────────────────────────────────────────────────────────────

/**
 * Отказы математики баллов. [code] — строка ошибки **ровно как её отдаёт сервер**
 * (тело ответа `{"error": ...}`), чтобы клиент мог показывать один и тот же текст
 * и на предсказании, и на реальном ответе.
 */
sealed class PointsError(val code: String) {
    /** Баллы выключены у заведения. */
    data object PointsOff : PointsError("points_off")
    /** Режим `cashback`, но сумма чека не введена. */
    data object MissingAmount : PointsError("missing_amount")
    /** Режим `bands`, но кнопка диапазона не выбрана / её нет в каталоге. */
    data object BadBand : PointsError("bad_band")
    /** Конфиг даёт ноль баллов — начислять нечего. */
    data object NoPoints : PointsError("no_points")
    /** `money`-награда: списываемых баллов меньше минимума. */
    data class BelowMin(val minRedeem: Int) : PointsError("below_min")
    /** `item`-награда с нулевой ценой — сломанный конфиг. */
    data object BadReward : PointsError("bad_reward")
    /** Награды нет в каталоге или она снята с публикации. */
    data object RewardNotFound : PointsError("reward_not_found")
    /** Не хватает баллов на балансе. */
    data object Insufficient : PointsError("insufficient")
}
