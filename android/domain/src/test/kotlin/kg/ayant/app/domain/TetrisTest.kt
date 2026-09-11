package kg.ayant.app.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test

/** Правила тетриса — чистые, поэтому проверяются без экрана и без таймера. */
class TetrisTest {

    @Test fun `start gives piece on empty board`() {
        val s = Tetris.start()
        assertNotNull(s.piece)
        assertFalse(s.isOver)
        assertEquals(0, s.lines)
        assertEquals(Tetris.ROWS, s.board.size)
        assertEquals(Tetris.COLUMNS, s.board[0].size)
        assertTrue(s.board.all { row -> row.all { it == null } })
    }

    @Test fun `same seed gives same game`() {
        assertEquals(Tetris.start(42), Tetris.start(42))
    }

    @Test fun `piece cannot leave the field`() {
        var s = Tetris.start()
        repeat(20) { s = Tetris.move(s, -1) }
        assertTrue(s.piece!!.occupied.all { it.x >= 0 })
        repeat(30) { s = Tetris.move(s, 1) }
        assertTrue(s.piece!!.occupied.all { it.x < Tetris.COLUMNS })
    }

    @Test fun `hard drop lands and spawns next`() {
        val s = Tetris.start()
        val expectedNext = s.next
        val after = Tetris.hardDrop(s)
        assertEquals(expectedNext, after.piece?.shape)
        assertTrue(after.board.any { row -> row.any { it != null } })
    }

    @Test fun `full row is cleared and counted`() {
        val base = Tetris.start()
        val board = base.board.map { it.toMutableList() }
        for (x in 0 until Tetris.COLUMNS) if (x != 0) board[Tetris.ROWS - 1][x] = Tetris.Shape.O
        val s = base.copy(
            board = board.map { it.toList() },
            piece = Tetris.Piece(Tetris.Shape.I, rotation = 1, x = -2, y = 0),
        )
        assertTrue(Tetris.fits(s.piece!!, s.board))
        val after = Tetris.hardDrop(s)
        assertEquals(1, after.lines)
        assertEquals(Tetris.BONUS_PER_LINE, after.bonuses)
        assertTrue(after.board[Tetris.ROWS - 1].any { it == null })
    }

    @Test fun `game over when spawn is blocked`() {
        val base = Tetris.start()
        // Пустым оставляем один столбец: ни одна строка не полная (иначе сгорела
        // бы и место освободилось), но новой фигуре в центре встать некуда.
        val board = base.board.map { it.toMutableList() }
        for (y in 0 until Tetris.ROWS) for (x in 1 until Tetris.COLUMNS) board[y][x] = Tetris.Shape.O
        val after = Tetris.hardDrop(base.copy(board = board.map { it.toList() }))
        assertTrue(after.isOver)
        assertNull(after.piece)
    }

    @Test fun `rotation stays inside the field`() {
        val base = Tetris.start()
        val s = base.copy(piece = Tetris.Piece(Tetris.Shape.I, 0, Tetris.COLUMNS - 2, 5))
        val rotated = Tetris.rotate(s)
        assertTrue(rotated.piece!!.occupied.all { it.x in 0 until Tetris.COLUMNS })
    }
}

/** Одна механика лояльности на заведение (см. [LoyaltyKind]). */
class LoyaltyKindTest {

    @Test fun `points win when both enabled`() {
        assertEquals(LoyaltyKind.POINTS, LoyaltyKind.active(pointsEnabled = true, loyaltyEnabled = true))
    }

    @Test fun `stamps only when points off`() {
        assertEquals(LoyaltyKind.STAMPS, LoyaltyKind.active(pointsEnabled = false, loyaltyEnabled = true))
    }

    @Test fun `none when both off`() {
        assertEquals(LoyaltyKind.NONE, LoyaltyKind.active(pointsEnabled = false, loyaltyEnabled = false))
    }
}
