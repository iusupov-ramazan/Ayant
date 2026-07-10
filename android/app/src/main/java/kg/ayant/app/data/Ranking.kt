package kg.ayant.app.data

import kg.ayant.app.data.model.Deal
import kg.ayant.app.data.model.FeedItem
import kg.ayant.app.data.model.Venue
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Pure, Android-free ranking math extracted from AppViewModel so it can be unit-tested
 * directly (and to keep the view model from being a god object). Every function here is
 * a pure function of its inputs — no state, no framework types.
 */
object Ranking {

    /** Organic venue score (mirrors AppStore.venueScore). */
    fun venueScore(
        rating: Double,
        reviewCount: Int,
        savedByCount: Int,
        isVerified: Boolean,
        hasTodaySpecial: Boolean,
        isOpenNow: Boolean,
        activeDealCount: Int,
    ): Double {
        var s = 0.0
        s += rating * 2.0
        s += ln(reviewCount + 1.0) * 1.5
        s += ln(savedByCount + 1.0) * 1.0
        if (isVerified) s += 3.0
        if (hasTodaySpecial) s += 1.5
        if (isOpenNow) s += 1.0
        s += min(activeDealCount.toDouble(), 5.0) * 0.8
        return s
    }

    /** Deal score: its venue's score plus freshness and recency bonuses. */
    fun dealScore(venueScore: Double, isFresh: Boolean, daysSinceStart: Double?): Double {
        var s = venueScore
        if (isFresh) s += 6.0
        if (daysSinceStart != null) s += maxOf(0.0, 10 - daysSinceStart)
        return s
    }

    /** Distance-weighted feed score (mirrors AppStore.feedScore). */
    fun feedScore(
        distanceKm: Double?,
        rating: Double,
        reviewCount: Int,
        hasFreshDeal: Boolean,
        hasTodaySpecial: Boolean,
        dealCount: Int,
    ): Double {
        var score = 0.0
        if (distanceKm != null) score += maxOf(0.0, 5 - distanceKm) * 3.0
        score += rating * ln(maxOf(reviewCount, 1) + 1.0) * 1.5
        if (hasFreshDeal) score += 4.0
        if (hasTodaySpecial) score += 4.0
        score += dealCount * 0.5
        return score
    }

    /** Great-circle distance in km between two lat/lng points. */
    fun haversineKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val r = 6371.0
        val dLat = (lat2 - lat1) * Math.PI / 180
        val dLon = (lon2 - lon1) * Math.PI / 180
        val a = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1 * Math.PI / 180) * cos(lat2 * Math.PI / 180) *
            sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /**
     * Interleave sponsored venue cards into a ranked deal feed. A sponsored card is
     * inserted before every 4th deal (indexes 3, 8, 13, …); any leftover ads are
     * appended. Mirrors AppStore.feedItems.
     */
    fun feed(deals: List<Deal>, ads: List<Venue>): List<FeedItem> {
        val items = mutableListOf<FeedItem>()
        var ai = 0
        deals.forEachIndexed { i, d ->
            if (i % 5 == 3 && ai < ads.size) { items.add(FeedItem.AdVenue(ads[ai])); ai++ }
            items.add(FeedItem.DealItem(d))
        }
        while (ai < ads.size) { items.add(FeedItem.AdVenue(ads[ai])); ai++ }
        return items
    }
}
