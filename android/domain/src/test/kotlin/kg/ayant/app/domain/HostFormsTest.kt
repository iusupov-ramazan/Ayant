package kg.ayant.app.domain

import kg.ayant.app.domain.model.DealType
import kg.ayant.app.domain.model.HostDealDTO
import kg.ayant.app.domain.model.HostVenueDTO
import kg.ayant.app.domain.model.Branch
import kg.ayant.app.domain.model.ModerationStatus
import kg.ayant.app.domain.model.PointsBand
import kg.ayant.app.domain.model.PointsReward
import kg.ayant.app.domain.model.VenueCategory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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

    // MARK: Баллы САН

    private fun pointsFields(
        enabled: Boolean = true, mode: String = "cashback", flat: Int = 50,
        bands: List<PointsBand> = emptyList(), cashback: Double = 10.0,
        rewards: List<PointsReward> = emptyList(), expiry: Int = 6,
        redeemMode: String = "staffScan", cooldown: Int = 60,
    ) = HostForms.PointsFields(
        pointsEnabled = enabled, pointsMode = mode, pointsFlat = flat,
        pointsBands = bands, cashbackPercent = cashback,
        pointsRewards = rewards, pointsExpiryMonths = expiry,
        redeemMode = redeemMode, earnCooldownMinutes = cooldown,
    )

    @Test
    fun `applyPoints writes fields and leaves the rest alone`() {
        val existing = existingVenue().copy(
            loyaltyEnabled = true, loyaltyGoal = 8, loyaltyReward = "Чай",
            isPaused = true,
            branches = listOf(Branch("b1", "ул. Южная 1", 42.8, 74.6)),
        )
        val reward = PointsReward(id = "rw_1", type = "item", title = "Кофе", cost = 100)
        val dto = HostForms.applyPoints(existing, pointsFields(
            bands = listOf(PointsBand(500, 10)), rewards = listOf(reward),
        ))

        assertTrue(dto.pointsEnabled)
        assertEquals("cashback", dto.pointsMode)
        assertEquals(50, dto.pointsFlat)
        assertEquals(10.0, dto.cashbackPercent, 0.0)
        assertEquals(listOf(PointsBand(500, 10)), dto.pointsBands)
        assertEquals(listOf(reward), dto.pointsRewards)
        assertEquals(6, dto.pointsExpiryMonths)
        assertEquals("staffScan", dto.redeemMode)
        assertEquals(60, dto.earnCooldownMinutes)

        // Правка баллов — не правка заведения: всё остальное нетронуто.
        assertEquals("hv_kept", dto.id)
        assertEquals("approved", dto.status)
        assertEquals("Плов дня", dto.todaySpecial)
        assertTrue(dto.loyaltyEnabled)
        assertEquals(8, dto.loyaltyGoal)
        assertEquals("Чай", dto.loyaltyReward)
        assertTrue(dto.isPaused)
        assertTrue(dto.isVerified)
        assertEquals(1, dto.branches.size)
    }

    @Test
    fun `applyPoints clamps to server guardrails`() {
        val dto = HostForms.applyPoints(existingVenue(), pointsFields(
            flat = 50_000, cashback = 55.0, expiry = 99, cooldown = 100_000,
        ))
        assertEquals(10_000, dto.pointsFlat)
        assertEquals(20.0, dto.cashbackPercent, 0.0)
        assertEquals(24, dto.pointsExpiryMonths)
        assertEquals(1440, dto.earnCooldownMinutes)

        val low = HostForms.applyPoints(existingVenue(), pointsFields(
            flat = -5, cashback = -3.0, expiry = 0, cooldown = -10,
        ))
        assertEquals(0, low.pointsFlat)
        assertEquals(0.0, low.cashbackPercent, 0.0)
        // 0 месяцев — не значение (пол 1), а 0 минут — легальное «без паузы».
        assertEquals(1, low.pointsExpiryMonths)
        assertEquals(0, low.earnCooldownMinutes)

        val nan = HostForms.applyPoints(existingVenue(), pointsFields(cashback = Double.NaN))
        assertEquals(0.0, nan.cashbackPercent, 0.0)
    }

    @Test
    fun `applyPoints falls back on unknown modes`() {
        val dto = HostForms.applyPoints(existingVenue(), pointsFields(
            mode = "lottery", redeemMode = "magic",
        ))
        assertEquals("flat", dto.pointsMode)
        assertEquals("staffScan", dto.redeemMode)

        val ok = HostForms.applyPoints(existingVenue(), pointsFields(
            mode = "bands", redeemMode = "customerInitiated",
        ))
        assertEquals("bands", ok.pointsMode)
        assertEquals("customerInitiated", ok.redeemMode)
    }

    /**
     * Сервер выбирает диапазон по индексу — порядок должен быть по возрастанию
     * суммы, а два диапазона с одной границей неразличимы.
     */
    @Test
    fun `applyPoints sorts bands, drops duplicates and clamps points`() {
        val dto = HostForms.applyPoints(existingVenue(), pointsFields(
            mode = "bands",
            bands = listOf(
                PointsBand(1000, 20),
                PointsBand(300, 99_999),
                PointsBand(1000, 7),      // дубль → отброшен
                PointsBand(-50, -1),
            ),
        ))
        assertEquals(
            listOf(PointsBand(0, 0), PointsBand(300, 10_000), PointsBand(1000, 20)),
            dto.pointsBands,
        )
    }

    @Test
    fun `applyPoints cleans rewards`() {
        val rewards = listOf(
            PointsReward(id = "a", type = "item", title = "  Кофе  ", cost = 0),
            PointsReward(id = "b", type = "money", title = "Скидка", cost = 50, ratio = 0.2),
            PointsReward(id = "c", type = "item", title = "   ", cost = 100),       // без названия → удалена
            PointsReward(id = "d", type = "voucher", title = "Десерт", cost = 30, ratio = 0.5, active = false),
        )
        val dto = HostForms.applyPoints(existingVenue(), pointsFields(rewards = rewards))
        assertEquals(listOf("a", "b", "d"), dto.pointsRewards.map { it.id })
        assertEquals("Кофе", dto.pointsRewards[0].title)
        assertEquals(1, dto.pointsRewards[0].cost)
        // money: коэффициент не ниже 1 — балл не может стоить дешевле сома.
        assertEquals(1.0, dto.pointsRewards[1].ratio, 0.0)
        // Неизвестный тип → item; коэффициент у item не трогаем; active сохраняется.
        assertEquals("item", dto.pointsRewards[2].type)
        assertEquals(0.5, dto.pointsRewards[2].ratio, 0.0)
        assertFalse(dto.pointsRewards[2].active)
    }

    @Test
    fun `points fields round trip through DTO`() {
        val existing = existingVenue().copy(
            pointsEnabled = true, pointsMode = "bands",
            pointsBands = listOf(PointsBand(500, 5)),
            cashbackPercent = 7.0, pointsExpiryMonths = 12,
            redeemMode = "customerInitiated", earnCooldownMinutes = 0,
        )
        val fields = HostForms.pointsFields(existing)
        assertEquals(existing, HostForms.applyPoints(existing, fields))
    }

    // MARK: Акция

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
