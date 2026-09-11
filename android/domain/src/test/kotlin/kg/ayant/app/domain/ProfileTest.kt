package kg.ayant.app.domain

import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.DealType
import kg.ayant.app.domain.model.Review
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenueCategory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Date

/**
 * Личная библиотека: сборка списков по каталогу и проверки прав.
 * Зеркалит `DomainProfileTests.swift`.
 */
class ProfileTest {

    private val now = 1_700_000_000_000L

    private fun venue(id: String) = Venue(
        id = id, name = id, category = VenueCategory.CAFE, district = "", address = "",
        phone = "", emoji = "🍽", gradient = listOf(0L),
    )

    private fun deal(id: String, venueID: String = "v1", untilMs: Long = 86_400_000L) = Deal(
        id = id, venueID = venueID, type = DealType.DISCOUNT, title = id, details = "",
        emoji = "🔥", validUntil = Date(now + untilMs),
    )

    private val catalog = FeedCatalog(
        venues = listOf(venue("v1"), venue("v2"), venue("v3")),
        deals = listOf(deal("d1"), deal("d2"), deal("expired", untilMs = -3_600_000L)),
    )

    @Test
    fun `saved venues skip ids missing from catalog`() {
        val state = ProfileState(savedVenueIDs = setOf("v1", "v3", "ghost"))
        assertEquals(listOf("v1", "v3"), state.savedVenues(catalog).map { it.id })
    }

    @Test
    fun `favorite deals drop expired and sort by expiry`() {
        val state = ProfileState(favoriteDealIDs = setOf("d1", "d2", "expired"))
        assertEquals(listOf("d1", "d2"), state.favoriteDeals(catalog, now).map { it.id })
    }

    @Test
    fun `hasVisited requires a redeemed deal at that venue`() {
        val visited = ProfileState(redeemedDealIDs = setOf("d1"))
        assertTrue(visited.hasVisited("v1", catalog))
        assertFalse(visited.hasVisited("v2", catalog))
        assertFalse(ProfileState().hasVisited("v1", catalog))
    }

    @Test
    fun `guest cannot contribute and has no referral code`() {
        val guest = ProfileState(userID = "", isGuest = true)
        assertFalse(guest.canContribute)
        assertEquals("", guest.referralCode)

        val signedIn = ProfileState(userID = "u1", isGuest = false)
        assertTrue(signedIn.canContribute)
        assertEquals("u1", signedIn.referralCode)
    }

    @Test
    fun `my reviews are scoped to author and newest first`() {
        val older = Review("old", "v1", "u1", "Я", 4, "",
            createdAt = Date(now - 86_400_000L), updatedAt = Date(now))
        val newer = Review("new", "v2", "u1", "Я", 5, "",
            createdAt = Date(now), updatedAt = Date(now))
        val other = Review("other", "v1", "u2", "Кто-то", 1, "",
            createdAt = Date(now), updatedAt = Date(now))

        val state = ProfileState(userID = "u1", isGuest = false)
        assertEquals(listOf("new", "old"), state.myReviews(listOf(older, newer, other)).map { it.id })
    }

    @Test
    fun `anonymous user has no reviews`() {
        val review = Review("r", "v1", "", "", 5, "",
            createdAt = Date(now), updatedAt = Date(now))
        assertTrue(ProfileState().myReviews(listOf(review)).isEmpty())
    }

    /** Ключи хранилища читают уже установленные приложения — их нельзя менять. */
    @Test
    fun `storage keys match shipped installs`() {
        assertEquals("san.savedVenues", ProfileStorageKey.SAVED_VENUES)
        assertEquals("san.favorites", ProfileStorageKey.FAVORITE_DEALS)
        assertEquals("san.redeemed", ProfileStorageKey.REDEEMED_DEALS)
    }
}
