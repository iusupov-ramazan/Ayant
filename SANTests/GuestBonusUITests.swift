import XCTest
@testable import SAN

/// Чистые правила экранов гостя вокруг баллов и бонусов.
final class GuestBonusUITests: XCTestCase {

    // MARK: Списание сотрудником (лист награды, режим staffScan)

    /// Сотрудник списал награду за 100 — лист должен показать чек на 100.
    func testDropByCostIsRedeem() {
        XCTAssertEqual(StaffRedeemWatch.observe(baseline: 250, balance: 150, minCost: 100), .redeemed(100))
    }

    /// Money-награда: списали больше минимальной цены — показываем фактически списанное.
    func testDropAboveCostReportsActualAmount() {
        XCTAssertEqual(StaffRedeemWatch.observe(baseline: 500, balance: 260, minCost: 100), .redeemed(240))
    }

    /// Сгорание пары баллов — не списание награды.
    func testSmallDropIsIgnored() {
        XCTAssertEqual(StaffRedeemWatch.observe(baseline: 250, balance: 240, minCost: 100), .none)
    }

    /// Начисление под открытым листом поднимает точку отсчёта, а не считается списанием.
    func testGrowthRebases() {
        XCTAssertEqual(StaffRedeemWatch.observe(baseline: 250, balance: 300, minCost: 100), .rebase(300))
        XCTAssertEqual(StaffRedeemWatch.observe(baseline: 300, balance: 200, minCost: 100), .redeemed(100))
    }

    /// Без точки отсчёта первый снимок — только точка отсчёта.
    func testNoBaselineIsNoEvent() {
        XCTAssertEqual(StaffRedeemWatch.observe(baseline: nil, balance: 250, minCost: 100), .none)
    }

    /// Бесплатная (cost 0) награда не превращает любое колебание в «списано».
    func testZeroCostNeedsRealDrop() {
        XCTAssertEqual(StaffRedeemWatch.observe(baseline: 10, balance: 10, minCost: 0), .none)
    }

    // MARK: Ошибки

    func testPurchaseErrorTextsAreSpecific() {
        let generic = BonusPurchaseErrorText.message("something_else")
        for code in ["app_check_failed", "key_reused", "gift_not_allowed", "unauthenticated", "no_token", "bad_token"] {
            XCTAssertNotEqual(BonusPurchaseErrorText.message(code), generic, code)
        }
    }
}
