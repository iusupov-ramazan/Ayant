package kg.ayant.app.data

import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.tasks.await
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

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
}

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
}

/** Reads/writes analytics/{venueID}/days/{yyyy-MM-dd} with FieldValue.increment. */
class FirebaseAnalyticsService : AnalyticsService {
    private val db = FirebaseFirestore.getInstance()

    override fun log(venueID: String, metric: String) {
        val day = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        db.collection("analytics").document(venueID).collection("days").document(day)
            .set(mapOf(metric to FieldValue.increment(1)), com.google.firebase.firestore.SetOptions.merge())
    }

    override suspend fun fetchStats(venueID: String, days: Int): Map<String, Int> {
        val fmt = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        val cutoff = fmt.format(Date(System.currentTimeMillis() - days * 86_400_000L))
        val snap = db.collection("analytics").document(venueID).collection("days").get().await()
        val totals = mutableMapOf<String, Int>()
        for (doc in snap.documents) {
            if (doc.id < cutoff) continue   // yyyy-MM-dd compares lexicographically
            for ((k, v) in doc.data ?: emptyMap()) {
                (v as? Number)?.let { totals[k] = (totals[k] ?: 0) + it.toInt() }
            }
        }
        return totals
    }
}
