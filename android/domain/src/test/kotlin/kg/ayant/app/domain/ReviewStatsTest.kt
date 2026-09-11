package kg.ayant.app.domain

import kg.ayant.app.domain.model.Review
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenueCategory
import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Date

/**
 * Юнит-тесты пакетной агрегации отзывов.
 *
 * Зеркалит `DomainReviewStatsTests.swift` (раздел aggregateAll) — та же математика
 * должна давать те же числа на обеих платформах.
 */
class ReviewStatsTest {

    @Test
    fun `aggregateAll совпадает с поштучным aggregate`() {
        val venues = listOf(
            venue("v1", seedRating = 4.2, seedCount = 37),
            venue("v2", seedRating = 3.0, seedCount = 5),
            venue("v3", seedRating = 1.5, seedCount = 99),   // без отзывов → фолбэк
        )
        val reviews = listOf(
            review("a", rating = 5, venueID = "v1"),
            review("b", rating = 3, venueID = "v1"),
            review("c", rating = 4, venueID = "v1"),
            review("d", rating = 2, venueID = "v2"),
        )

        val batch = ReviewStats.aggregateAll(venues, reviews)

        // Эталон — тот самый поштучный путь, который пакетный вариант вытеснил.
        for (v in venues) {
            val mine = reviews.filter { it.venueID == v.id }
            val expected = ReviewStats.aggregate(mine, v.rating, v.reviewCount)
            assertEquals("рейтинг разошёлся для ${v.id}", expected.first, batch[v.id]!!.rating, 1e-9)
            assertEquals("число отзывов разошлось для ${v.id}", expected.second, batch[v.id]!!.count)
        }
    }

    @Test
    fun `aggregateAll падает на seed для заведений без отзывов`() {
        val batch = ReviewStats.aggregateAll(listOf(venue("v3", 1.5, 99)), emptyList())
        assertEquals(1.5, batch["v3"]!!.rating, 1e-9)
        assertEquals(99, batch["v3"]!!.count)
    }

    @Test
    fun `aggregateAll игнорирует отзывы на заведения вне каталога`() {
        val batch = ReviewStats.aggregateAll(
            listOf(venue("v1", 4.0, 2)),
            listOf(review("x", rating = 1, venueID = "ghost")),
        )
        assertEquals(setOf("v1"), batch.keys)
        assertEquals(4.0, batch["v1"]!!.rating, 1e-9)   // фолбэк, чужой отзыв не учтён
    }

    @Test
    fun `aggregateAll покрывает каждое заведение ровно один раз`() {
        val venues = (1..50).map { venue("v$it", 3.0, 1) }
        assertEquals(50, ReviewStats.aggregateAll(venues, emptyList()).size)
    }

    // --- фабрики ------------------------------------------------------------

    private fun review(id: String, rating: Int, venueID: String = "v") = Review(
        id = id, venueID = venueID, authorID = "a", authorName = "A",
        rating = rating, text = "", photoEmojis = emptyList(),
        createdAt = Date(0), updatedAt = Date(0), hostReply = null,
    )

    private fun venue(id: String, seedRating: Double, seedCount: Int) = Venue(
        id = id, name = "Venue $id", category = VenueCategory.CAFE, district = "",
        address = "", phone = "", emoji = "🍽", gradient = listOf(0xFFFF5A1FL),
        rating = seedRating, reviewCount = seedCount,
    )
}
