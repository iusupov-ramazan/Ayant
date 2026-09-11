package kg.ayant.app.data.firestore

/**
 * **Единственное место, где записаны имена коллекций и полей Firestore.**
 *
 * Раньше каждое имя было строковым литералом и встречалось 2–3 раза: в чтении
 * (`getString("venueName")`), в записи (`"venueName" to …`), иногда ещё в запросе.
 * Переименование поля требовало найти их все — а промах не ломал сборку, он тихо
 * возвращал `null` и подставлял дефолт. Теперь имя объявлено один раз, и опечатка
 * в нём — ошибка компиляции.
 *
 * Важно: одни и те же документы пишут ещё три поверхности — iOS-приложение,
 * Cloud Functions (`functions/src/index.ts`) и админ-панель (`docs/admin/index.html`).
 * Компилятор их не проверяет, поэтому при переименовании поля правьте все четыре.
 *
 * Зеркалит `SAN/Firebase/FirestoreSchema.swift` на iOS 1:1.
 */
object FS {

    // ── Коллекции ────────────────────────────────────────────────────────────

    object Collection {
        const val VENUES = "venues"
        const val DEALS = "deals"
        const val REVIEWS = "reviews"
        const val COUPONS = "coupons"
        const val GIFT_COUPONS = "giftCoupons"
        const val LOYALTY_CARDS = "loyaltyCards"
        const val VENUE_POINTS = "venuePoints"
        const val BONUS_GRANTS = "bonusGrants"
        const val REDEMPTIONS = "redemptions"
        const val REFERRALS = "referrals"
        const val RANKING_EVENTS = "rankingEvents"
        const val ANALYTICS = "analytics"
        const val ANALYTICS_EVENTS = "analyticsEvents"
        const val USER_TOKENS = "userTokens"
        const val PUSH_CAMPAIGNS = "pushCampaigns"
        const val CONFIG = "config"
        /** Подколлекция `analytics/{venueID}/days/{yyyy-MM-dd}`. */
        const val DAYS = "days"
    }

    /** Документы с фиксированным id. */
    object Document {
        const val RANKING_WEIGHTS = "rankingWeights"
    }

    // ── venues/{id} ──────────────────────────────────────────────────────────

    object VenueDoc {
        const val NAME = "name"
        const val CATEGORY = "category"
        const val DISTRICT = "district"
        const val ADDRESS = "address"
        const val PHONE = "phone"
        const val EMOJI = "emoji"
        const val IMAGE_URL = "imageURL"
        const val RATING = "rating"
        const val REVIEW_COUNT = "reviewCount"
        const val IS_VERIFIED = "isVerified"
        const val SAVED_BY_COUNT = "savedByCount"
        /** Слаг города. Внимание: поле называется `city`, а в модели — `citySlug`. */
        const val CITY = "city"
        const val LATITUDE = "latitude"
        const val LONGITUDE = "longitude"
        const val TODAY_SPECIAL = "todaySpecial"
        const val OPEN_HOUR = "openHour"
        const val CLOSE_HOUR = "closeHour"
        const val WEEK_HOURS = "weekHours"
        const val PDF_MENU_URL = "pdfMenuURL"
        const val PHOTO_EMOJIS = "photoEmojis"
        const val OWNER_ID = "ownerID"
        const val STATUS = "status"
        const val IS_PAUSED = "isPaused"
        const val WHATSAPP = "whatsapp"
        const val INSTAGRAM = "instagram"
        const val TELEGRAM = "telegram"
        const val BRANCHES = "branches"
        const val BOOSTED_UNTIL = "boostedUntil"
        // Карта лояльности.
        const val LOYALTY_ENABLED = "loyaltyEnabled"
        const val LOYALTY_GOAL = "loyaltyGoal"
        const val LOYALTY_REWARD = "loyaltyReward"
        const val COUPONS_ENABLED = "couponsEnabled"
        // Баллы САН — эти поля ведёт админ-панель.
        const val POINTS_ENABLED = "pointsEnabled"
        const val POINTS_MODE = "pointsMode"
        const val POINTS_FLAT = "pointsFlat"
        const val POINTS_BANDS = "pointsBands"
        const val CASHBACK_PERCENT = "cashbackPercent"
        const val POINTS_REWARDS = "pointsRewards"
        const val POINTS_EXPIRY_MONTHS = "pointsExpiryMonths"
        const val REDEEM_MODE = "redeemMode"
        const val EARN_COOLDOWN_MINUTES = "earnCooldownMinutes"
    }

    // ── deals/{id} ───────────────────────────────────────────────────────────

    object DealDoc {
        const val VENUE_ID = "venueID"
        const val TYPE = "type"
        const val TITLE = "title"
        const val DETAILS = "details"
        /** Условия акции: массив строк, по строке на пункт. */
        const val TERMS = "terms"
        const val EMOJI = "emoji"
        const val OLD_PRICE = "oldPrice"
        const val NEW_PRICE = "newPrice"
        const val DISCOUNT_PERCENT = "discountPercent"
        const val VALID_UNTIL = "validUntil"
        const val STATUS = "status"
        const val START_DATE = "startDate"
        const val IMAGE_URL = "imageURL"
        const val IMAGE_URLS = "imageURLs"
        /** Ключ партиционирования по городам — то же поле `city`, что у заведения. */
        const val CITY = "city"
    }

    // ── reviews/{id} ─────────────────────────────────────────────────────────

    object ReviewDoc {
        const val VENUE_ID = "venueID"
        const val AUTHOR_ID = "authorID"
        const val AUTHOR_NAME = "authorName"
        const val RATING = "rating"
        const val TEXT = "text"
        const val PHOTOS = "photos"
        const val CREATED_AT = "createdAt"
        const val UPDATED_AT = "updatedAt"
        const val HOST_REPLY = "hostReply"
        const val ITEM_ID = "itemID"
        const val ITEM_NAME = "itemName"
        const val VERIFIED_VISIT = "verifiedVisit"
        /** Ключ партиционирования по городам — то же поле `city`, что у заведения. */
        const val CITY = "city"
    }

    /** Вложенная карта `reviews/{id}.hostReply`. */
    object HostReplyField {
        const val TEXT = "text"
        const val CREATED_AT = "createdAt"
        const val UPDATED_AT = "updatedAt"
    }

    // ── Вложенные объекты внутри venues/{id} ─────────────────────────────────

    /** Элемент массива `branches` (филиал). */
    object BranchField {
        const val ID = "id"
        const val ADDRESS = "address"
        const val LATITUDE = "latitude"
        const val LONGITUDE = "longitude"
        const val PHONE = "phone"
    }

    /** Элемент массива `weekHours` (часы одного дня). */
    object DayHoursField {
        const val CLOSED = "closed"
        const val OPEN = "open"
        const val CLOSE = "close"
    }

    /** Элемент массива `pointsBands` (диапазон чек→баллы). */
    object PointsBandField {
        const val MAX_AMOUNT = "maxAmount"
        const val POINTS = "points"
    }

    /** Элемент массива `pointsRewards` (награда за баллы). */
    object PointsRewardField {
        const val ID = "id"
        const val TYPE = "type"
        const val TITLE = "title"
        const val COST = "cost"
        const val RATIO = "ratio"
        const val ACTIVE = "active"
    }

    // ── Кошельки гостя ───────────────────────────────────────────────────────

    object CouponDoc {
        const val CODE = "code"
        const val USER_ID = "userID"
        const val VENUE_ID = "venueID"
        const val VENUE_NAME = "venueName"
        const val TITLE = "title"
        const val KIND = "kind"
        const val DEAL_ID = "dealID"
        const val USED = "used"
        const val CREATED_AT = "createdAt"
    }

    object LoyaltyCardDoc {
        const val USER_ID = "userID"
        const val VENUE_ID = "venueID"
        const val VENUE_NAME = "venueName"
        const val STAMPS = "stamps"
        const val COMPLETED_ROUNDS = "completedRounds"
        const val GOAL = "goal"
        const val REWARD = "reward"
    }

    object VenuePointsDoc {
        const val USER_ID = "userID"
        const val VENUE_ID = "venueID"
        const val VENUE_NAME = "venueName"
        const val BALANCE = "balance"
        const val LIFETIME_EARNED = "lifetimeEarned"
        const val LIFETIME_REDEEMED = "lifetimeRedeemed"
    }

    object BonusGrantDoc {
        const val USER_ID = "userID"
        const val AMOUNT = "amount"
        const val CLAIMED = "claimed"
    }

    /** `redemptions/{userID}_{dealID}` — детерминированный id, повторов не будет. */
    object RedemptionDoc {
        const val USER_ID = "userID"
        const val DEAL_ID = "dealID"
        const val VENUE_ID = "venueID"
        const val CREATED_AT = "createdAt"
        const val STATUS = "status"
        /** Значение поля `status` для свежей записи. */
        const val STATUS_NEW = "new"
    }

    /** `referrals/{inviteeID}` — один документ на приглашённого. */
    object ReferralDoc {
        const val INVITEE_ID = "inviteeID"
        const val REFERRER_ID = "referrerID"
        const val CREATED_AT = "createdAt"
    }

    /** `giftCoupons/{code}` — подарочный купон, забирается один раз. */
    object GiftCouponDoc {
        const val TITLE = "title"
        const val CODE = "code"
        const val FROM_NAME = "fromName"
        const val CLAIMED = "claimed"
        const val CLAIMED_AT = "claimedAt"
        const val CREATED_AT = "createdAt"
    }

    // ── Телеметрия ───────────────────────────────────────────────────────────

    /**
     * `analyticsEvents/{auto}` — клиентское событие; счётчики досчитывает
     * Cloud Function (писать в `analytics/…` напрямую клиенту запрещено).
     */
    object AnalyticsEventDoc {
        const val VENUE_ID = "venueID"
        const val METRIC = "metric"
        const val CREATED_AT = "createdAt"
    }

    /**
     * `analytics/{venueID}/days/{yyyy-MM-dd}` — счётчики за день.
     * Все поля, кроме `date`, суммируются как метрики.
     */
    object AnalyticsDayDoc {
        const val DATE = "date"
    }

    /**
     * `pushCampaigns/{auto}` — заявка на рассылку; админ одобряет в панели
     * (`status` → `approved`), дальше рассылает Cloud Function `sendPushCampaign`.
     *
     * `STATUS_PENDING` обязателен: админ-панель показывает к одобрению только
     * документы со `status == "pending"`, а функция шлёт только `"approved"`.
     * Любое другое значение = заявка навсегда застревает невидимой.
     */
    object PushCampaignDoc {
        const val HEADLINE = "headline"
        const val BODY = "body"
        const val CITY = "city"
        const val CATEGORY = "category"
        const val VENUE_ID = "venueID"
        const val DEAL_ID = "dealID"
        const val OWNER_ID = "ownerID"
        const val STATUS = "status"
        const val DELIVERED = "delivered"
        const val CREATED_AT = "createdAt"
        const val STATUS_PENDING = "pending"
    }

    /** `userTokens/{fcmToken}` — устройство для адресной рассылки. */
    object UserTokenDoc {
        const val CITY = "city"
        const val UID = "uid"
        const val UPDATED_AT = "updatedAt"
    }

    // ── Ответы Cloud Functions (scanCoupon / redeemVenuePoints) ──────────────
    //
    // Это не Firestore, а тело HTTP-ответа. Держим здесь по той же причине:
    // ключи заданы сервером в functions/src/index.ts и должны совпадать.

    object ScanResponse {
        const val OK = "ok"
        const val TITLE = "title"
        const val LOYALTY = "loyalty"
        const val STAMPS = "stamps"
        const val GOAL = "goal"
        const val REWARD_ISSUED = "rewardIssued"
        const val REWARD_TITLE = "rewardTitle"
        const val ERROR = "error"
        const val POINTS = "points"
        const val AWARDED = "awarded"
        const val BALANCE = "balance"
        // Поля запроса.
        const val CODE = "code"
        const val VENUE_ID = "venueID"
        const val BILL_AMOUNT = "billAmount"
        const val BAND_INDEX = "bandIndex"
        const val IDEMPOTENCY_KEY = "idempotencyKey"
        /** true — сервер распознал повтор по ключу и НЕ начислил снова. */
        const val REPLAYED = "replayed"
    }

    object RedeemResponse {
        const val OK = "ok"
        const val REDEEMED = "redeemed"
        const val BALANCE = "balance"
        const val REWARD_TITLE = "rewardTitle"
        const val SOM_OFF = "somOff"
        const val ERROR = "error"
        /** true — сервер распознал повтор по idempotencyKey и НЕ списал баллы снова. */
        const val REPLAYED = "replayed"
        const val IDEMPOTENCY_KEY = "idempotencyKey"
        // Поля запроса.
        const val VENUE_ID = "venueID"
        const val USER_ID = "userID"
        const val REWARD_ID = "rewardId"
        const val POINTS_TO_SPEND = "pointsToSpend"
    }

    /**
     * Data-payload push-уведомления (его собирает `sendPushCampaign`).
     * По этим ключам приложение решает, что открыть по тапу.
     */
    object PushPayload {
        const val DEAL_ID = "dealID"
        const val VENUE_ID = "venueID"
    }
}

/**
 * Слаги категорий/типов/статусов — тоже часть схемы: их пишет и админка.
 * Значения совпадают с `FSKeys` на iOS.
 */
object FSKeys {
    /** slug → отображаемое имя категории (RU). */
    val category = mapOf(
        "cafe" to "Кафе", "coffee" to "Кофейня", "fastfood" to "Фастфуд",
        "restaurant" to "Ресторан", "teahouse" to "Чайхана", "bakery" to "Пекарня",
    )

    const val DEAL_TYPE_DISCOUNT = "discount"
    const val DEAL_TYPE_PROMO = "promo"
    const val DEAL_TYPE_NOVELTY = "novelty"
    const val DEAL_TYPE_ANNOUNCEMENT = "announcement"

    const val DEAL_STATUS_ACTIVE = "active"
    const val DEAL_STATUS_PAUSED = "paused"
    const val DEAL_STATUS_EXPIRED = "expired"
    const val DEAL_STATUS_DRAFT = "draft"

    const val MODERATION_PENDING = "pending"
    const val MODERATION_APPROVED = "approved"
    const val MODERATION_REJECTED = "rejected"
}
