import XCTest
@testable import AyantDomain

/// Сборка DTO хоста из формы. Правила «что при правке сохраняется» раньше жили
/// внутри стора вперемешку с записью в кэш и не проверялись ничем.
final class DomainHostFormsTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func fields(name: String = "  Navat  ") -> HostForms.VenueFields {
        HostForms.VenueFields(
            name: name, category: .teahouse, district: " Центр ", address: " ул. Чуй 1 ",
            phone: " +996 ", emoji: "🫖", latitude: 42.87, longitude: 74.6,
            openHour: 9, closeHour: 22, imageURL: " https://img/1.jpg ",
            weekHours: [], pdfMenuURL: " https://menu.pdf ",
            whatsapp: " 996700 ", instagram: " @navat ", telegram: " @navat ",
            branches: [], loyaltyEnabled: true, loyaltyGoal: 6,
            loyaltyReward: " Чай в подарок ", couponsEnabled: true)
    }

    private func existingVenue() -> HostVenueDTO {
        HostVenueDTO(id: "hv_kept", name: "Старое", categoryRaw: VenueCategory.cafe.rawValue,
                     district: "", address: "", phone: "", emoji: "🍽",
                     latitude: 0, longitude: 0, openHour: 8, closeHour: 20,
                     todaySpecial: "Плов дня", isPaused: false, isVerified: true,
                     status: ModerationStatus.approved.rawValue)
    }

    // MARK: Заведение

    func testEditKeepsIDModerationAndTodaySpecial() {
        let dto = HostForms.venue(existing: existingVenue(), fields: fields(), newID: "hv_new")
        XCTAssertEqual(dto.id, "hv_kept")
        // Одобренное заведение не должно молча уехать обратно на модерацию.
        XCTAssertEqual(dto.status, ModerationStatus.approved.rawValue)
        XCTAssertEqual(dto.todaySpecial, "Плов дня")
    }

    func testCreateUsesGeneratedIDAndStartsPending() {
        let dto = HostForms.venue(existing: nil, fields: fields(), newID: "hv_new")
        XCTAssertEqual(dto.id, "hv_new")
        XCTAssertEqual(dto.status, ModerationStatus.pending.rawValue)
        XCTAssertNil(dto.todaySpecial)
    }

    func testTextFieldsAreTrimmed() {
        let dto = HostForms.venue(existing: nil, fields: fields(), newID: "x")
        XCTAssertEqual(dto.name, "Navat")
        XCTAssertEqual(dto.district, "Центр")
        XCTAssertEqual(dto.address, "ул. Чуй 1")
        XCTAssertEqual(dto.phone, "+996")
        XCTAssertEqual(dto.imageURL, "https://img/1.jpg")
        XCTAssertEqual(dto.pdfMenuURL, "https://menu.pdf")
        XCTAssertEqual(dto.instagram, "@navat")
        XCTAssertEqual(dto.loyaltyReward, "Чай в подарок")
    }

    func testHoursAreClampedToADay() {
        var f = fields()
        f.openHour = -3; f.closeHour = 99
        let dto = HostForms.venue(existing: nil, fields: f, newID: "x")
        XCTAssertEqual(dto.openHour, 0)
        XCTAssertEqual(dto.closeHour, 24)
    }

    // MARK: Баллы САН

    private func pointsFields(
        enabled: Bool = true, mode: String = "cashback", flat: Int = 50,
        bands: [PointsBand] = [], cashback: Double = 10,
        rewards: [PointsReward] = [], expiry: Int = 6,
        redeemMode: String = "staffScan", cooldown: Int = 60
    ) -> HostForms.PointsFields {
        HostForms.PointsFields(pointsEnabled: enabled, pointsMode: mode, pointsFlat: flat,
                               pointsBands: bands, cashbackPercent: cashback,
                               pointsRewards: rewards, pointsExpiryMonths: expiry,
                               redeemMode: redeemMode, earnCooldownMinutes: cooldown)
    }

    func testApplyPointsWritesFieldsAndLeavesTheRestAlone() {
        var existing = existingVenue()
        existing.loyaltyEnabled = true; existing.loyaltyGoal = 8; existing.loyaltyReward = "Чай"
        existing.isPaused = true; existing.branches = [Branch(id: "b1", address: "ул. Южная 1", latitude: 42.8, longitude: 74.6)]
        let reward = PointsReward(id: "rw_1", type: "item", title: "Кофе", cost: 100)
        let dto = HostForms.applyPoints(to: existing, fields: pointsFields(
            bands: [PointsBand(maxAmount: 500, points: 10)], rewards: [reward]))

        XCTAssertTrue(dto.pointsEnabled)
        XCTAssertEqual(dto.pointsMode, "cashback")
        XCTAssertEqual(dto.pointsFlat, 50)
        XCTAssertEqual(dto.cashbackPercent, 10)
        XCTAssertEqual(dto.pointsBands, [PointsBand(maxAmount: 500, points: 10)])
        XCTAssertEqual(dto.pointsRewards, [reward])
        XCTAssertEqual(dto.pointsExpiryMonths, 6)
        XCTAssertEqual(dto.redeemMode, "staffScan")
        XCTAssertEqual(dto.earnCooldownMinutes, 60)

        // Правка баллов — не правка заведения: всё остальное нетронуто.
        XCTAssertEqual(dto.id, "hv_kept")
        XCTAssertEqual(dto.status, ModerationStatus.approved.rawValue)
        XCTAssertEqual(dto.todaySpecial, "Плов дня")
        XCTAssertTrue(dto.loyaltyEnabled)
        XCTAssertEqual(dto.loyaltyGoal, 8)
        XCTAssertEqual(dto.loyaltyReward, "Чай")
        XCTAssertTrue(dto.isPaused)
        XCTAssertTrue(dto.isVerified)
        XCTAssertEqual(dto.branches.count, 1)
    }

    func testApplyPointsClampsToServerGuardrails() {
        let dto = HostForms.applyPoints(to: existingVenue(), fields: pointsFields(
            flat: 50_000, cashback: 55, expiry: 99, cooldown: 100_000))
        XCTAssertEqual(dto.pointsFlat, 10_000)
        XCTAssertEqual(dto.cashbackPercent, 20)
        XCTAssertEqual(dto.pointsExpiryMonths, 24)
        XCTAssertEqual(dto.earnCooldownMinutes, 1440)

        let low = HostForms.applyPoints(to: existingVenue(), fields: pointsFields(
            flat: -5, cashback: -3, expiry: 0, cooldown: -10))
        XCTAssertEqual(low.pointsFlat, 0)
        XCTAssertEqual(low.cashbackPercent, 0)
        // 0 месяцев — не значение (пол 1), а 0 минут — легальное «без паузы».
        XCTAssertEqual(low.pointsExpiryMonths, 1)
        XCTAssertEqual(low.earnCooldownMinutes, 0)

        let nan = HostForms.applyPoints(to: existingVenue(), fields: pointsFields(cashback: .nan))
        XCTAssertEqual(nan.cashbackPercent, 0)
    }

    func testApplyPointsFallsBackOnUnknownModes() {
        let dto = HostForms.applyPoints(to: existingVenue(), fields: pointsFields(
            mode: "lottery", redeemMode: "magic"))
        XCTAssertEqual(dto.pointsMode, "flat")
        XCTAssertEqual(dto.redeemMode, "staffScan")

        let ok = HostForms.applyPoints(to: existingVenue(), fields: pointsFields(
            mode: "bands", redeemMode: "customerInitiated"))
        XCTAssertEqual(ok.pointsMode, "bands")
        XCTAssertEqual(ok.redeemMode, "customerInitiated")
    }

    /// Сервер выбирает диапазон по индексу — порядок должен быть по возрастанию
    /// суммы, а два диапазона с одной границей неразличимы.
    func testApplyPointsSortsBandsDropsDuplicatesAndClampsPoints() {
        let dto = HostForms.applyPoints(to: existingVenue(), fields: pointsFields(
            mode: "bands",
            bands: [PointsBand(maxAmount: 1000, points: 20),
                    PointsBand(maxAmount: 300, points: 99_999),
                    PointsBand(maxAmount: 1000, points: 7),      // дубль → отброшен
                    PointsBand(maxAmount: -50, points: -1)]))
        XCTAssertEqual(dto.pointsBands, [
            PointsBand(maxAmount: 0, points: 0),
            PointsBand(maxAmount: 300, points: 10_000),
            PointsBand(maxAmount: 1000, points: 20),
        ])
    }

    func testApplyPointsCleansRewards() {
        let rewards = [
            PointsReward(id: "a", type: "item", title: "  Кофе  ", cost: 0),
            PointsReward(id: "b", type: "money", title: "Скидка", cost: 50, ratio: 0.2),
            PointsReward(id: "c", type: "item", title: "   ", cost: 100),       // без названия → удалена
            PointsReward(id: "d", type: "voucher", title: "Десерт", cost: 30, ratio: 0.5, active: false),
        ]
        let dto = HostForms.applyPoints(to: existingVenue(), fields: pointsFields(rewards: rewards))
        XCTAssertEqual(dto.pointsRewards.map(\.id), ["a", "b", "d"])
        XCTAssertEqual(dto.pointsRewards[0].title, "Кофе")
        XCTAssertEqual(dto.pointsRewards[0].cost, 1)
        // money: коэффициент не ниже 1 — балл не может стоить дешевле сома.
        XCTAssertEqual(dto.pointsRewards[1].ratio, 1)
        // Неизвестный тип → item; коэффициент у item не трогаем; active сохраняется.
        XCTAssertEqual(dto.pointsRewards[2].type, "item")
        XCTAssertEqual(dto.pointsRewards[2].ratio, 0.5)
        XCTAssertFalse(dto.pointsRewards[2].active)
    }

    func testPointsFieldsRoundTripThroughDTO() {
        var existing = existingVenue()
        existing.pointsEnabled = true; existing.pointsMode = "bands"
        existing.pointsBands = [PointsBand(maxAmount: 500, points: 5)]
        existing.cashbackPercent = 7; existing.pointsExpiryMonths = 12
        existing.redeemMode = "customerInitiated"; existing.earnCooldownMinutes = 0
        let fields = HostForms.pointsFields(from: existing)
        XCTAssertEqual(HostForms.applyPoints(to: existing, fields: fields), existing)
    }

    // MARK: Акция

    private func dealFields(isDraft: Bool = false) -> HostForms.DealFields {
        HostForms.DealFields(venueID: "v1", type: .discount, title: "  −20%  ",
                             details: "  на всё  ", emoji: "🔥", newPrice: 200,
                             discountPercent: 20, endDate: nil, isDraft: isDraft,
                             imageURLs: [" https://img/a.jpg ", "https://img/b.jpg"])
    }

    /// Условия: пустые строки и пробельный мусор до заведения не доезжают.
    func testDealTermsAreTrimmedAndEmptiesDropped() {
        let fields = HostForms.DealFields(
            venueID: "v1", type: .discount, title: "t", details: "d", emoji: "🔥",
            newPrice: nil, discountPercent: nil, endDate: nil, isDraft: false,
            imageURLs: [],
            terms: ["  Каждый день до 12:00 ", "", "   ", "Один напиток на гостя"])
        let dto = HostForms.deal(existing: nil, fields: fields, now: now, newID: "hd_1")
        XCTAssertEqual(dto.terms, ["Каждый день до 12:00", "Один напиток на гостя"])
        // Условия доезжают до пользовательской модели — их читает лента.
        XCTAssertEqual(dto.asDeal.terms, ["Каждый день до 12:00", "Один напиток на гостя"])
    }

    func testEditKeepsDealIDAndStartDate() {
        let existing = HostDealDTO(id: "hd_kept", venueID: "v1", typeRaw: DealType.promo.rawValue,
                                   title: "old", details: "", emoji: "🔥",
                                   startDate: now.addingTimeInterval(-86_400),
                                   statusRaw: DealStatus.active.rawValue)
        let dto = HostForms.deal(existing: existing, fields: dealFields(),
                                 now: now, newID: "hd_new")
        XCTAssertEqual(dto.id, "hd_kept")
        // Свежесть в ленте считается от startDate — правка не должна её обнулять.
        XCTAssertEqual(dto.startDate, now.addingTimeInterval(-86_400))
    }

    func testCreateStampsStartDateFromInjectedNow() {
        let dto = HostForms.deal(existing: nil, fields: dealFields(), now: now, newID: "hd_new")
        XCTAssertEqual(dto.id, "hd_new")
        XCTAssertEqual(dto.startDate, now)
    }

    func testDraftFlagMapsToStatusAndCoverIsFirstImage() {
        let published = HostForms.deal(existing: nil, fields: dealFields(), now: now, newID: "x")
        XCTAssertEqual(published.statusRaw, DealStatus.active.rawValue)
        XCTAssertEqual(published.imageURL, "https://img/a.jpg")   // тримнута
        XCTAssertEqual(published.title, "−20%")

        let draft = HostForms.deal(existing: nil, fields: dealFields(isDraft: true),
                                   now: now, newID: "x")
        XCTAssertEqual(draft.statusRaw, DealStatus.draft.rawValue)
    }
}
