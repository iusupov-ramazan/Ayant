package kg.ayant.app.domain

import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.DealType
import kg.ayant.app.domain.model.FeedItem
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenueCategory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Date
import kotlin.math.ln

/** Unit tests for the pure ranking math extracted from AppViewModel. */
class RankingTest {

    // --- helpers -------------------------------------------------------------

    private fun venue(id: String) = Venue(
        id = id, name = id, category = VenueCategory.CAFE, district = "", address = "",
        phone = "", emoji = "🍽", gradient = listOf(0xFFFF5A1FL),
    )

    private fun deal(id: String, venueID: String = "v") = Deal(
        id = id, venueID = venueID, type = DealType.DISCOUNT, title = id, details = "",
        emoji = "🔥", validUntil = Date(System.currentTimeMillis() + 86_400_000L),
    )

    /** Saturating popularity term, recomputed here to check exact contributions. */
    private fun sat(n: Double, ref: Double) = minOf(1.0, ln(n + 1.0) / ln(ref + 1.0))

    // --- bayesianRating (shrinkage toward the catalogue mean) ----------------

    @Test
    fun `bayesianRating pulls sparse ratings toward the prior`() {
        // (v·R + m·C)/(v+m) with C=4.0, m=20.
        assertEquals((2 * 5.0 + 20 * 4.0) / 22.0, Ranking.bayesianRating(5.0, 2), 1e-9)
        assertEquals((400 * 4.6 + 20 * 4.0) / 420.0, Ranking.bayesianRating(4.6, 400), 1e-9)
    }

    @Test
    fun `a well-reviewed 4_6 outranks a barely-reviewed 5_0`() {
        // The headline fix: raw rating no longer wins on 2 reviews.
        val fiveButThin = Ranking.venueScore(5.0, 2, 0, false, false, false, 0)
        val strongFourSix = Ranking.venueScore(4.6, 400, 0, false, false, false, 0)
        assertTrue("400-review 4.6 should beat a 2-review 5.0", strongFourSix > fiveButThin)
    }

    // --- venueScore ----------------------------------------------------------

    @Test
    fun `venueScore rewards rating monotonically`() {
        val low = Ranking.venueScore(3.0, 10, 5, false, false, false, 0)
        val high = Ranking.venueScore(4.5, 10, 5, false, false, false, 0)
        assertTrue("higher rating should score higher", high > low)
        // Only the Bayesian-quality term differs: weight 4.0 on (bayes/5).
        val expected = 4.0 * (Ranking.bayesianRating(4.5, 10) - Ranking.bayesianRating(3.0, 10)) / 5.0
        assertEquals(expected, high - low, 1e-9)
    }

    @Test
    fun `venueScore verified bonus is 1_5 points`() {
        val plain = Ranking.venueScore(4.0, 20, 10, false, false, false, 2)
        val verified = Ranking.venueScore(4.0, 20, 10, true, false, false, 2)
        assertEquals(1.5, verified - plain, 1e-9)
    }

    @Test
    fun `venueScore active deals saturate`() {
        val five = Ranking.venueScore(4.0, 20, 10, false, false, false, 5)
        val fifty = Ranking.venueScore(4.0, 20, 10, false, false, false, 50)
        // Both are at/above the saturation reference (5) -> capped, equal contribution.
        assertEquals("deal contribution saturates", five, fifty, 1e-9)
        val four = Ranking.venueScore(4.0, 20, 10, false, false, false, 4)
        // weight 1.5 on the saturating term.
        assertEquals(1.5 * (sat(5.0, 5.0) - sat(4.0, 5.0)), five - four, 1e-9)
    }

    // --- dealScore -----------------------------------------------------------

    @Test
    fun `dealScore adds freshness and recency`() {
        val base = 10.0
        // 20 days old, not fresh, no discount/expiry, neutral time (0) -> just base.
        val stale = Ranking.dealScore(base, false, 20.0, null, null, 0.0)
        assertEquals(base, stale, 1e-9) // (14-20)/14 clamped to 0
        val fresh = Ranking.dealScore(base, true, 0.0, null, null, 0.0)
        assertEquals(base + 3.0 + 2.0, fresh, 1e-9) // fresh(+3) + full recency(+2)
        val recentOnly = Ranking.dealScore(base, false, 7.0, null, null, 0.0)
        assertEquals(base + 2.0 * (14.0 - 7.0) / 14.0, recentOnly, 1e-9) // half-decayed
    }

    @Test
    fun `dealScore rewards discount depth up to the reference`() {
        val base = 10.0
        assertEquals(base + 1.5, Ranking.dealScore(base, false, null, 25, null, 0.0), 1e-9) // 25/50 -> 1.5
        assertEquals(base + 3.0, Ranking.dealScore(base, false, null, 50, null, 0.0), 1e-9) // 50/50 -> 3
        assertEquals(base + 3.0, Ranking.dealScore(base, false, null, 90, null, 0.0), 1e-9) // capped at 3
        assertEquals(base, Ranking.dealScore(base, false, null, 0, null, 0.0), 1e-9)        // no discount
    }

    @Test
    fun `dealScore nudges deals that end soon`() {
        val base = 10.0
        assertEquals(base + 1.5, Ranking.dealScore(base, false, null, null, 0.0, 0.0), 1e-9)  // expiring now
        assertEquals(base + 0.75, Ranking.dealScore(base, false, null, null, 24.0, 0.0), 1e-9) // half a day
        assertEquals(base, Ranking.dealScore(base, false, null, null, 48.0, 0.0), 1e-9)        // edge of window
        assertEquals(base, Ranking.dealScore(base, false, null, null, 100.0, 0.0), 1e-9)       // outside window
    }

    @Test
    fun `dealScore adds time-of-day relevance`() {
        val base = 10.0
        // weight 2.0 on the 0..1 relevance term; everything else neutral.
        val off = Ranking.dealScore(base, false, null, null, null, 0.0)
        val peak = Ranking.dealScore(base, false, null, null, null, 1.0)
        assertEquals(base, off, 1e-9)
        assertEquals(base + 2.0, peak, 1e-9)
    }

    // --- VenueCategory.timeRelevance (category ↔ hour fit) -------------------

    @Test
    fun `timeRelevance favours coffee in the morning and restaurants at dinner`() {
        // 9:00 — coffee peaks, dinner restaurant is off-peak.
        assertTrue(VenueCategory.COFFEE.timeRelevance(9) > VenueCategory.RESTAURANT.timeRelevance(9))
        // 20:00 — restaurant peaks, coffee is off-peak.
        assertTrue(VenueCategory.RESTAURANT.timeRelevance(20) > VenueCategory.COFFEE.timeRelevance(20))
        // Unknown/backend category is neutral (0.5) at any hour.
        assertEquals(0.5, VenueCategory("Барбершоп").timeRelevance(9), 1e-9)
    }

    // --- feedScore + haversine distance weighting ----------------------------

    @Test
    fun `feedScore weights nearer venues higher`() {
        val near = Ranking.feedScore(1.0, 4.0, 10, false, false, 0, 0.0)
        val far = Ranking.feedScore(4.0, 4.0, 10, false, false, 0, 0.0)
        assertTrue("nearer venue ranks higher", near > far)
        // distance term: 6 * (5-km)/5  ->  6*(4/5) - 6*(1/5) = 4.8 - 1.2 = 3.6
        assertEquals(3.6, near - far, 1e-9)
    }

    @Test
    fun `feedScore ignores distance beyond five km`() {
        val atFive = Ranking.feedScore(5.0, 4.0, 10, false, false, 0, 0.0)
        val atTen = Ranking.feedScore(10.0, 4.0, 10, false, false, 0, 0.0)
        assertEquals(atFive, atTen, 1e-9)
    }

    @Test
    fun `feedScore null distance drops the distance term`() {
        val withDist = Ranking.feedScore(0.0, 4.0, 10, false, false, 0, 0.0)
        val noDist = Ranking.feedScore(null, 4.0, 10, false, false, 0, 0.0)
        assertEquals(6.0, withDist - noDist, 1e-9) // 6 * (5-0)/5
    }

    @Test
    fun `haversine is zero for identical points`() {
        assertEquals(0.0, Ranking.haversineKm(42.8746, 74.5698, 42.8746, 74.5698), 1e-9)
    }

    @Test
    fun `haversine one degree of latitude is about 111 km`() {
        val km = Ranking.haversineKm(0.0, 0.0, 1.0, 0.0)
        assertEquals(111.19, km, 0.5)
    }

    // --- feed ad-insertion cadence -------------------------------------------

    @Test
    fun `feed inserts a sponsored card before the fourth deal`() {
        val deals = (0 until 6).map { deal("d$it") }
        val ads = listOf(venue("ad0"))
        val feed = Ranking.feed(deals, ads)

        // 6 deals + 1 ad = 7 items; the ad sits at index 3 (before the 4th deal)
        assertEquals(7, feed.size)
        assertTrue(feed[3] is FeedItem.AdVenue)
        assertEquals("ad0", (feed[3] as FeedItem.AdVenue).venue.id)
        // deal order preserved around the ad
        assertEquals("d2", (feed[2] as FeedItem.DealItem).deal.id)
        assertEquals("d3", (feed[4] as FeedItem.DealItem).deal.id)
        assertEquals(1, feed.count { it is FeedItem.AdVenue })
    }

    @Test
    fun `feed appends leftover ads when deals are too few to place them`() {
        val deals = listOf(deal("d0"), deal("d1"))
        val ads = listOf(venue("ad0"), venue("ad1"))
        val feed = Ranking.feed(deals, ads)

        // no slot reaches index 3, so both ads land at the tail in order
        assertEquals(listOf("d_d0", "d_d1", "av_ad0", "av_ad1"), feed.map { it.id })
    }

    @Test
    fun `feed with no deals returns ads only`() {
        val feed = Ranking.feed(emptyList(), listOf(venue("ad0"), venue("ad1")))
        assertEquals(2, feed.size)
        assertTrue(feed.all { it is FeedItem.AdVenue })
    }

    // --- RankingWeights (published config → weights) -------------------------

    @Test
    fun `RankingWeights from overlays known keys and defaults the rest`() {
        val w = RankingWeights.from(mapOf("W_RATING" to 10.0, "W_VALUE" to 9.0, "UNKNOWN" to 1.0))
        assertEquals(10.0, w.rating, 1e-9)                             // overridden
        assertEquals(9.0, w.value, 1e-9)                              // overridden
        assertEquals(RankingWeights.DEFAULT.reviews, w.reviews, 1e-9) // untouched → default
    }

    @Test
    fun `RankingWeights from null or empty returns defaults`() {
        assertEquals(RankingWeights.DEFAULT, RankingWeights.from(null))
        assertEquals(RankingWeights.DEFAULT, RankingWeights.from(emptyMap()))
    }

    @Test
    fun `published weights change the score`() {
        val base = Ranking.venueScore(5.0, 200, 0, false, false, false, 0)
        val heavier = Ranking.venueScore(5.0, 200, 0, false, false, false, 0,
            RankingWeights.from(mapOf("W_RATING" to 8.0)))  // rating weight 4 → 8
        assertTrue("doubling the rating weight raises a top-rated venue's score", heavier > base)
    }
}
