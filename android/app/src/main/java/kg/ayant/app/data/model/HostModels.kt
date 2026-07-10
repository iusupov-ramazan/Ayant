package kg.ayant.app.data.model

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import java.util.Date

// MARK: - Date serializer (epoch millis) — Date isn't serializable out of the box.

object DateAsLongSerializer : KSerializer<Date> {
    override val descriptor = PrimitiveSerialDescriptor("Date", PrimitiveKind.LONG)
    override fun serialize(encoder: Encoder, value: Date) = encoder.encodeLong(value.time)
    override fun deserialize(decoder: Decoder): Date = Date(decoder.decodeLong())
}

// MARK: - Host verification

@Serializable
enum class VerificationStatus(val title: String) {
    NONE("Не запрошена"),
    PENDING("На рассмотрении"),
    VERIFIED("Подтверждено ✓"),
    REJECTED("Отклонено"),
}

// MARK: - Host profile

@Serializable
data class HostProfile(
    var businessName: String,
    var categoryRaw: String,
    var phone: String,
    var email: String,
    var verification: VerificationStatus = VerificationStatus.NONE,
    var legalForm: String = "",
    var legalName: String = "",
    var inn: String = "",
    var registrationAddress: String = "",
    var website: String = "",
    var about: String = "",
) {
    val category: VenueCategory get() = VenueCategory(categoryRaw.ifEmpty { "Кафе" })
}

// MARK: - Host venue DTO (editable; converts to Venue)

@Serializable
data class HostVenueDTO(
    val id: String,
    var name: String,
    var categoryRaw: String,
    var district: String,
    var address: String,
    var phone: String,
    var emoji: String,
    var latitude: Double,
    var longitude: Double,
    var openHour: Int,
    var closeHour: Int,
    var todaySpecial: String? = null,
    var isPaused: Boolean = false,
    var isVerified: Boolean = false,
    var status: String = "pending",
    var items: List<VenueItem> = emptyList(),
    var imageURL: String = "",
    var pdfMenuURL: String = "",
    var whatsapp: String = "",
    var instagram: String = "",
    var telegram: String = "",
    @Serializable(with = DateAsLongSerializer::class) var boostedUntil: Date? = null,
    var loyaltyEnabled: Boolean = false,
    var loyaltyGoal: Int = 6,
    var loyaltyReward: String = "Награда за лояльность",
    var couponsEnabled: Boolean = true,
    var weekHours: List<DayHours> = emptyList(),
    var branches: List<Branch> = emptyList(),
) {
    val category: VenueCategory get() = VenueCategory(categoryRaw.ifEmpty { "Кафе" })
    val moderation: ModerationStatus get() = when (status) {
        "approved" -> ModerationStatus.APPROVED
        "rejected" -> ModerationStatus.REJECTED
        else -> ModerationStatus.PENDING
    }

    val asVenue: Venue
        get() = Venue(
            id = id, name = name, category = category, district = district,
            address = address, phone = phone, emoji = emoji,
            gradient = listOf(0xFFFF5A1FL, 0xFFFF9800L),   // Accent → amber
            imageURL = imageURL.ifEmpty { null },
            isVerified = isVerified,
            latitude = latitude, longitude = longitude,
            todaySpecialText = todaySpecial?.takeIf { it.isNotEmpty() },
            openHour = openHour, closeHour = closeHour,
            weekHours = if (weekHours.size == 7) weekHours else emptyList(),
            pdfMenuURL = pdfMenuURL.ifEmpty { null },
            photoEmojis = listOf(emoji), items = items,
            status = moderation, isPaused = isPaused,
            whatsapp = whatsapp, instagram = instagram, telegram = telegram,
            branches = branches,
            boostedUntil = boostedUntil,
            loyaltyEnabled = loyaltyEnabled, loyaltyGoal = loyaltyGoal, loyaltyReward = loyaltyReward,
            couponsEnabled = couponsEnabled,
        )
}

// MARK: - Host deal DTO

@Serializable
data class HostDealDTO(
    val id: String,
    val venueID: String,
    var typeRaw: String,
    var title: String,
    var details: String,
    var emoji: String,
    var newPrice: Int? = null,
    var discountPercent: Int? = null,
    @Serializable(with = DateAsLongSerializer::class) var startDate: Date = Date(),
    @Serializable(with = DateAsLongSerializer::class) var endDate: Date? = null,
    var statusRaw: String = "active",
    var imageURL: String = "",
) {
    val type: DealType get() = DealType.entries.firstOrNull { it.title == typeRaw } ?: DealType.DISCOUNT
    val status: DealStatus get() = when (statusRaw) {
        "paused" -> DealStatus.PAUSED
        "expired" -> DealStatus.EXPIRED
        "draft" -> DealStatus.DRAFT
        else -> DealStatus.ACTIVE
    }

    val asDeal: Deal
        get() = Deal(
            id = id, venueID = venueID, type = type, title = title, details = details,
            emoji = emoji, oldPrice = null, newPrice = newPrice, discountPercent = discountPercent,
            validUntil = endDate ?: Date(System.currentTimeMillis() + 365L * 86_400_000),
            status = status, startDate = startDate, imageEmojis = listOf(emoji),
            imageURL = imageURL.ifEmpty { null },
        )
}

// MARK: - Ad campaign

@Serializable
data class AdCampaign(
    val id: String,
    val kind: Kind,
    val venueID: String,
    var status: Status,
    @Serializable(with = DateAsLongSerializer::class) val startAt: Date,
    @Serializable(with = DateAsLongSerializer::class) val endAt: Date,
    val impressions: Int,
    val taps: Int,
    val spend: Int,
) {
    @Serializable
    enum class Kind(val title: String) { BOOST("Буст заведения"), PUSH("Push-уведомление") }
    @Serializable
    enum class Status(val title: String) {
        SCHEDULED("Запланирована"), ACTIVE("Активна"), SENT("Отправлено"),
        COMPLETED("Завершена"), CANCELLED("Отменена");
        val isLive: Boolean get() = this == ACTIVE || this == SENT
    }

    val effectiveStatus: Status
        get() = when {
            status == Status.CANCELLED -> Status.CANCELLED
            kind == Kind.PUSH -> status
            endAt.before(Date()) -> Status.COMPLETED
            else -> status
        }
}
