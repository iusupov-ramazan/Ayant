import XCTest
@testable import AyantDomain

/// Курс денежной награды не обходит потолок кэшбэка 20% — то же правило, что
/// `effectiveMoneyRatio` на сервере (functions/test/points.test.js, «RDM: курс…»).
final class PointsRatioTests: XCTestCase {
    private func money(ratio: Double) -> PointsReward {
        PointsReward(id: "m", type: "money", title: "Скидка", cost: 10, ratio: ratio, active: true)
    }

    func testCashbackCapsRatio() {
        XCTAssertEqual(PointsMath.effectiveRatio(5, pointsMode: "cashback", cashbackPercent: 20), 1)
        XCTAssertEqual(PointsMath.effectiveRatio(10, pointsMode: "cashback", cashbackPercent: 5), 4)
        XCTAssertEqual(PointsMath.effectiveRatio(2, pointsMode: "cashback", cashbackPercent: 5), 2)
        XCTAssertEqual(PointsMath.somOff(reward: money(ratio: 5), cost: 100,
                                         pointsMode: "cashback", cashbackPercent: 20), 100)
    }

    func testFlatAndBandsNotCapped() {
        XCTAssertEqual(PointsMath.effectiveRatio(10, pointsMode: "flat", cashbackPercent: 0), 10)
        XCTAssertEqual(PointsMath.effectiveRatio(10, pointsMode: "bands", cashbackPercent: 20), 10)
    }

    func testHostFormClampsRatioOnSave() {
        let dto = HostVenueDTO(id: "v1", name: "Кафе", categoryRaw: "cafe", district: "", address: "",
                               phone: "", emoji: "☕", latitude: 0, longitude: 0, openHour: 9, closeHour: 22,
                               todaySpecial: nil, isPaused: false, isVerified: false)
        let fields = HostForms.PointsFields(
            pointsEnabled: true, pointsMode: "cashback", pointsFlat: 0, pointsBands: [],
            cashbackPercent: 20, pointsRewards: [money(ratio: 5)],
            pointsExpiryMonths: 6, redeemMode: "staffScan", earnCooldownMinutes: 60)
        let out = HostForms.applyPoints(to: dto, fields: fields)
        XCTAssertEqual(out.pointsRewards.first?.ratio, 1)
    }
}
