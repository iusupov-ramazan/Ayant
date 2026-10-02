import XCTest
@testable import AyantDomain

/// Акция из формы: дата окончания и статус при правке.
final class DomainHostFormsDealTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func fields(endDate: Date?, isDraft: Bool = false) -> HostForms.DealFields {
        HostForms.DealFields(venueID: "v1", type: .discount, title: "−20%", details: "",
                             emoji: "🔥", newPrice: nil, discountPercent: 20,
                             endDate: endDate, isDraft: isDraft, imageURLs: [])
    }

    private func existing(_ status: DealStatus, endDate: Date? = nil) -> HostDealDTO {
        HostDealDTO(id: "hd_1", venueID: "v1", typeRaw: DealType.discount.rawValue,
                    title: "old", details: "", emoji: "🔥",
                    startDate: now.addingTimeInterval(-86_400), endDate: endDate,
                    statusRaw: status.rawValue)
    }

    private var bishkek: Calendar { City.calendar(forSlug: City.bishkek.id) }

    // MARK: Дата окончания

    func testEndDateIsEndOfPickedDayInCityZone() {
        // Форму открыли 5 октября в 14:20 по Бишкеку и выбрали 5 октября.
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 5; c.hour = 14; c.minute = 20
        let picked = bishkek.date(from: c)!
        let dto = HostForms.deal(existing: nil, fields: fields(endDate: picked), now: now,
                                 pickerCalendar: bishkek, newID: "hd_new")
        let end = bishkek.dateComponents([.year, .month, .day, .hour, .minute, .second], from: dto.endDate!)
        XCTAssertEqual([end.year, end.month, end.day, end.hour, end.minute, end.second],
                       [2026, 10, 5, 23, 59, 59])
    }

    func testPickedDayComesFromThePhoneCalendar() {
        // Телефон в Москве (UTC+3): выбран 5 октября 23:30 по Москве — это уже
        // 6-е в Бишкеке, но хозяин выбирал 5-е.
        var moscow = Calendar(identifier: .gregorian)
        moscow.timeZone = TimeZone(identifier: "Europe/Moscow")!
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 5; c.hour = 23; c.minute = 30
        let picked = moscow.date(from: c)!
        let dto = HostForms.deal(existing: nil, fields: fields(endDate: picked), now: now,
                                 pickerCalendar: moscow, newID: "hd_new")
        XCTAssertEqual(bishkek.component(.day, from: dto.endDate!), 5)
        XCTAssertEqual(bishkek.component(.hour, from: dto.endDate!), 23)
    }

    func testUntouchedEndDateIsKeptOnEdit() {
        let stored = Date(timeIntervalSince1970: 1_790_100_000)
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Pacific/Auckland")!
        let dto = HostForms.deal(existing: existing(.active, endDate: stored),
                                 fields: fields(endDate: stored), now: now,
                                 pickerCalendar: tokyo, newID: "x")
        XCTAssertEqual(dto.endDate, stored)
    }

    func testNoEndDateStaysNil() {
        let dto = HostForms.deal(existing: nil, fields: fields(endDate: nil), now: now, newID: "x")
        XCTAssertNil(dto.endDate)
    }

    // MARK: Статус

    func testEditingPausedDealKeepsItPaused() {
        let dto = HostForms.deal(existing: existing(.paused), fields: fields(endDate: nil),
                                 now: now, newID: "x")
        XCTAssertEqual(dto.status, .paused)
    }

    func testDraftToggleStillWins() {
        let toDraft = HostForms.deal(existing: existing(.paused), fields: fields(endDate: nil, isDraft: true),
                                     now: now, newID: "x")
        XCTAssertEqual(toDraft.status, .draft)
        let published = HostForms.deal(existing: existing(.draft), fields: fields(endDate: nil),
                                       now: now, newID: "x")
        XCTAssertEqual(published.status, .active)
    }

    func testActiveAndExpiredBecomeActive() {
        XCTAssertEqual(HostForms.deal(existing: existing(.active), fields: fields(endDate: nil),
                                      now: now, newID: "x").status, .active)
        XCTAssertEqual(HostForms.deal(existing: existing(.expired), fields: fields(endDate: nil),
                                      now: now, newID: "x").status, .active)
        XCTAssertEqual(HostForms.deal(existing: nil, fields: fields(endDate: nil),
                                      now: now, newID: "x").status, .active)
    }
}
