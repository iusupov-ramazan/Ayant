import XCTest
@testable import AyantDomain

/// Правила тетриса — чистые, поэтому проверяются без экрана и без таймера.
final class TetrisTests: XCTestCase {

    func testStartGivesPieceOnEmptyBoard() {
        let s = Tetris.start()
        XCTAssertNotNil(s.piece)
        XCTAssertFalse(s.isOver)
        XCTAssertEqual(s.lines, 0)
        XCTAssertEqual(s.board.count, Tetris.rows)
        XCTAssertEqual(s.board[0].count, Tetris.columns)
        XCTAssertTrue(s.board.allSatisfy { $0.allSatisfy { $0 == nil } })
    }

    func testSameSeedGivesSameGame() {
        XCTAssertEqual(Tetris.start(seed: 42), Tetris.start(seed: 42))
    }

    func testPieceCannotLeaveTheField() {
        var s = Tetris.start()
        // Уезжаем далеко влево: стенка обязана остановить.
        for _ in 0..<20 { s = Tetris.move(s, dx: -1) }
        XCTAssertTrue(s.piece!.occupied.allSatisfy { $0.x >= 0 })
        for _ in 0..<30 { s = Tetris.move(s, dx: 1) }
        XCTAssertTrue(s.piece!.occupied.allSatisfy { $0.x < Tetris.columns })
    }

    func testHardDropLandsAndSpawnsNext() {
        let s = Tetris.start()
        let expectedNext = s.next
        let after = Tetris.hardDrop(s)
        XCTAssertEqual(after.piece?.shape, expectedNext, "после фиксации приходит заявленная следующая")
        XCTAssertTrue(after.board.contains { row in row.contains { $0 != nil } },
                      "уложенная фигура осталась на поле")
    }

    func testFullRowIsClearedAndCounted() {
        var s = Tetris.start()
        // Забиваем нижнюю строку, оставив одну дырку под падающую фигуру.
        for x in 0..<Tetris.columns where x != 0 {
            s.board[Tetris.rows - 1][x] = .o
        }
        // Ставим вертикальную I-фигуру ровно в дырку и роняем.
        s.piece = Tetris.Piece(shape: .i, rotation: 1, x: -2, y: 0)
        XCTAssertTrue(Tetris.fits(s.piece!, in: s.board))
        let after = Tetris.hardDrop(s)
        XCTAssertEqual(after.lines, 1, "полная строка сгорела")
        XCTAssertEqual(after.bonuses, Tetris.bonusPerLine)
        XCTAssertTrue(after.board[Tetris.rows - 1].contains { $0 == nil },
                      "нижняя строка больше не заполнена целиком")
    }

    func testGameOverWhenSpawnIsBlocked() {
        var s = Tetris.start()
        // Заливаем всё поле, оставив пустым один столбец: так ни одна строка не
        // полная (иначе она бы сгорела и место освободилось), но новой фигуре в
        // центре встать всё равно некуда.
        for y in 0..<Tetris.rows {
            for x in 0..<Tetris.columns where x != 0 { s.board[y][x] = .o }
        }
        let after = Tetris.hardDrop(s)
        XCTAssertTrue(after.isOver)
        XCTAssertNil(after.piece)
    }

    func testRotationStaysInsideTheField() {
        var s = Tetris.start()
        s.piece = Tetris.Piece(shape: .i, rotation: 0, x: Tetris.columns - 2, y: 5)
        let rotated = Tetris.rotate(s)
        XCTAssertTrue(rotated.piece!.occupied.allSatisfy { $0.x < Tetris.columns && $0.x >= 0 })
    }
}
