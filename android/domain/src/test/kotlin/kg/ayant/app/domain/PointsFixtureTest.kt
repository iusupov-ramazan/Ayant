package kg.ayant.app.domain

import kg.ayant.app.domain.model.PointsBand
import kg.ayant.app.domain.model.PointsReward
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Прогон общего фикстура `specs/fixtures/points-fixtures.json` через [PointsMath].
 *
 * Тот же файл гоняют iOS (`PointsFixtureTests.swift`) и сервер
 * (`functions/test/fixtures.test.js`). Это единственное место, где ловится
 * расхождение трёх реализаций математики баллов: ошибка в округлении кэшбэка не
 * падает тестом «на глаз», а всплывает через недели жалобой заведения — уже в сомах.
 *
 * Новый кейс добавляется **в JSON**, а не сюда: иначе он проверит одну платформу
 * из трёх, ради чего фикстур и заводился.
 *
 * Файл попадает на classpath теста через `sourceSets["test"].resources.srcDir(...)`
 * в `app/build.gradle.kts` — он лежит вне модуля, в корне репозитория.
 */
class PointsFixtureTest {

    private val fixture: Fixture = run {
        val stream = javaClass.getResourceAsStream("/points-fixtures.json")
        assertNotNull("Фикстур не найден на classpath: /points-fixtures.json", stream)
        val json = Json { ignoreUnknownKeys = true }
        json.decodeFromString(Fixture.serializer(), stream!!.bufferedReader().use { it.readText() })
    }

    // ── Константы ────────────────────────────────────────────────────────────

    @Test
    fun `constants match fixture`() {
        val c = fixture.constants
        assertEquals(c.maxPointsPerEarn, PointsMath.MAX_POINTS_PER_EARN)
        assertEquals(c.maxCashbackPercent, PointsMath.MAX_CASHBACK_PERCENT, 0.0)
        assertEquals(c.defaultEarnCooldownMinutes, PointsMath.DEFAULT_EARN_COOLDOWN_MINUTES)
        assertEquals(c.defaultStampCooldownMinutes, PointsMath.DEFAULT_STAMP_COOLDOWN_MINUTES)
        assertEquals(c.defaultExpiryMonths, PointsMath.DEFAULT_EXPIRY_MONTHS)
    }

    // ── Начисление ───────────────────────────────────────────────────────────

    @Test
    fun `award cases`() {
        assertTrue("В фикстуре нет кейсов начисления", fixture.award.isNotEmpty())
        for (c in fixture.award) {
            when (val result = PointsMath.award(c.config.toConfig(), c.billAmount, c.bandIndex)) {
                is PointsResult.Ok ->
                    assertEquals("«${c.name}»: неверное начисление", c.expect.points, result.value)
                is PointsResult.Err ->
                    assertEquals("«${c.name}»: неверный код отказа", c.expect.error, result.error.code)
            }
        }
    }

    // ── Кулдаун ──────────────────────────────────────────────────────────────

    @Test
    fun `cooldown cases`() {
        assertTrue("В фикстуре нет кейсов кулдауна", fixture.cooldown.isNotEmpty())
        val now = 1_700_000_000_000L
        for (c in fixture.cooldown) {
            val last = c.minutesSinceLastEarn?.let { now - it * 60_000L }
            val can = PointsMath.canEarn(last, c.earnCooldownMinutes, now)
            assertEquals("«${c.name}»: неверное решение по кулдауну", c.expect.canEarn, can)
        }
    }

    /**
     * Обратный отсчёт до следующего начисления — чисто клиентская математика
     * (сервер её не считает), поэтому в фикстуре её нет.
     */
    @Test
    fun `cooldown remaining seconds`() {
        val now = 1_700_000_000_000L
        assertEquals(0, PointsMath.cooldownRemainingSeconds(null, 60, now))
        assertEquals(3000, PointsMath.cooldownRemainingSeconds(now - 600_000L, 60, now))
        assertEquals(0, PointsMath.cooldownRemainingSeconds(now - 3_600_000L, 60, now))
        // Отрицательный кулдаун отключён — ждать нечего.
        assertEquals(0, PointsMath.cooldownRemainingSeconds(now, -5, now))
    }

    // ── Списание ─────────────────────────────────────────────────────────────

    @Test
    fun `redeem cases`() {
        assertTrue("В фикстуре нет кейсов списания", fixture.redeem.isNotEmpty())
        for (c in fixture.redeem) {
            val found = PointsMath.findReward(c.rewards, c.rewardId)
            if (found is PointsResult.Err) {
                assertEquals("«${c.name}»: неверный код отказа поиска награды",
                    c.expect.error, found.error.code)
                continue
            }
            val reward = (found as PointsResult.Ok).value
            when (val result = PointsMath.redeemCost(reward, c.pointsToSpend, c.balance)) {
                is PointsResult.Ok -> {
                    assertEquals("«${c.name}»: неверное списание", c.expect.cost, result.value)
                    assertEquals("«${c.name}»: неверный остаток",
                        c.expect.newBalance, c.balance - result.value)
                    assertEquals("«${c.name}»: неверная скидка в сомах",
                        c.expect.somOff, PointsMath.somOff(reward, result.value))
                }
                is PointsResult.Err -> {
                    assertEquals("«${c.name}»: неверный код отказа", c.expect.error, result.error.code)
                    val error = result.error
                    if (error is PointsError.BelowMin) {
                        assertEquals("«${c.name}»: неверный минимум к списанию",
                            c.expect.minRedeem, error.minRedeem)
                    }
                }
            }
        }
    }
}

// ── Разбор фикстура ──────────────────────────────────────────────────────────

@Serializable
private data class Fixture(
    val version: Int,
    val constants: Constants,
    val award: List<AwardCase>,
    val cooldown: List<CooldownCase>,
    val redeem: List<RedeemCase>,
)

@Serializable
private data class Constants(
    val maxPointsPerEarn: Int,
    val maxCashbackPercent: Double,
    val defaultEarnCooldownMinutes: Int,
    val defaultStampCooldownMinutes: Int,
    val defaultExpiryMonths: Int,
)

/**
 * Поля конфига опциональны: кейс задаёт только то, что для него важно, остальное
 * берётся из дефолтов [PointsConfig] — ровно как отсутствующее поле в Firestore.
 */
@Serializable
private data class ConfigJson(
    val pointsEnabled: Boolean? = null,
    val pointsMode: String? = null,
    val pointsFlat: Int? = null,
    val pointsBands: List<PointsBand>? = null,
    val cashbackPercent: Double? = null,
    val earnCooldownMinutes: Int? = null,
) {
    fun toConfig(): PointsConfig {
        val default = PointsConfig()
        return PointsConfig(
            pointsEnabled = pointsEnabled ?: default.pointsEnabled,
            pointsMode = pointsMode ?: default.pointsMode,
            pointsFlat = pointsFlat ?: default.pointsFlat,
            pointsBands = pointsBands ?: default.pointsBands,
            cashbackPercent = cashbackPercent ?: default.cashbackPercent,
            earnCooldownMinutes = earnCooldownMinutes ?: default.earnCooldownMinutes,
        )
    }
}

@Serializable
private data class ExpectJson(
    val points: Int? = null,
    val error: String? = null,
    val canEarn: Boolean? = null,
    val minRedeem: Int? = null,
    val cost: Int? = null,
    val newBalance: Int? = null,
    val somOff: Int? = null,
)

@Serializable
private data class AwardCase(
    val name: String,
    val config: ConfigJson,
    val billAmount: Int? = null,
    val bandIndex: Int? = null,
    val expect: ExpectJson,
)

@Serializable
private data class CooldownCase(
    val name: String,
    val earnCooldownMinutes: Int,
    val minutesSinceLastEarn: Int? = null,
    val expect: ExpectJson,
)

@Serializable
private data class RedeemCase(
    val name: String,
    val rewards: List<PointsReward>,
    val rewardId: String,
    val pointsToSpend: Int,
    val balance: Int,
    val expect: ExpectJson,
)
