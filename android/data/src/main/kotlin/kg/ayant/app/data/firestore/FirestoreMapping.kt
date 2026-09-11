package kg.ayant.app.data.firestore

import com.google.firebase.Timestamp
import com.google.firebase.firestore.DocumentSnapshot
import kg.ayant.app.domain.model.Branch
import kg.ayant.app.domain.model.City
import kg.ayant.app.domain.model.Coupon
import kg.ayant.app.domain.model.DayHours
import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.DealStatus
import kg.ayant.app.domain.model.DealType
import kg.ayant.app.domain.model.HostReply
import kg.ayant.app.domain.model.LoyaltyCard
import kg.ayant.app.domain.model.ModerationStatus
import kg.ayant.app.domain.model.PointsBand
import kg.ayant.app.domain.model.PointsReward
import kg.ayant.app.domain.model.Review
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenueCategory
import kg.ayant.app.domain.model.VenuePointsCard
import java.util.Date

/**
 * Маппинг Firestore ⇄ доменные модели.
 *
 * Весь разбор и сборка документов живёт здесь; репозитории и сервисы только
 * делают запросы и вызывают эти мапперы. Имена полей берутся из [FS] — своих
 * строковых литералов в этом файле нет, поэтому переименование поля правится
 * в одном месте (см. FirestoreSchema.kt).
 *
 * Зеркалит `SAN/Firebase/FirestoreMapping.swift` на iOS.
 */

// ── Venue ────────────────────────────────────────────────────────────────────

fun DocumentSnapshot.toVenue(): Venue? {
    val name = getString(FS.VenueDoc.NAME) ?: return null
    val catKey = getString(FS.VenueDoc.CATEGORY) ?: "cafe"
    val categoryName = FSKeys.category[catKey] ?: catKey   // slug → RU, else use as-is
    return Venue(
        id = id, name = name,
        category = VenueCategory(categoryName),
        district = getString(FS.VenueDoc.DISTRICT) ?: "",
        address = getString(FS.VenueDoc.ADDRESS) ?: "",
        phone = getString(FS.VenueDoc.PHONE) ?: "",
        emoji = getString(FS.VenueDoc.EMOJI) ?: "🍽",
        gradient = listOf(0xFFFF5A1FL, 0xFFFF9800L),   // Accent → amber
        imageURL = getString(FS.VenueDoc.IMAGE_URL),
        rating = getDouble(FS.VenueDoc.RATING) ?: 0.0,
        reviewCount = (getLong(FS.VenueDoc.REVIEW_COUNT) ?: 0).toInt(),
        isVerified = getBoolean(FS.VenueDoc.IS_VERIFIED) ?: false,
        savedByCount = (getLong(FS.VenueDoc.SAVED_BY_COUNT) ?: 0).toInt(),
        citySlug = getString(FS.VenueDoc.CITY) ?: City.BISHKEK.id,
        latitude = getDouble(FS.VenueDoc.LATITUDE) ?: City.BISHKEK.latitude,
        longitude = getDouble(FS.VenueDoc.LONGITUDE) ?: City.BISHKEK.longitude,
        todaySpecialText = getString(FS.VenueDoc.TODAY_SPECIAL)?.takeIf { it.isNotEmpty() },
        openHour = (getLong(FS.VenueDoc.OPEN_HOUR) ?: 9).toInt(),
        closeHour = (getLong(FS.VenueDoc.CLOSE_HOUR) ?: 22).toInt(),
        pdfMenuURL = getString(FS.VenueDoc.PDF_MENU_URL)?.takeIf { it.isNotEmpty() },
        photoEmojis = stringList(FS.VenueDoc.PHOTO_EMOJIS),
        status = when (getString(FS.VenueDoc.STATUS)) {
            FSKeys.MODERATION_PENDING -> ModerationStatus.PENDING
            FSKeys.MODERATION_REJECTED -> ModerationStatus.REJECTED
            else -> ModerationStatus.APPROVED
        },
        isPaused = getBoolean(FS.VenueDoc.IS_PAUSED) ?: false,
        whatsapp = getString(FS.VenueDoc.WHATSAPP) ?: "",
        instagram = getString(FS.VenueDoc.INSTAGRAM) ?: "",
        telegram = getString(FS.VenueDoc.TELEGRAM) ?: "",
        weekHours = maps(FS.VenueDoc.WEEK_HOURS).map { it.toDayHours() },
        branches = maps(FS.VenueDoc.BRANCHES).mapNotNull { it.toBranch() },
        boostedUntil = getDate(FS.VenueDoc.BOOSTED_UNTIL),
        loyaltyEnabled = getBoolean(FS.VenueDoc.LOYALTY_ENABLED) ?: false,
        loyaltyGoal = (getLong(FS.VenueDoc.LOYALTY_GOAL) ?: 6).toInt(),
        loyaltyReward = getString(FS.VenueDoc.LOYALTY_REWARD) ?: "Награда за лояльность",
        couponsEnabled = getBoolean(FS.VenueDoc.COUPONS_ENABLED) ?: true,
        pointsEnabled = getBoolean(FS.VenueDoc.POINTS_ENABLED) ?: false,
        pointsMode = getString(FS.VenueDoc.POINTS_MODE) ?: "flat",
        pointsFlat = (getLong(FS.VenueDoc.POINTS_FLAT) ?: 0).toInt(),
        pointsBands = maps(FS.VenueDoc.POINTS_BANDS).mapNotNull { it.toPointsBand() },
        cashbackPercent = getDouble(FS.VenueDoc.CASHBACK_PERCENT) ?: 0.0,
        pointsRewards = maps(FS.VenueDoc.POINTS_REWARDS).mapNotNull { it.toPointsReward() },
        pointsExpiryMonths = (getLong(FS.VenueDoc.POINTS_EXPIRY_MONTHS) ?: 6).toInt(),
        redeemMode = getString(FS.VenueDoc.REDEEM_MODE) ?: "staffScan",
        earnCooldownMinutes = (getLong(FS.VenueDoc.EARN_COOLDOWN_MINUTES) ?: 60).toInt(),
    )
}

// ── Вложенные объекты заведения ──────────────────────────────────────────────

private fun Map<*, *>.toDayHours() = DayHours(
    bool(FS.DayHoursField.CLOSED) ?: false,
    int(FS.DayHoursField.OPEN) ?: 540,
    int(FS.DayHoursField.CLOSE) ?: 1320,
)

private fun Map<*, *>.toBranch(): Branch? {
    val address = str(FS.BranchField.ADDRESS) ?: return null
    return Branch(
        str(FS.BranchField.ID) ?: address,
        address,
        double(FS.BranchField.LATITUDE) ?: City.BISHKEK.latitude,
        double(FS.BranchField.LONGITUDE) ?: City.BISHKEK.longitude,
        str(FS.BranchField.PHONE) ?: "",
    )
}

private fun Map<*, *>.toPointsBand(): PointsBand? {
    val points = int(FS.PointsBandField.POINTS) ?: return null
    return PointsBand(int(FS.PointsBandField.MAX_AMOUNT) ?: 0, points)
}

private fun Map<*, *>.toPointsReward(): PointsReward? {
    val id = str(FS.PointsRewardField.ID) ?: return null
    val title = str(FS.PointsRewardField.TITLE) ?: return null
    return PointsReward(
        id,
        str(FS.PointsRewardField.TYPE) ?: "item",
        title,
        int(FS.PointsRewardField.COST) ?: 0,
        double(FS.PointsRewardField.RATIO) ?: 1.0,
        bool(FS.PointsRewardField.ACTIVE) ?: true,
    )
}

// ── Deal ─────────────────────────────────────────────────────────────────────

fun DocumentSnapshot.toDeal(): Deal? {
    val venueID = getString(FS.DealDoc.VENUE_ID) ?: return null
    val title = getString(FS.DealDoc.TITLE) ?: return null
    val typeKey = getString(FS.DealDoc.TYPE) ?: FSKeys.DEAL_TYPE_DISCOUNT
    return Deal(
        id = id, venueID = venueID,
        type = dealType(typeKey),
        title = title, details = getString(FS.DealDoc.DETAILS) ?: "",
        emoji = getString(FS.DealDoc.EMOJI) ?: "🔥",
        oldPrice = getLong(FS.DealDoc.OLD_PRICE)?.toInt(),
        newPrice = getLong(FS.DealDoc.NEW_PRICE)?.toInt(),
        discountPercent = getLong(FS.DealDoc.DISCOUNT_PERCENT)?.toInt(),
        validUntil = getDate(FS.DealDoc.VALID_UNTIL)
            ?: Date(System.currentTimeMillis() + 365L * 86_400_000),
        status = when (getString(FS.DealDoc.STATUS)) {
            FSKeys.DEAL_STATUS_PAUSED -> DealStatus.PAUSED
            FSKeys.DEAL_STATUS_EXPIRED -> DealStatus.EXPIRED
            FSKeys.DEAL_STATUS_DRAFT -> DealStatus.DRAFT
            else -> DealStatus.ACTIVE
        },
        citySlug = getString(FS.DealDoc.CITY) ?: City.BISHKEK.id,
        startDate = getDate(FS.DealDoc.START_DATE),
        imageURL = getString(FS.DealDoc.IMAGE_URL),
        imageURLs = stringList(FS.DealDoc.IMAGE_URLS),
        terms = stringList(FS.DealDoc.TERMS),
    )
}

/** Слаг типа акции → enum; неизвестный слаг пробуем как отображаемое имя. */
private fun dealType(key: String): DealType = when (key) {
    FSKeys.DEAL_TYPE_DISCOUNT -> DealType.DISCOUNT
    FSKeys.DEAL_TYPE_PROMO -> DealType.PROMO
    FSKeys.DEAL_TYPE_NOVELTY -> DealType.NOVELTY
    FSKeys.DEAL_TYPE_ANNOUNCEMENT -> DealType.ANNOUNCEMENT
    else -> DealType.entries.firstOrNull { it.title == key } ?: DealType.DISCOUNT
}

// ── Review ───────────────────────────────────────────────────────────────────

fun DocumentSnapshot.toReview(): Review? {
    val venueID = getString(FS.ReviewDoc.VENUE_ID) ?: return null
    return Review(
        id = id, venueID = venueID,
        authorID = getString(FS.ReviewDoc.AUTHOR_ID) ?: "",
        authorName = getString(FS.ReviewDoc.AUTHOR_NAME) ?: "Гость",
        rating = (getLong(FS.ReviewDoc.RATING) ?: 5).toInt(),
        text = getString(FS.ReviewDoc.TEXT) ?: "",
        createdAt = getDate(FS.ReviewDoc.CREATED_AT) ?: Date(),
        updatedAt = getDate(FS.ReviewDoc.UPDATED_AT) ?: Date(),
        hostReply = (get(FS.ReviewDoc.HOST_REPLY) as? Map<*, *>)?.toHostReply(),
        itemID = getString(FS.ReviewDoc.ITEM_ID),
        itemName = getString(FS.ReviewDoc.ITEM_NAME),
        photos = stringList(FS.ReviewDoc.PHOTOS),
        verifiedVisit = getBoolean(FS.ReviewDoc.VERIFIED_VISIT) ?: false,
        citySlug = getString(FS.ReviewDoc.CITY) ?: City.BISHKEK.id,
    )
}

private fun Map<*, *>.toHostReply(): HostReply? {
    val text = str(FS.HostReplyField.TEXT)?.takeIf { it.isNotEmpty() } ?: return null
    val created = (this[FS.HostReplyField.CREATED_AT] as? Timestamp)?.toDate() ?: Date()
    val updated = (this[FS.HostReplyField.UPDATED_AT] as? Timestamp)?.toDate() ?: created
    return HostReply(text, created, updated)
}

/** Документ отзыва для записи (поля, которые ведёт клиент). */
fun Review.toFirestoreMap(): Map<String, Any?> = mapOf(
    FS.ReviewDoc.VENUE_ID to venueID,
    FS.ReviewDoc.AUTHOR_ID to authorID,
    FS.ReviewDoc.AUTHOR_NAME to authorName,
    FS.ReviewDoc.RATING to rating,
    FS.ReviewDoc.TEXT to text,
    FS.ReviewDoc.CREATED_AT to createdAt,
    FS.ReviewDoc.UPDATED_AT to updatedAt,
    FS.ReviewDoc.ITEM_ID to itemID,
    FS.ReviewDoc.ITEM_NAME to itemName,
    FS.ReviewDoc.CITY to citySlug,
)

/** Вложенная карта `hostReply`. `createdAt` сохраняем исходный, если он был. */
fun hostReplyMap(text: String, createdAt: Any?): Map<String, Any?> = mapOf(
    FS.HostReplyField.TEXT to text,
    FS.HostReplyField.CREATED_AT to (createdAt ?: Date()),
    FS.HostReplyField.UPDATED_AT to Date(),
)

// ── Кошельки гостя ───────────────────────────────────────────────────────────

fun Coupon.toFirestoreMap(userID: String): Map<String, Any?> = mapOf(
    FS.CouponDoc.CODE to code,
    FS.CouponDoc.USER_ID to userID,
    FS.CouponDoc.VENUE_ID to venueID,
    FS.CouponDoc.VENUE_NAME to venueName,
    FS.CouponDoc.TITLE to title,
    FS.CouponDoc.KIND to kind,
    FS.CouponDoc.DEAL_ID to dealID,
    FS.CouponDoc.USED to used,
    FS.CouponDoc.CREATED_AT to createdAt,
)

fun DocumentSnapshot.toCoupon() = Coupon(
    id = id,
    title = getString(FS.CouponDoc.TITLE) ?: "Купон",
    code = getString(FS.CouponDoc.CODE) ?: "",
    createdAt = getDate(FS.CouponDoc.CREATED_AT) ?: Date(),
    used = getBoolean(FS.CouponDoc.USED) ?: false,
    venueID = getString(FS.CouponDoc.VENUE_ID) ?: "",
    venueName = getString(FS.CouponDoc.VENUE_NAME) ?: "",
    kind = getString(FS.CouponDoc.KIND) ?: "bonus",
    dealID = getString(FS.CouponDoc.DEAL_ID) ?: "",
)

fun DocumentSnapshot.toLoyaltyCard() = LoyaltyCard(
    venueID = getString(FS.LoyaltyCardDoc.VENUE_ID) ?: "",
    venueName = getString(FS.LoyaltyCardDoc.VENUE_NAME) ?: "",
    stamps = (getLong(FS.LoyaltyCardDoc.STAMPS) ?: 0).toInt(),
    completedRounds = (getLong(FS.LoyaltyCardDoc.COMPLETED_ROUNDS) ?: 0).toInt(),
    goal = (getLong(FS.LoyaltyCardDoc.GOAL) ?: 6).toInt(),
    reward = getString(FS.LoyaltyCardDoc.REWARD) ?: "Награда за лояльность",
)

fun DocumentSnapshot.toVenuePointsCard() = VenuePointsCard(
    venueID = getString(FS.VenuePointsDoc.VENUE_ID) ?: "",
    venueName = getString(FS.VenuePointsDoc.VENUE_NAME) ?: "",
    balance = (getLong(FS.VenuePointsDoc.BALANCE) ?: 0).toInt(),
    lifetimeEarned = (getLong(FS.VenuePointsDoc.LIFETIME_EARNED) ?: 0).toInt(),
    lifetimeRedeemed = (getLong(FS.VenuePointsDoc.LIFETIME_REDEEMED) ?: 0).toInt(),
)

// ── Типизированное чтение ────────────────────────────────────────────────────
//
// Firestore отдаёт вложенные объекты как `Map<*, *>` с `Any?`-значениями,
// поэтому каждое чтение — приведение типа. Здесь оно сделано один раз, а вызов
// читается как объявление типа поля.

private fun Map<*, *>.str(key: String): String? = this[key] as? String
private fun Map<*, *>.bool(key: String): Boolean? = this[key] as? Boolean
private fun Map<*, *>.int(key: String): Int? = (this[key] as? Number)?.toInt()
private fun Map<*, *>.double(key: String): Double? = (this[key] as? Number)?.toDouble()

private fun DocumentSnapshot.stringList(key: String): List<String> =
    (get(key) as? List<*>)?.filterIsInstance<String>() ?: emptyList()

private fun DocumentSnapshot.maps(key: String): List<Map<*, *>> =
    (get(key) as? List<*>)?.filterIsInstance<Map<*, *>>() ?: emptyList()
