import XCTest
@testable import AyantDomain

/// Правила «2048» — чистые, поэтому проверяются без экрана и без таймера.
///
/// Поле в тестах задаётся числами построчно, `0` — пустая клетка. Так раскладка
/// видна глазами, а не собирается циклом, который надо держать в голове.
final class Game2048Tests: XCTestCase {

    // MARK: Помощники

    private func state(_ layout: [[Int]], score: Int = 0, bestTile: Int = 0,
                       file: StaticString = #filePath, line: UInt = #line) -> Game2048.State {
        XCTAssertEqual(layout.count, Game2048.size, "строк должно быть ровно поле",
                       file: file, line: line)
        var tiles: [Game2048.Tile] = []
        var id = 1
        for (y, row) in layout.enumerated() {
            XCTAssertEqual(row.count, Game2048.size, "в строке должно быть ровно поле",
                           file: file, line: line)
            for (x, value) in row.enumerated() where value > 0 {
                tiles.append(Game2048.Tile(id: id, value: value, x: x, y: y))
                id += 1
            }
        }
        let best = max(bestTile, tiles.map(\.value).max() ?? 0)
        return Game2048.State(tiles: tiles, score: score, bestTile: best, moves: 0,
                              isOver: false, hasWon: false, seed: 777, nextID: id)
    }

    /// Поле числами — так результат хода читается так же, как задавалась раскладка.
    private func values(_ state: Game2048.State) -> [[Int]] {
        state.grid.map { row in row.map { $0?.value ?? 0 } }
    }

    private let empty = [[Int]](repeating: [Int](repeating: 0, count: Game2048.size),
                                count: Game2048.size)

    private func row(_ y: Int, _ cells: [Int]) -> [[Int]] {
        var layout = empty
        layout[y] = cells
        return layout
    }

    // MARK: Старт

    func testStartGivesTwoTiles() {
        let s = Game2048.start()
        XCTAssertEqual(s.tiles.count, 2)
        XCTAssertTrue(s.tiles.allSatisfy { $0.value == 2 || $0.value == 4 })
        XCTAssertFalse(s.isOver)
        XCTAssertFalse(s.hasWon)
        XCTAssertEqual(s.score, 0)
        XCTAssertEqual(s.moves, 0)
        XCTAssertEqual(s.bestTile, s.tiles.map(\.value).max())
    }

    func testSameSeedGivesSameGame() {
        XCTAssertEqual(Game2048.start(seed: 42), Game2048.start(seed: 42))
        // И партия целиком: один и тот же посев — одни и те же досыпки.
        var a = Game2048.start(seed: 42)
        var b = Game2048.start(seed: 42)
        for direction in [Game2048.Direction.left, .down, .right, .up, .left] {
            a = Game2048.move(a, direction).last ?? a
            b = Game2048.move(b, direction).last ?? b
        }
        XCTAssertEqual(a, b)
    }

    func testTilesNeverShareAnIdentity() {
        var s = Game2048.start(seed: 9)
        var seen = Set(s.tiles.map(\.id))
        for direction in [Game2048.Direction.left, .up, .right, .down, .left, .up] {
            guard let next = Game2048.move(s, direction).last else { continue }
            s = next
            for tile in s.tiles where !seen.contains(tile.id) { seen.insert(tile.id) }
            XCTAssertEqual(Set(s.tiles.map(\.id)).count, s.tiles.count,
                           "две плитки с одним id — вью телепортирует одну на место другой")
        }
    }

    // MARK: Скольжение

    func testSlideCompactsWithoutMerging() {
        let s = state(row(1, [0, 2, 0, 4]))
        let frames = Game2048.move(s, .left)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(values(frames[0])[1], [2, 4, 0, 0])
        XCTAssertEqual(frames[0].score, 0, "простое скольжение не приносит очков")
    }

    func testSlideRightPacksToTheWall() {
        let s = state(row(0, [2, 0, 4, 0]))
        let frames = Game2048.move(s, .right)
        XCTAssertEqual(values(frames[0])[0], [0, 0, 2, 4])
    }

    func testMoveIntoAWallChangesNothing() {
        let s = state(row(0, [2, 4, 0, 0]))
        XCTAssertTrue(Game2048.move(s, .left).isEmpty,
                      "ход, который ничего не двигает, не ход — и новую плитку не досыпает")
    }

    func testColumnsSlideToo() {
        var layout = empty
        layout[1][2] = 2
        layout[3][2] = 2
        let frames = Game2048.move(state(layout), .up)
        XCTAssertEqual(values(frames[1])[0][2], 4)
    }

    // MARK: Слияния

    func testEqualNeighboursMergeOnce() {
        let frames = Game2048.move(state(row(0, [2, 2, 2, 2])), .left)
        XCTAssertEqual(values(frames[1])[0], [4, 4, 0, 0],
                       "четыре двойки дают две четвёрки, а не одну восьмёрку")
    }

    func testMergedTileDoesNotMergeAgainInTheSameMove() {
        let frames = Game2048.move(state(row(0, [4, 2, 2, 0])), .left)
        XCTAssertEqual(values(frames[1])[0], [4, 4, 0, 0],
                       "свежая четвёрка не должна слиться с соседней в том же ходу")
    }

    func testMergeGivesScoreOfTheNewTile() {
        let frames = Game2048.move(state(row(0, [8, 8, 0, 0])), .left)
        XCTAssertEqual(frames[1].score, 16)
    }

    func testMergePairTravelsTogetherBeforeItCollapses() {
        let s = state(row(0, [2, 0, 0, 2]))
        let frames = Game2048.move(s, .left)

        // Кадр 1: обе плитки уже в одной клетке и обе ещё двойки.
        let arrived = frames[0].tiles
        XCTAssertEqual(arrived.count, 2)
        XCTAssertTrue(arrived.allSatisfy { $0.x == 0 && $0.y == 0 && $0.value == 2 })
        XCTAssertEqual(arrived.filter(\.absorbed).count, 1,
                       "ровно одна из пары помечена поглощённой")
        XCTAssertEqual(frames[0].tiles.filter(\.born).count, 0,
                       "на кадре доезда ещё никто не рождается")

        // Выживает та, что была ближе к стене: вторая въезжает в неё.
        let survivor = arrived.first { !$0.absorbed }
        XCTAssertEqual(survivor?.id, s.tiles.first { $0.x == 0 }?.id)

        // Кадр 2: поглощённой нет, выжившая удвоилась и помечена рождённой.
        XCTAssertNil(frames[1].tiles.first { $0.absorbed })
        XCTAssertEqual(frames[1].tiles.first { $0.id == survivor?.id }?.value, 4)
        XCTAssertTrue(frames[1].tiles.first { $0.id == survivor?.id }?.born ?? false)
    }

    func testEveryMoveAddsExactlyOneTile() {
        let frames = Game2048.move(state(row(0, [2, 2, 0, 0])), .left)
        XCTAssertEqual(frames[0].tiles.count, 2, "на кадре доезда новых плиток нет")
        XCTAssertEqual(frames[1].tiles.count, 2, "две слились в одну, одну досыпали")
        XCTAssertEqual(frames[1].tiles.filter(\.born).count, 2,
                       "слияние и досыпка — обе новые для вью")
    }

    func testMoveCounterGrowsOnlyOnRealMoves() {
        let s = state(row(0, [2, 4, 0, 0]))
        XCTAssertEqual(Game2048.move(s, .left).count, 0)
        XCTAssertEqual(Game2048.move(s, .right).last?.moves, 1)
    }

    // MARK: Конец партии

    func testDeadBoardTakesNoMoveAtAll() {
        let s = state([[2, 4, 2, 4],
                       [4, 2, 4, 2],
                       [2, 4, 2, 4],
                       [4, 2, 4, 2]])
        XCTAssertFalse(Game2048.canMove(s), "поле забито и одинаковых соседей нет")
        for direction in Game2048.Direction.allCases {
            XCTAssertTrue(Game2048.move(s, direction).isEmpty, "\(direction)")
        }
    }

    /// Последняя свободная клетка зажата между большими плитками, поэтому
    /// партия кончается при ЛЮБОЙ досыпке — и двойка, и четвёрка мертвы.
    /// Так проверка не зависит от того, что выпало генератору.
    func testGameEndsWhenTheLastGapIsFilled() {
        let s = state([[2, 4, 8, 32],
                       [4, 2, 4, 8],
                       [2, 4, 2, 8],
                       [4, 2, 4, 8]])
        let frames = Game2048.move(s, .down)
        XCTAssertEqual(values(frames[1])[0], [2, 4, 8, frames[1].grid[0][3]?.value ?? 0])
        XCTAssertEqual(frames[1].tiles.count, Game2048.size * Game2048.size,
                       "досыпка заняла последнюю клетку")
        XCTAssertTrue(frames[1].isOver, "ходов больше нет")
        XCTAssertTrue(Game2048.move(frames[1], .left).isEmpty,
                      "после конца партии ходы не принимаются")
    }

    func testFullBoardWithAPairIsNotOver() {
        let s = state([[2, 4, 2, 4],
                       [4, 2, 4, 2],
                       [2, 4, 2, 4],
                       [4, 2, 4, 4]])
        XCTAssertTrue(Game2048.canMove(s))
    }

    func testWinningTileDoesNotEndTheGame() {
        let frames = Game2048.move(state(row(0, [1024, 1024, 0, 0])), .left)
        XCTAssertTrue(frames[1].hasWon)
        XCTAssertFalse(frames[1].isOver, "после 2048 можно играть дальше")
    }

    // MARK: Бонусы

    func testBonusesStartAtTheThresholdTileAndDoubleUp() {
        XCTAssertEqual(state(row(0, [64, 0, 0, 0])).bonuses, 0)
        XCTAssertEqual(state(row(0, [128, 0, 0, 0])).bonuses, 1)
        XCTAssertEqual(state(row(0, [256, 0, 0, 0])).bonuses, 2)
        XCTAssertEqual(state(row(0, [512, 0, 0, 0])).bonuses, 3)
        XCTAssertEqual(state(row(0, [2048, 0, 0, 0])).bonuses, 5)
    }

    func testBonusIsEarnedOnceAndSurvivesTheTileItself() {
        let frames = Game2048.move(state(row(0, [64, 64, 0, 0])), .left)
        let earned = frames[1]
        XCTAssertEqual(earned.bestTile, 128)
        XCTAssertEqual(earned.bonuses, 1)

        // Плитка слилась дальше — бонус за 128 не должен пропасть.
        var next = earned
        next.tiles = [Game2048.Tile(id: 99, value: 4, x: 0, y: 0)]
        XCTAssertEqual(next.bestTile, 128)
        XCTAssertEqual(next.bonuses, 1)
    }

    func testNextBonusValueLeadsTheWay() {
        XCTAssertEqual(state(row(0, [4, 0, 0, 0])).nextBonusValue, Game2048.bonusFromValue)
        XCTAssertEqual(state(row(0, [128, 0, 0, 0])).nextBonusValue, 256)
        XCTAssertEqual(state(row(0, [512, 0, 0, 0])).nextBonusValue, 1024)
    }

    /// Ступенька важнее порога: каждый следующий бонус стоит вдвое дороже, и
    /// дневной потолок нельзя выбрать перезапусками «до 128».
    func testEachBonusCostsTwiceThePrevious() {
        for step in 1...4 {
            let tile = Game2048.bonusFromValue << (step - 1)
            XCTAssertEqual(state(row(0, [tile, 0, 0, 0])).bonuses, step)
        }
    }
}
