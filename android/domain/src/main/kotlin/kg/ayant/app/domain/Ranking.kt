package kg.ayant.app.domain

import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.FeedItem
import kg.ayant.app.domain.model.Venue
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Tunable ranking coefficients. Extracted from the `Ranking` object so they can be
 * **published as data** (Firestore `config/rankingWeights`) and swapped for weights
 * learned from the `rankingEvents` log — without an app release (see ml/README.md).
 * [DEFAULT] holds the hand-tuned values; [from] overlays a published map field-by-field
 * (missing keys keep their default, so a partial/absent doc is always safe).
 *
 * Map keys match the training-script output (W_RATING, FW_DISTANCE, …). Mirror
 * `RankingWeights` in `Domain/Ranking.swift` 1:1 (fields, defaults, key names).
 * Normalization refs (REVIEWS_REF, VALUE_REF_PCT, …) are NOT here — they are shared
 * hyperparameters that must stay identical across both clients and the trainer.
 */
data class RankingWeights(
    // Venue quality.
    val rating: Double, val reviews: Double, val saves: Double, val verified: Double,
    val todaySpecial: Double, val openNow: Double, val activeDeals: Double,
    // Deal.
    val fresh: Double, val recency: Double, val value: Double, val urgency: Double, val time: Double,
    // Feed (venue list).
    val fwDistance: Double, val fwQuality: Double, val fwPopularity: Double,
    val fwFreshDeal: Double, val fwTodaySpecial: Double, val fwDeals: Double, val fwTime: Double,
) {
    companion object {
        val DEFAULT = RankingWeights(
            rating = 4.0, reviews = 2.0, saves = 1.0, verified = 1.5, todaySpecial = 1.0,
            openNow = 1.0, activeDeals = 1.5,
            fresh = 3.0, recency = 2.0, value = 3.0, urgency = 1.5, time = 2.0,
            fwDistance = 6.0, fwQuality = 4.0, fwPopularity = 1.5, fwFreshDeal = 3.0,
            fwTodaySpecial = 3.0, fwDeals = 1.5, fwTime = 2.0,
        )

        /** Overlay a published weight map onto [DEFAULT]; unknown/missing keys keep defaults. */
        fun from(m: Map<String, Double>?): RankingWeights {
            if (m.isNullOrEmpty()) return DEFAULT
            val d = DEFAULT
            fun g(k: String, dv: Double) = m[k] ?: dv
            return RankingWeights(
                rating = g("W_RATING", d.rating), reviews = g("W_REVIEWS", d.reviews),
                saves = g("W_SAVES", d.saves), verified = g("W_VERIFIED", d.verified),
                todaySpecial = g("W_TODAY_SPECIAL", d.todaySpecial), openNow = g("W_OPEN_NOW", d.openNow),
                activeDeals = g("W_ACTIVE_DEALS", d.activeDeals),
                fresh = g("W_FRESH", d.fresh), recency = g("W_RECENCY", d.recency),
                value = g("W_VALUE", d.value), urgency = g("W_URGENCY", d.urgency), time = g("W_TIME", d.time),
                fwDistance = g("FW_DISTANCE", d.fwDistance), fwQuality = g("FW_QUALITY", d.fwQuality),
                fwPopularity = g("FW_POPULARITY", d.fwPopularity), fwFreshDeal = g("FW_FRESH_DEAL", d.fwFreshDeal),
                fwTodaySpecial = g("FW_TODAY_SPECIAL", d.fwTodaySpecial), fwDeals = g("FW_DEALS", d.fwDeals),
                fwTime = g("FW_TIME", d.fwTime),
            )
        }
    }
}

/**
 * Pure, Android-free ranking math extracted from AppViewModel so it can be unit-tested
 * directly (and to keep the view model from being a god object). Every function here is
 * a pure function of its inputs — no state, no framework types.
 *
 * Design notes (mirror `Domain/Ranking.swift` on iOS 1:1 — signatures, weights, and
 * term order must stay identical or the two clients rank the same Firestore docs
 * differently):
 *  - The score is a **linear model** over normalized terms. Coefficients come from
 *    [RankingWeights] (defaulted to the hand-tuned values, overridable from config), so
 *    weights **learned from the rankingEvents log** can ship without touching this logic.
 *  - Each term is **normalized** to a comparable range (mostly 0..1) before it is
 *    weighted, so a weight's magnitude actually reflects that signal's influence.
 *  - Ratings are **Bayesian-shrunk** toward the catalogue mean so a 5.0 with 2 reviews
 *    cannot outrank a 4.6 with 400.
 */
object Ranking {

    // --- Normalization references (shared hyperparameters — keep in sync with trainer) ---
    private const val PRIOR_MEAN = 4.0        // assumed catalogue-average rating (C)
    private const val PRIOR_WEIGHT = 20.0     // # of "virtual" reviews the prior is worth (m)
    private const val REVIEWS_REF = 150.0     // review count at which popularity ≈ 1
    private const val SAVES_REF = 150.0       // saves at which popularity ≈ 1
    private const val DEALS_REF = 5.0         // deal count at which the term ≈ 1
    private const val RECENCY_DAYS = 14.0     // recency bonus decays to 0 over this many days
    private const val VALUE_REF_PCT = 50.0    // ≥50% off earns the full value score
    private const val URGENCY_HOURS = 48.0    // urgency ramps up inside the last 48h
    private const val DISTANCE_MAX_KM = 5.0   // beyond this, proximity contributes 0

    /**
     * Rating shrunk toward the catalogue mean (classic Bayesian / IMDB weighting):
     * `(v·R + m·C) / (v + m)`. Sparse ratings are pulled toward [PRIOR_MEAN]; a rating
     * only earns its extremes once enough reviews ([PRIOR_WEIGHT]-scale) back it.
     */
    fun bayesianRating(rating: Double, reviewCount: Int): Double {
        val v = reviewCount.toDouble()
        return (v * rating + PRIOR_WEIGHT * PRIOR_MEAN) / (v + PRIOR_WEIGHT)
    }

    /** Diminishing-returns popularity in 0..1: `ln(n+1) / ln(ref+1)`, capped at 1. */
    private fun saturating(n: Double, ref: Double): Double =
        min(1.0, ln(n + 1.0) / ln(ref + 1.0))

    /** Organic venue score (mirrors AppStore.venueScore). */
    fun venueScore(
        rating: Double,
        reviewCount: Int,
        savedByCount: Int,
        isVerified: Boolean,
        hasTodaySpecial: Boolean,
        isOpenNow: Boolean,
        activeDealCount: Int,
        w: RankingWeights = RankingWeights.DEFAULT,
    ): Double {
        var s = 0.0
        s += w.rating * (bayesianRating(rating, reviewCount) / 5.0)
        s += w.reviews * saturating(reviewCount.toDouble(), REVIEWS_REF)
        s += w.saves * saturating(savedByCount.toDouble(), SAVES_REF)
        if (isVerified) s += w.verified
        if (hasTodaySpecial) s += w.todaySpecial
        if (isOpenNow) s += w.openNow
        s += w.activeDeals * saturating(activeDealCount.toDouble(), DEALS_REF)
        return s
    }

    /**
     * Organic deal score: its venue's score plus freshness, recency, how good the
     * discount is, and a mild ending-soon nudge.
     *  - [discountPercent]: effective % off (null/≤0 → no value bonus).
     *  - [hoursUntilExpiry]: hours to `validUntil`; the urgency nudge only applies
     *    inside the last [URGENCY_HOURS] and ramps up as expiry approaches. Expired
     *    deals are filtered upstream (`isActive`), so this is ≥ 0 in the feed.
     *  - [timeRelevance]: 0..1 fit of the venue's category to the current hour
     *    (`VenueCategory.timeRelevance`), computed by the caller so this stays pure.
     */
    fun dealScore(
        venueScore: Double,
        isFresh: Boolean,
        daysSinceStart: Double?,
        discountPercent: Int?,
        hoursUntilExpiry: Double?,
        timeRelevance: Double,
        w: RankingWeights = RankingWeights.DEFAULT,
    ): Double {
        var s = venueScore
        if (isFresh) s += w.fresh
        if (daysSinceStart != null) {
            s += w.recency * maxOf(0.0, (RECENCY_DAYS - daysSinceStart) / RECENCY_DAYS)
        }
        if (discountPercent != null && discountPercent > 0) {
            s += w.value * min(1.0, discountPercent / VALUE_REF_PCT)
        }
        if (hoursUntilExpiry != null && hoursUntilExpiry in 0.0..URGENCY_HOURS) {
            s += w.urgency * ((URGENCY_HOURS - hoursUntilExpiry) / URGENCY_HOURS)
        }
        s += w.time * timeRelevance
        return s
    }

    /**
     * Distance-weighted feed score (mirrors AppStore.feedScore).
     *  - [timeRelevance]: 0..1 fit of the venue's category to the current hour
     *    (`VenueCategory.timeRelevance`), computed by the caller so this stays pure.
     */
    fun feedScore(
        distanceKm: Double?,
        rating: Double,
        reviewCount: Int,
        hasFreshDeal: Boolean,
        hasTodaySpecial: Boolean,
        dealCount: Int,
        timeRelevance: Double,
        w: RankingWeights = RankingWeights.DEFAULT,
    ): Double {
        var score = 0.0
        if (distanceKm != null) {
            score += w.fwDistance * maxOf(0.0, (DISTANCE_MAX_KM - distanceKm) / DISTANCE_MAX_KM)
        }
        score += w.fwQuality * (bayesianRating(rating, reviewCount) / 5.0)
        score += w.fwPopularity * saturating(reviewCount.toDouble(), REVIEWS_REF)
        if (hasFreshDeal) score += w.fwFreshDeal
        if (hasTodaySpecial) score += w.fwTodaySpecial
        score += w.fwDeals * saturating(dealCount.toDouble(), DEALS_REF)
        score += w.fwTime * timeRelevance
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

/**
 * Осмысленность расстояния. Зеркалит `GeoDisplay` в `Ranking.swift`.
 *
 * Каталог всегда в пределах ОДНОГО города (`citySlug`, сейчас всегда «bishkek»),
 * поэтому расстояние имеет смысл, только пока пользователь рядом с этим городом.
 * Если геопозиция за тысячи километров (другая страна, эмулятор с дефолтной
 * точкой, VPN), «11358.7 км» в каждой строке — шум, а не данные.
 */
object GeoDisplay {
    /**
     * Дальше этого — считаем, что пользователь не в городе каталога.
     * Сам Бишкек укладывается в ~30 км, так что 100 км — с большим запасом.
     */
    const val MAX_MEANINGFUL_KM = 100.0

    /** Стоит ли вообще показывать это расстояние. */
    fun isMeaningful(km: Double): Boolean =
        km.isFinite() && km >= 0 && km <= MAX_MEANINGFUL_KM
}
