package kg.ayant.app.domain

import kg.ayant.app.domain.model.City
import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.DealType
import kg.ayant.app.domain.model.ModerationStatus
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenueCategory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Date

/**
 * Тесты сборки ленты. Зеркалят `DomainFeedBuilderTests.swift`.
 *
 * Смысл именно в том, что `nowMs` — параметр: раньше эта логика жила в
 * `AppViewModel`, звала `Date()` внутри и проверялась только глазами.
 */
class FeedBuilderTest {

    private val now = 1_700_000_000_000L

    private fun venue(
        id: String,
        city: String = City.BISHKEK.id,
        paused: Boolean = false,
        status: ModerationStatus = ModerationStatus.APPROVED,
        boosted: Date? = null,
        rating: Double = 4.5,
        reviews: Int = 100,
        category: VenueCategory = VenueCategory.CAFE,
    ) = Venue(
        id = id, name = id, category = category, district = "Центр", address = "ул. 1",
        phone = "", emoji = "🍽", gradient = listOf(0xFFFF5A1FL),
        rating = rating, reviewCount = reviews, citySlug = city,
        status = status, isPaused = paused, boostedUntil = boosted,
    )

    private fun deal(id: String, venueID: String, untilMs: Long = 86_400_000L) = Deal(
        id = id, venueID = venueID, type = DealType.DISCOUNT, title = id, details = "",
        emoji = "🔥", validUntil = Date(now + untilMs),
    )

    // ── Видимость ────────────────────────────────────────────────────────────

    @Test
    fun `hides paused, unapproved and other cities`() {
        val catalog = FeedCatalog(
            venues = listOf(
                venue("ok"),
                venue("paused", paused = true),
                venue("pending", status = ModerationStatus.PENDING),
                venue("almaty", city = "almaty"),
            )
        )
        assertEquals(
            listOf("ok"),
            FeedBuilder.visibleVenues(catalog, City.BISHKEK.id).map { it.id },
        )
    }

    @Test
    fun `category filter narrows venues`() {
        val catalog = FeedCatalog(
            venues = listOf(venue("cafe"), venue("bakery", category = VenueCategory.BAKERY))
        )
        assertEquals(
            listOf("bakery"),
            FeedBuilder.visibleVenues(catalog, City.BISHKEK.id, VenueCategory.BAKERY).map { it.id },
        )
    }

    // ── Выдача ───────────────────────────────────────────────────────────────

    @Test
    fun `only active deals of visible venues reach the feed`() {
        val catalog = FeedCatalog(
            venues = listOf(venue("a"), venue("paused", paused = true)),
            deals = listOf(
                deal("live", "a"),
                deal("expired", "a", untilMs = -3_600_000L),   // уже кончилась
                deal("hidden", "paused"),
            ),
        )
        assertEquals(
            listOf("live"),
            FeedBuilder.rankedDeals(catalog, City.BISHKEK.id,
                weights = RankingWeights.DEFAULT, nowMs = now).map { it.id },
        )
    }

    @Test
    fun `review aggregate overrides seed rating in score`() {
        val v = venue("a", rating = 3.0, reviews = 10)
        val seedOnly = FeedCatalog(venues = listOf(v))
        val withReviews = FeedCatalog(
            venues = listOf(v),
            ratings = mapOf("a" to VenueRating(5.0, 400)),
        )
        assertTrue(
            FeedBuilder.venueScore(v, withReviews, RankingWeights.DEFAULT, now) >
                FeedBuilder.venueScore(v, seedOnly, RankingWeights.DEFAULT, now)
        )
    }

    @Test
    fun `boosted venues become ad cards`() {
        val boostedUntil = Date(now + 86_400_000L)
        val catalog = FeedCatalog(
            venues = listOf(venue("a"), venue("ad1", boosted = boostedUntil),
                venue("ad2", boosted = boostedUntil)),
            deals = listOf(deal("d", "a")),
        )
        val ads = FeedBuilder.boostedVenues(catalog, City.BISHKEK.id, nowMs = now).map { it.id }
        assertEquals(setOf("ad1", "ad2"), ads.toSet())
    }

    @Test
    fun `feed is deterministic for a fixed now`() {
        val catalog = FeedCatalog(
            venues = listOf(venue("a"), venue("b")),
            deals = listOf(deal("d1", "a"), deal("d2", "b")),
        )
        val first = FeedBuilder.items(catalog, City.BISHKEK.id,
            weights = RankingWeights.DEFAULT, nowMs = now)
        val second = FeedBuilder.items(catalog, City.BISHKEK.id,
            weights = RankingWeights.DEFAULT, nowMs = now)
        assertEquals(first.map { it.id }, second.map { it.id })
    }

    // ── Состояние ────────────────────────────────────────────────────────────

    @Test
    fun `state derives feed and distinguishes empty city from empty category`() {
        val catalog = FeedCatalog(venues = listOf(venue("a")), deals = listOf(deal("d", "a")))
        var state = FeedState(catalog = LoadState.Loaded(catalog))
        assertTrue(state.hasVenuesInCity)
        assertEquals(1, state.items(now).size)

        state = state.copy(category = VenueCategory.BAKERY)  // город есть, категории — нет
        assertTrue(state.hasVenuesInCity)
        assertTrue(state.items(now).isEmpty())

        state = state.copy(citySlug = "almaty")               // а тут города нет вовсе
        assertFalse(state.hasVenuesInCity)
    }

    @Test
    fun `idle state yields empty feed rather than crashing`() {
        val state = FeedState()
        assertTrue(state.items(now).isEmpty())
        assertFalse(state.hasVenuesInCity)
    }

    // ── Часовой пояс заведения ───────────────────────────────────────────

    /**
     * Часы работы записаны по времени ГОРОДА. Телефон в другом поясе не должен
     * сдвигать «открыто/закрыто»: раньше считалось по часам устройства, и гость
     * из Москвы видел бишкекское кафе закрытым за три часа до закрытия.
     * Зеркалит `testOpenNowUsesCityTimeZoneNotDeviceTimeZone` на iOS.
     */
    @Test fun `open now uses city time zone not device time zone`() {
        val venue = Venue(
            id = "v", name = "Кафе", category = VenueCategory.CAFE, district = "",
            address = "", phone = "", emoji = "☕️", gradient = listOf(0L),
            openHour = 9, closeHour = 18,
        )
        val bishkek = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("Asia/Bishkek"))

        bishkek.set(2024, 0, 10, 12, 0, 0); bishkek.set(java.util.Calendar.MILLISECOND, 0)
        assertTrue(venue.isOpenAt(bishkek.timeInMillis))

        bishkek.set(2024, 0, 10, 20, 0, 0)
        assertFalse(venue.isOpenAt(bishkek.timeInMillis))
    }

    /** День недели тоже берётся по городу — возле полуночи это заметно. */
    @Test fun `today index uses city time zone`() {
        val bishkek = java.util.Calendar.getInstance(java.util.TimeZone.getTimeZone("Asia/Bishkek"))
        bishkek.set(2024, 0, 8, 0, 30, 0)   // понедельник, 00:30 по Бишкеку
        bishkek.set(java.util.Calendar.MILLISECOND, 0)
        assertEquals(0, Venue.todayIndexAt(bishkek.timeInMillis, City.BISHKEK.id))
    }
}
