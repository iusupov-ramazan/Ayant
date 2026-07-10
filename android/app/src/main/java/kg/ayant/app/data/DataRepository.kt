package kg.ayant.app.data

import kg.ayant.app.data.model.Review
import kg.ayant.app.data.model.Deal
import kg.ayant.app.data.model.Venue

/**
 * Source of venues/deals/reviews. MockDataRepository serves local data;
 * a FirebaseDataRepository (see FirebaseDataRepository.kt) reads the same models
 * from Firestore — the UI does not change. Mirrors DataRepository.swift.
 */
/** Data claimed from a gift-coupon link. */
data class GiftInfo(val title: String, val code: String)

interface DataRepository {
    suspend fun fetchVenues(): List<Venue>
    suspend fun fetchDeals(): List<Deal>
    suspend fun fetchReviews(): List<Review>
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
}

class MockDataRepository : DataRepository {
    override suspend fun fetchVenues(): List<Venue> = MockData.venues
    override suspend fun fetchDeals(): List<Deal> = MockData.deals
    override suspend fun fetchReviews(): List<Review> = MockData.reviews
    override suspend fun saveReview(review: Review) {}
    override suspend fun deleteReview(id: String) {}
    override suspend fun updateReviewReply(reviewID: String, replyText: String?) {}
    override suspend fun logRedemption(userID: String, dealID: String, venueID: String) {}
    override suspend fun recordReferral(inviteeID: String, referrerID: String) {}
    override suspend fun createGiftCoupon(title: String, code: String, fromName: String) {}
    override suspend fun claimGiftCoupon(code: String): GiftInfo? = null
    override suspend fun claimBonusGrants(userID: String): Int = 0
}
