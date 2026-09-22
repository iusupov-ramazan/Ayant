import XCTest
@testable import AyantDomain

/// Купон заведения: правила формы и доступность к покупке.
///
/// Здесь закреплено то, что стоит денег заведению, если сломается: цена,
/// остаток и счётчик продаж. Всё остальное в купоне — текст.
final class DomainCouponOfferTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fields(cost: Int = 500, stock: Int? = nil,
                        expiresAt: Date? = nil, isPaused: Bool = false) -> HostForms.CouponFields {
        HostForms.CouponFields(venueID: "v1", venueName: "  Кафе  ",
                               title: "  Бесплатный капучино  ",
                               details: "  Только до 12:00  ",
                               emoji: "☕️", imageURL: " https://img/a.jpg ",
                               cost: cost, stock: stock, expiresAt: expiresAt, isPaused: isPaused)
    }

    // MARK: Форма

    func testCreateTrimsTextAndStartsOnModeration() {
        let offer = HostForms.couponOffer(existing: nil, fields: fields(), newID: "co_1")
        XCTAssertEqual(offer.id, "co_1")
        XCTAssertEqual(offer.title, "Бесплатный капучино")
        XCTAssertEqual(offer.details, "Только до 12:00")
        XCTAssertEqual(offer.venueName, "Кафе")
        XCTAssertEqual(offer.imageURL, "https://img/a.jpg")
        XCTAssertEqual(offer.status, .pending, "новый купон проходит модерацию")
        XCTAssertEqual(offer.soldCount, 0)
    }

    /// Бесплатный купон — это снова раздача всем подряд, от которой уходили.
    func testCostIsClampedToMinimum() {
        XCTAssertEqual(HostForms.couponOffer(existing: nil, fields: fields(cost: 0),
                                             newID: "x").cost, HostForms.minCouponCost)
        XCTAssertEqual(HostForms.couponOffer(existing: nil, fields: fields(cost: -50),
                                             newID: "x").cost, HostForms.minCouponCost)
    }

    /// Правка текста не должна возвращать одобренный купон на модерацию —
    /// иначе исправленная опечатка снимает его с продажи на сутки.
    func testEditKeepsIdStatusAndSoldCount() {
        let existing = CouponOffer(id: "co_kept", venueID: "v1", venueName: "Кафе",
                                   title: "Старое", cost: 500, stock: 100, soldCount: 37,
                                   statusRaw: ModerationStatus.approved.rawValue)
        let edited = HostForms.couponOffer(existing: existing, fields: fields(cost: 700, stock: 100),
                                           newID: "co_new")
        XCTAssertEqual(edited.id, "co_kept")
        XCTAssertEqual(edited.status, .approved)
        XCTAssertEqual(edited.soldCount, 37, "счётчик продаж принадлежит серверу")
        XCTAssertEqual(edited.cost, 700, "цену заведение менять вправе")
    }

    /// Остаток ниже проданного сделал бы `remaining` отрицательным, а отчёты —
    /// противоречивыми: «продано 37 из 10».
    func testStockCannotDropBelowSold() {
        let existing = CouponOffer(id: "co_1", venueID: "v1", venueName: "Кафе",
                                   title: "t", cost: 500, stock: 100, soldCount: 37)
        let edited = HostForms.couponOffer(existing: existing, fields: fields(stock: 10), newID: "x")
        XCTAssertEqual(edited.stock, 37)
        XCTAssertEqual(edited.remaining, 0)
    }

    func testUnlimitedStockStaysUnlimited() {
        let offer = HostForms.couponOffer(existing: nil, fields: fields(stock: nil), newID: "x")
        XCTAssertNil(offer.stock)
        XCTAssertNil(offer.remaining)
        XCTAssertFalse(offer.isSoldOut)
    }

    // MARK: Доступность

    func testAvailableOnlyWhenApprovedActiveInStockAndFresh() {
        let base = CouponOffer(id: "co_1", venueID: "v1", venueName: "Кафе", title: "t",
                               cost: 500, stock: 10, soldCount: 0,
                               expiresAt: now.addingTimeInterval(86_400),
                               statusRaw: ModerationStatus.approved.rawValue)
        XCTAssertTrue(base.isAvailable(at: now))

        var pending = base; pending.statusRaw = ModerationStatus.pending.rawValue
        XCTAssertFalse(pending.isAvailable(at: now), "немодерированный купон не продаём")

        var paused = base; paused.isPaused = true
        XCTAssertFalse(paused.isAvailable(at: now), "заведение сняло с продажи")

        var soldOut = base; soldOut.soldCount = 10
        XCTAssertFalse(soldOut.isAvailable(at: now), "остаток кончился")

        var expired = base; expired.expiresAt = now.addingTimeInterval(-1)
        XCTAssertFalse(expired.isAvailable(at: now), "срок вышел")
    }

    func testNoExpiryMeansNeverExpires() {
        let offer = CouponOffer(id: "co_1", venueID: "v1", venueName: "Кафе", title: "t",
                                cost: 500, statusRaw: ModerationStatus.approved.rawValue)
        XCTAssertFalse(offer.isExpired(at: now.addingTimeInterval(10 * 365 * 86_400)))
        XCTAssertTrue(offer.isAvailable(at: now))
    }

    /// Терпимое чтение кэша: запись, сделанная до появления полей.
    func testDecodesLegacyCacheWithoutNewFields() throws {
        let json = #"{"id":"co_1","venueID":"v1","title":"Старый купон"}"#
        let offer = try JSONDecoder().decode(CouponOffer.self, from: Data(json.utf8))
        XCTAssertEqual(offer.title, "Старый купон")
        XCTAssertEqual(offer.cost, 0)
        XCTAssertEqual(offer.status, .pending)
        XCTAssertEqual(offer.citySlug, City.bishkek.id)
    }
}
