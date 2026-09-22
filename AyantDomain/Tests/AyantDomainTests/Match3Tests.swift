import XCTest
@testable import AyantDomain

/// Правила «трёх в ряд» — чистые, поэтому проверяются без экрана и без таймера.
///
/// Поле в тестах задаётся строками: одна буква — один вид фишки. Так раскладка
/// видна глазами, а не собирается циклом, который надо держать в голове.
final class Match3Tests: XCTestCase {

    // MARK: Помощники

    private static let letters: [Character: Match3.Kind] = [
        "r": .ruby, "a": .amethyst, "o": .rose, "g": .gold, "e": .emerald, "s": .sapphire
    ]

    /// Раскладка без единого совпадения — основа почти всех тестов.
    private let base = [
        "raoraor",
        "oraorao",
        "aoraora",
        "raoraor",
        "oraorao",
        "aoraora",
        "raoraor",
    ]

    private func board(_ layout: [String], file: StaticString = #filePath, line: UInt = #line) -> [[Match3.Tile]] {
        XCTAssertEqual(layout.count, Match3.rows, "строк должно быть ровно поле", file: file, line: line)
        var id = 0
        return layout.map { row -> [Match3.Tile] in
            XCTAssertEqual(row.count, Match3.columns, "в строке должно быть ровно поле", file: file, line: line)
            return row.map { letter in
                id += 1
                return Match3.Tile(id: id, kind: Self.letters[letter] ?? .ruby)
            }
        }
    }

    private func state(_ layout: [String], score: Int = 0, movesLeft: Int = Match3.movesPerLevel,
                       level: Int = 1, file: StaticString = #filePath, line: UInt = #line) -> Match3.State {
        let b = board(layout, file: file, line: line)
        XCTAssertTrue(Match3.matches(on: b).isEmpty,
                      "стартовая раскладка теста не должна собираться сама", file: file, line: line)
        return Match3.State(board: b, score: score, movesLeft: movesLeft, level: level,
                            matches: 0, isOver: false, seed: 777, clearing: [],
                            nextID: Match3.rows * Match3.columns + 1)
    }

    /// Первый кадр со вспышкой — ровно то, что сгорает на первом каскаде.
    private func firstBurn(_ frames: [Match3.State]) -> Set<Match3.Point> {
        frames.first(where: { !$0.clearing.isEmpty })?.clearing ?? []
    }

    private func p(_ x: Int, _ y: Int) -> Match3.Point { Match3.Point(x: x, y: y) }

    // MARK: Старт

    func testStartGivesFullBoardWithoutMatches() {
        let s = Match3.start()
        XCTAssertEqual(s.board.count, Match3.rows)
        XCTAssertTrue(s.board.allSatisfy { $0.count == Match3.columns })
        XCTAssertTrue(Match3.matches(on: s.board).isEmpty, "поле не должно собираться само на старте")
        XCTAssertTrue(Match3.hasMoves(s), "на старте обязан быть хотя бы один ход")
        XCTAssertEqual(s.movesLeft, Match3.movesPerLevel)
        XCTAssertEqual(s.level, 1)
        XCTAssertFalse(s.isOver)
    }

    func testSameSeedGivesSameGame() {
        XCTAssertEqual(Match3.start(seed: 42), Match3.start(seed: 42))
    }

    func testGoalGrowsWithLevel() {
        XCTAssertEqual(Match3.goal(forLevel: 1), 800)
        XCTAssertEqual(Match3.goal(forLevel: 2), 2000)
        XCTAssertTrue(Match3.goal(forLevel: 3) > Match3.goal(forLevel: 2))
    }

    func testLevelProgressCountsFromPreviousGoal() {
        var s = state(base)
        XCTAssertEqual(s.levelProgress, 0)
        s.score = Match3.goal(forLevel: 1)
        XCTAssertEqual(s.levelProgress, 1)
        // На втором уровне отсчёт идёт от цели первого, а не от нуля.
        s.level = 2
        XCTAssertEqual(s.levelProgress, 0)
        s.score = (Match3.goal(forLevel: 1) + Match3.goal(forLevel: 2)) / 2
        XCTAssertEqual(s.levelProgress, 0.5, accuracy: 0.01)
    }

    // MARK: Запрещённые ходы

    func testSwapWithoutMatchIsRejected() {
        let s = state(base)
        XCTAssertTrue(Match3.swap(s, p(0, 0), p(1, 0)).isEmpty,
                      "обмен, который ничего не собирает, не ход")
    }

    func testDistantSwapIsRejected() {
        let s = state(base)
        XCTAssertTrue(Match3.swap(s, p(0, 0), p(3, 3)).isEmpty)
        XCTAssertTrue(Match3.swap(s, p(0, 0), p(1, 1)).isEmpty, "по диагонали нельзя")
    }

    func testSwapOutsideBoardIsRejected() {
        let s = state(base)
        XCTAssertTrue(Match3.swap(s, p(0, 0), p(-1, 0)).isEmpty)
    }

    func testFinishedGameTakesNoMoves() {
        var s = state(base)
        s.isOver = true
        XCTAssertTrue(Match3.swap(s, p(2, 5), p(2, 6)).isEmpty)
    }

    func testExchangedSwapsTilesWithoutSpendingAMove() {
        let s = state(base)
        let a = p(0, 0), b = p(1, 0)
        let swapped = Match3.exchanged(s, a, b)
        XCTAssertEqual(swapped?.board[0][0].kind, s.board[0][1].kind)
        XCTAssertEqual(swapped?.board[0][1].kind, s.board[0][0].kind)
        XCTAssertEqual(swapped?.movesLeft, s.movesLeft, "показ обмена — не ход")
        XCTAssertEqual(swapped?.score, s.score)
        XCTAssertNil(Match3.exchanged(s, a, p(3, 3)), "несоседние не меняются местами")
    }

    // MARK: Совпадения

    /// Раскладка, где обмен (2,5)↔(2,6) собирает в нижней строке ровно тройку.
    private var tripleLayout: [String] {
        var rows = base
        rows[6] = "rroaoao"
        return rows
    }

    func testTripleBurnsAndScores() {
        let s = state(tripleLayout)
        let frames = Match3.swap(s, p(2, 5), p(2, 6))
        XCTAssertFalse(frames.isEmpty, "ход собирает тройку — он обязан пройти")
        XCTAssertEqual(firstBurn(frames), [p(0, 6), p(1, 6), p(2, 6)])

        let final = frames.last!
        XCTAssertEqual(final.movesLeft, Match3.movesPerLevel - 1, "ход списан один раз")
        XCTAssertGreaterThanOrEqual(final.score, 3 * Match3.pointsPerTile)
        XCTAssertGreaterThanOrEqual(final.matches, 1)
        XCTAssertTrue(final.clearing.isEmpty, "итоговый кадр уже без вспышки")
    }

    func testBoardStaysFullAfterCascades() {
        let frames = Match3.swap(state(tripleLayout), p(2, 5), p(2, 6))
        let final = frames.last!
        XCTAssertEqual(final.board.count, Match3.rows)
        XCTAssertTrue(final.board.allSatisfy { $0.count == Match3.columns },
                      "сгоревшее досыпается сверху — пустых клеток не остаётся")
        XCTAssertTrue(Match3.matches(on: final.board).isEmpty,
                      "каскад доигран до конца: на итоговом поле совпадений нет")
    }

    // MARK: Спецэлементы

    func testFourInRowLeavesLineTile() {
        var rows = base
        rows[6] = "rroroao"          // после обмена в нижней строке будет четвёрка
        let frames = Match3.swap(state(rows), p(2, 5), p(2, 6))
        XCTAssertEqual(firstBurn(frames), [p(0, 6), p(1, 6), p(2, 6), p(3, 6)])

        // Полоска рождается там, куда игрок вёл ход, и бьёт вдоль своего ряда.
        let afterFall = frames[2]
        XCTAssertEqual(afterFall.board[6][2].power, .line(horizontal: true))
        XCTAssertEqual(afterFall.board[6][2].kind, .ruby)
    }

    func testFiveInRowLeavesBomb() {
        var rows = base
        rows[6] = "rrorrao"          // после обмена — пятёрка
        let frames = Match3.swap(state(rows), p(2, 5), p(2, 6))
        XCTAssertEqual(firstBurn(frames).count, 5)
        XCTAssertEqual(frames[2].board[6][2].power, .bomb)
    }

    func testLineTileBurnsWholeRow() {
        var s = state(tripleLayout)
        s.board[6][0].power = .line(horizontal: true)   // сгорит в тройке и подожжёт строку
        let frames = Match3.swap(s, p(2, 5), p(2, 6))
        let burn = firstBurn(frames)
        XCTAssertEqual(burn.count, Match3.columns, "полоска сжигает весь свой ряд")
        for x in 0..<Match3.columns { XCTAssertTrue(burn.contains(p(x, 6))) }
    }

    func testBombBurnsThreeByThree() {
        var s = state(tripleLayout)
        s.board[6][0].power = .bomb
        let burn = firstBurn(Match3.swap(s, p(2, 5), p(2, 6)))
        // Тройка плюс квадрат 3×3 вокруг угловой (0,6) — угол обрезан полем.
        XCTAssertEqual(burn, [p(0, 6), p(1, 6), p(2, 6), p(0, 5), p(1, 5)])
    }

    func testPowersChainEachOther() {
        var s = state(tripleLayout)
        s.board[6][0].power = .line(horizontal: true)
        s.board[6][5].power = .bomb                      // его зажжёт полоска
        let burn = firstBurn(Match3.swap(s, p(2, 5), p(2, 6)))
        XCTAssertTrue(burn.contains(p(4, 5)), "бомба сработала от полоски, а не сама по себе")
        XCTAssertTrue(burn.contains(p(6, 5)))
    }

    // MARK: Личность фишек (без неё вью не умеет анимировать падение)

    func testEveryTileHasItsOwnID() {
        let ids = Match3.start().board.flatMap { $0 }.map(\.id)
        XCTAssertEqual(Set(ids).count, Match3.rows * Match3.columns, "id не повторяются")
    }

    func testSurvivingTilesKeepTheirIDsAndFall() {
        let s = state(tripleLayout)
        // Фишка прямо над сгорающей тройкой: она обязана оказаться ниже, но
        // остаться той же самой — иначе вью покажет подмену вместо падения.
        let above = s.board[5][0]
        let final = Match3.swap(s, p(2, 5), p(2, 6)).last!
        XCTAssertEqual(final.board[6][0].id, above.id, "фишка та же, просто упала")
        XCTAssertEqual(final.board[6][0].kind, above.kind)
    }

    func testRefilledTilesGetFreshIDs() {
        let s = state(tripleLayout)
        let before = Set(s.board.flatMap { $0 }.map(\.id))
        let final = Match3.swap(s, p(2, 5), p(2, 6)).last!
        let after = final.board.flatMap { $0 }.map(\.id)
        XCTAssertEqual(Set(after).count, after.count, "id по-прежнему уникальны")
        XCTAssertFalse(after.contains { before.contains($0) && $0 > Match3.rows * Match3.columns },
                       "досыпанные фишки не переиспользуют чужие id")
    }

    func testSpecialTileKeepsTheIDOfItsCell() {
        var rows = base
        rows[6] = "rroroao"
        let s = state(rows)
        // Полоска рождается на месте (2,6) — id туда приезжает с обменянной фишкой.
        let travelling = s.board[5][2]
        let frames = Match3.swap(s, p(2, 5), p(2, 6))
        XCTAssertEqual(frames[2].board[6][2].id, travelling.id,
                       "спецэлемент — это превращение фишки, а не новая фишка")
    }

    // MARK: Бонусы, уровни и конец партии

    func testBonusesCountedPerMatches() {
        var s = state(base)
        s.matches = Match3.matchesPerBonus * 2 - 1
        XCTAssertEqual(s.bonuses, 1)
        s.matches += 1
        XCTAssertEqual(s.bonuses, 2, "бонус за каждые \(Match3.matchesPerBonus) совпадений")
    }

    func testGoalReachedRaisesLevelAndAddsMoves() {
        let s = state(tripleLayout, score: Match3.goal(forLevel: 1) - 10, movesLeft: 5)
        let final = Match3.swap(s, p(2, 5), p(2, 6)).last!
        XCTAssertEqual(final.level, 2, "цель взята — следующий уровень")
        XCTAssertEqual(final.movesLeft, 4 + Match3.movesPerLevel, "и новая порция ходов")
        XCTAssertFalse(final.isOver)
    }

    func testLastMoveEndsTheGame() {
        let s = state(tripleLayout, movesLeft: 1)
        let final = Match3.swap(s, p(2, 5), p(2, 6)).last!
        XCTAssertEqual(final.movesLeft, 0)
        XCTAssertTrue(final.isOver, "ходы кончились, а цель не взята")
        XCTAssertTrue(Match3.swap(final, p(2, 5), p(2, 6)).isEmpty)
    }

    // MARK: Тупик

    func testShuffleRestoresMoves() {
        // Настоящий тупик: совпадений нет и ни один обмен их не даёт.
        // «Шахматка» тупиком не была бы — там обмен по горизонтали ставит фишку
        // между двумя такими же по вертикали.
        var s = state(["esaegar",
                       "gressgo",
                       "regroer",
                       "oasrrao",
                       "easegge",
                       "eoresra",
                       "aoosgog"])
        XCTAssertFalse(Match3.hasMoves(s), "раскладка для теста обязана быть тупиком")

        let before = s.board.flatMap { $0 }.map(\.kind).sorted { $0.rawValue < $1.rawValue }
        s = Match3.shuffled(s)
        XCTAssertTrue(Match3.hasMoves(s), "после перемешивания ход обязан найтись")
        XCTAssertTrue(Match3.matches(on: s.board).isEmpty, "и поле не должно собраться само")
        XCTAssertEqual(s.board.flatMap { $0 }.map(\.kind).sorted { $0.rawValue < $1.rawValue }, before,
                       "перемешивание не выдумывает и не теряет фишки")
    }
}
