package kg.ayant.app.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Guards the `rankingEvents` document shape (field names + optional omission). These
 * names are the contract shared with iOS `RankingEvent.swift` and the training export;
 * a drift here silently corrupts the learning-to-rank dataset.
 */
class RankingEventTest {

    private fun features(discountPercent: Int?, distanceKm: Double?) = RankingItemFeatures(
        dealID = "d0", venueID = "v0", position = 0, kind = "deal", score = 12.5,
        bayesRating = 4.1, reviewCount = 10, savedByCount = 3, isVerified = true,
        hasTodaySpecial = false, activeDealCount = 2, isFresh = true, daysSinceStart = 1.0,
        discountPercent = discountPercent, hoursUntilExpiry = 20.0, distanceKm = distanceKm,
        timeRelevance = 0.7,
    )

    private fun event(type: RankingEventType, items: List<RankingItemFeatures> = emptyList()) =
        RankingEvent(
            type = type, userID = "me", sessionID = "s1", renderID = "r1",
            citySlug = "bishkek", category = null, hour = 9, weekday = 2, clientTs = 1.0,
            items = items, dealID = if (items.isEmpty()) "d0" else null,
            venueID = if (items.isEmpty()) "v0" else null,
        )

    @Test
    fun `impression carries items and no single-item fields`() {
        val doc = event(RankingEventType.IMPRESSION, listOf(features(20, 1.2))).asFirestore()
        assertEquals("impression", doc["type"])
        assertEquals("android", doc["platform"])
        @Suppress("UNCHECKED_CAST")
        val items = doc["items"] as List<Map<String, Any>>
        assertEquals(1, items.size)
        assertEquals(20, items[0]["discountPercent"])
        assertEquals(1.2, items[0]["distanceKm"])
        assertFalse(doc.containsKey("dealID"))   // single-item fields only on tap/redeem
    }

    @Test
    fun `tap and redeem carry single-item fields and no items`() {
        val doc = event(RankingEventType.REDEEM).asFirestore()
        assertEquals("redeem", doc["type"])
        assertEquals("d0", doc["dealID"])
        assertEquals("v0", doc["venueID"])
        assertFalse(doc.containsKey("items"))
    }

    @Test
    fun `null optionals are omitted, not written as null`() {
        val m = features(discountPercent = null, distanceKm = null).asMap()
        assertFalse("null discount omitted", m.containsKey("discountPercent"))
        assertFalse("null distance omitted", m.containsKey("distanceKm"))
        assertTrue("present fields kept", m.containsKey("hoursUntilExpiry"))
        // null category is omitted from the envelope too.
        assertFalse(event(RankingEventType.TAP).asFirestore().containsKey("category"))
    }
}
