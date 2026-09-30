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

    func testEndlessAwardStopsAtDailyCap() {
        let cap = 5
        XCTAssertEqual(engine.awardEndlessGameplay(3, dailyCap: cap), 3)
        XCTAssertEqual(engine.awardEndlessGameplay(3, dailyCap: cap), 2, "выдаётся только остаток до потолка")
        XCTAssertEqual(engine.awardEndlessGameplay(3, dailyCap: cap), 0)
        XCTAssertEqual(engine.balance, 5)
        XCTAssertEqual(engine.remainingEndlessToday(dailyCap: cap), 0)
    }

    func testEndlessCapResetsNextDay() {
        let cap = 4
        engine.awardEndlessGameplay(10, dailyCap: cap)
        XCTAssertEqual(engine.remainingEndlessToday(dailyCap: cap), 0)
        clock.advance(by: 86_400)
        XCTAssertEqual(engine.remainingEndlessToday(dailyCap: cap), cap, "новый день — новый лимит")
        XCTAssertEqual(engine.awardEndlessGameplay(1, dailyCap: cap), 1)
    }

    func testEndlessCapDoesNotLimitOtherGames() {
        engine.awardEndlessGameplay(GameEconomy.endlessDailyBonusCap)
        XCTAssertEqual(engine.awardGameplay(7), 7, "Змейку и Тетрис потолок бесконечной игры не трогает")
    }

    func testDefaultEndlessCapKeepsCouponsFarAway() {
        // 300-бонусный купон не должен собираться за один день одной игрой.
        XCTAssertLessThan(GameEconomy.endlessDailyBonusCap * 3, 300)
    }
}
