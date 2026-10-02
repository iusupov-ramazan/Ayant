import XCTest
@testable import SAN
import AyantDomain
import AyantFeatures

/// Кошелёк бонусов: начисление с мини-игр больше ничем не ограничено.
///
/// Тест здесь не ради арифметики, а ради границы: дневной потолок убран
/// осознанно, и вернуться он должен тоже осознанно — правкой этого теста, а не
/// незаметной строчкой `min(...)` в движке.
@MainActor
final class BonusEngineTests: XCTestCase {

    private var engine: BonusEngine!
    private var clock: FixedClock!

    override func setUp() {
        super.setUp()
        clock = FixedClock(Date(timeIntervalSince1970: 1_700_000_000))
        engine = BonusEngine(clock: clock)
        // Кошелёк хранится в UserDefaults устройства — начинаем с чистого,
        // иначе тест считает чужой баланс.
        engine.resetForNewUser()
    }

    func testGameplayAwardHasNoDailyCeiling() {
        // Старый потолок был 3 бонуса в день: раньше третий вызов вернул бы 0.
        XCTAssertEqual(engine.awardGameplay(2), 2)
        XCTAssertEqual(engine.awardGameplay(2), 2)
        XCTAssertEqual(engine.awardGameplay(2), 2)
        XCTAssertEqual(engine.awardGameplay(50), 50, "крупное начисление тоже проходит целиком")
        XCTAssertEqual(engine.balance, 56)
    }

    func testAwardReportsExactlyWhatItGranted() {
        // Вью показывает «+N» по возвращённому числу — оно обязано совпадать
        // с тем, что реально легло в кошелёк.
        let before = engine.balance
        let granted = engine.awardGameplay(7)
        XCTAssertEqual(granted, 7)
        XCTAssertEqual(engine.balance - before, granted)
    }

    func testEarnedTodayCountsEverythingFromGames() {
        engine.awardGameplay(4)
        engine.awardGameplay(9)
        XCTAssertEqual(engine.gameEarnedToday, 13, "счётчик дня считает, а не режет")
    }

    func testNonPositiveAwardChangesNothing() {
        let before = engine.balance
        XCTAssertEqual(engine.awardGameplay(0), 0)
        XCTAssertEqual(engine.awardGameplay(-5), 0)
        XCTAssertEqual(engine.balance, before)
    }

    func testNewUserStartsWithEmptyWallet() {
        engine.awardGameplay(12)
        engine.resetForNewUser()
        XCTAssertEqual(engine.balance, 0)
        XCTAssertEqual(engine.gameEarnedToday, 0, "иначе анти-фарм обходится перезаходом")
    }

    // MARK: Бесконечные игры

    // У партии без конца нет естественного предела заработка, поэтому она
    // платит через свой дневной потолок. Общий `awardGameplay` при этом
    // по-прежнему ничего не режет — это разные решения.

    // MARK: Дневные лимиты по играм (Remote Config `ios_bonus_<game>_daily_cap`)

    func testDiamondHasDailyCapByDefault() {
        XCTAssertEqual(engine.remainingToday(.diamond), GameEconomy.endlessDailyBonusCap,
                       "бесконечная игра без удалённых настроек всё равно ограничена")
        XCTAssertNil(engine.remainingToday(.snake), "обычные игры по умолчанию без лимита")
    }

    func testCappedGamePaysOnlyRemainder() {
        engine.setBonusDailyCaps([.diamond: 5])
        let diamond = BonusGame.diamond.source
        XCTAssertEqual(engine.awardGameplay(3, source: diamond), 3)
        XCTAssertEqual(engine.awardGameplay(3, source: diamond), 2, "выдаётся только остаток до лимита")
        XCTAssertEqual(engine.awardGameplay(3, source: diamond), 0)
        XCTAssertEqual(engine.balance, 5)
        XCTAssertEqual(engine.remainingToday(.diamond), 0)
    }

    func testCapResetsNextDay() {
        engine.setBonusDailyCaps([.tetris: 4])
        engine.awardGameplay(10, source: BonusGame.tetris.source)
        XCTAssertEqual(engine.remainingToday(.tetris), 0)
        clock.advance(by: 86_400)
        XCTAssertEqual(engine.remainingToday(.tetris), 4, "новый день — новый лимит")
        XCTAssertEqual(engine.awardGameplay(1, source: BonusGame.tetris.source), 1)
    }

    func testCapsAreCountedPerGame() {
        engine.setBonusDailyCaps([.snake: 2, .diamond: 2])
        XCTAssertEqual(engine.awardGameplay(5, source: BonusGame.snake.source), 2)
        XCTAssertEqual(engine.awardGameplay(5, source: BonusGame.diamond.source), 2, "лимит змейки не трогает Diamond")
        XCTAssertEqual(engine.awardGameplay(5, source: BonusGame.game2048.source), 5, "игра без лимита платит целиком")
    }

    func testRaisingCapMidDayPaysTheDifference() {
        engine.setBonusDailyCaps([.snake: 2])
        engine.awardGameplay(5, source: BonusGame.snake.source)
        engine.setBonusDailyCaps([.snake: 6])
        XCTAssertEqual(engine.remainingToday(.snake), 4, "поднятый в консоли лимит считает уже начисленное")
    }

    func testDefaultEndlessCapKeepsCouponsFarAway() {
        // 300-бонусный купон не должен собираться за один день одной игрой.
        XCTAssertLessThan(GameEconomy.endlessDailyBonusCap * 3, 300)
    }

    // MARK: Удалённый выключатель начисления по играм

    func testPausedGamePaysNothingOthersStillPay() {
        engine.setBonusPaused([.snake])
        XCTAssertEqual(engine.awardGameplay(5, source: BonusGame.snake.source), 0, "выключенная игра не платит")
        XCTAssertEqual(engine.awardGameplay(5, source: BonusGame.tetris.source), 5, "остальные игры не задеты")
        XCTAssertEqual(engine.balance, 5)
    }

    func testPausedGameDoesNotEatDailyCap() {
        engine.setBonusDailyCaps([.diamond: 5])
        engine.setBonusPaused([.diamond])
        XCTAssertEqual(engine.awardGameplay(3, source: BonusGame.diamond.source), 0)
        XCTAssertEqual(engine.remainingToday(.diamond), 5, "пауза не расходует дневной лимит")
        engine.setBonusPaused([])
        XCTAssertEqual(engine.awardGameplay(3, source: BonusGame.diamond.source), 3,
                       "включили обратно — платит сразу")
    }

    func testNonGameSourcesIgnoreGameSwitches() {
        engine.setBonusPaused(Set(BonusGame.allCases))
        XCTAssertEqual(engine.awardGameplay(4, source: "game"), 4, "источник без игры этим выключателем не гасится")
    }
}
