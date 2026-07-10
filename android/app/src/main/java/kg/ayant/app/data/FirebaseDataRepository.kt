package kg.ayant.app.data

import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.tasks.await
import kg.ayant.app.data.model.City
import kg.ayant.app.data.model.Deal
import kg.ayant.app.data.model.DealStatus
import kg.ayant.app.data.model.DealType
import kg.ayant.app.data.model.HostReply
import kg.ayant.app.data.model.ModerationStatus
import kg.ayant.app.data.model.Review
import kg.ayant.app.data.model.Venue
import kg.ayant.app.data.model.VenueCategory
import java.util.Date

/**
 * Reads the same Firestore collections as the iOS app (project san-25d32):
 * `venues`, `deals`, `reviews`. Field names, slug maps and Timestamp handling
 * match FirebaseServices.swift exactly so both platforms read the same docs.
 */
class FirebaseDataRepository : DataRepository {

    private val db = FirebaseFirestore.getInstance()

    override suspend fun fetchVenues(): List<Venue> =
        db.collection("venues").get().await().documents.mapNotNull { it.toVenue() }

    override suspend fun fetchDeals(): List<Deal> =
        db.collection("deals").get().await().documents.mapNotNull { it.toDeal() }

    override suspend fun fetchReviews(): List<Review> =
        db.collection("reviews").get().await().documents.mapNotNull { it.toReview() }

    override suspend fun saveReview(review: Review) {
        db.collection("reviews").document(review.id).set(
            mapOf(
                "venueID" to review.venueID, "authorID" to review.authorID, "authorName" to review.authorName,
                "rating" to review.rating, "text" to review.text,
                "createdAt" to review.createdAt, "updatedAt" to review.updatedAt,
                "itemID" to review.itemID, "itemName" to review.itemName,
            )
        ).await()
    }

    override suspend fun deleteReview(id: String) {
        db.collection("reviews").document(id).delete().await()
    }

    override suspend fun updateReviewReply(reviewID: String, replyText: String?) {
        val doc = db.collection("reviews").document(reviewID)
        if (replyText != null) {
            doc.set(mapOf("hostReply" to mapOf("text" to replyText, "updatedAt" to Date())), com.google.firebase.firestore.SetOptions.merge()).await()
        } else {
            doc.update("hostReply", com.google.firebase.firestore.FieldValue.delete()).await()
        }
    }

    override suspend fun logRedemption(userID: String, dealID: String, venueID: String) {
        db.collection("redemptions").document("${userID}_$dealID").set(
            mapOf("userID" to userID, "dealID" to dealID, "venueID" to venueID, "createdAt" to Date(), "status" to "new"),
            com.google.firebase.firestore.SetOptions.merge(),
        ).await()
    }

    override suspend fun recordReferral(inviteeID: String, referrerID: String) {
        db.collection("referrals").document(inviteeID).set(
            mapOf("inviteeID" to inviteeID, "referrerID" to referrerID, "createdAt" to Date()),
            com.google.firebase.firestore.SetOptions.merge(),
        ).await()
    }

    override suspend fun createGiftCoupon(title: String, code: String, fromName: String) {
        db.collection("giftCoupons").document(code).set(
            mapOf("title" to title, "code" to code, "fromName" to fromName, "claimed" to false, "createdAt" to Date()),
        ).await()
    }

    override suspend fun claimGiftCoupon(code: String): GiftInfo? {
        val ref = db.collection("giftCoupons").document(code)
        val snap = ref.get().await()
        if (!snap.exists() || snap.getBoolean("claimed") == true) return null
        val title = snap.getString("title") ?: return null
        ref.set(mapOf("claimed" to true, "claimedAt" to Date()), com.google.firebase.firestore.SetOptions.merge()).await()
        return GiftInfo(title, code)
    }

    override suspend fun claimBonusGrants(userID: String): Int {
        val snap = db.collection("bonusGrants").whereEqualTo("userID", userID).get().await()
        val unclaimed = snap.documents.filter { it.getBoolean("claimed") != true }
        if (unclaimed.isEmpty()) return 0
        var total = 0
        val batch = db.batch()
        for (doc in unclaimed) {
            total += (doc.getLong("amount") ?: 0).toInt()
            batch.set(doc.reference, mapOf("claimed" to true), com.google.firebase.firestore.SetOptions.merge())
        }
        batch.commit().await()
        return total
    }

    // MARK: - Slug maps (mirror categoryMap / typeMap / statusMap)

    private val categoryMap = mapOf(
        "cafe" to "Кафе", "coffee" to "Кофейня", "fastfood" to "Фастфуд",
        "restaurant" to "Ресторан", "teahouse" to "Чайхана", "bakery" to "Пекарня",
    )
    private val typeMap = mapOf(
        "discount" to DealType.DISCOUNT, "promo" to DealType.PROMO,
        "novelty" to DealType.NOVELTY, "announcement" to DealType.ANNOUNCEMENT,
    )

    // MARK: - Mapping

    private fun DocumentSnapshot.toVenue(): Venue? {
        val name = getString("name") ?: return null
        val catKey = getString("category") ?: "cafe"
        val categoryName = categoryMap[catKey] ?: catKey   // slug → RU, else use as-is
        return Venue(
            id = id, name = name,
            category = VenueCategory(categoryName),
            district = getString("district") ?: "",
            address = getString("address") ?: "",
            phone = getString("phone") ?: "",
            emoji = getString("emoji") ?: "🍽",
            gradient = listOf(0xFFFF5A1FL, 0xFFFF9800L),   // Accent → amber
            imageURL = getString("imageURL"),
            rating = getDouble("rating") ?: 0.0,
            reviewCount = (getLong("reviewCount") ?: 0).toInt(),
            isVerified = getBoolean("isVerified") ?: false,
            savedByCount = (getLong("savedByCount") ?: 0).toInt(),
            citySlug = getString("city") ?: City.BISHKEK.id,
            latitude = getDouble("latitude") ?: City.BISHKEK.latitude,
            longitude = getDouble("longitude") ?: City.BISHKEK.longitude,
            todaySpecialText = getString("todaySpecial")?.takeIf { it.isNotEmpty() },
            openHour = (getLong("openHour") ?: 9).toInt(),
            closeHour = (getLong("closeHour") ?: 22).toInt(),
            pdfMenuURL = getString("pdfMenuURL")?.takeIf { it.isNotEmpty() },
            photoEmojis = (get("photoEmojis") as? List<*>)?.filterIsInstance<String>() ?: emptyList(),
            status = when (getString("status")) {
                "pending" -> ModerationStatus.PENDING
                "rejected" -> ModerationStatus.REJECTED
                else -> ModerationStatus.APPROVED
            },
            isPaused = getBoolean("isPaused") ?: false,
            whatsapp = getString("whatsapp") ?: "",
            instagram = getString("instagram") ?: "",
            telegram = getString("telegram") ?: "",
            weekHours = (get("weekHours") as? List<*>)?.mapNotNull { row ->
                (row as? Map<*, *>)?.let { m ->
                    kg.ayant.app.data.model.DayHours(
                        m["closed"] as? Boolean ?: false,
                        (m["open"] as? Number)?.toInt() ?: 540,
                        (m["close"] as? Number)?.toInt() ?: 1320,
                    )
                }
            } ?: emptyList(),
            branches = (get("branches") as? List<*>)?.mapNotNull { row ->
                (row as? Map<*, *>)?.let { m ->
                    val addr = m["address"] as? String ?: return@mapNotNull null
                    kg.ayant.app.data.model.Branch(
                        m["id"] as? String ?: addr, addr,
                        (m["latitude"] as? Number)?.toDouble() ?: City.BISHKEK.latitude,
                        (m["longitude"] as? Number)?.toDouble() ?: City.BISHKEK.longitude,
                        m["phone"] as? String ?: "",
                    )
                }
            } ?: emptyList(),
            boostedUntil = getDate("boostedUntil"),
            loyaltyEnabled = getBoolean("loyaltyEnabled") ?: false,
            loyaltyGoal = (getLong("loyaltyGoal") ?: 6).toInt(),
            loyaltyReward = getString("loyaltyReward") ?: "Награда за лояльность",
            couponsEnabled = getBoolean("couponsEnabled") ?: true,
        )
    }

    private fun DocumentSnapshot.toDeal(): Deal? {
        val venueID = getString("venueID") ?: return null
        val title = getString("title") ?: return null
        val typeKey = getString("type") ?: "discount"
        return Deal(
            id = id, venueID = venueID,
            type = typeMap[typeKey] ?: DealType.entries.firstOrNull { it.title == typeKey } ?: DealType.DISCOUNT,
            title = title, details = getString("details") ?: "",
            emoji = getString("emoji") ?: "🔥",
            oldPrice = getLong("oldPrice")?.toInt(),
            newPrice = getLong("newPrice")?.toInt(),
            discountPercent = getLong("discountPercent")?.toInt(),
            validUntil = getDate("validUntil") ?: Date(System.currentTimeMillis() + 365L * 86_400_000),
            status = when (getString("status")) {
                "paused" -> DealStatus.PAUSED; "expired" -> DealStatus.EXPIRED; "draft" -> DealStatus.DRAFT
                else -> DealStatus.ACTIVE
            },
            startDate = getDate("startDate"),
            imageURL = getString("imageURL"),
            imageURLs = (get("imageURLs") as? List<*>)?.filterIsInstance<String>() ?: emptyList(),
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun DocumentSnapshot.toReview(): Review? {
        val venueID = getString("venueID") ?: return null
        val reply = (get("hostReply") as? Map<String, Any?>)?.let { m ->
            (m["text"] as? String)?.takeIf { it.isNotEmpty() }?.let { HostReply(it, Date(), Date()) }
        }
        return Review(
            id = id, venueID = venueID,
            authorID = getString("authorID") ?: "",
            authorName = getString("authorName") ?: "Гость",
            rating = (getLong("rating") ?: 5).toInt(),
            text = getString("text") ?: "",
            createdAt = getDate("createdAt") ?: Date(),
            updatedAt = getDate("updatedAt") ?: Date(),
            hostReply = reply,
            itemID = getString("itemID"),
            itemName = getString("itemName"),
            photos = (get("photos") as? List<*>)?.filterIsInstance<String>() ?: emptyList(),
            verifiedVisit = getBoolean("verifiedVisit") ?: false,
        )
    }
}
