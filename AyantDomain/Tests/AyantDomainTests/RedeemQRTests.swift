import XCTest
@testable import AyantDomain

/// QR списания баллов: nonce на попытку — повторный скан того же кода
/// сервер воспроизводит, а не списывает второй раз.
final class RedeemQRTests: XCTestCase {

    func testRoundTripWithNonce() {
        let nonce = RedeemQR.newNonce()
        let code = RedeemQR.code(userID: "u1", rewardID: "r1", points: 250, nonce: nonce)
        XCTAssertEqual(code, "AYANT-RDM:u1:r1:250:\(nonce)")
        let p = RedeemQR.parse(code)
        XCTAssertEqual(p?.userID, "u1")
        XCTAssertEqual(p?.rewardID, "r1")
        XCTAssertEqual(p?.points, 250)
        XCTAssertEqual(p?.nonce, nonce)
    }

    func testItemRewardCarriesZeroPoints() {
        let p = RedeemQR.parse(RedeemQR.code(userID: "u1", rewardID: "coffee", points: 0, nonce: "abcdef123456"))
        XCTAssertEqual(p?.points, 0)
        XCTAssertEqual(p?.nonce, "abcdef123456")
    }

    func testLegacyCodesStillParse() {
        let three = RedeemQR.parse("AYANT-RDM:u1:r1")
        XCTAssertEqual(three?.userID, "u1")
        XCTAssertEqual(three?.points, 0)
        XCTAssertNil(three?.nonce)
        let four = RedeemQR.parse("AYANT-RDM:u1:r1:300")
        XCTAssertEqual(four?.points, 300)
        XCTAssertNil(four?.nonce)
    }

    func testNoncesAreFreshAndValid() {
        let a = RedeemQR.newNonce(), b = RedeemQR.newNonce()
        XCTAssertNotEqual(a, b)
        XCTAssertGreaterThanOrEqual(a.count, RedeemQR.minNonceLength)
        XCTAssertTrue(RedeemQR.isValidNonce(a))
    }

    func testRejectsGarbage() {
        XCTAssertNil(RedeemQR.parse("AYANT-PTS:u1"))
        XCTAssertNil(RedeemQR.parse("AYANT-RDM:u1"))
        XCTAssertNil(RedeemQR.parse("AYANT-RDM::r1"))
        XCTAssertNil(RedeemQR.parse("AYANT-RDM:u1:r1:-5"))
        XCTAssertNil(RedeemQR.parse("AYANT-RDM:u1:r1:abc"))
        XCTAssertNil(RedeemQR.parse("AYANT-RDM:u1:r1:10:short"), "nonce короче 12 — не наш код")
        XCTAssertNil(RedeemQR.parse("AYANT-RDM:u1:r1:10:abcdef123456:extra"))
        XCTAssertNil(RedeemQR.parse("AYANT-RDM:u1:r1:10:abcdef12345ж"))
    }

    // MARK: - Токен списания (AYANT-RDT)

    func testTokenRoundTrip() {
        let token = "Ab3_-xYz0123456789AbCdEfGh"
        let code = RedeemQR.tokenCode(token)
        XCTAssertEqual(code, "AYANT-RDT:\(token)")
        XCTAssertEqual(RedeemQR.parseToken(code), token)
        XCTAssertEqual(RedeemQR.scan(code), .token(token))
        XCTAssertFalse(code.contains("u1"), "в QR нет uid")
    }

    func testTokenRejectsGarbage() {
        XCTAssertNil(RedeemQR.parseToken("AYANT-RDT:short"))
        XCTAssertNil(RedeemQR.parseToken("AYANT-RDT:" + String(repeating: "a", count: 65)))
        XCTAssertNil(RedeemQR.parseToken("AYANT-RDT:abcdefghijklmnopqrst:extra"))
        XCTAssertNil(RedeemQR.parseToken("AYANT-RDT:abcdefghijklmnopqrsж"))
        XCTAssertNil(RedeemQR.parseToken("AYANT-RDM:u1:r1"))
    }

    func testScanStillReadsLegacyCodes() {
        XCTAssertEqual(RedeemQR.scan("AYANT-RDM:u1:r1:300:abcdef123456"),
                       .legacy(userID: "u1", rewardID: "r1", points: 300, nonce: "abcdef123456"))
        XCTAssertEqual(RedeemQR.scan("AYANT-RDM:u1:r1"),
                       .legacy(userID: "u1", rewardID: "r1", points: 0, nonce: nil))
        XCTAssertNil(RedeemQR.scan("AYANT-PTS:u1"))
    }

    func testRefreshTimingAndCountdown() {
        let now = Date(timeIntervalSince1970: 1_000)
        let exp = now.addingTimeInterval(RedeemQR.tokenTTL)
        XCTAssertEqual(RedeemQR.refreshDelay(expiresAt: exp, now: now), RedeemQR.tokenTTL - RedeemQR.refreshLead)
        XCTAssertEqual(RedeemQR.refreshDelay(expiresAt: now.addingTimeInterval(5), now: now), 0,
                       "почти истёк — обновляем сразу")
        XCTAssertEqual(RedeemQR.secondsLeft(expiresAt: exp, now: now), 180)
        XCTAssertEqual(RedeemQR.secondsLeft(expiresAt: now.addingTimeInterval(-3), now: now), 0)
    }
}
