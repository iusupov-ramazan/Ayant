import Foundation
import AyantDomain

/// **Единственное место, где записаны имена коллекций и полей Firestore.**
///
/// Раньше каждое имя было строковым литералом и встречалось 2–3 раза: в чтении
/// (`d["gradientFrom"]`), в записи (`"gradientFrom": …`), иногда ещё в запросе.
/// Переименование поля требовало найти их все — а промах не ломал сборку, он тихо
/// возвращал `nil` и подставлял дефолт. Теперь имя объявлено один раз, и опечатка
/// в нём — ошибка компиляции.
///
/// Важно: одни и те же документы пишут ещё две поверхности — Cloud Functions
/// (`functions/src/index.ts`) и админ-панель (`docs/admin/index.html`). Компилятор
/// их не проверяет, поэтому при переименовании поля правьте все четыре.
///
/// Зеркалит `data/firestore/FirestoreSchema.kt` на Android 1:1.
public enum FS {

    // MARK: - Коллекции

    public enum Collection {
        public static let venues = "venues"
        public static let deals = "deals"
        public static let reviews = "reviews"
        public static let hosts = "hosts"
        public static let categories = "categories"
        public static let coupons = "coupons"
        public static let giftCoupons = "giftCoupons"
        public static let loyaltyCards = "loyaltyCards"
        public static let venuePoints = "venuePoints"
        public static let bonusGrants = "bonusGrants"
        public static let redemptions = "redemptions"
        public static let referrals = "referrals"
        public static let rankingEvents = "rankingEvents"
        public static let analytics = "analytics"
        public static let analyticsEvents = "analyticsEvents"
        public static let pushCampaigns = "pushCampaigns"
        public static let userTokens = "userTokens"
        public static let config = "config"
        /// Подколлекция `analytics/{venueID}/days/{yyyy-MM-dd}`.
        public static let days = "days"
    }

    /// Документы с фиксированным id.
    public enum Document {
        public static let rankingWeights = "rankingWeights"
    }

    // MARK: - venues/{id}

    public enum VenueDoc {
        public static let name = "name"
        public static let category = "category"
        public static let district = "district"
        public static let address = "address"
        public static let phone = "phone"
        public static let emoji = "emoji"
        public static let gradientFrom = "gradientFrom"
        public static let gradientTo = "gradientTo"
        public static let imageURL = "imageURL"
        public static let rating = "rating"
        public static let reviewCount = "reviewCount"
        public static let isVerified = "isVerified"
        public static let savedByCount = "savedByCount"
        /// Слаг города. Внимание: поле называется `city`, а в модели — `citySlug`.
        public static let city = "city"
        public static let latitude = "latitude"
        public static let longitude = "longitude"
        public static let todaySpecial = "todaySpecial"
        public static let openHour = "openHour"
        public static let closeHour = "closeHour"
        public static let weekHours = "weekHours"
        public static let pdfMenuURL = "pdfMenuURL"
        public static let photoEmojis = "photoEmojis"
        public static let ownerID = "ownerID"
        public static let items = "items"
        public static let status = "status"
        public static let isPaused = "isPaused"
        public static let whatsapp = "whatsapp"
        public static let instagram = "instagram"
        public static let telegram = "telegram"
        public static let branches = "branches"
        public static let boostedUntil = "boostedUntil"
        // Карта лояльности.
        public static let loyaltyEnabled = "loyaltyEnabled"
        public static let loyaltyGoal = "loyaltyGoal"
        public static let loyaltyReward = "loyaltyReward"
        public static let couponsEnabled = "couponsEnabled"
        // Баллы САН. Эти поля пишет ТОЛЬКО админ-панель — хост их не трогает,
        // иначе сохранение из приложения затёрло бы настройки (см. HostVenueDTO).
        public static let pointsEnabled = "pointsEnabled"
        public static let pointsMode = "pointsMode"
        public static let pointsFlat = "pointsFlat"
        public static let pointsBands = "pointsBands"
        public static let cashbackPercent = "cashbackPercent"
        public static let pointsRewards = "pointsRewards"
        public static let pointsExpiryMonths = "pointsExpiryMonths"
        public static let redeemMode = "redeemMode"
        public static let earnCooldownMinutes = "earnCooldownMinutes"
    }

    // MARK: - deals/{id}

    public enum DealDoc {
        public static let venueID = "venueID"
        public static let type = "type"
        public static let title = "title"
        public static let details = "details"
        /// Условия акции: массив строк, по строке на пункт.
        public static let terms = "terms"
        public static let emoji = "emoji"
        public static let oldPrice = "oldPrice"
        public static let newPrice = "newPrice"
        public static let discountPercent = "discountPercent"
        public static let validUntil = "validUntil"
        public static let status = "status"
        public static let startDate = "startDate"
        public static let endDate = "endDate"
        public static let imageEmojis = "imageEmojis"
        public static let imageURL = "imageURL"
        public static let imageURLs = "imageURLs"
        public static let ownerID = "ownerID"
        /// Ключ партиционирования по городам — то же поле `city`, что у заведения.
        public static let city = "city"
    }

    // MARK: - reviews/{id}

    public enum ReviewDoc {
        public static let venueID = "venueID"
        public static let authorID = "authorID"
        public static let authorName = "authorName"
        public static let rating = "rating"
        public static let text = "text"
        public static let photoEmojis = "photoEmojis"
        public static let photos = "photos"
        public static let createdAt = "createdAt"
        public static let updatedAt = "updatedAt"
        public static let hostReply = "hostReply"
        public static let itemID = "itemID"
        public static let itemName = "itemName"
        public static let verifiedVisit = "verifiedVisit"
        /// Ключ партиционирования по городам — то же поле `city`, что у заведения.
        public static let city = "city"
    }

    /// Вложенная карта `reviews/{id}.hostReply`.
    public enum HostReplyField {
        public static let text = "text"
        public static let createdAt = "createdAt"
        public static let updatedAt = "updatedAt"
    }

    // MARK: - hosts/{uid}

    public enum HostDoc {
        public static let businessName = "businessName"
        public static let categoryRaw = "categoryRaw"
        public static let phone = "phone"
        public static let email = "email"
        public static let verification = "verification"
        // Реквизиты / расширенная информация о бизнесе. Имена полей совпадают
        // с именами свойств `HostProfile`.
        public static let legalForm = "legalForm"
        public static let legalName = "legalName"
        public static let inn = "inn"
        public static let registrationAddress = "registrationAddress"
        public static let website = "website"
        public static let about = "about"
    }

    // MARK: - categories/{slug}

    public enum CategoryDoc {
        public static let slug = "slug"
        public static let name = "name"
        public static let icon = "icon"
        public static let emoji = "emoji"
        public static let order = "order"
        public static let enabled = "enabled"
    }

    // MARK: - Вложенные объекты внутри venues/{id}

    /// Элемент массива `items` (блюдо/услуга).
    public enum ItemField {
        public static let id = "id"
        public static let name = "name"
        public static let emoji = "emoji"
        public static let kind = "kind"
        public static let imageURL = "imageURL"
    }

    /// Элемент массива `branches` (филиал).
    public enum BranchField {
        public static let id = "id"
        public static let address = "address"
        public static let latitude = "latitude"
        public static let longitude = "longitude"
        public static let phone = "phone"
    }

    /// Элемент массива `weekHours` (часы одного дня).
    public enum DayHoursField {
        public static let closed = "closed"
        public static let open = "open"
        public static let close = "close"
    }

    /// Элемент массива `pointsBands` (диапазон чек→баллы).
    public enum PointsBandField {
        public static let maxAmount = "maxAmount"
        public static let points = "points"
    }

    /// Элемент массива `pointsRewards` (награда за баллы).
    public enum PointsRewardField {
        public static let id = "id"
        public static let type = "type"
        public static let title = "title"
        public static let cost = "cost"
        public static let ratio = "ratio"
        public static let active = "active"
    }

    // MARK: - Кошельки гостя

    public enum CouponDoc {
        public static let code = "code"
        public static let userID = "userID"
        public static let venueID = "venueID"
        public static let venueName = "venueName"
        public static let title = "title"
        public static let kind = "kind"
        public static let dealID = "dealID"
        public static let used = "used"
        public static let createdAt = "createdAt"
    }

    public enum LoyaltyCardDoc {
        public static let userID = "userID"
        public static let venueID = "venueID"
        public static let venueName = "venueName"
        public static let stamps = "stamps"
        public static let completedRounds = "completedRounds"
        public static let goal = "goal"
        public static let reward = "reward"
    }

    public enum VenuePointsDoc {
        public static let userID = "userID"
        public static let venueID = "venueID"
        public static let venueName = "venueName"
        public static let balance = "balance"
        public static let lifetimeEarned = "lifetimeEarned"
        public static let lifetimeRedeemed = "lifetimeRedeemed"
    }

    public enum BonusGrantDoc {
        public static let userID = "userID"
        public static let amount = "amount"
        public static let claimed = "claimed"
    }

    /// `redemptions/{userID}_{dealID}` — детерминированный id, повторов не будет.
    public enum RedemptionDoc {
        public static let userID = "userID"
        public static let dealID = "dealID"
        public static let venueID = "venueID"
        public static let createdAt = "createdAt"
        public static let status = "status"
        /// Значение поля `status` для свежей записи (её досчитывает Cloud Function).
        public static let statusNew = "new"
    }

    /// `referrals/{inviteeID}` — один документ на приглашённого.
    public enum ReferralDoc {
        public static let inviteeID = "inviteeID"
        public static let referrerID = "referrerID"
        public static let createdAt = "createdAt"
    }

    /// `giftCoupons/{code}` — подарочный купон, забирается один раз.
    public enum GiftCouponDoc {
        public static let title = "title"
        public static let code = "code"
        public static let fromName = "fromName"
        public static let claimed = "claimed"
        public static let claimedAt = "claimedAt"
        public static let createdAt = "createdAt"
    }

    // MARK: - Телеметрия и рассылки

    /// `analyticsEvents/{auto}` — клиентское событие; счётчики досчитывает
    /// Cloud Function (писать в `analytics/*` напрямую клиенту запрещено).
    public enum AnalyticsEventDoc {
        public static let venueID = "venueID"
        public static let metric = "metric"
        public static let createdAt = "createdAt"
    }

    /// `analytics/{venueID}/days/{yyyy-MM-dd}` — счётчики за день.
    /// Все поля, кроме `date`, суммируются как метрики.
    public enum AnalyticsDayDoc {
        public static let date = "date"
    }

    /// `userTokens/{fcmToken}` — устройство для адресной рассылки.
    public enum UserTokenDoc {
        public static let city = "city"
        public static let uid = "uid"
        public static let updatedAt = "updatedAt"
    }

    /// `pushCampaigns/{auto}` — заявка на рассылку; админ одобряет в панели
    /// (`status` → `approved`), дальше рассылает Cloud Function.
    public enum PushCampaignDoc {
        public static let headline = "headline"
        public static let body = "body"
        public static let city = "city"
        public static let category = "category"
        public static let venueID = "venueID"
        public static let dealID = "dealID"
        public static let ownerID = "ownerID"
        public static let status = "status"
        public static let delivered = "delivered"
        public static let createdAt = "createdAt"
        /// Значение `status` у только что созданной заявки.
        public static let statusPending = "pending"
    }

    // MARK: - Ответы Cloud Functions (scanCoupon / redeemVenuePoints)
    //
    // Это не Firestore, а тело HTTP-ответа. Держим здесь по той же причине:
    // ключи заданы сервером в functions/src/index.ts и должны совпадать.

    public enum ScanResponse {
        public static let ok = "ok"
        public static let title = "title"
        public static let loyalty = "loyalty"
        public static let stamps = "stamps"
        public static let goal = "goal"
        public static let rewardIssued = "rewardIssued"
        public static let rewardTitle = "rewardTitle"
        public static let error = "error"
        public static let points = "points"
        public static let awarded = "awarded"
        public static let balance = "balance"
        // Поля запроса.
        public static let code = "code"
        public static let venueID = "venueID"
        public static let billAmount = "billAmount"
        public static let bandIndex = "bandIndex"
        public static let idempotencyKey = "idempotencyKey"
        /// true — сервер распознал повтор по ключу и НЕ начислил снова.
        public static let replayed = "replayed"
    }

    /// Data-payload push-уведомления (его собирает `sendPushCampaign`).
    /// По этим ключам приложение решает, что открыть по тапу.
    public enum PushPayload {
        public static let dealID = "dealID"
        public static let venueID = "venueID"
    }

    public enum RedeemResponse {
        public static let ok = "ok"
        public static let redeemed = "redeemed"
        public static let balance = "balance"
        public static let rewardTitle = "rewardTitle"
        public static let somOff = "somOff"
        public static let error = "error"
        /// true — сервер распознал повтор по idempotencyKey и НЕ списал баллы снова.
        public static let replayed = "replayed"
        public static let idempotencyKey = "idempotencyKey"
        // Поля запроса.
        public static let venueID = "venueID"
        public static let userID = "userID"
        public static let rewardId = "rewardId"
        public static let pointsToSpend = "pointsToSpend"
    }
}

// MARK: - Кодирование enum'ов в строковые ключи Firestore

/// Слаги категорий/типов/статусов — тоже часть схемы: их пишет и админка.
public enum FSKeys {
    public static let category: [String: VenueCategory] = [
        "cafe": .cafe, "coffee": .coffee, "fastfood": .fastfood,
        "restaurant": .restaurant, "teahouse": .teahouse, "bakery": .bakery,
    ]

    public static let dealType: [String: DealType] = [
        "discount": .discount, "promo": .promo, "novelty": .novelty, "announcement": .announcement,
    ]

    public static let dealStatus: [String: DealStatus] = [
        "active": .active, "paused": .paused, "expired": .expired, "draft": .draft,
    ]

    // Обратные карты: модель → строковый ключ для записи.
    private static let categoryKey: [VenueCategory: String] = [
        .cafe: "cafe", .coffee: "coffee", .fastfood: "fastfood",
        .restaurant: "restaurant", .teahouse: "teahouse", .bakery: "bakery",
    ]
    private static let dealTypeKey: [DealType: String] = [
        .discount: "discount", .promo: "promo", .novelty: "novelty", .announcement: "announcement",
    ]

    /// Пользовательские категории из админки пишем как есть (`rawValue`).
    public static func key(for c: VenueCategory) -> String { categoryKey[c] ?? c.rawValue }
    public static func key(for t: DealType) -> String { dealTypeKey[t] ?? t.rawValue }
}
