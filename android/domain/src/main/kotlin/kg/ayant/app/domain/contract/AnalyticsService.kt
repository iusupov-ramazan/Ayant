package kg.ayant.app.domain.contract

import kg.ayant.app.domain.RankingEvent

/*
 * Контракты телеметрии. Реализации (Mock/Firebase) — в модуле :data.
 */

/** Venue analytics events. Mirrors AnalyticsService.swift + AnalyticsMetric. */
object AnalyticsMetric {
    const val VIEWS = "views"
    const val SAVES = "saves"
    const val CALLS = "calls"
    const val MAPS = "maps"
    const val DEAL_TAPS = "dealTaps"
    const val REDEMPTIONS = "redemptions"
}

interface AnalyticsService {
    fun log(venueID: String, metric: String)
    /** Sum of each metric over the last [days] days. */
    suspend fun fetchStats(venueID: String, days: Int): Map<String, Int>

    /**
     * Metrics BY DAY over the last [days] days, keyed "yyyy-MM-dd".
     *
     * The analytics chart needs the series: [fetchStats] collapses it, and bars
     * drawn from anything but real data would be fabricated. Firestore already
     * stores one document per day — this just does not sum them.
     */
    suspend fun fetchDailyStats(venueID: String, days: Int): Map<String, Map<String, Int>>
}


/**
 * Ranking-event log (learning-to-rank): rank-time features + outcomes, appended to
 * the `rankingEvents` collection. Fire-and-forget; failures are swallowed so
 * telemetry never breaks the user flow. Schema — [RankingEvent]. Mirrors iOS.
 */
interface RankingEventService {
    fun log(event: RankingEvent)
}

