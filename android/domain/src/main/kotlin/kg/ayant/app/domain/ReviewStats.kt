package kg.ayant.app.domain

import kg.ayant.app.domain.model.HostReply
import kg.ayant.app.domain.model.Review
import kg.ayant.app.domain.model.Venue

/**
 * Чистая математика и слияние отзывов, вынесенные из `AppViewModel`.
 *
 * Firebase- и UI-независимо: на вход — уже загруженные модели, на выход — числа
 * или собранный список. I/O (Firestore, SharedPreferences) остаётся во ViewModel.
 * Так агрегаты рейтинга и слияние отзывов тестируются без ViewModel и Compose.
 *
 * Зеркалит `ReviewStats.swift` в AyantDomain.
 */
object ReviewStats {

    /**
     * Агрегированный рейтинг и число отзывов. Пока отзывов нет — фолбэк на seed
     * (значения из документа заведения: `venue.rating` / `venue.reviewCount`).
     */
    fun aggregate(
        reviews: List<Review>,
        fallbackRating: Double,
        fallbackCount: Int,
    ): Pair<Double, Int> {
        if (reviews.isEmpty()) return fallbackRating to fallbackCount
        val avg = reviews.sumOf { it.rating }.toDouble() / reviews.size
        return avg to reviews.size
    }

    /**
     * Агрегаты рейтинга сразу для всего каталога — за один проход по отзывам.
     *
     * Наивный вариант («для каждого заведения отфильтровать все отзывы») —
     * O(заведения × отзывы): на 3000 заведений и 150 000 отзывов это 450 млн
     * сравнений в главном потоке при каждой пересборке каталога. Здесь отзывы
     * раскладываются по `venueID` один раз, дальше каждое заведение читает
     * только свою корзину: O(отзывы + заведения).
     *
     * Результат идентичен поштучному [aggregate], включая фолбэк на seed-значения
     * документа для заведений без отзывов.
     *
     * Зеркалит `ReviewStats.aggregateAll` в AyantDomain 1:1.
     */
    fun aggregateAll(venues: List<Venue>, reviews: List<Review>): Map<String, VenueRating> {
        val byVenue = reviews.groupBy { it.venueID }
        return venues.associate { v ->
            val agg = aggregate(byVenue[v.id].orEmpty(), v.rating, v.reviewCount)
            v.id to VenueRating(agg.first, agg.second)
        }
    }

    /** Разбивка 5★…1★ → количество. Ключи 1…5 всегда присутствуют (в т.ч. нули). */
    fun ratingBreakdown(reviews: List<Review>): Map<Int, Int> {
        val counts = mutableMapOf(1 to 0, 2 to 0, 3 to 0, 4 to 0, 5 to 0)
        for (r in reviews) counts[r.rating] = (counts[r.rating] ?: 0) + 1
        return counts
    }

    /**
     * Объединяет отзывы из репозитория с локальными отзывами пользователя
     * (дедуп по id — база «выигрывает») и накладывает ответы владельца.
     */
    fun merge(
        base: List<Review>,
        userReviews: List<Review>,
        hostReplies: Map<String, HostReply>,
    ): List<Review> {
        val baseIDs = base.map { it.id }.toSet()
        val combined = base + userReviews.filter { it.id !in baseIDs }
        return combined.map { r -> hostReplies[r.id]?.let { r.copy(hostReply = it) } ?: r }
    }
}
