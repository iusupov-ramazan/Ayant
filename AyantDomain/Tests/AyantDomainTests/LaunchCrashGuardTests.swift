import XCTest
@testable import AyantDomain

/// Входы из чужих данных (файл меню, документ заведения), на которых раньше
/// было `!`/`Int(Double)` — то есть падение вместо «не распознано».
final class LaunchCrashGuardTests: XCTestCase {

    // MARK: Цены меню с не-ASCII цифрами

    func testNonASCIIThousandsDoNotCrashPriceParsing() {
        // Арабско-индийские цифры подходят под `\d`, но `Int(_:)` их не читает.
        XCTAssertNil(MenuPrice.numberGroup("١.٢٠٠"))
        XCTAssertNil(MenuPrice.numberGroup("١٢٠"))
        _ = MenuPrice.parse("Плов ١.٢٠٠")   // не падает
        // Обычные цены — как раньше.
        XCTAssertEqual(MenuPrice.numberGroup("1.200"), [1200])
        XCTAssertEqual(MenuPrice.numberGroup("720/1220"), [720, 1220])
    }

    // MARK: Скидка по баллам с безумным курсом

    func testSomOffClampsInsteadOfTrapping() {
        let huge = PointsReward(id: "r", type: "money", title: "Скидка", cost: Int.max, ratio: 1e300)
        XCTAssertEqual(PointsMath.somOff(reward: huge, cost: Int.max), Int.max)
        XCTAssertEqual(PointsMath.somOff(reward: huge, cost: Int.max,
                                         pointsMode: "flat", cashbackPercent: 0), Int.max)
        let normal = PointsReward(id: "r", type: "money", title: "Скидка", cost: 100, ratio: 2)
        XCTAssertEqual(PointsMath.somOff(reward: normal, cost: 100), 200)
    }

    func testClampedIntHandlesNonFinite() {
        XCTAssertEqual(PointsMath.clampedInt(.nan), 0)
        XCTAssertEqual(PointsMath.clampedInt(.infinity), Int.max)
        XCTAssertEqual(PointsMath.clampedInt(-.infinity), Int.min)
        XCTAssertEqual(PointsMath.clampedInt(42.0), 42)
    }

    func testHugeCooldownDoesNotTrap() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(PointsMath.cooldownRemainingSeconds(lastEarnAt: now, cooldownMinutes: Int.max, now: now),
                       Int.max)
    }
}
