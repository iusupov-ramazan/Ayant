package kg.ayant.app.domain

import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.Review
import kg.ayant.app.domain.model.Venue

/**
 * Контракт источника каталога — заведения, акции, отзывы.
 *
 * Живёт в `:domain`, реализации — в `:app` (`MockDataRepository` на локальных
 * данных, `FirebaseDataRepository` на Firestore). Так зависимость направлена
 * внутрь: домен знает, ЧТО ему нужно, и ничего не знает о Firebase.
 *
 * Зеркалит `DataRepository.swift` на iOS.
 */
interface DataRepository {
    suspend fun fetchVenues(): List<Venue>
    suspend fun fetchDeals(): List<Deal>

    // --- Отзывы: только ограниченные выборки ---------------------------------
    //
    // Раньше здесь был `fetchReviews()` без аргументов: он выгружал ВСЮ коллекцию
    // на каждом холодном старте, и на каталоге в 1000 бизнесов это была главная
    // статья расходов Firestore (см. docs/design/system-design.md §2, B2).
    // Метода «дай все отзывы» больше нет намеренно. Рейтинг для ленты приходит
    // готовым на документе заведения (его считает Cloud Function
    // `aggregateReviewRating`), а сами отзывы грузятся тремя выборками ниже.

    /** Отзывы одного заведения, свежие сверху. Для карточки заведения. */
    suspend fun fetchReviews(venueID: String, limit: Int): List<Review>
    /** Отзывы группы заведений — инбокс владельца. */
    suspend fun fetchReviews(venueIDs: List<String>, limit: Int): List<Review>
    /** Отзывы, написанные пользователем. Для профиля. */
    suspend fun fetchReviewsByAuthor(authorID: String, limit: Int): List<Review>
    suspend fun saveReview(review: Review)
    suspend fun deleteReview(id: String)
    /** Owner reply on a review (visible to all). null clears it. */
    suspend fun updateReviewReply(reviewID: String, replyText: String?)
    /** Redemption log (server counter + anti-abuse). Deterministic id. */
    suspend fun logRedemption(userID: String, dealID: String, venueID: String)
    /** Referral: inviter → invitee. */
    suspend fun recordReferral(inviteeID: String, referrerID: String)
    /** Create a gift coupon (giftCoupons/{code}). */
    suspend fun createGiftCoupon(title: String, code: String, fromName: String)
    /** Claim a gift once; null if already claimed or missing. */
    suspend fun claimGiftCoupon(code: String): GiftInfo?
    /** Claim server-granted bonuses (referral rewards); returns total. */
    suspend fun claimBonusGrants(userID: String): Int
    /** Published ranking weights (config/rankingWeights); null → RankingWeights.DEFAULT.
     *  Keys match the trainer output (W_RATING, …). See ml/README.md. Only
     *  FirebaseDataRepository overrides this; others keep the default weights. */
    suspend fun fetchRankingWeights(): Map<String, Double>? = null
}

/** Data claimed from a gift-coupon link. */
data class GiftInfo(val title: String, val code: String)
