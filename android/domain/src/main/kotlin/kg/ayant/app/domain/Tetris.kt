package kg.ayant.app.domain

/**
 * Правила тетриса — чистые и общие для обеих платформ. Зеркалит `Tetris.swift`.
 *
 * Игра живёт в домене по той же причине, что `Ranking` и `PointsMath`: это
 * арифметика без экрана, её надо считать одинаково на iOS и Android и покрывать
 * тестами. Вью остаётся только нарисовать [State] и слать ходы.
 */
object Tetris {
    const val COLUMNS = 10
    const val ROWS = 20

    /**
     * Сколько бонусов даёт одна линия. Начисление всё равно проходит через общий
     * дневной лимит мини-игр — своей экономики у игры нет.
     */
    const val BONUS_PER_LINE = 5

    enum class Shape { I, O, T, S, Z, J, L }

    data class Cell(val x: Int, val y: Int)

    /** Занятые клетки фигуры в её рамке 4×4 для каждого поворота. */
    fun cells(shape: Shape, rotation: Int): List<Cell> {
        val r = ((rotation % 4) + 4) % 4
        return when (shape) {
            Shape.I -> if (r % 2 == 0) listOf(Cell(0, 1), Cell(1, 1), Cell(2, 1), Cell(3, 1))
                       else listOf(Cell(2, 0), Cell(2, 1), Cell(2, 2), Cell(2, 3))
            Shape.O -> listOf(Cell(1, 0), Cell(2, 0), Cell(1, 1), Cell(2, 1))
            Shape.S -> if (r % 2 == 0) listOf(Cell(1, 0), Cell(2, 0), Cell(0, 1), Cell(1, 1))
                       else listOf(Cell(1, 0), Cell(1, 1), Cell(2, 1), Cell(2, 2))
            Shape.Z -> if (r % 2 == 0) listOf(Cell(0, 0), Cell(1, 0), Cell(1, 1), Cell(2, 1))
                       else listOf(Cell(2, 0), Cell(1, 1), Cell(2, 1), Cell(1, 2))
            Shape.T -> when (r) {
                0 -> listOf(Cell(1, 0), Cell(0, 1), Cell(1, 1), Cell(2, 1))
                1 -> listOf(Cell(1, 0), Cell(1, 1), Cell(2, 1), Cell(1, 2))
                2 -> listOf(Cell(0, 1), Cell(1, 1), Cell(2, 1), Cell(1, 2))
                else -> listOf(Cell(1, 0), Cell(0, 1), Cell(1, 1), Cell(1, 2))
            }
            Shape.J -> when (r) {
                0 -> listOf(Cell(0, 0), Cell(0, 1), Cell(1, 1), Cell(2, 1))
                1 -> listOf(Cell(1, 0), Cell(2, 0), Cell(1, 1), Cell(1, 2))
                2 -> listOf(Cell(0, 1), Cell(1, 1), Cell(2, 1), Cell(2, 2))
                else -> listOf(Cell(1, 0), Cell(1, 1), Cell(0, 2), Cell(1, 2))
            }
            Shape.L -> when (r) {
                0 -> listOf(Cell(2, 0), Cell(0, 1), Cell(1, 1), Cell(2, 1))
                1 -> listOf(Cell(1, 0), Cell(1, 1), Cell(1, 2), Cell(2, 2))
                2 -> listOf(Cell(0, 1), Cell(1, 1), Cell(2, 1), Cell(0, 2))
                else -> listOf(Cell(0, 0), Cell(1, 0), Cell(1, 1), Cell(1, 2))
            }
        }
    }

    data class Piece(
        val shape: Shape,
        val rotation: Int = 0,
        /** Левый верхний угол рамки 4×4 в координатах поля. */
        val x: Int = 3,
        val y: Int = -1,
    ) {
        /** Занятые клетки в координатах поля. */
        val occupied: List<Cell> get() = cells(shape, rotation).map { Cell(x + it.x, y + it.y) }
    }

    data class State(
        /** Уложенные клетки: [ROWS] × [COLUMNS], `null` — пусто. */
        val board: List<List<Shape?>>,
        val piece: Piece?,
        val next: Shape,
        val lines: Int,
        val isOver: Boolean,
        /** Свой генератор, чтобы состояние оставалось воспроизводимым в тестах. */
        val seed: Long,
    ) {
        /** Заработанные бонусы (до дневного лимита — его считает BonusViewModel). */
        val bonuses: Int get() = lines * BONUS_PER_LINE
    }

    fun start(seed: Long = -0x61c8864680b583ebL): State {
        var s = seed
        val first = randomShape(s).also { s = nextSeed(s) }
        val next = randomShape(s).also { s = nextSeed(s) }
        val empty = List(ROWS) { List<Shape?>(COLUMNS) { null } }
        return State(empty, Piece(first), next, lines = 0, isOver = false, seed = s)
    }

    /**
     * Линейный конгруэнтный генератор: нужен воспроизводимый, а не «настоящий»
     * рандом — иначе тест на конкретную раскладку не написать.
     */
    private fun nextSeed(seed: Long): Long = seed * 6364136223846793005L + 1442695040888963407L
    private fun randomShape(seed: Long): Shape {
        val v = ((seed ushr 33) % Shape.entries.size).toInt()
        return Shape.entries[if (v < 0) v + Shape.entries.size else v]
    }

    /** Помещается ли фигура: в поле по бокам/снизу и не наезжает на уложенное. */
    fun fits(piece: Piece, board: List<List<Shape?>>): Boolean {
        for (cell in piece.occupied) {
            if (cell.x < 0 || cell.x >= COLUMNS || cell.y >= ROWS) return false
            if (cell.y < 0) continue            // над полем — нормально при спавне
            if (board[cell.y][cell.x] != null) return false
        }
        return true
    }

    fun move(state: State, dx: Int): State {
        val p = state.piece ?: return state
        if (state.isOver) return state
        val moved = p.copy(x = p.x + dx)
        return if (fits(moved, state.board)) state.copy(piece = moved) else state
    }

    fun rotate(state: State): State {
        val p = state.piece ?: return state
        if (state.isOver) return state
        val turned = p.copy(rotation = (p.rotation + 1) % 4)
        // Простой «отскок» от стен: пробуем сдвинуть на клетку внутрь.
        for (dx in listOf(0, -1, 1, -2, 2)) {
            val candidate = turned.copy(x = turned.x + dx)
            if (fits(candidate, state.board)) return state.copy(piece = candidate)
        }
        return state
    }

    /** Шаг вниз. Если некуда — фигура фиксируется, линии сгорают, приходит новая. */
    fun tick(state: State): State {
        val p = state.piece ?: return state
        if (state.isOver) return state
        val dropped = p.copy(y = p.y + 1)
        return if (fits(dropped, state.board)) state.copy(piece = dropped) else lock(state, p)
    }

    fun hardDrop(state: State): State {
        var p = state.piece ?: return state
        if (state.isOver) return state
        while (true) {
            val down = p.copy(y = p.y + 1)
            if (fits(down, state.board)) p = down else break
        }
        return lock(state, p)
    }

    private fun lock(state: State, piece: Piece): State {
        val board = state.board.map { it.toMutableList() }.toMutableList()
        for (cell in piece.occupied) if (cell.y >= 0) board[cell.y][cell.x] = piece.shape

        // Сгоревшие линии убираем, сверху досыпаем пустые.
        val kept = board.filter { row -> row.any { it == null } }
        val cleared = ROWS - kept.size
        val result = List(cleared) { List<Shape?>(COLUMNS) { null } } + kept.map { it.toList() }

        val seed = nextSeed(state.seed)
        val spawned = Piece(state.next)
        val over = !fits(spawned, result)
        return State(
            board = result,
            piece = if (over) null else spawned,
            next = randomShape(seed),
            lines = state.lines + cleared,
            isOver = over,
            seed = seed,
        )
    }
}
