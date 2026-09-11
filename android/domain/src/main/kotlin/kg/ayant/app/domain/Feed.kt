package kg.ayant.app.domain

import kg.ayant.app.domain.model.City
import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.FeedItem
import kg.ayant.app.domain.model.Review
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenueCategory

/*
 * Фича «Лента»: состояние, намерения и ЧИСТАЯ сборка выдачи.
 * Имена полей совпадают с `Feed.swift` в AyantDomain.
 */

/** Агрегат отзывов заведения. Живые отзывы перевешивают seed-значения из документа. */
data class VenueRating(val rating: Double, val count: Int)

/**
 * Снимок каталога, из которого строится лента. Ровно то, что нужно ранжированию,
 * и ничего больше — поэтому сборку можно прогнать в тесте без ViewModel и сети.
 */
data class FeedCatalog(
    val venues: List<Venue> = emptyList(),
    val deals: List<Deal> = emptyList(),
    /** `venueID` → агрегат отзывов. Нет ключа — берём рейтинг из самого заведения. */
    val ratings: Map<String, VenueRating> = emptyMap(),
) {
    companion object { val EMPTY = FeedCatalog() }
}

/**
 * Вся математика выдачи одним чистым объектом.
 *
 * Раньше это жило в `AppViewModel` и звало `Date()`/`Calendar.getInstance()` прямо
 * внутри скоринга — из-за чего лента не проверялась без ViewModel и «сегодня» было
 * невоспроизводимо. Здесь время приходит параметром [nowMs], а данные — снимком
 * [FeedCatalog], поэтому весь порядок выдачи детерминирован.
 */
object FeedBuilder {

    /** Заведения города, видимые пользователю: одобренные модерацией и не на паузе. */
    /**
     * Каталог, видимый пользователю ВНЕ ленты: поиск, карта, избранное, «рядом»
     * на экране QR, переходы по ссылкам.
     *
     * Лента фильтровала модерацию сама, а всё остальное читало сырой каталог —
     * поэтому отклонённое модератором заведение исчезало с главной, но
     * продолжало находиться поиском. Зеркалит `FeedBuilder.userVisible` на iOS.
     */
    fun userVisibleVenues(venues: List<Venue>): List<Venue> =
        venues.filter { it.isApproved && !it.isPaused }

    /**
     * Акции скрытых заведений скрываются вместе с ними. Акция без заведения в
     * каталоге остаётся: это пробел в данных, а не решение модератора.
     */
    fun userVisibleDeals(deals: List<Deal>, venues: List<Venue>): List<Deal> {
        val hidden = venues.filterNot { it.isApproved && !it.isPaused }.map { it.id }.toSet()
        return deals.filterNot { it.venueID in hidden }
    }

    fun visibleVenues(
        catalog: FeedCatalog,
        citySlug: String,
        category: VenueCategory? = null,
    ): List<Venue> = catalog.venues.filter {
        it.citySlug == citySlug && it.isApproved && !it.isPaused &&
            (category == null || it.category == category)
    }

    /** Оценка привлекательности заведения. */
    fun venueScore(
        venue: Venue,
        catalog: FeedCatalog,
        weights: RankingWeights,
        nowMs: Long,
    ): Double {
        val aggregate = catalog.ratings[venue.id] ?: VenueRating(venue.rating, venue.reviewCount)
        val activeDeals = catalog.deals.count { it.venueID == venue.id && it.isActiveAt(nowMs) }
        return Ranking.venueScore(
            rating = aggregate.rating, reviewCount = aggregate.count,
            savedByCount = venue.savedByCount, isVerified = venue.isVerified,
            hasTodaySpecial = venue.hasTodaySpecial, isOpenNow = venue.isOpenAt(nowMs),
            activeDealCount = activeDeals, w = weights,
        )
    }

    /** Органическая оценка предложения. Платный буст — отдельно. */
    fun dealScore(
        deal: Deal,
        catalog: FeedCatalog,
        weights: RankingWeights,
        nowMs: Long,
    ): Double {
        val venue = catalog.venues.firstOrNull { it.id == deal.venueID }
        val vs = venue?.let { venueScore(it, catalog, weights, nowMs) } ?: 0.0
        val daysSinceStart = deal.startDate?.let { (nowMs - it.time) / 86_400_000.0 }
        val hoursUntilExpiry = (deal.validUntil.time - nowMs) / 3_600_000.0
        // Час — по городу акции, а не по телефону: «время завтрака» должно
        // совпадать с местным утром, даже если гость приехал из другого пояса.
        val hour = kg.ayant.app.domain.model.City.calendarForSlug(deal.citySlug)
            .apply { timeInMillis = nowMs }
            .get(java.util.Calendar.HOUR_OF_DAY)
        val timeRelevance = venue?.category?.timeRelevance(hour) ?: 0.5
        return Ranking.dealScore(
            venueScore = vs, isFresh = deal.isFreshAt(nowMs),
            daysSinceStart = daysSinceStart,
            discountPercent = deal.effectiveDiscountPercent,
            hoursUntilExpiry = hoursUntilExpiry,
            timeRelevance = timeRelevance, w = weights,
        )
    }

    /** Заведения города по релевантности. */
    fun rankedVenues(
        catalog: FeedCatalog,
        citySlug: String,
        category: VenueCategory? = null,
        weights: RankingWeights,
        nowMs: Long,
    ): List<Venue> = visibleVenues(catalog, citySlug, category)
        .sortedByDescending { venueScore(it, catalog, weights, nowMs) }

    /** Активные акции заведений города, отсортированные по [dealScore]. */
    fun rankedDeals(
        catalog: FeedCatalog,
        citySlug: String,
        category: VenueCategory? = null,
        weights: RankingWeights,
        nowMs: Long,
    ): List<Deal> {
        val ids = visibleVenues(catalog, citySlug, category).map { it.id }.toSet()
        return catalog.deals
            .filter { it.isActiveAt(nowMs) && it.venueID in ids }
            .sortedByDescending { dealScore(it, catalog, weights, nowMs) }
    }

    /**
     * Заведения с активным платным бустом — рекламные карточки в ленте.
     * Порядок вращается раз в 30 минут, чтобы верхнее место доставалось не всегда одному.
     */
    fun boostedVenues(
        catalog: FeedCatalog,
        citySlug: String,
        category: VenueCategory? = null,
        nowMs: Long,
    ): List<Venue> {
        val rotation = (nowMs / 1_800_000).toInt()
        return visibleVenues(catalog, citySlug, category)
            .filter { it.isBoostedAt(nowMs) }
            .sortedBy { it.id.hashCode() + rotation }
    }

    /** Готовая лента: акции + рекламные карточки, вставленные через интервал. */
    fun items(
        catalog: FeedCatalog,
        citySlug: String,
        category: VenueCategory? = null,
        weights: RankingWeights,
        nowMs: Long,
    ): List<FeedItem> = Ranking.feed(
        deals = rankedDeals(catalog, citySlug, category, weights, nowMs),
        ads = boostedVenues(catalog, citySlug, category, nowMs),
    )
}

/**
 * Всё состояние ленты одним значением.
 *
 * Выдача — не хранимое поле, а функция от состояния ([items]): так она не может
 * разъехаться с каталогом, городом и фильтром.
 */
data class FeedState(
    val catalog: LoadState<FeedCatalog> = LoadState.Idle,
    val citySlug: String = City.BISHKEK.id,
    val category: VenueCategory? = null,
    /** Опубликованные веса ранжирования; при их отсутствии — ручные дефолты. */
    val weights: RankingWeights = RankingWeights.DEFAULT,
    /**
     * Отзывы: база из репозитория плюс локальные пользовательские.
     *
     * Лежат в состоянии, а не отдельным `mutableStateListOf` в ViewModel: их
     * читают карточка заведения, поиск, профиль и хост-кабинет, и всем нужна
     * рекомпозиция при изменении. Раз состояние — одно значение, экран получает
     * свежие отзывы тем же `collectAsState()`, что и остальную ленту.
     */
    val reviews: List<Review> = emptyList(),
) {
    private val loaded: FeedCatalog get() = catalog.valueOrNull() ?: FeedCatalog.EMPTY

    /** Загруженный каталог или пустой — когда экрану нужны сырые списки. */
    val loadedCatalog: FeedCatalog get() = loaded

    fun items(nowMs: Long): List<FeedItem> =
        FeedBuilder.items(loaded, citySlug, category, weights, nowMs)

    fun deals(nowMs: Long): List<Deal> =
        FeedBuilder.rankedDeals(loaded, citySlug, category, weights, nowMs)

    fun venues(nowMs: Long): List<Venue> =
        FeedBuilder.rankedVenues(loaded, citySlug, category, weights, nowMs)

    /** Есть ли в городе вообще заведения — отличает «город пуст» от «нет акций в категории». */
    val hasVenuesInCity: Boolean
        get() = FeedBuilder.visibleVenues(loaded, citySlug).isNotEmpty()

    // ── Отзывы (чистые выборки; раньше жили методами на AppViewModel) ─────────

    /** Отзывы заведения, свежие сверху. */
    fun reviews(forVenue: Venue): List<Review> =
        reviews.filter { it.venueID == forVenue.id }.sortedByDescending { it.createdAt }

    /** Отзывы по набору заведений — хост-кабинету, чтобы считать неотвеченные. */
    fun reviews(forVenueIDs: Set<String>): List<Review> =
        reviews.filter { it.venueID in forVenueIDs }

    /** Мои отзывы, недавно изменённые сверху. */
    fun myReviews(userID: String): List<Review> =
        reviews.filter { it.authorID == userID }.sortedByDescending { it.updatedAt }

    /** Рейтинг заведения: живые отзывы перевешивают seed-значения документа. */
    fun aggregate(venue: Venue): Pair<Double, Int> =
        ReviewStats.aggregate(reviews(forVenue = venue), venue.rating, venue.reviewCount)

    /** Разбивка «сколько каких звёзд» — для гистограммы в карточке. */
    fun ratingBreakdown(venue: Venue): Map<Int, Int> =
        ReviewStats.ratingBreakdown(reviews(forVenue = venue))
}

sealed interface FeedIntent {
    /** Каталог перезагружен владельцем (сейчас — `AppViewModel`). */
    data class SetCatalog(val catalog: FeedCatalog) : FeedIntent
    data object SetLoading : FeedIntent
    data class SetFailure(val error: AppError) : FeedIntent
    data class SetWeights(val weights: RankingWeights) : FeedIntent
    /** Отзывы пересобраны (загрузка, свой отзыв, удаление). */
    data class SetReviews(val reviews: List<Review>) : FeedIntent
    data class SelectCity(val citySlug: String) : FeedIntent
    data class SelectCategory(val category: VenueCategory?) : FeedIntent
}
