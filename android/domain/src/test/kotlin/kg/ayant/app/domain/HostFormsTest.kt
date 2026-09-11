package kg.ayant.app.domain

import kg.ayant.app.domain.model.DealType
import kg.ayant.app.domain.model.HostDealDTO
import kg.ayant.app.domain.model.HostVenueDTO
import kg.ayant.app.domain.model.ModerationStatus
import kg.ayant.app.domain.model.VenueCategory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Date

/**
 * Сборка DTO хоста из формы. Зеркалит `DomainHostFormsTests.swift`.
 *
 * Правила «что при правке сохраняется» раньше жили прямо в Compose-форме и
 * не проверялись ничем.
 */
class HostFormsTest {

    private val now = Date(1_700_000_000_000L)

    private fun fields(name: String = "  Navat  ") = HostForms.VenueFields(
        name = name, category = VenueCategory.TEAHOUSE, district = " Центр ",
        address = " ул. Чуй 1 ", phone = " +996 ", emoji = "🫖",
        latitude = 42.87, longitude = 74.6, openHour = 9, closeHour = 22,
        imageURL = " https://img/1.jpg ", weekHours = emptyList(),
        pdfMenuURL = " https://menu.pdf ", whatsapp = " 996700 ",
        instagram = " @navat ", telegram = " @navat ", branches = emptyList(),
        loyaltyEnabled = true, loyaltyGoal = 6,
        loyaltyReward = " Чай в подарок ", couponsEnabled = true,
    )

    private fun existingVenue() = HostVenueDTO(
        id = "hv_kept", name = "Старое", categoryRaw = VenueCategory.CAFE.rawValue,
        district = "", address = "", phone = "", emoji = "🍽",
        latitude = 0.0, longitude = 0.0, openHour = 8, closeHour = 20,
        todaySpecial = "Плов дня", isPaused = false, isVerified = true,
        status = "approved",
    )

    @Test
    fun `edit keeps id, moderation and today special`() {
        val dto = HostForms.venue(existingVenue(), fields()) { "hv_new" }
        assertEquals("hv_kept", dto.id)
        // Одобренное заведение не должно молча уехать обратно на модерацию.
        assertEquals("approved", dto.status)
        assertEquals("Плов дня", dto.todaySpecial)
    }

    @Test
    fun `create uses generated id and starts pending`() {
        val dto = HostForms.venue(null, fields()) { "hv_new" }
        assertEquals("hv_new", dto.id)
        assertEquals(ModerationStatus.PENDING, dto.moderation)
        assertNull(dto.todaySpecial)
    }

    @Test
    fun `text fields are trimmed`() {
        val dto = HostForms.venue(null, fields()) { "x" }
        assertEquals("Navat", dto.name)
        assertEquals("Центр", dto.district)
        assertEquals("ул. Чуй 1", dto.address)
        assertEquals("+996", dto.phone)
        assertEquals("https://img/1.jpg", dto.imageURL)
        assertEquals("https://menu.pdf", dto.pdfMenuURL)
        assertEquals("@navat", dto.instagram)
        assertEquals("Чай в подарок", dto.loyaltyReward)
    }

    @Test
    fun `hours are clamped to a day`() {
        val dto = HostForms.venue(null, fields().copy(openHour = -3, closeHour = 99)) { "x" }
        assertEquals(0, dto.openHour)
        assertEquals(24, dto.closeHour)
    }

    private fun dealFields(isDraft: Boolean = false) = HostForms.DealFields(
        venueID = "v1", type = DealType.DISCOUNT, title = "  −20%  ",
        details = "  на всё  ", emoji = "🔥", newPrice = 200, discountPercent = 20,
        endDate = null, isDraft = isDraft,
        imageURLs = listOf(" https://img/a.jpg ", "https://img/b.jpg"),
    )

    @Test
    fun `edit keeps deal id and start date`() {
        val existing = HostDealDTO(
            id = "hd_kept", venueID = "v1", typeRaw = DealType.PROMO.title,
            title = "old", details = "", emoji = "🔥",
            startDate = Date(now.time - 86_400_000L), statusRaw = "active",
        )
        val dto = HostForms.deal(existing, dealFields(), now) { "hd_new" }
        assertEquals("hd_kept", dto.id)
        // Свежесть в ленте считается от startDate — правка не должна её обнулять.
        assertEquals(Date(now.time - 86_400_000L), dto.startDate)
    }

    @Test
    fun `create stamps start date from injected now`() {
        val dto = HostForms.deal(null, dealFields(), now) { "hd_new" }
        assertEquals("hd_new", dto.id)
        assertEquals(now, dto.startDate)
    }

    @Test
    fun `draft flag maps to status and cover is first image`() {
        val published = HostForms.deal(null, dealFields(), now) { "x" }
        assertEquals("active", published.statusRaw)
        assertEquals("https://img/a.jpg", published.imageURL)   // тримнута
        assertEquals("−20%", published.title)

        val draft = HostForms.deal(null, dealFields(isDraft = true), now) { "x" }
        assertEquals("draft", draft.statusRaw)
    }

    /** Условия: пустые строки и пробельный мусор до заведения не доезжают. */
    @Test fun `deal terms are trimmed and empties dropped`() {
        val fields = HostForms.DealFields(
            venueID = "v1", type = DealType.DISCOUNT, title = "t", details = "d",
            emoji = "🔥", newPrice = null, discountPercent = null, endDate = null,
            isDraft = false, imageURLs = emptyList(),
            terms = listOf("  Каждый день до 12:00 ", "", "   ", "Один напиток на гостя"),
        )
        val dto = HostForms.deal(null, fields, now) { "hd_1" }
        assertEquals(listOf("Каждый день до 12:00", "Один напиток на гостя"), dto.terms)
        // Условия доезжают до пользовательской модели — их читает лента.
        assertEquals(listOf("Каждый день до 12:00", "Один напиток на гостя"), dto.asDeal.terms)
    }
}
