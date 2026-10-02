import XCTest
@testable import SAN
import AyantDomain
import AyantFeatures

/// Токен списания для QR гостя (`AYANT-RDT:`, аудит запуска 2026-10-01):
/// QR несёт только одноразовый токен, а не uid; стор просит его заново при
/// смене суммы и до истечения, без сети честно падает, на сервере без
/// `issueRedeemToken` откатывается на старый QR.
@MainActor
final class RedeemTokenStoreTests: XCTestCase {

    private func token(_ id: String, ttl: TimeInterval = 180, now: Date = Date(timeIntervalSince1970: 1000)) -> RedeemToken {
        RedeemToken(token: id + String(repeating: "x", count: max(0, 24 - id.count)),
                    expiresAt: now.addingTimeInterval(ttl), cost: 50)
    }

    /// Ждёт, пока условие станет истинным (задачи стора асинхронные).
    private func wait(_ cond: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if cond() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("условие не выполнилось", file: file, line: line)
    }

    func testReadyTokenGivesTokenQRWithoutUserID() async {
        let clock = FixedClock(Date(timeIntervalSince1970: 1000))
        let store = RedeemTokenStore(clock: clock, sleep: { _ in try? await Task.sleep(nanoseconds: 10_000_000_000) }) { _, _, _ in
            self.token("tokA")
        }
        store.start(venueID: "v1", rewardID: "coffee", points: 0)
        await wait { store.qrText != nil }
        XCTAssertEqual(store.qrText, RedeemQR.tokenCode(token("tokA").token))
        XCTAssertTrue(store.qrText!.hasPrefix(RedeemQR.tokenPrefix))
        XCTAssertFalse(store.qrText!.contains("guest-uid"))
        store.stop()
        XCTAssertEqual(store.phase, .idle)
    }

    func testRefreshesBeforeExpiry() async {
        var calls = 0
        var requestedDelays: [TimeInterval] = []
        let clock = FixedClock(Date(timeIntervalSince1970: 1000))
        let store = RedeemTokenStore(clock: clock, sleep: { delay in
            requestedDelays.append(delay)
            if requestedDelays.count >= 2 { try? await Task.sleep(nanoseconds: 10_000_000_000) }
        }) { _, _, _ in
            calls += 1
            return self.token("tok\(calls)")
        }
        store.start(venueID: "v1", rewardID: "coffee", points: 0)
        await wait { calls >= 2 }
        XCTAssertEqual(requestedDelays.first, RedeemQR.tokenTTL - RedeemQR.refreshLead,
                       "новый токен — за refreshLead до истечения")
        await wait { store.qrText == RedeemQR.tokenCode(self.token("tok2").token) }
        store.stop()
    }

    func testAmountChangeRequestsNewTokenAndDropsStaleAnswer() async {
        var asked: [Int] = []
        let store = RedeemTokenStore(sleep: { _ in try? await Task.sleep(nanoseconds: 10_000_000_000) }) { _, _, points in
            asked.append(points)
            if points == 100 { try? await Task.sleep(nanoseconds: 50_000_000) }   // старый ответ опаздывает
            return self.token("p\(points)")
        }
        store.start(venueID: "v1", rewardID: "money", points: 100)
        store.start(venueID: "v1", rewardID: "money", points: 200)
        await wait { store.qrText != nil }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(store.qrText, RedeemQR.tokenCode(token("p200").token), "опоздавший ответ на 100 не перезаписал 200")
        XCTAssertTrue(asked.contains(200))
        store.stop()
    }

    func testOfflineFailsWithNetwork() async {
        let store = RedeemTokenStore { _, _, _ in throw AppError.network }
        store.start(venueID: "v1", rewardID: "coffee", points: 0)
        await wait { if case .failed = store.phase { return true }; return false }
        XCTAssertEqual(store.phase, .failed(.network))
        XCTAssertNil(store.qrText)
        XCTAssertEqual(RedeemSheet.tokenErrorText(.network),
                       LS("Нет связи — QR для списания не получить. Проверьте интернет и повторите."))
    }

    func testServerWithoutFunctionFallsBackToLegacy() async {
        let store = RedeemTokenStore { _, _, _ in throw AppError.server(code: "not_deployed") }
        store.start(venueID: "v1", rewardID: "coffee", points: 0)
        await wait { store.phase == .legacy }
        XCTAssertNil(store.qrText)
    }

    func testServerRefusalIsShown() async {
        let store = RedeemTokenStore { _, _, _ in throw AppError.server(code: "insufficient") }
        store.start(venueID: "v1", rewardID: "coffee", points: 0)
        await wait { store.phase == .failed(.server(code: "insufficient")) }
    }

    func testMockCouponServiceIssuesLocalToken() async throws {
        let t = try await MockTokenCouponService().issueRedeemToken(venueID: "v1", rewardId: "r", pointsToSpend: 0, idToken: "")
        XCTAssertTrue(RedeemQR.isValidToken(t.token))
    }
}

/// Сервис без своих реализаций токена — берёт умолчания протокола (мок-режим).
private struct MockTokenCouponService: CouponService {
    func saveCoupon(_ coupon: Coupon, userID: String) async throws {}
    func fetchGlobalRewards() async throws -> [Reward] { [] }
    func fetchCouponOffers(venueID: String) async throws -> [CouponOffer] { [] }
    func fetchApprovedCouponOffers() async throws -> [CouponOffer] { [] }
    func fetchCoupons(userID: String) async throws -> [Coupon] { [] }
    func coupons(userID: String) -> AsyncStream<[Coupon]> { AsyncStream { $0.finish() } }
    func fetchLoyaltyCards(userID: String) async throws -> [LoyaltyCard] { [] }
    func loyaltyCards(userID: String) -> AsyncStream<[LoyaltyCard]> { AsyncStream { $0.finish() } }
    func fetchVenuePoints(userID: String) async throws -> [VenuePointsCard] { [] }
    func scanCoupon(code: String, venueID: String, idToken: String, billAmount: Int?, bandIndex: Int?,
                    idempotencyKey: String, cardID: String?) async throws -> ScanOutcome {
        throw URLError(.unsupportedURL)
    }
    func redeemVenuePoints(venueID: String, userID: String, rewardId: String, pointsToSpend: Int,
                           idToken: String, idempotencyKey: String, nonce: String?) async throws -> RedeemOutcome {
        throw URLError(.unsupportedURL)
    }
}
