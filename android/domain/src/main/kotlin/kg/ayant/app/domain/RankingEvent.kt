package kg.ayant.app.domain

import java.util.Date

/**
 * Ranking event schema — the learning-to-rank training log.
 *
 * Written to the append-only Firestore collection `rankingEvents` (rules: `create`
 * only for signed-in users, no read/update/delete — see firestore.rules). One
 * document per event. The key idea: **features are logged at rank time**, because
 * they can't be reconstructed later (distance shifts, ratings grow, deals expire).
 * This is what the `Ranking` weights are later learned from instead of hand-tuned.
 *
 * Mirrors iOS `Analytics/RankingEvent.swift` 1:1 — document field names must match
 * or the training export mixes two schemas. Change BOTH sides and the `rankingEvents`
 * rule in firestore.rules together.
 *
 * Document shape:
 * ```
 * {
 *   type: "impression" | "tap" | "redeem",
 *   userID, sessionID, renderID,        // renderID links impression → tap/redeem
 *   platform: "ios" | "android",
 *   citySlug, category,                  // feed filter (null = all)
 *   hour, weekday,                       // local context (0..23, 0=Mon)
 *   clientTs,                            // client epoch ms (in-session ordering)
 *   createdAt,                           // server-side authoritative time
 *   // impression only:
 *   items: [{ dealID, venueID, position, kind, score, <features> }],
 *   // tap/redeem only:
 *   dealID, venueID, position
 * }
 * ```
 */
enum class RankingEventType(val raw: String) {
    IMPRESSION("impression"),   // a feed slate was shown (candidates + positions + features)
    TAP("tap"),                 // user opened a deal
    REDEEM("redeem"),           // coupon redeemed (the primary label)
}

/**
 * Snapshot of a deal's features at rank time — the training input. Each field maps
 * to a term of `Ranking.dealScore`/`feedScore`.
 */
data class RankingItemFeatures(
    val dealID: String,
    val venueID: String,
    val position: Int,          // rank in the slate (0 = top)
    val kind: String,           // "deal" | "ad"
    val score: Double,          // final dealScore at display time
    // Raw signals (what score is computed from):
    val bayesRating: Double,
    val reviewCount: Int,
    val savedByCount: Int,
    val isVerified: Boolean,
    val hasTodaySpecial: Boolean,
    val activeDealCount: Int,
    val isFresh: Boolean,
    val daysSinceStart: Double?,
    val discountPercent: Int?,
    val hoursUntilExpiry: Double?,
    val distanceKm: Double?,
    val timeRelevance: Double,
) {
    fun asMap(): Map<String, Any> {
        val m = mutableMapOf<String, Any>(
            "dealID" to dealID, "venueID" to venueID, "position" to position, "kind" to kind,
            "score" to score, "bayesRating" to bayesRating, "reviewCount" to reviewCount,
            "savedByCount" to savedByCount, "isVerified" to isVerified,
            "hasTodaySpecial" to hasTodaySpecial, "activeDealCount" to activeDealCount,
            "isFresh" to isFresh, "timeRelevance" to timeRelevance,
        )
        daysSinceStart?.let { m["daysSinceStart"] = it }
        discountPercent?.let { m["discountPercent"] = it }
        hoursUntilExpiry?.let { m["hoursUntilExpiry"] = it }
        distanceKm?.let { m["distanceKm"] = it }
        return m
    }
}

/** One ranking-log event (envelope + type-specific payload). */
data class RankingEvent(
    val type: RankingEventType,
    val userID: String,
    val sessionID: String,
    val renderID: String,
    val citySlug: String,
    val category: String?,
    val hour: Int,
    val weekday: Int,
    val clientTs: Double,
    // impression: the full shown slate; tap/redeem: a single position.
    val items: List<RankingItemFeatures> = emptyList(),
    val dealID: String? = null,
    val venueID: String? = null,
    val position: Int? = null,
) {
    fun asFirestore(): Map<String, Any> {
        val m = mutableMapOf<String, Any>(
            "type" to type.raw, "userID" to userID, "sessionID" to sessionID,
            "renderID" to renderID, "platform" to "android", "citySlug" to citySlug,
            "hour" to hour, "weekday" to weekday, "clientTs" to clientTs,
            "createdAt" to Date(),
        )
        category?.let { m["category"] = it }
        if (type == RankingEventType.IMPRESSION) {
            m["items"] = items.map { it.asMap() }
        } else {
            dealID?.let { m["dealID"] = it }
            venueID?.let { m["venueID"] = it }
            position?.let { m["position"] = it }
        }
        return m
    }
}
