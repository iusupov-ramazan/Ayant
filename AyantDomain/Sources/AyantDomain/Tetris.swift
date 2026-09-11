import Foundation

/// Правила тетриса — чистые и общие для обеих платформ.
///
/// Игра живёт в домене по той же причине, что `Ranking` и `PointsMath`: это
/// арифметика без экрана, её надо считать одинаково на iOS и Android и покрывать
/// тестами. Вью остаётся только нарисовать `State` и слать ходы.
///
/// Прошлая версия тетриса была на SpriteKit, у которого нет пары в Compose —
/// поэтому её и убрали. Здесь только сетка, так что обе платформы рисуют её
/// штатными средствами.
public enum Tetris {
    public static let columns = 10
    public static let rows = 20

    /// Сколько бонусов даёт одна линия. Начисление всё равно проходит через
    /// общий дневной лимит мини-игр — своей экономики у игры нет.
    public static let bonusPerLine = 5

    public enum Shape: Int, CaseIterable, Sendable {
        case i, o, t, s, z, j, l
    }

    /// Занятые клетки фигуры в её рамке 4×4 для каждого поворота.
    public static func cells(_ shape: Shape, rotation: Int) -> [(x: Int, y: Int)] {
        let r = ((rotation % 4) + 4) % 4
        switch shape {
        case .i:  return r % 2 == 0 ? [(0,1),(1,1),(2,1),(3,1)] : [(2,0),(2,1),(2,2),(2,3)]
        case .o:  return [(1,0),(2,0),(1,1),(2,1)]
        case .s:  return r % 2 == 0 ? [(1,0),(2,0),(0,1),(1,1)] : [(1,0),(1,1),(2,1),(2,2)]
        case .z:  return r % 2 == 0 ? [(0,0),(1,0),(1,1),(2,1)] : [(2,0),(1,1),(2,1),(1,2)]
        case .t:
            switch r {
            case 0: return [(1,0),(0,1),(1,1),(2,1)]
            case 1: return [(1,0),(1,1),(2,1),(1,2)]
            case 2: return [(0,1),(1,1),(2,1),(1,2)]
            default: return [(1,0),(0,1),(1,1),(1,2)]
            }
        case .j:
            switch r {
            case 0: return [(0,0),(0,1),(1,1),(2,1)]
            case 1: return [(1,0),(2,0),(1,1),(1,2)]
            case 2: return [(0,1),(1,1),(2,1),(2,2)]
            default: return [(1,0),(1,1),(0,2),(1,2)]
            }
        case .l:
            switch r {
            case 0: return [(2,0),(0,1),(1,1),(2,1)]
            case 1: return [(1,0),(1,1),(1,2),(2,2)]
            case 2: return [(0,1),(1,1),(2,1),(0,2)]
            default: return [(0,0),(1,0),(1,1),(1,2)]
            }
        }
    }

    public struct Piece: Equatable, Sendable {
        public var shape: Shape
        public var rotation: Int
        /// Левый верхний угол рамки 4×4 в координатах поля.
        public var x: Int
        public var y: Int

        public init(shape: Shape, rotation: Int = 0, x: Int = 3, y: Int = -1) {
            self.shape = shape; self.rotation = rotation; self.x = x; self.y = y
        }

        /// Занятые клетки в координатах поля.
        public var occupied: [(x: Int, y: Int)] {
            Tetris.cells(shape, rotation: rotation).map { (x + $0.x, y + $0.y) }
        }
    }

    public struct State: Equatable, Sendable {
        /// Уложенные клетки: `rows` × `columns`, `nil` — пусто.
        public var board: [[Shape?]]
        public var piece: Piece?
        public var next: Shape
        public var lines: Int
        public var isOver: Bool
        /// Свой генератор, чтобы состояние оставалось воспроизводимым в тестах.
        public var seed: UInt64

        public init(board: [[Shape?]], piece: Piece?, next: Shape,
                    lines: Int, isOver: Bool, seed: UInt64) {
            self.board = board; self.piece = piece; self.next = next
            self.lines = lines; self.isOver = isOver; self.seed = seed
        }

        /// Заработанные бонусы (до дневного лимита — его считает `BonusEngine`).
        public var bonuses: Int { lines * Tetris.bonusPerLine }
    }

    // MARK: - Старт и случайность

    public static func start(seed: UInt64 = 0x9E3779B97F4A7C15) -> State {
        var s = seed
        let first = randomShape(&s)
        let next = randomShape(&s)
        let empty = [[Shape?]](repeating: [Shape?](repeating: nil, count: columns), count: rows)
        return State(board: empty, piece: Piece(shape: first), next: next,
                     lines: 0, isOver: false, seed: s)
    }

    /// Линейный конгруэнтный генератор: нужен воспроизводимый, а не «настоящий»
    /// рандом — иначе тест на конкретную раскладку не написать.
    private static func randomShape(_ seed: inout UInt64) -> Shape {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Shape(rawValue: Int((seed >> 33) % UInt64(Shape.allCases.count))) ?? .i
    }

    // MARK: - Проверки

    /// Помещается ли фигура: в поле по бокам/снизу и не наезжает на уложенное.
    public static func fits(_ piece: Piece, in board: [[Shape?]]) -> Bool {
        for cell in piece.occupied {
            if cell.x < 0 || cell.x >= columns || cell.y >= rows { return false }
            if cell.y < 0 { continue }          // над полем — это нормально при спавне
            if board[cell.y][cell.x] != nil { return false }
        }
        return true
    }

    // MARK: - Ходы

    public static func move(_ state: State, dx: Int) -> State {
        guard var p = state.piece, !state.isOver else { return state }
        p.x += dx
        guard fits(p, in: state.board) else { return state }
        var next = state; next.piece = p; return next
    }

    public static func rotate(_ state: State) -> State {
        guard var p = state.piece, !state.isOver else { return state }
        p.rotation = (p.rotation + 1) % 4
        // Простой «отскок» от стен: пробуем сдвинуть на клетку внутрь.
        for dx in [0, -1, 1, -2, 2] {
            var candidate = p
            candidate.x += dx
            if fits(candidate, in: state.board) {
                var next = state; next.piece = candidate; return next
            }
        }
        return state
    }

    /// Шаг вниз. Если некуда — фигура фиксируется, линии сгорают, приходит новая.
    public static func tick(_ state: State) -> State {
        guard let p = state.piece, !state.isOver else { return state }
        var dropped = p
        dropped.y += 1
        if fits(dropped, in: state.board) {
            var next = state; next.piece = dropped; return next
        }
        return lock(state, piece: p)
    }

    public static func hardDrop(_ state: State) -> State {
        guard var p = state.piece, !state.isOver else { return state }
        while true {
            var down = p
            down.y += 1
            if fits(down, in: state.board) { p = down } else { break }
        }
        return lock(state, piece: p)
    }

    private static func lock(_ state: State, piece: Piece) -> State {
        var board = state.board
        for cell in piece.occupied where cell.y >= 0 {
            board[cell.y][cell.x] = piece.shape
        }
        // Сгоревшие линии убираем, сверху досыпаем пустые.
        let kept = board.filter { row in row.contains(where: { $0 == nil }) }
        let cleared = rows - kept.count
        let empty = [Shape?](repeating: nil, count: columns)
        board = [[Shape?]](repeating: empty, count: cleared) + kept

        var seed = state.seed
        let spawned = Piece(shape: state.next)
        let following = randomShape(&seed)
        let over = !fits(spawned, in: board)

        return State(board: board,
                     piece: over ? nil : spawned,
                     next: following,
                     lines: state.lines + cleared,
                     isOver: over,
                     seed: seed)
    }
}
