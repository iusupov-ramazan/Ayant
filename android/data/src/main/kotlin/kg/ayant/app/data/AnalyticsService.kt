package kg.ayant.app.data

import kg.ayant.app.domain.contract.AnalyticsMetric
import kg.ayant.app.domain.contract.AnalyticsService
import kg.ayant.app.domain.contract.RankingEventService

import kg.ayant.app.domain.RankingEvent

import com.google.firebase.firestore.FirebaseFirestore
import kg.ayant.app.data.firestore.FS
import kotlinx.coroutines.tasks.await
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kg.ayant.app.domain.HostMetrics
import java.util.Calendar

class MockAnalyticsService : AnalyticsService {
    override fun log(venueID: String, metric: String) { /* no-op */ }
    override suspend fun fetchStats(venueID: String, days: Int): Map<String, Int> {
        // Deterministic demo values (same shape as iOS HostMetrics).
        val base = mapOf(
            AnalyticsMetric.VIEWS to 40, AnalyticsMetric.DEAL_TAPS to 12, AnalyticsMetric.SAVES to 6,
            AnalyticsMetric.CALLS to 3, AnalyticsMetric.MAPS to 4, AnalyticsMetric.REDEMPTIONS to 5,
        )
        return base.mapValues { (k, b) ->
            val seed = (venueID + k).sumOf { it.code }
            (seed % 7 + 1) * b * days / 7
        }
    }

    /** Оффлайн-режим ряда по дням не хранит — график просто не рисуется. */
    override suspend fun fetchDailyStats(venueID: String, days: Int): Map<String, Map<String, Int>> = emptyMap()
}

/** Mock ranking log: keeps events in memory (for tests), sends nothing. */
class MockRankingEventService : RankingEventService {
    val logged = mutableListOf<RankingEvent>()
    override fun log(event: RankingEvent) { logged.add(event) }
}

/** Appends ranking events to the append-only `rankingEvents` collection. */
class FirebaseRankingEventService : RankingEventService {
    private val db = FirebaseFirestore.getInstance()
    override fun log(event: RankingEvent) {
        db.collection(FS.Collection.RANKING_EVENTS).add(event.asFirestore())
    }
}

/** Reads/writes analytics/{venueID}/days/{yyyy-MM-dd} with FieldValue.increment. */
class FirebaseAnalyticsService : AnalyticsService {
    private val db = FirebaseFirestore.getInstance()

    override fun log(venueID: String, metric: String) {
        // Событие телеметрии: счётчик инкрементирует Cloud Function countAnalyticsEvent
        // (клиенту запрещено писать в analytics/* напрямую — см. firestore.rules).
        db.collection(FS.Collection.ANALYTICS_EVENTS).add(
            mapOf(
                FS.AnalyticsEventDoc.VENUE_ID to venueID,
                FS.AnalyticsEventDoc.METRIC to metric,
                FS.AnalyticsEventDoc.CREATED_AT to Date(),
            )
        )
    }

    override suspend fun fetchStats(venueID: String, days: Int): Map<String, Int> {
        val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val cutoff = fmt.format(Date(System.currentTimeMillis() - days * 86_400_000L))
        val snap = db.collection(FS.Collection.ANALYTICS).document(venueID)
            .collection(FS.Collection.DAYS).get().await()
        val totals = mutableMapOf<String, Int>()
        for (doc in snap.documents) {
            if (doc.id < cutoff) continue   // yyyy-MM-dd compares lexicographically
            for ((k, v) in doc.data ?: emptyMap()) {
                (v as? Number)?.let { totals[k] = (totals[k] ?: 0) + it.toInt() }
            }
        }
        return totals
    }

    override suspend fun fetchDailyStats(venueID: String, days: Int): Map<String, Map<String, Int>> {
        val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val cutoff = fmt.format(Date(System.currentTimeMillis() - days * 86_400_000L))
        val snap = db.collection(FS.Collection.ANALYTICS).document(venueID)
            .collection(FS.Collection.DAYS).get().await()
        val byDay = mutableMapOf<String, Map<String, Int>>()
        for (doc in snap.documents) {
            if (doc.id < cutoff) continue   // yyyy-MM-dd сравнивается лексикографически
            val metrics = mutableMapOf<String, Int>()
            for ((k, v) in doc.data ?: emptyMap()) {
                (v as? Number)?.let { metrics[k] = it.toInt() }
            }
            byDay[doc.id] = metrics
        }
        return byDay
    }
}


/**
 * ВРЕМЕННО: витринная аналитика поверх настоящей. Зеркалит `DemoAnalyticsService` в Swift.
 *
 * Пока у заведений нет своего трафика, реальные счётчики стоят на нуле и
 * «Аналитика» выглядит сломанной. Этот декоратор ЧИТАЕТ сгенерированные ряды
 * ([HostMetrics]), но [log] продолжает писать в настоящий сервис — телеметрия
 * копится, и когда флаг `AppConfig.useDemoAnalytics` выключат, в отчётах
 * окажутся реальные накопленные данные, а не дыра за весь период показа.
 */
class DemoAnalyticsService(private val real: AnalyticsService) : AnalyticsService {

    override fun log(venueID: String, metric: String) = real.log(venueID, metric)

    override suspend fun fetchStats(venueID: String, days: Int): Map<String, Int> =
        METRICS.associateWith { m ->
            HostMetrics.total(venueID, m, days) { weekdayOfDaysAgo(it) }
        }

    override suspend fun fetchDailyStats(venueID: String, days: Int): Map<String, Map<String, Int>> {
        val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val out = LinkedHashMap<String, Map<String, Int>>()
        for (i in 0 until maxOf(1, days)) {
            val cal = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -i) }
            val weekday = cal.get(Calendar.DAY_OF_WEEK) - 1
            out[fmt.format(cal.time)] = METRICS.associateWith { m ->
                HostMetrics.daily(venueID, m, i, weekday)
            }
        }
        return out
    }

    private fun weekdayOfDaysAgo(i: Int): Int =
        Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -i) }.get(Calendar.DAY_OF_WEEK) - 1

    private companion object {
        val METRICS = listOf(
            AnalyticsMetric.VIEWS, AnalyticsMetric.SAVES, AnalyticsMetric.CALLS,
            AnalyticsMetric.MAPS, AnalyticsMetric.DEAL_TAPS, AnalyticsMetric.REDEMPTIONS,
        )
    }
}
