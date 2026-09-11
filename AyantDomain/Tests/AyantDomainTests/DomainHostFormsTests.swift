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
