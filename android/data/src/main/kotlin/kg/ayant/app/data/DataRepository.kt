package kg.ayant.app.data
import kg.ayant.app.domain.MockData

import kg.ayant.app.domain.DataRepository
import kg.ayant.app.domain.GiftInfo
import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.Review
import kg.ayant.app.domain.model.Venue

/**
 * Оффлайн-реализация [DataRepository] на bundled-данных ([MockData]).
 *
 * Сам контракт живёт в `:domain` — сюда он приходит как зависимость, а не наоборот.
 * Вторая реализация — [FirebaseDataRepository]; переключает их `AppConfig`.
 */
class MockDataRepository : DataRepository {
    override suspend fun fetchVenues(): List<Venue> = MockData.venues
    override suspend fun fetchDeals(): List<Deal> = MockData.deals
    // Mock работает на полном локальном наборе — фильтруем его в памяти,
    // но форму запроса повторяем 1:1, чтобы офлайн-режим вёл себя как боевой.
    override suspend fun fetchReviews(venueID: String, limit: Int): List<Review> =
        MockData.reviews.filter { it.venueID == venueID }
            .sortedByDescending { it.createdAt }.take(limit)

    override suspend fun fetchReviews(venueIDs: List<String>, limit: Int): List<Review> {
        val ids = venueIDs.toSet()
        return MockData.reviews.filter { it.venueID in ids }
            .sortedByDescending { it.createdAt }.take(limit)
    }

    override suspend fun fetchReviewsByAuthor(authorID: String, limit: Int): List<Review> =
        MockData.reviews.filter { it.authorID == authorID }
            .sortedByDescending { it.updatedAt }.take(limit)
    override suspend fun saveReview(review: Review) {}
    override suspend fun deleteReview(id: String) {}
    override suspend fun updateReviewReply(reviewID: String, replyText: String?) {}
    override suspend fun logRedemption(userID: String, dealID: String, venueID: String) {}
    override suspend fun recordReferral(inviteeID: String, referrerID: String) {}
    override suspend fun createGiftCoupon(title: String, code: String, fromName: String) {}
    override suspend fun claimGiftCoupon(code: String): GiftInfo? = null
    override suspend fun claimBonusGrants(userID: String): Int = 0
}
