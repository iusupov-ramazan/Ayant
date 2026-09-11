package kg.ayant.app.domain.model

import kotlinx.serialization.Serializable
import java.util.Calendar
import java.util.Date
import java.util.TimeZone
import kotlin.math.floor
import kotlin.math.roundToInt

// MARK: - Deal type (mirrors Models.swift DealType)
// Note: the per-type accent color lives in the UI layer (ui.theme.color extension);
// the data layer stays free of Compose types.

enum class DealType(val title: String) {
    DISCOUNT("Скидка"),
    PROMO("Акция"),
    NOVELTY("Новинка"),
    ANNOUNCEMENT("Объявление"),
}

// MARK: - Deal status

enum class DealStatus { ACTIVE, PAUSED, EXPIRED, DRAFT }

// MARK: - Moderation status

enum class ModerationStatus { PENDING, APPROVED, REJECTED }

// MARK: - Venue category (open type — categories can come from backend)

data class VenueCategory(val rawValue: String) {
    val icon: String get() = builtinIcons[rawValue] ?: "tag"

    /**
     * How "in season" this category is at the given local hour, 0..1 — a contextual
     * feed nudge (coffee in the morning, restaurants at dinner), keyed by rawValue
     * like [icon]. Heuristic defaults, tune freely. Unknown/backend categories return
     * a neutral 0.5 so they are neither boosted nor penalised. Mirrors iOS.
     */
    fun timeRelevance(hour: Int): Double = when (rawValue) {
        "Кофейня", "Пекарня" -> when (hour) {   // morning-focused
            in 7..10 -> 1.0
            in 11..16 -> 0.6
            else -> 0.35
        }
        "Фастфуд" -> when (hour) {               // lunch + evening
            in 11..14 -> 1.0
            in 18..22 -> 0.8
            else -> 0.45
        }
        "Ресторан" -> when (hour) {              // dinner
            in 18..22 -> 1.0
            in 12..15 -> 0.7
            else -> 0.4
        }
        "Чайхана" -> if (hour in 12..22) 1.0 else 0.45  // midday → evening
        "Кафе" -> 0.7                            // broad, all-day
        else -> 0.5                              // unknown → neutral
    }

    companion object {
        val CAFE = VenueCategory("Кафе")
        val COFFEE = VenueCategory("Кофейня")
        val FASTFOOD = VenueCategory("Фастфуд")
        val RESTAURANT = VenueCategory("Ресторан")
        val TEAHOUSE = VenueCategory("Чайхана")
        val BAKERY = VenueCategory("Пекарня")

        val all = listOf(CAFE, COFFEE, FASTFOOD, RESTAURANT, TEAHOUSE, BAKERY)

        // Material icon keys (resolved to ImageVector in Icons.kt)
        private val builtinIcons = mapOf(
            "Кафе" to "restaurant",
            "Кофейня" to "local_cafe",
            "Фастфуд" to "lunch_dining",
            "Ресторан" to "wine_bar",
            "Чайхана" to "emoji_food_beverage",
            "Пекарня" to "bakery_dining",
        )
    }
}

// MARK: - City

data class City(
    val id: String,
    val name: String,
    val country: String,
    val latitude: Double,
    val longitude: Double,
    /**
     * Часовой пояс города (IANA). Часы работы заведений записаны по МЕСТНОМУ
     * времени города, а телефон может стоять в любом другом поясе — без этого
     * «открыто сейчас» считалось по часам телефона и врало на всю разницу.
     */
    val timeZoneID: String = DEFAULT_TIME_ZONE_ID,
) {
    val timeZone: TimeZone get() = TimeZone.getTimeZone(timeZoneID)

    companion object {
        const val DEFAULT_TIME_ZONE_ID = "Asia/Bishkek"

        val BISHKEK = City("bishkek", "Бишкек", "Кыргызстан", 42.8746, 74.5698, "Asia/Bishkek")

        /** Пока город один; когда появятся другие — добавлять сюда, а не в UI. */
        val ALL: List<City> = listOf(BISHKEK)

        /**
         * Пояс города по slug. Неизвестный slug — пояс каталога по умолчанию:
         * лучше показать часы Бишкека, чем часы телефона в другой стране.
         */
        fun timeZoneForSlug(slug: String): TimeZone =
            ALL.firstOrNull { it.id == slug }?.timeZone
                ?: TimeZone.getTimeZone(DEFAULT_TIME_ZONE_ID)

        /** Календарь в поясе города — им считаются «сегодня» и время открытия. */
        fun calendarForSlug(slug: String): Calendar =
            Calendar.getInstance(timeZoneForSlug(slug))
    }
}

// MARK: - Venue item (dish/service for reviews)

@Serializable
data class VenueItem(
    val id: String,
    val name: String,
    val emoji: String,
    val kind: String,             // "food" | "service" | "other"
    val imageURL: String = "",
) {
    val kindTitle: String
        get() = when (kind) {
            "service" -> "Услуга"
            "other" -> "Объект"
            else -> "Блюдо"
        }
}

// MARK: - Branch

@Serializable
data class Branch(
    val id: String,
    val address: String,
    val latitude: Double,
    val longitude: Double,
    val phone: String = "",
)

// MARK: - Day hours (minutes from midnight)

@Serializable
data class DayHours(
    val closed: Boolean = false,
    val open: Int = 9 * 60,
    val close: Int = 22 * 60,
) {
    val label: String get() = if (closed) "Выходной" else "${time(open)} – ${time(close)}"

    companion object {
        fun time(minutes: Int): String =
            "%02d:%02d".format((minutes / 60) % 24, minutes % 60)
    }
}

// MARK: - Бонусы САН (баллы заведения)

/** Диапазон суммы чека → баллы (режим начисления "bands"). */
@Serializable
data class PointsBand(
    val maxAmount: Int,
    val points: Int,
)

/** Награда из каталога заведения, покупается за баллы. */
@Serializable
data class PointsReward(
    val id: String,
    val type: String,          // "item" (фикс. цена) | "money" (скидка баллами)
    val title: String,
    val cost: Int,             // item: цена в баллах; money: минимум к списанию
    val ratio: Double = 1.0,   // money: сом скидки за 1 балл
    val active: Boolean = true,
)

// MARK: - Venue

data class Venue(
    val id: String,
    val name: String,
    val category: VenueCategory,
    val district: String,
    val address: String,
    val phone: String,
    val emoji: String,
    /** ARGB colors (0xAARRGGBB) for the venue card gradient. Mapped to Compose
     *  Color in the UI layer via [kg.ayant.app.ui.theme.gradientColors]. */
    val gradient: List<Long>,
    val imageURL: String? = null,
    val rating: Double = 0.0,
    val reviewCount: Int = 0,
    val isVerified: Boolean = false,
    val savedByCount: Int = 0,
    val citySlug: String = City.BISHKEK.id,
    val latitude: Double = City.BISHKEK.latitude,
    val longitude: Double = City.BISHKEK.longitude,
    val todaySpecialText: String? = null,
    val openHour: Int = 9,
    val closeHour: Int = 22,
    val weekHours: List<DayHours> = emptyList(),
    val pdfMenuURL: String? = null,
    val photoEmojis: List<String> = emptyList(),
    val ownerID: String = "",
    val items: List<VenueItem> = emptyList(),
    val status: ModerationStatus = ModerationStatus.APPROVED,
    val isPaused: Boolean = false,
    val whatsapp: String = "",
    val instagram: String = "",
    val telegram: String = "",
    val branches: List<Branch> = emptyList(),
    val boostedUntil: Date? = null,
    val loyaltyEnabled: Boolean = false,
    val loyaltyGoal: Int = 6,
    val loyaltyReward: String = "Награда за лояльность",
    val couponsEnabled: Boolean = true,
    // Бонусы САН (баллы заведения, System 1)
    val pointsEnabled: Boolean = false,
    val pointsMode: String = "flat",           // "flat" | "bands" | "cashback"
    val pointsFlat: Int = 0,
    val pointsBands: List<PointsBand> = emptyList(),
    val cashbackPercent: Double = 0.0,
    val pointsRewards: List<PointsReward> = emptyList(),
    val pointsExpiryMonths: Int = 6,
    val redeemMode: String = "staffScan",      // "staffScan" | "customerInitiated"
    val earnCooldownMinutes: Int = 60,
) {
    val isApproved: Boolean get() = status == ModerationStatus.APPROVED

    /** Активен ли платный буст в момент [nowMs]. */
    fun isBoostedAt(nowMs: Long): Boolean = boostedUntil?.let { it.time > nowMs } ?: false
    /**
     * Системное «сейчас». Ниже слоя UI используйте [isBoostedAt] — иначе логика
     * не воспроизводится в тесте (см. `Clock`).
     */
    val isBoosted: Boolean get() = isBoostedAt(System.currentTimeMillis())

    fun hours(index: Int): DayHours =
        if (weekHours.size == 7) weekHours[index]
        else DayHours(false, openHour * 60, closeHour * 60)

    fun todayHoursAt(nowMs: Long): DayHours = hours(todayIndexAt(nowMs, citySlug))

    /** Пояс заведения — из его города. */
    val timeZone: TimeZone get() = City.timeZoneForSlug(citySlug)
    val todayHours: DayHours get() = todayHoursAt(System.currentTimeMillis())

    /**
     * Открыто ли заведение в момент [nowMs] (по часам текущего дня недели).
     *
     * Всё считается в поясе ГОРОДА заведения: часы работы записаны по местному
     * времени, а [nowMs] — абсолютный момент. Телефон в другом поясе больше не
     * сдвигает открытие/закрытие на разницу часов.
     */
    fun isOpenAt(nowMs: Long): Boolean {
        val d = todayHoursAt(nowMs)
        if (d.closed) return false
        val cal = City.calendarForSlug(citySlug).apply { timeInMillis = nowMs }
        val cur = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
        return if (d.close > d.open) cur in d.open until d.close
        else cur >= d.open || cur < d.close
    }
    val isOpenNow: Boolean get() = isOpenAt(System.currentTimeMillis())

    val hoursStatusText: String
        get() {
            val d = todayHours
            if (d.closed) return "Сегодня выходной"
            return if (isOpenNow) "Открыто · до ${DayHours.time(d.close)}" else "Закрыто"
        }

    val hasTodaySpecial: Boolean get() = todaySpecialText?.trim()?.isNotEmpty() == true

    val whatsappURL: String?
        get() {
            val digits = whatsapp.filter { it.isDigit() }
            return if (digits.isEmpty()) null else "https://wa.me/$digits"
        }
    val instagramURL: String?
        get() = when {
            instagram.isEmpty() -> null
            instagram.startsWith("http") -> instagram
            else -> "https://instagram.com/${instagram.replace("@", "")}"
        }
    val telegramURL: String?
        get() = when {
            telegram.isEmpty() -> null
            telegram.startsWith("http") -> telegram
            else -> "https://t.me/${telegram.replace("@", "")}"
        }

    companion object {
        val weekdayLong = listOf(
            "Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"
        )
        // 0 = Monday … 6 = Sunday
        /**
         * 0 = понедельник … 6 = воскресенье — В ПОЯСЕ ГОРОДА.
         *
         * По часам телефона возле полуночи получался соседний день недели, и
         * заведение показывалось с чужим расписанием.
         */
        fun todayIndexAt(nowMs: Long, citySlug: String = City.BISHKEK.id): Int =
            (City.calendarForSlug(citySlug).apply { timeInMillis = nowMs }
                .get(Calendar.DAY_OF_WEEK) + 5) % 7
        val todayIndex: Int get() = todayIndexAt(System.currentTimeMillis())

        fun defaultWeek(): List<DayHours> = List(7) { DayHours() }
    }
}

// MARK: - Deal

data class Deal(
    val id: String,
    val venueID: String,
    val type: DealType,
    val title: String,
    val details: String,
    val emoji: String,
    val oldPrice: Int? = null,
    val newPrice: Int? = null,
    val discountPercent: Int? = null,
    val validUntil: Date,
    /**
     * Ключ партиционирования по городам. Пока константа «bishkek» — заведён
     * заранее: доставить его в живой каталог задним числом дороже, чем нести
     * неиспользуемое поле. Совпадает с [Venue.citySlug].
     */
    val citySlug: String = City.BISHKEK.id,
    val status: DealStatus = DealStatus.ACTIVE,
    val startDate: Date? = null,
    val imageEmojis: List<String> = emptyList(),
    val imageURL: String? = null,
    val imageURLs: List<String> = emptyList(),
    /**
     * Условия акции — по строке на пункт («Каждый день до 12:00»).
     *
     * Отдельно от [details]: описание продаёт, условия ограничивают. Сложенные
     * в один текст, ограничения либо теряются в абзаце, либо превращают его в
     * юридическую сноску. Пусто — блока условий в ленте просто нет.
     */
    val terms: List<String> = emptyList(),
) {
    val allImages: List<String>
        get() {
            val extra = imageURLs.filter { it.isNotEmpty() }
            if (extra.isNotEmpty()) return extra
            val u = imageURL
            return if (!u.isNullOrEmpty()) listOf(u) else emptyList()
        }

    /** Не протухла/не на паузе/не черновик в момент [nowMs]. */
    fun isActiveAt(nowMs: Long): Boolean = status == DealStatus.ACTIVE && validUntil.time >= nowMs
    /** Системное «сейчас». Ниже слоя UI используйте [isActiveAt]. */
    val isActive: Boolean get() = isActiveAt(System.currentTimeMillis())

    val isRedeemable: Boolean get() = type == DealType.DISCOUNT || type == DealType.PROMO

    val hoursLeft: Int
        get() = maxOf(0, floor((validUntil.time - Date().time) / 3_600_000.0).toInt())

    val urgencyText: String?
        get() {
            if (!isActive) return null
            // «Сегодня» — день ГОРОДА, а не телефона: акция заканчивается по
            // местному времени заведения.
            val now = Date()
            val isToday = run {
                val c1 = City.calendarForSlug(citySlug).apply { time = validUntil }
                val c2 = City.calendarForSlug(citySlug).apply { time = now }
                c1.get(Calendar.YEAR) == c2.get(Calendar.YEAR) &&
                    c1.get(Calendar.DAY_OF_YEAR) == c2.get(Calendar.DAY_OF_YEAR)
            }
            if (isToday) return "Заканчивается сегодня"
            val h = hoursLeft
            if (h in 1..48) return "Осталось $h ч"
            return null
        }

    /** Добавлено в последние 48 ч до [nowMs] — буст в ранжировании. */
    fun isFreshAt(nowMs: Long): Boolean {
        val start = startDate ?: return false
        return start.time >= nowMs - 48L * 3_600_000
    }
    val isFresh: Boolean get() = isFreshAt(System.currentTimeMillis())

    /** Effective discount % for ranking: explicit [discountPercent], else derived
     *  from old/new price. Null when neither is available. Mirrors iOS. */
    val effectiveDiscountPercent: Int?
        get() {
            discountPercent?.let { return it }
            val old = oldPrice ?: return null
            val new = newPrice ?: return null
            if (old <= 0 || new >= old) return null
            return ((old - new).toDouble() / old * 100).roundToInt()
        }
}

// MARK: - Review + host reply

data class HostReply(
    val text: String,
    val createdAt: Date,
    val updatedAt: Date,
)

data class Review(
    val id: String,
    val venueID: String,
    val authorID: String,
    val authorName: String,
    val rating: Int,               // 1…5
    val text: String,
    val photoEmojis: List<String> = emptyList(),
    val createdAt: Date,
    val updatedAt: Date,
    val hostReply: HostReply? = null,
    val itemID: String? = null,
    val itemName: String? = null,
    val photos: List<String> = emptyList(),
    val verifiedVisit: Boolean = false,
    /** Ключ партиционирования по городам (см. [Deal.citySlug]). */
    val citySlug: String = City.BISHKEK.id,
) {
    val initial: String get() = authorName.take(1).uppercase()
}

// MARK: - Feed item (deal or sponsored venue)

sealed class FeedItem {
    abstract val id: String
    data class DealItem(val deal: Deal) : FeedItem() { override val id = "d_${deal.id}" }
    data class AdVenue(val venue: Venue) : FeedItem() { override val id = "av_${venue.id}" }
}
