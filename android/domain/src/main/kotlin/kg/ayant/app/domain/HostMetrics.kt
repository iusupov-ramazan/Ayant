package kg.ayant.app.domain

import kg.ayant.app.domain.contract.AnalyticsMetric
import kotlin.math.roundToInt

/**
 * Правдоподобные цифры для витрины аналитики. Зеркалит `HostMetrics.swift`.
 *
 * ВРЕМЕННО. Пока у заведений нет своего трафика, реальные счётчики стоят на
 * нуле, и «Аналитика» выглядит сломанной, а не пустой. Выключается одним
 * флагом — `AppConfig.useDemoAnalytics`.
 *
 * Числа ДЕТЕРМИНИРОВАННЫЕ: зависят от id заведения, метрики и номера дня, а не
 * от `Random`. Настоящий рандом менялся бы при каждом обновлении экрана —
 * цифры бы прыгали на глазах, и это читалось бы как баг, а не как живые данные.
 */
object HostMetrics {

    /** Средний дневной уровень метрики для заведения. */
    private fun dailyBase(id: String, metric: String): Double {
        val seed = hash(id + metric)
        // Воронка: просмотров много, звонков единицы.
        val base = when (metric) {
            AnalyticsMetric.VIEWS -> 42.0
            AnalyticsMetric.DEAL_TAPS -> 11.0
            AnalyticsMetric.SAVES -> 6.0
            AnalyticsMetric.MAPS -> 4.0
            AnalyticsMetric.CALLS -> 3.0
            AnalyticsMetric.REDEMPTIONS -> 2.0
            else -> 5.0
        }
        // ±45 % на заведение, чтобы соседние карточки не были близнецами.
        val spread = 0.55 + (seed % 90) / 100.0
        return base * spread
    }

    /** Значение метрики за конкретный день. [dayIndex] — сколько дней назад (0 = сегодня). */
    fun daily(id: String, metric: String, dayIndex: Int, weekday: Int): Int {
        val base = dailyBase(id, metric)
        // Выходные заметно живее буднего вторника.
        val weekly = listOf(1.22, 0.82, 0.86, 0.9, 0.96, 1.15, 1.3)[weekday.coerceIn(0, 6)]
        // Разброс по дню — тоже из хеша, а не из генератора случайных чисел.
        val jitter = 0.75 + (hash("$id$metric$dayIndex") % 50) / 100.0
        return (base * weekly * jitter).roundToInt()
    }

    /**
     * Сумма метрики за [days] дней, считается по тем же дневным значениям, что
     * рисует график, — иначе итог и столбики разошлись бы.
     */
    fun total(id: String, metric: String, days: Int, weekdayOfDayAgo: (Int) -> Int): Int =
        (0 until maxOf(1, days)).sumOf { daily(id, metric, it, weekdayOfDayAgo(it)) }

    /**
     * Устойчивый хеш строки. `hashCode` не подходит: у него нет гарантии
     * стабильности между версиями, а ряд не должен меняться сам по себе.
     */
    private fun hash(s: String): Int {
        var h = 5381
        for (b in s.toByteArray()) h = (h * 33 + b.toInt()) and 0x7fff_ffff
        return h
    }
}
