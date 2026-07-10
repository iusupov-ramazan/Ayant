package kg.ayant.app.data

import kg.ayant.app.data.model.Deal
import kg.ayant.app.data.model.DealType
import kg.ayant.app.data.model.FeedItem
import kg.ayant.app.data.model.Venue
import kg.ayant.app.data.model.VenueCategory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Date

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

    // --- venueScore ----------------------------------------------------------

    @Test
    fun `venueScore rewards rating monotonically`() {
        val low = Ranking.venueScore(3.0, 10, 5, false, false, false, 0)
        val high = Ranking.venueScore(4.5, 10, 5, false, false, false, 0)
        assertTrue("higher rating should score higher", high > low)
        // rating weight is 2.0 per point
        assertEquals(2.0 * (4.5 - 3.0), high - low, 1e-9)
    }

    @Test
    fun `venueScore verified bonus is 3 points`() {
        val plain = Ranking.venueScore(4.0, 20, 10, false, false, false, 2)
        val verified = Ranking.venueScore(4.0, 20, 10, true, false, false, 2)
        assertEquals(3.0, verified - plain, 1e-9)
    }

    @Test
    fun `venueScore active deals saturate at five`() {
        val five = Ranking.venueScore(4.0, 20, 10, false, false, false, 5)
        val fifty = Ranking.venueScore(4.0, 20, 10, false, false, false, 50)
        assertEquals("deal contribution is capped", five, fifty, 1e-9)
        val four = Ranking.venueScore(4.0, 20, 10, false, false, false, 4)
        assertEquals(0.8, five - four, 1e-9) // each of first 5 deals worth 0.8
    }

    // --- dealScore -----------------------------------------------------------

    @Test
    fun `dealScore adds freshness and recency`() {
        val base = 10.0
        val stale = Ranking.dealScore(base, isFresh = false, daysSinceStart = 20.0)
        assertEquals(base, stale, 1e-9) // 20 days -> max(0, 10-20)=0, not fresh
        val fresh = Ranking.dealScore(base, isFresh = true, daysSinceStart = 0.0)
        assertEquals(base + 6.0 + 10.0, fresh, 1e-9) // fresh bonus + full recency
        val recentOnly = Ranking.dealScore(base, isFresh = false, daysSinceStart = 3.0)
        assertEquals(base + 7.0, recentOnly, 1e-9) // 10 - 3
    }

    // --- feedScore + haversine distance weighting ----------------------------

    @Test
    fun `feedScore weights nearer venues higher`() {
        val near = Ranking.feedScore(1.0, 4.0, 10, false, false, 0)
        val far = Ranking.feedScore(4.0, 4.0, 10, false, false, 0)
        assertTrue("nearer venue ranks higher", near > far)
        // distance term: max(0, 5-km) * 3  ->  (5-1)*3 - (5-4)*3 = 9
        assertEquals(9.0, near - far, 1e-9)
    }

    @Test
    fun `feedScore ignores distance beyond five km`() {
        val atFive = Ranking.feedScore(5.0, 4.0, 10, false, false, 0)
        val atTen = Ranking.feedScore(10.0, 4.0, 10, false, false, 0)
        assertEquals(atFive, atTen, 1e-9)
    }

    @Test
    fun `feedScore null distance drops the distance term`() {
        val withDist = Ranking.feedScore(0.0, 4.0, 10, false, false, 0)
        val noDist = Ranking.feedScore(null, 4.0, 10, false, false, 0)
        assertEquals(15.0, withDist - noDist, 1e-9) // (5-0)*3
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
}
