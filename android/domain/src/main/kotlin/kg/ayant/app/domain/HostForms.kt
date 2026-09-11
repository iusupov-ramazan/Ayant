package kg.ayant.app.domain

import kg.ayant.app.domain.model.Branch
import kg.ayant.app.domain.model.DayHours
import kg.ayant.app.domain.model.DealType
import kg.ayant.app.domain.model.HostDealDTO
import kg.ayant.app.domain.model.HostVenueDTO
import kg.ayant.app.domain.model.VenueCategory
import java.util.Date

/**
 * Сборка DTO хоста из полей формы — чистая часть бизнес-кабинета.
 *
 * Раньше это жило прямо в Compose-форме (`ui/host/HostForms.kt`) и в
 * `HostStore.saveVenueForm` на iOS, поэтому правила «что при правке сохраняется,
 * а что перезаписывается» нигде не проверялись и разъехались между платформами.
 *
 * Правила, которые легко нарушить и трудно заметить:
 *  • при **правке** сохраняются `id`, `status` (модерация) и `todaySpecial` —
 *    иначе одобренное заведение молча уедет обратно на модерацию;
 *  • при **правке акции** сохраняется `startDate` — иначе «свежесть» в ленте
 *    обнулится и акция подпрыгнет наверх;
 *  • текстовые поля тримятся, часы зажимаются в 0…24.
 *
 * Зеркалит `HostForms.swift` в AyantDomain.
 */
object HostForms {

    /** Поля формы заведения. */
    data class VenueFields(
        val name: String,
        val category: VenueCategory,
        val district: String,
        val address: String,
        val phone: String,
        val emoji: String,
        val latitude: Double,
        val longitude: Double,
        val openHour: Int,
        val closeHour: Int,
        val imageURL: String,
        val weekHours: List<DayHours>,
        val pdfMenuURL: String,
        val whatsapp: String,
        val instagram: String,
        val telegram: String,
        val branches: List<Branch>,
        val loyaltyEnabled: Boolean,
        val loyaltyGoal: Int,
        val loyaltyReward: String,
        val couponsEnabled: Boolean,
    )

    /**
     * Поля формы из уже существующего заведения. Зеркалит `HostForms.fields(from:)`.
     *
     * Нужна, когда экран правит ОДНУ настройку (например карту лояльности с
     * вкладки «Лояльность»), а `saveVenue` принимает форму целиком: собирать её
     * по полю в UI — верный способ незаметно затереть остальные.
     */
    fun fields(dto: HostVenueDTO): VenueFields = VenueFields(
        name = dto.name, category = dto.category, district = dto.district,
        address = dto.address, phone = dto.phone, emoji = dto.emoji,
        latitude = dto.latitude, longitude = dto.longitude,
        openHour = dto.openHour, closeHour = dto.closeHour,
        imageURL = dto.imageURL, weekHours = dto.weekHours,
        pdfMenuURL = dto.pdfMenuURL, whatsapp = dto.whatsapp,
        instagram = dto.instagram, telegram = dto.telegram,
        branches = dto.branches,
        loyaltyEnabled = dto.loyaltyEnabled, loyaltyGoal = dto.loyaltyGoal,
        loyaltyReward = dto.loyaltyReward, couponsEnabled = dto.couponsEnabled,
    )

    /** Поля формы акции. */
    data class DealFields(
        val venueID: String,
        val type: DealType,
        val title: String,
        val details: String,
        val emoji: String,
        val newPrice: Int?,
        val discountPercent: Int?,
        val endDate: Date?,
        val isDraft: Boolean,
        val imageURLs: List<String>,
        val terms: List<String> = emptyList(),
    )

    /**
     * Заведение из формы. [existing] == null — создание (статус «на модерации»),
     * иначе правка поверх существующего DTO.
     */
    fun venue(existing: HostVenueDTO?, fields: VenueFields, newID: () -> String): HostVenueDTO {
        val base = existing ?: HostVenueDTO(
            id = newID(), name = "", categoryRaw = fields.category.rawValue,
            district = "", address = "", phone = "", emoji = fields.emoji,
            latitude = fields.latitude, longitude = fields.longitude,
            openHour = fields.openHour, closeHour = fields.closeHour,
        )
        // id / status / todaySpecial у существующего DTO намеренно не трогаем.
        return base.copy(
            name = fields.name.trim(),
            categoryRaw = fields.category.rawValue,
            district = fields.district.trim(),
            address = fields.address.trim(),
            phone = fields.phone.trim(),
            emoji = fields.emoji,
            latitude = fields.latitude,
            longitude = fields.longitude,
            openHour = fields.openHour.coerceIn(0, 24),
            closeHour = fields.closeHour.coerceIn(0, 24),
            imageURL = fields.imageURL.trim(),
            weekHours = fields.weekHours,
            pdfMenuURL = fields.pdfMenuURL.trim(),
            whatsapp = fields.whatsapp.trim(),
            instagram = fields.instagram.trim(),
            telegram = fields.telegram.trim(),
            branches = fields.branches,
            loyaltyEnabled = fields.loyaltyEnabled,
            loyaltyGoal = fields.loyaltyGoal,
            loyaltyReward = fields.loyaltyReward.trim(),
            couponsEnabled = fields.couponsEnabled,
        )
    }

    /** Акция из формы. При правке сохраняется `id` и исходный `startDate`. */
    fun deal(existing: HostDealDTO?, fields: DealFields, now: Date, newID: () -> String) =
        HostDealDTO(
            id = existing?.id ?: newID(),
            venueID = fields.venueID,
            typeRaw = fields.type.title,
            title = fields.title.trim(),
            details = fields.details.trim(),
            emoji = fields.emoji,
            newPrice = fields.newPrice,
            discountPercent = fields.discountPercent,
            startDate = existing?.startDate ?: now,
            endDate = fields.endDate,
            // Литералы совпадают с разбором в HostDealDTO.status.
            statusRaw = if (fields.isDraft) "draft" else "active",
            // У Android-модели пока одна картинка, у iOS — галерея; берём первую.
            imageURL = fields.imageURLs.firstOrNull()?.trim() ?: "",
            // Пустые строки не сохраняем: пустой пункт условий — буллет в никуда.
            terms = fields.terms.map { it.trim() }.filter { it.isNotEmpty() },
        )
}
