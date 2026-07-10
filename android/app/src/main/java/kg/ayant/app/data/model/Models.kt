package kg.ayant.app.data.model

import kotlinx.serialization.Serializable
import java.util.Calendar
import java.util.Date
import kotlin.math.floor

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
) {
    companion object {
        val BISHKEK = City("bishkek", "Бишкек", "Кыргызстан", 42.8746, 74.5698)
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
) {
    val isApproved: Boolean get() = status == ModerationStatus.APPROVED

    /** Paid boost is active right now. */
    val isBoosted: Boolean get() = boostedUntil?.let { it.after(Date()) } ?: false

    fun hours(index: Int): DayHours =
        if (weekHours.size == 7) weekHours[index]
        else DayHours(false, openHour * 60, closeHour * 60)

    val todayHours: DayHours get() = hours(todayIndex)

    val isOpenNow: Boolean
        get() {
            val d = todayHours
            if (d.closed) return false
            val cal = Calendar.getInstance()
            val cur = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE)
            return if (d.close > d.open) cur in d.open until d.close
            else cur >= d.open || cur < d.close
        }

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
        val todayIndex: Int
            get() = (Calendar.getInstance().get(Calendar.DAY_OF_WEEK) + 5) % 7

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
    val status: DealStatus = DealStatus.ACTIVE,
    val startDate: Date? = null,
    val imageEmojis: List<String> = emptyList(),
    val imageURL: String? = null,
    val imageURLs: List<String> = emptyList(),
) {
    val allImages: List<String>
        get() {
            val extra = imageURLs.filter { it.isNotEmpty() }
            if (extra.isNotEmpty()) return extra
            val u = imageURL
            return if (!u.isNullOrEmpty()) listOf(u) else emptyList()
        }

    val isActive: Boolean get() = status == DealStatus.ACTIVE && validUntil >= Date()

    val isRedeemable: Boolean get() = type == DealType.DISCOUNT || type == DealType.PROMO

    val hoursLeft: Int
        get() = maxOf(0, floor((validUntil.time - Date().time) / 3_600_000.0).toInt())

    val urgencyText: String?
        get() {
            if (!isActive) return null
            val cal = Calendar.getInstance()
            val now = cal.time
            val isToday = run {
                val c1 = Calendar.getInstance().apply { time = validUntil }
                val c2 = Calendar.getInstance().apply { time = now }
                c1.get(Calendar.YEAR) == c2.get(Calendar.YEAR) &&
                    c1.get(Calendar.DAY_OF_YEAR) == c2.get(Calendar.DAY_OF_YEAR)
            }
            if (isToday) return "Заканчивается сегодня"
            val h = hoursLeft
            if (h in 1..48) return "Осталось $h ч"
            return null
        }

    val isFresh: Boolean
        get() {
            val start = startDate ?: return false
            val cutoff = Date(Date().time - 48L * 3_600_000)
            return start >= cutoff
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
) {
    val initial: String get() = authorName.take(1).uppercase()
}

// MARK: - Feed item (deal or sponsored venue)

sealed class FeedItem {
    abstract val id: String
    data class DealItem(val deal: Deal) : FeedItem() { override val id = "d_${deal.id}" }
    data class AdVenue(val venue: Venue) : FeedItem() { override val id = "av_${venue.id}" }
}
