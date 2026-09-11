package kg.ayant.app.data

import kg.ayant.app.domain.DataRepository
import kg.ayant.app.domain.GiftInfo
import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.Review
import kg.ayant.app.domain.model.Venue

import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.SetOptions
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kg.ayant.app.data.firestore.FS
import kg.ayant.app.data.firestore.hostReplyMap
import kg.ayant.app.data.firestore.toDeal
import kg.ayant.app.data.firestore.toFirestoreMap
import kg.ayant.app.data.firestore.toReview
import kg.ayant.app.data.firestore.toVenue
import kotlinx.coroutines.tasks.await
import java.util.Date

/**
 * Reads the same Firestore collections as the iOS app (project san-25d32):
 * `venues`, `deals`, `reviews`. Field names, slug maps and Timestamp handling
 * match FirebaseServices.swift exactly so both platforms read the same docs.
 */
class FirebaseDataRepository : DataRepository {

    private val db = FirebaseFirestore.getInstance()

    override suspend fun fetchVenues(): List<Venue> =
        db.collection(FS.Collection.VENUES).get().await().documents.mapNotNull { it.toVenue() }

    override suspend fun fetchDeals(): List<Deal> =
        db.collection(FS.Collection.DEALS).get().await().documents.mapNotNull { it.toDeal() }

    /**
     * Отзывы одного заведения. Индекс: reviews (venueID ASC, createdAt DESC)
     * — он объявлен в firestore.indexes.json, без него запрос падает в проде.
     */
    override suspend fun fetchReviews(venueID: String, limit: Int): List<Review> =
        db.collection(FS.Collection.REVIEWS)
            .whereEqualTo(FS.ReviewDoc.VENUE_ID, venueID)
            .orderBy(FS.ReviewDoc.CREATED_AT, Query.Direction.DESCENDING)
            .limit(limit.toLong())
            .get().await().documents.mapNotNull { it.toReview() }

    /**
     * Инбокс владельца. `whereIn` у Firestore ограничен 30 значениями, поэтому
     * список заведений режем на куски и запрашиваем их параллельно.
     */
    override suspend fun fetchReviews(venueIDs: List<String>, limit: Int): List<Review> {
        if (venueIDs.isEmpty()) return emptyList()
        val collected = coroutineScope {
            venueIDs.chunked(WHERE_IN_LIMIT).map { chunk ->
                async {
                    db.collection(FS.Collection.REVIEWS)
                        .whereIn(FS.ReviewDoc.VENUE_ID, chunk)
                        .orderBy(FS.ReviewDoc.CREATED_AT, Query.Direction.DESCENDING)
                        .limit(limit.toLong())
                        .get().await().documents.mapNotNull { it.toReview() }
                }
            }.awaitAll().flatten()
        }
        // Каждый кусок вернул свои `limit` — общий срез делаем после слияния.
        return collected.sortedByDescending { it.createdAt }.take(limit)
    }

    /** Отзывы пользователя. Одиночное равенство — хватает автоиндекса по полю. */
    override suspend fun fetchReviewsByAuthor(authorID: String, limit: Int): List<Review> =
        db.collection(FS.Collection.REVIEWS)
            .whereEqualTo(FS.ReviewDoc.AUTHOR_ID, authorID)
            .limit(limit.toLong())
            .get().await().documents.mapNotNull { it.toReview() }
            .sortedByDescending { it.updatedAt }

    override suspend fun saveReview(review: Review) {
        db.collection(FS.Collection.REVIEWS).document(review.id)
            .set(review.toFirestoreMap()).await()
    }

    override suspend fun deleteReview(id: String) {
        db.collection(FS.Collection.REVIEWS).document(id).delete().await()
    }

    override suspend fun updateReviewReply(reviewID: String, replyText: String?) {
        val doc = db.collection(FS.Collection.REVIEWS).document(reviewID)
        if (replyText != null) {
            // Сохраняем исходное время создания ответа, обновляем только updatedAt.
            val existing = doc.get().await().get(FS.ReviewDoc.HOST_REPLY) as? Map<*, *>
            doc.set(
                mapOf(FS.ReviewDoc.HOST_REPLY to hostReplyMap(replyText, existing?.get(FS.HostReplyField.CREATED_AT))),
                SetOptions.merge(),
            ).await()
        } else {
            doc.update(FS.ReviewDoc.HOST_REPLY, FieldValue.delete()).await()
        }
    }

    override suspend fun logRedemption(userID: String, dealID: String, venueID: String) {
        db.collection(FS.Collection.REDEMPTIONS).document("${userID}_$dealID").set(
            mapOf(
                FS.RedemptionDoc.USER_ID to userID,
                FS.RedemptionDoc.DEAL_ID to dealID,
                FS.RedemptionDoc.VENUE_ID to venueID,
                FS.RedemptionDoc.CREATED_AT to Date(),
                FS.RedemptionDoc.STATUS to FS.RedemptionDoc.STATUS_NEW,
            ),
            SetOptions.merge(),
        ).await()
    }

    override suspend fun recordReferral(inviteeID: String, referrerID: String) {
        db.collection(FS.Collection.REFERRALS).document(inviteeID).set(
            mapOf(
                FS.ReferralDoc.INVITEE_ID to inviteeID,
                FS.ReferralDoc.REFERRER_ID to referrerID,
                FS.ReferralDoc.CREATED_AT to Date(),
            ),
            SetOptions.merge(),
        ).await()
    }

    override suspend fun createGiftCoupon(title: String, code: String, fromName: String) {
        db.collection(FS.Collection.GIFT_COUPONS).document(code).set(
            mapOf(
                FS.GiftCouponDoc.TITLE to title,
                FS.GiftCouponDoc.CODE to code,
                FS.GiftCouponDoc.FROM_NAME to fromName,
                FS.GiftCouponDoc.CLAIMED to false,
                FS.GiftCouponDoc.CREATED_AT to Date(),
            ),
        ).await()
    }

    override suspend fun claimGiftCoupon(code: String): GiftInfo? {
        val ref = db.collection(FS.Collection.GIFT_COUPONS).document(code)
        val snap = ref.get().await()
        if (!snap.exists() || snap.getBoolean(FS.GiftCouponDoc.CLAIMED) == true) return null
        val title = snap.getString(FS.GiftCouponDoc.TITLE) ?: return null
        ref.set(
            mapOf(FS.GiftCouponDoc.CLAIMED to true, FS.GiftCouponDoc.CLAIMED_AT to Date()),
            SetOptions.merge(),
        ).await()
        return GiftInfo(title, code)
    }

    override suspend fun claimBonusGrants(userID: String): Int {
        val snap = db.collection(FS.Collection.BONUS_GRANTS)
            .whereEqualTo(FS.BonusGrantDoc.USER_ID, userID).get().await()
        val unclaimed = snap.documents.filter { it.getBoolean(FS.BonusGrantDoc.CLAIMED) != true }
        if (unclaimed.isEmpty()) return 0
        var total = 0
        val batch = db.batch()
        for (doc in unclaimed) {
            total += (doc.getLong(FS.BonusGrantDoc.AMOUNT) ?: 0).toInt()
            batch.set(doc.reference, mapOf(FS.BonusGrantDoc.CLAIMED to true), SetOptions.merge())
        }
        batch.commit().await()
        return total
    }

    /** Published ranking weights from config/rankingWeights (map W_*→number). Missing
     *  doc/fields → null → client stays on RankingWeights.DEFAULT. Mirrors iOS. */
    override suspend fun fetchRankingWeights(): Map<String, Double>? {
        val snap = db.collection(FS.Collection.CONFIG)
            .document(FS.Document.RANKING_WEIGHTS).get().await()
        if (!snap.exists()) return null
        val out = HashMap<String, Double>()
        for ((k, v) in snap.data ?: emptyMap()) {
            (v as? Number)?.let { out[k] = it.toDouble() }
        }
        return out.ifEmpty { null }
    }

    private companion object {
        /** Потолок значений в `whereIn` у Firestore. */
        const val WHERE_IN_LIMIT = 30
    }
}
