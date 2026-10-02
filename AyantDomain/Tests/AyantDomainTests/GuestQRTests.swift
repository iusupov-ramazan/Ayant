import XCTest
@testable import AyantDomain

/// Один QR гостя: те же четыре случая, что в `scanCoupon` (functions/test/scanCoupon.test.js).
final class GuestQRTests: XCTestCase {
    func testEarnCodeAtStampVenueBecomesCard() {
        XCTAssertEqual(GuestQR.route("AYANT-PTS:u1", venueID: "v1", pointsEnabled: false, loyaltyEnabled: true),
                       "AYANT-CARD:u1:v1")
    }

    func testCardCodeAtPointsVenueBecomesEarn() {
        XCTAssertEqual(GuestQR.route("AYANT-CARD:u1:v1", venueID: "v1", pointsEnabled: true, loyaltyEnabled: true),
                       "AYANT-PTS:u1")
    }

    func testOtherVenuesCardStaysAsIs() {
        XCTAssertEqual(GuestQR.route("AYANT-CARD:u1:v2", venueID: "v1", pointsEnabled: true, loyaltyEnabled: false),
                       "AYANT-CARD:u1:v2")
    }

    func testNoLoyaltyAndForeignCodesUntouched() {
        XCTAssertEqual(GuestQR.route("AYANT-PTS:u1", venueID: "v1", pointsEnabled: false, loyaltyEnabled: false),
                       "AYANT-PTS:u1")
        XCTAssertEqual(GuestQR.route("AYANT-RDM:u1:r1", venueID: "v1", pointsEnabled: true, loyaltyEnabled: true),
                       "AYANT-RDM:u1:r1")
        XCTAssertEqual(GuestQR.route("AYANT-ABC123", venueID: "v1", pointsEnabled: false, loyaltyEnabled: true),
                       "AYANT-ABC123")
        XCTAssertEqual(GuestQR.route("AYANT-PTS:", venueID: "v1", pointsEnabled: false, loyaltyEnabled: true),
                       "AYANT-PTS:")
    }
}
