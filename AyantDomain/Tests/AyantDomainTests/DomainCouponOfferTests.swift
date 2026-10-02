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

    /// Правка того, что модерация не проверяет (остаток, срок, лимит, пауза),
    /// не возвращает одобренный купон на модерацию — иначе добавить ещё 50
    /// штук стоило бы суток без продаж.
    func testEditKeepsIdStatusAndSoldCount() {
        let existing = HostForms.couponOffer(existing: nil, fields: fields(stock: 100), newID: "co_kept")
        var approved = existing
        approved.soldCount = 37
        approved.statusRaw = ModerationStatus.approved.rawValue
        let edited = HostForms.couponOffer(existing: approved,
                                           fields: fields(stock: 150, expiresAt: now, isPaused: true),
                                           newID: "co_new")
        XCTAssertEqual(edited.id, "co_kept")
        XCTAssertEqual(edited.status, .approved)
        XCTAssertEqual(edited.soldCount, 37, "счётчик продаж принадлежит серверу")
        XCTAssertEqual(edited.stock, 150)
    }

    /// Одобренный купон с новой ценой, названием, условиями, эмодзи или фото —
    /// уже не тот купон, который видела модерация. `firestore.rules` требует
    /// для такой правки `pending`; форма обязана поставить его сама, иначе
    /// сервер отклонит сохранение.
    func testEditingReviewedContentOfApprovedCouponSendsItBackToModeration() {
        var approved = HostForms.couponOffer(existing: nil, fields: fields(), newID: "co_1")
        approved.statusRaw = ModerationStatus.approved.rawValue
        approved.soldCount = 5

        var f = fields(cost: 700)
        XCTAssertEqual(HostForms.couponOffer(existing: approved, fields: f, newID: "x").status, .pending, "цена")
        XCTAssertEqual(HostForms.couponOffer(existing: approved, fields: f, newID: "x").cost, 700,
                       "цену заведение менять вправе")
        f = fields(); f.title = "Два капучино"
        XCTAssertEqual(HostForms.couponOffer(existing: approved, fields: f, newID: "x").status, .pending, "название")
        f = fields(); f.details = "Весь день"
        XCTAssertEqual(HostForms.couponOffer(existing: approved, fields: f, newID: "x").status, .pending, "условия")
        f = fields(); f.emoji = "🍰"
        XCTAssertEqual(HostForms.couponOffer(existing: approved, fields: f, newID: "x").status, .pending, "эмодзи")
        f = fields(); f.imageURL = "https://img/b.jpg"
        XCTAssertEqual(HostForms.couponOffer(existing: approved, fields: f, newID: "x").status, .pending, "фото")

        let edited = HostForms.couponOffer(existing: approved, fields: fields(cost: 700), newID: "x")
        XCTAssertEqual(edited.soldCount, 5, "возврат на модерацию не трогает продажи")
    }

    /// Пробелы вокруг текста формы — не правка: тримминг даёт тот же купон,
    /// и он остаётся в продаже.
    func testWhitespaceOnlyEditKeepsApproval() {
        var approved = HostForms.couponOffer(existing: nil, fields: fields(), newID: "co_1")
        approved.statusRaw = ModerationStatus.approved.rawValue
        var f = fields(); f.title = "Бесплатный капучино   "
        XCTAssertEqual(HostForms.couponOffer(existing: approved, fields: f, newID: "x").status, .approved)
    }

    /// Купон ещё на модерации или отклонён — статус не меняется: решение о нём
    /// остаётся за модерацией.
    func testEditOfPendingOrRejectedCouponKeepsStatus() {
        for status in [ModerationStatus.pending, .rejected] {
            var offer = HostForms.couponOffer(existing: nil, fields: fields(), newID: "co_1")
            offer.statusRaw = status.rawValue
            XCTAssertEqual(HostForms.couponOffer(existing: offer, fields: fields(cost: 900),
                                                 newID: "x").status, status)
        }
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

    // MARK: Какой статус уходит на сервер

    private func approvedOnServer() -> CouponOffer {
        var o = HostForms.couponOffer(existing: nil, fields: fields(stock: 100), newID: "co_1")
        o.statusRaw = ModerationStatus.approved.rawValue
        return o
    }

    func testStatusSentOnCreate() {
        let offer = HostForms.couponOffer(existing: nil, fields: fields(), newID: "co_1")
        XCTAssertEqual(HostForms.couponStatusToWrite(server: nil, edited: offer), "pending")
    }

    /// Регрессия: кэш кабинета ещё помнит `pending`, а админ уже одобрил купон.
    /// Правка остатка или паузы не должна снимать одобрение.
    func testStaleCachedPendingDoesNotUnapprove() {
        var cached = approvedOnServer()
        cached.statusRaw = ModerationStatus.pending.rawValue
        let edited = HostForms.couponOffer(existing: cached, fields: fields(stock: 50, isPaused: true),
                                           newID: "x")
        XCTAssertEqual(edited.status, .pending, "локально статус из кэша")
        XCTAssertNil(HostForms.couponStatusToWrite(server: approvedOnServer(), edited: edited),
                     "статус не отправляется — merge оставит серверный approved")
    }

    func testContentEditOfServerApprovedSendsPending() {
        var cached = approvedOnServer()
        cached.statusRaw = ModerationStatus.pending.rawValue   // даже при устаревшем кэше
        let edited = HostForms.couponOffer(existing: cached, fields: fields(cost: 900, stock: 100),
                                           newID: "x")
        XCTAssertEqual(HostForms.couponStatusToWrite(server: approvedOnServer(), edited: edited), "pending")
    }

    func testEditOfPendingOrRejectedOmitsStatus() {
        for raw in [ModerationStatus.pending.rawValue, ModerationStatus.rejected.rawValue] {
            var server = approvedOnServer()
            server.statusRaw = raw
            let edited = HostForms.couponOffer(existing: server, fields: fields(cost: 900), newID: "x")
            XCTAssertNil(HostForms.couponStatusToWrite(server: server, edited: edited), raw)
        }
    }
}
