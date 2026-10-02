import XCTest
@testable import AyantDomain

/// Курс игр из Remote Config: правило «0/мусор/нет ключа — как собрано» и
/// границы, которые не дают опечатке в консоли раздать бонусы даром.
final class GameRatesTests: XCTestCase {
    typealias K = GameRates.Key

    func testEmptyConsoleIsBuiltInEconomy() {
        let r = GameRates.resolve([:])
        XCTAssertEqual(r, .defaults)
        XCTAssertEqual(r.applesPerBonus, GameEconomy.applesPerBonus)
        XCTAssertEqual(r.linesPerBonus, Tetris.linesPerBonus)
        XCTAssertEqual(r.matchesPerBonus, Match3.matchesPerBonus)
        XCTAssertEqual(r.game2048FirstTile, Game2048.bonusFromValue)
        XCTAssertEqual(r.timeGoalSeconds, 30 * 60)
        XCTAssertEqual(r.timeDailyMax, 4)
    }

    func testAnchorMovesAllLinearGamesTogether() {
        let r = GameRates.resolve([K.minutesPerBonus: 2])
        XCTAssertEqual(r.applesPerBonus, Int((GameEconomy.applesPerMinute * 2).rounded()))
        XCTAssertEqual(r.linesPerBonus, Int((GameEconomy.linesPerMinute * 2).rounded()))
        XCTAssertEqual(r.matchesPerBonus, Int((GameEconomy.matchesPerMinute * 2).rounded()))
    }

    func testDirectPriceOverridesAnchor() {
        let r = GameRates.resolve([K.minutesPerBonus: 2, K.applesPerBonus: 7])
        XCTAssertEqual(r.applesPerBonus, 7)
        XCTAssertEqual(r.linesPerBonus, Int((GameEconomy.linesPerMinute * 2).rounded()))
    }

    func testZeroNegativeAndGarbageFallBack() {
        let r = GameRates.resolve([K.applesPerBonus: 0, K.linesPerBonus: -3, K.matchesPerBonus: .nan,
                                   K.timeRewardPerGoal: 0, K.minutesPerBonus: .infinity])
        XCTAssertEqual(r, .defaults)
    }

    func testValuesAreClamped() {
        let r = GameRates.resolve([K.applesPerBonus: 1_000_000, K.timeGoalMinutes: 0.2,
                                   K.timeGoalsPerDay: 500, K.minutesPerBonus: 0.0001])
        XCTAssertEqual(r.applesPerBonus, 1000)
        XCTAssertEqual(r.timeGoalMinutes, 1)
        XCTAssertEqual(r.timeGoalsPerDay, 24)
        XCTAssertEqual(r.minutesPerBonus, 0.25)
        XCTAssertGreaterThanOrEqual(r.linesPerBonus, 1, "цена не бывает нулевой")
    }

    func test2048FirstTileOnlyRealPowersOfTwo() {
        XCTAssertEqual(GameRates.resolve([K.game2048FirstTile: 256]).game2048FirstTile, 256)
        XCTAssertEqual(GameRates.resolve([K.game2048FirstTile: 100]).game2048FirstTile, 128)
        XCTAssertEqual(GameRates.resolve([K.game2048FirstTile: 4]).game2048FirstTile, 128)
        XCTAssertEqual(GameRates.resolve([K.game2048FirstTile: 4096]).game2048FirstTile, 128)
    }

    /// Лестница «2048» не начинается ниже 64: с 8/16/32 перезапуск партии —
    /// ферма бонусов за секунды.
    func test2048FirstTileFloorIs64() {
        XCTAssertEqual(GameRates.resolve([K.game2048FirstTile: 64]).game2048FirstTile, 64)
        XCTAssertEqual(GameRates.resolve([K.game2048FirstTile: 32]).game2048FirstTile, 128)
        XCTAssertEqual(GameRates.resolve([K.game2048FirstTile: 8]).game2048FirstTile, 128)
    }

    func testAnchorFloorIsQuarterMinute() {
        XCTAssertEqual(GameRates.resolve([K.minutesPerBonus: 0.1]).minutesPerBonus, 0.25)
        XCTAssertEqual(GameRates.resolve([K.minutesPerBonus: 0.5]).minutesPerBonus, 0.5)
    }

    func testGamesPayByGivenRate() {
        var t = Tetris.start(seed: 1)
        t.lines = 9
        XCTAssertEqual(t.bonuses(linesPerBonus: 3), 3)
        XCTAssertEqual(t.bonuses(linesPerBonus: 0), 9, "нулевая цена не делит на ноль")

        var m = Match3.start(seed: 1)
        m.matches = 40
        XCTAssertEqual(m.bonuses(matchesPerBonus: 20), 2)

        var g = Game2048.start(seed: 1)
        g.bestTile = 512
        XCTAssertEqual(g.bonuses(from: 128), 3)    // 128, 256, 512
        XCTAssertEqual(g.bonuses(from: 256), 2)
        XCTAssertEqual(g.nextBonusValue(from: 1024), 1024)
    }
}
