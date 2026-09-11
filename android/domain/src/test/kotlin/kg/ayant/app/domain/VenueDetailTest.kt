package kg.ayant.app.domain

import kg.ayant.app.domain.model.Review
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenueCategory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Date

/**
 * Производные величины карточки заведения. Зеркалит `DomainVenueDetailTests.swift`.
 *
 * Раньше они жили в `AppViewModel` и проверялись только глазами; здесь это
 * чистые функции состояния.
 */
class VenueDetailTest {

    private fun venue(rating: Double = 4.0, reviews: Int = 10) = Venue(
        id = "v1", name = "Navat", category = VenueCategory.CAFE, district = "", address = "",
        phone = "", emoji = "🍽", gradient = listOf(0L), rating = rating, reviewCount = reviews,
    )

    private fun review(id: String, rating: Int, author: String = "me", itemID: String? = null) = Review(
        id = id, venueID = "v1", authorID = author, authorName = "Я",
        rating = rating, text = "", createdAt = Date(0), updatedAt = Date(0), itemID = itemID,
    )

    @Test
    fun `aggregate falls back to seed when no reviews`() {
        val state = VenueDetailState(venue = venue(rating = 4.6, reviews = 213))
        assertEquals(4.6, state.aggregate.rating, 1e-9)
        assertEquals(213, state.aggregate.count)
    }

    @Test
    fun `live reviews override seed rating`() {
        val state = VenueDetailState(
            venue = venue(rating = 4.6, reviews = 213),
            reviews = listOf(review("a", 2), review("b", 4)),
        )
        assertEquals(3.0, state.aggregate.rating, 1e-9)
        assertEquals(2, state.aggregate.count)
    }

    @Test
    fun `rating breakdown always has all five keys`() {
        val state = VenueDetailState(venue = venue(), reviews = listOf(review("a", 5)))
        assertEquals(mapOf(1 to 0, 2 to 0, 3 to 0, 4 to 0, 5 to 1), state.ratingBreakdown)
    }

    @Test
    fun `my review is scoped to author and item`() {
        val state = VenueDetailState(
            venue = venue(),
            reviews = listOf(
                review("mine", 5),
                review("mine-dish", 4, itemID = "dish1"),
                review("theirs", 1, author = "someone"),
            ),
            currentUserID = "me", isGuest = false,
        )
        assertEquals("mine", state.myReview()?.id)
        assertEquals("mine-dish", state.myReview("dish1")?.id)
        assertNull(state.myReview("dish2"))
    }

    @Test
    fun `guest has no own review and cannot contribute`() {
        val state = VenueDetailState(
            venue = venue(), reviews = listOf(review("mine", 5)),
            currentUserID = "", isGuest = true,
        )
        assertNull(state.myReview())
        assertFalse(state.canContribute)
    }

    @Test
    fun `empty state is safe to render`() {
        val state = VenueDetailState()
        assertNull(state.venue)
        assertEquals(0, state.aggregate.count)
        assertEquals(mapOf(1 to 0, 2 to 0, 3 to 0, 4 to 0, 5 to 0), state.ratingBreakdown)
        assertFalse(state.canContribute)
    }
}
