package kg.ayant.app.domain

import kg.ayant.app.domain.model.Review
import kg.ayant.app.domain.model.ReviewReport
import kg.ayant.app.domain.model.ReviewReportReason
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test
import java.util.Date

/** Жалоба на отзыв (App Review Guidelines 1.2). Зеркалит `DomainReviewReportTests`. */
class ReviewReportTest {

    private val now = Date(1_700_000_000_000L)

    private fun review(id: String = "rv1", venueID: String = "v1") = Review(
        id = id, venueID = venueID, authorID = "author", authorName = "Аида",
        rating = 1, text = "плохо", createdAt = now, updatedAt = now,
    )

    /**
     * Один человек — одна жалоба на отзыв: иначе очередь модерации можно
     * засыпать повторными нажатиями.
     */
    @Test fun `same reporter and review give same id`() {
        val first = ReviewReport.of(review(), "u1", ReviewReportReason.SPAM, now)
        val second = ReviewReport.of(review(), "u1", ReviewReportReason.OFFENSIVE, now)
        assertEquals(first.id, second.id)
    }

    @Test fun `different reporters give different ids`() {
        val a = ReviewReport.of(review(), "u1", ReviewReportReason.SPAM, now)
        val b = ReviewReport.of(review(), "u2", ReviewReportReason.SPAM, now)
        assertNotEquals(a.id, b.id)
    }

    @Test fun `report carries venue so moderator sees context`() {
        val r = ReviewReport.of(review(venueID = "navat"), "u1", ReviewReportReason.FAKE, now)
        assertEquals("navat", r.venueID)
        assertEquals("rv1", r.reviewID)
        assertEquals("fake", r.reason.slug)
        assertEquals(now, r.createdAt)
    }

    /** Причины ходят в Firestore слагами — переименование сломало бы админку. */
    @Test fun `reason slugs are stable`() {
        assertEquals(listOf("fake", "spam", "offensive"), ReviewReportReason.entries.map { it.slug })
    }
}
