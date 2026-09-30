import XCTest
@testable import AyantDomain

/// Курс мини-игр. Тест сторожит ровно то, из-за чего его и завели: игры не
/// должны расходиться по цене бонуса. Пока действовал дневной потолок,
/// расхождение было невидимым; теперь оно решает, во что будут играть.
final class GameEconomyTests: XCTestCase {

    /// Сколько минут игры стоит бонус в каждой игре по её собственным числам.
    private var minutesPerBonusByGame: [(String, Double)] {
        [("Змейка", Double(GameEconomy.applesPerBonus) / GameEconomy.applesPerMinute),
         ("Тетрис", Double(GameEconomy.linesPerBonus) / GameEconomy.linesPerMinute),
         ("Три в ряд", Double(GameEconomy.matchesPerBonus) / GameEconomy.matchesPerMinute)]
    }

    func testEveryGamePaysAboutTheSamePerMinute() {
        for (game, minutes) in minutesPerBonusByGame {
            XCTAssertEqual(minutes, GameEconomy.minutesPerBonus,
                           accuracy: GameEconomy.minutesPerBonus * 0.25,
                           "«\(game)» выбивается из общего курса: бонус за \(minutes) мин против \(GameEconomy.minutesPerBonus)")
        }
    }

    func testNoGameIsCheaperThanAnotherByMoreThanAQuarter() {
        let values = minutesPerBonusByGame.map(\.1)
        let cheapest = values.min()!, dearest = values.max()!
        XCTAssertLessThan(dearest / cheapest, 1.5,
                          "разброс курса больше полутора раз — играть будут только в самую дешёвую")
    }

    func testGamesTakeTheirPriceFromTheAnchor() {
        // Своих чисел у игр быть не должно: иначе курс снова разъедется.
        XCTAssertEqual(Match3.matchesPerBonus, GameEconomy.matchesPerBonus)
        XCTAssertEqual(Tetris.linesPerBonus, GameEconomy.linesPerBonus)
    }

    func testPriceIsNeverZero() {
        // При крошечном `minutesPerBonus` округление не должно давать «0 яблок
        // за бонус» — это был бы бесконечный кошелёк с первого же хода.
        XCTAssertGreaterThanOrEqual(GameEconomy.applesPerBonus, 1)
        XCTAssertGreaterThanOrEqual(GameEconomy.linesPerBonus, 1)
        XCTAssertGreaterThanOrEqual(GameEconomy.matchesPerBonus, 1)
    }
}
