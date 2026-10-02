import XCTest
@testable import AyantDomain

/// Курс из консоли и выплата «пакетами»: то, что раньше могло уронить
/// приложение или заплатить дважды.
final class GameRatesSafetyTests: XCTestCase {

    /// `Int(1e30)` падает, а активированный конфиг лежит на диске — значит,
    /// падение на каждом запуске. Огромное значение прижимается к границе.
    func testHugeConsoleValuesAreClampedNotCrashing() {
        let huge: [String: Double] = Dictionary(uniqueKeysWithValues: GameRates.Key.all.map { ($0, 1e30) })
        let r = GameRates.resolve(huge)
        XCTAssertEqual(r.applesPerBonus, 1000)
        XCTAssertEqual(r.linesPerBonus, 1000)
        XCTAssertEqual(r.matchesPerBonus, 1000)
        XCTAssertEqual(r.timeGoalMinutes, 240)
        XCTAssertEqual(r.timeRewardPerGoal, 100)
        XCTAssertEqual(r.timeGoalsPerDay, 24)
        XCTAssertEqual(r.minutesPerBonus, 60)
        XCTAssertEqual(r.game2048FirstTile, Game2048.bonusFromValue, "мусорная плитка — дефолт")
        let max = GameRates.resolve([GameRates.Key.timeRewardPerGoal: Double.greatestFiniteMagnitude])
        XCTAssertEqual(max.timeRewardPerGoal, 100)
    }

    func testBatchPayoutPaysOnlyNewFullBatches() {
        XCTAssertEqual(BatchPayout.newBonuses(units: 11, unitsPerBonus: 12, alreadyCredited: 0), 0)
        XCTAssertEqual(BatchPayout.newBonuses(units: 12, unitsPerBonus: 12, alreadyCredited: 0), 1)
        XCTAssertEqual(BatchPayout.newBonuses(units: 25, unitsPerBonus: 12, alreadyCredited: 1), 1)
        XCTAssertEqual(BatchPayout.newBonuses(units: 25, unitsPerBonus: 12, alreadyCredited: 2), 0,
                       "тот же счёт второй раз (game over после счёта) — без двойной выплаты")
        XCTAssertEqual(BatchPayout.newBonuses(units: 5, unitsPerBonus: 12, alreadyCredited: 3), 0,
                       "счёт меньше выплаченного — ничего не забираем и не платим")
        XCTAssertEqual(BatchPayout.newBonuses(units: 7, unitsPerBonus: 0, alreadyCredited: 0), 7,
                       "цена 0 не делит на ноль: как 1")
        XCTAssertEqual(BatchPayout.newBonuses(units: -3, unitsPerBonus: 12, alreadyCredited: 0), 0)
        XCTAssertEqual(BatchPayout.fullBatches(units: 37, unitsPerBonus: 12), 3)
    }
}
