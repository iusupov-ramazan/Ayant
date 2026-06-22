import SpriteKit
import GameplayKit

/// Тетрис на SpriteKit: единый игровой цикл update(_:) с гравитацией,
/// GKStateMachine для состояний (играем / конец), GKRandomSource для «мешка» фигур,
/// SKEmitterNode-вспышка при сборе линий.
final class TetrisScene: SKScene {

    // Колбэки наружу (в SwiftUI)
    var onScoreChange: ((Int) -> Void)?
    var onLinesChange: ((Int) -> Void)?
    var onGameOver: ((Int, Int) -> Void)?   // (score, lines)

    // Сетка (стандарт Тетриса 10×20)
    private let cols = 10
    private let rows = 20
    private var cell: CGFloat = 20
    private var origin: CGPoint = .zero

    // Поле: nil = пусто, иначе индекс цвета фигуры.
    // Инициализируем сразу нужного размера — didChangeSize/redraw могут
    // сработать до startGame(), а они обходят сетку по rows×cols.
    private lazy var board: [[Int?]] =
        Array(repeating: Array(repeating: nil, count: cols), count: rows)

    // Текущая фигура
    private var current: Tetromino = .empty
    private var pos = TetrisPoint(x: 0, y: 0)   // позиция «origin» фигуры в клетках поля

    // Счёт
    private(set) var score = 0
    private(set) var lines = 0

    // Игровой цикл (гравитация)
    private var dropInterval: TimeInterval = 0.6
    private let softDropInterval: TimeInterval = 0.05
    private var softDropping = false
    private var accumulator: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0

    // Узлы
    private let gridLayer = SKNode()    // фон + сетка + водяной знак
    private let stackLayer = SKNode()   // застывшие блоки
    private let pieceLayer = SKNode()   // текущая фигура

    // GameplayKit
    private let random = GKRandomSource.sharedRandom()
    private var bag: [Int] = []
    private lazy var stateMachine = GKStateMachine(states: [
        TetrisPlayingState(scene: self),
        TetrisGameOverState(scene: self)
    ])

    // MARK: Жизненный цикл

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        addChild(gridLayer)
        addChild(stackLayer)
        addChild(pieceLayer)
        computeGrid()
        addGestureRecognizers(to: view)
        startGame()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        computeGrid()
        redraw()
    }

    private func computeGrid() {
        cell = min(size.width / CGFloat(cols), size.height / CGFloat(rows))
        let boardW = cell * CGFloat(cols)
        let boardH = cell * CGFloat(rows)
        origin = CGPoint(x: (size.width - boardW) / 2,
                         y: (size.height - boardH) / 2)
        buildGrid(boardW: boardW, boardH: boardH)
    }

    /// Скруглённый фон поля + клетки сетки + водяной знак.
    private func buildGrid(boardW: CGFloat, boardH: CGFloat) {
        gridLayer.removeAllChildren()
        let boardRect = CGRect(x: origin.x, y: origin.y, width: boardW, height: boardH)

        let bg = SKShapeNode(rect: boardRect, cornerRadius: 12)
        bg.fillColor = SKColor.systemGray6
        bg.strokeColor = .clear
        gridLayer.addChild(bg)

        // тонкие линии сетки
        let path = CGMutablePath()
        for c in 1..<cols {
            let x = origin.x + CGFloat(c) * cell
            path.move(to: CGPoint(x: x, y: origin.y))
            path.addLine(to: CGPoint(x: x, y: origin.y + boardH))
        }
        for r in 1..<rows {
            let y = origin.y + CGFloat(r) * cell
            path.move(to: CGPoint(x: origin.x, y: y))
            path.addLine(to: CGPoint(x: origin.x + boardW, y: y))
        }
        let lines = SKShapeNode(path: path)
        lines.strokeColor = SKColor.gray.withAlphaComponent(0.22)
        lines.lineWidth = 1
        gridLayer.addChild(lines)

        // водяной знак по центру поля
        let watermark = SKLabelNode(text: "Здесь может быть ваша реклама")
        watermark.fontName = "AvenirNext-Bold"
        watermark.fontSize = min(boardW, boardH) * 0.07
        watermark.fontColor = SKColor.gray.withAlphaComponent(0.16)
        watermark.verticalAlignmentMode = .center
        watermark.horizontalAlignmentMode = .center
        watermark.numberOfLines = 2
        watermark.preferredMaxLayoutWidth = boardW * 0.8
        watermark.position = CGPoint(x: origin.x + boardW / 2,
                                     y: origin.y + boardH / 2)
        gridLayer.addChild(watermark)
    }

    // MARK: Управление игрой

    func startGame() {
        board = Array(repeating: Array(repeating: nil, count: cols), count: rows)
        score = 0; lines = 0
        onScoreChange?(0); onLinesChange?(0)
        dropInterval = 0.6
        softDropping = false
        accumulator = 0
        lastUpdate = 0
        bag.removeAll()
        spawnPiece()
        stateMachine.enter(TetrisPlayingState.self)
        redraw()
    }

    // Раздаём фигуры «мешком» по 7 — честная случайность как в современном Тетрисе.
    private func nextFromBag() -> Int {
        if bag.isEmpty {
            bag = Array(0..<7)
            // перетасовка Фишера–Йетса на GKRandomSource
            for i in stride(from: bag.count - 1, to: 0, by: -1) {
                let j = random.nextInt(upperBound: i + 1)
                bag.swapAt(i, j)
            }
        }
        return bag.removeLast()
    }

    private func spawnPiece() {
        current = Tetromino.make(nextFromBag())
        // появление сверху по центру (y растёт вверх, верх поля = rows-1)
        pos = TetrisPoint(x: cols / 2 - 2, y: rows - current.boundingHeight)
        if collides(current.blocks, at: pos) {
            stateMachine.enter(TetrisGameOverState.self)
        }
    }

    // MARK: Действия игрока

    func moveLeft()  { tryMove(dx: -1, dy: 0) }
    func moveRight() { tryMove(dx:  1, dy: 0) }

    func rotate() {
        guard stateMachine.currentState is TetrisPlayingState else { return }
        let rotated = current.rotated()
        // wall-kick: пробуем на месте, затем сдвиги ±1, ±2 по X
        for dx in [0, -1, 1, -2, 2] {
            let p = TetrisPoint(x: pos.x + dx, y: pos.y)
            if !collides(rotated.blocks, at: p) {
                current = rotated
                pos = p
                redraw()
                return
            }
        }
    }

    func setSoftDrop(_ on: Bool) { softDropping = on }

    /// Жёсткий сброс — фигура падает до упора.
    func hardDrop() {
        guard stateMachine.currentState is TetrisPlayingState else { return }
        while !collides(current.blocks, at: TetrisPoint(x: pos.x, y: pos.y - 1)) {
            pos.y -= 1
        }
        lockPiece()
    }

    @discardableResult
    private func tryMove(dx: Int, dy: Int) -> Bool {
        guard stateMachine.currentState is TetrisPlayingState else { return false }
        let p = TetrisPoint(x: pos.x + dx, y: pos.y + dy)
        guard !collides(current.blocks, at: p) else { return false }
        pos = p
        redraw()
        return true
    }

    // MARK: Игровой цикл

    override func update(_ currentTime: TimeInterval) {
        guard stateMachine.currentState is TetrisPlayingState else { return }
        if lastUpdate == 0 { lastUpdate = currentTime }
        let delta = currentTime - lastUpdate
        lastUpdate = currentTime

        accumulator += delta
        let interval = softDropping ? softDropInterval : dropInterval
        while accumulator >= interval {
            accumulator -= interval
            gravityStep()
        }
    }

    private func gravityStep() {
        // пробуем опустить фигуру на одну клетку; если нельзя — фиксируем
        if !tryMove(dx: 0, dy: -1) {
            lockPiece()
        }
    }

    private func lockPiece() {
        for b in current.blocks {
            let x = pos.x + b.x
            let y = pos.y + b.y
            if y >= 0 && y < rows && x >= 0 && x < cols {
                board[y][x] = current.colorIndex
            }
        }
        clearLines()
        // softDropping не сбрасываем — им управляет удержание пальца (touchesBegan/Ended)
        spawnPiece()
        redraw()
    }

    private func clearLines() {
        var cleared = 0
        var newBoard: [[Int?]] = []
        for r in 0..<rows {
            if board[r].allSatisfy({ $0 != nil }) {
                cleared += 1
                burstRow(r)   // вспышка по линии
            } else {
                newBoard.append(board[r])
            }
        }
        guard cleared > 0 else { return }
        // дополняем пустыми рядами сверху
        while newBoard.count < rows {
            newBoard.append(Array(repeating: nil, count: cols))
        }
        board = newBoard

        lines += cleared
        onLinesChange?(lines)
        // классический счёт: 1→100, 2→300, 3→500, 4→800
        let points = [0, 100, 300, 500, 800][min(cleared, 4)]
        score += points
        onScoreChange?(score)

        // ускорение каждые 5 линий
        let level = lines / 5
        dropInterval = max(0.10, 0.6 - Double(level) * 0.05)

        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func collides(_ blocks: [TetrisPoint], at p: TetrisPoint) -> Bool {
        for b in blocks {
            let x = p.x + b.x
            let y = p.y + b.y
            if x < 0 || x >= cols || y < 0 { return true }
            if y < rows && board[y][x] != nil { return true }
        }
        return false
    }

    // MARK: Отрисовка

    private func cellRect(col: Int, row: Int) -> CGRect {
        CGRect(x: origin.x + CGFloat(col) * cell + 1,
               y: origin.y + CGFloat(row) * cell + 1,
               width: cell - 2, height: cell - 2)
    }

    private func block(col: Int, row: Int, color: SKColor) -> SKShapeNode {
        let node = SKShapeNode(rect: cellRect(col: col, row: row), cornerRadius: 3)
        node.fillColor = color
        node.strokeColor = SKColor.black.withAlphaComponent(0.15)
        node.lineWidth = 1
        return node
    }

    private func redraw() {
        // Защита: пропускаем отрисовку, пока поле не нужного размера.
        guard board.count == rows, board.allSatisfy({ $0.count == cols }) else { return }
        stackLayer.removeAllChildren()
        for r in 0..<rows {
            for c in 0..<cols {
                if let idx = board[r][c] {
                    stackLayer.addChild(block(col: c, row: r, color: Tetromino.color(idx)))
                }
            }
        }

        pieceLayer.removeAllChildren()
        guard stateMachine.currentState is TetrisPlayingState else { return }
        let color = Tetromino.color(current.colorIndex)
        for b in current.blocks {
            let x = pos.x + b.x
            let y = pos.y + b.y
            if y < rows {
                pieceLayer.addChild(block(col: x, row: y, color: color))
            }
        }
    }

    /// Вспышка частиц вдоль собранной линии.
    private func burstRow(_ r: Int) {
        let emitter = SKEmitterNode()
        emitter.particleTexture = nil
        emitter.particleColor = SKColor(red: 1, green: 0.70, blue: 0.0, alpha: 1)
        emitter.particleColorBlendFactor = 1
        emitter.particleBirthRate = 1200
        emitter.numParticlesToEmit = 40
        emitter.particleLifetime = 0.4
        emitter.particleSpeed = 120
        emitter.particleSpeedRange = 60
        emitter.emissionAngleRange = .pi * 2
        emitter.particleScale = 0.25
        emitter.particleScaleRange = 0.1
        emitter.particleAlphaSpeed = -2.5
        emitter.particlePositionRange = CGVector(dx: cell * CGFloat(cols), dy: cell)
        emitter.position = CGPoint(x: origin.x + cell * CGFloat(cols) / 2,
                                   y: origin.y + (CGFloat(r) + 0.5) * cell)
        emitter.zPosition = 10
        addChild(emitter)
        emitter.run(.sequence([.wait(forDuration: 0.5), .removeFromParent()]))
    }

    fileprivate func notifyGameOver() {
        onGameOver?(score, lines)
    }

    // MARK: Жесты
    // Тап — поворот; свайпы — движение влево/вправо, вниз = софт-дроп,
    // вверх = жёсткий сброс. cancelsTouchesInView не трогаем — модалка полноэкранная.

    private func addGestureRecognizers(to view: SKView) {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        let dirs: [(UISwipeGestureRecognizer.Direction)] = [.left, .right, .down, .up]
        for d in dirs {
            let r = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            r.direction = d
            r.cancelsTouchesInView = false   // чтобы scene получала touchesBegan/Ended для «удержания»
            view.addGestureRecognizer(r)
        }
    }

    // Удержание пальца дольше 2 секунд — ускоренное падение (софт-дроп).
    private let softDropHoldDelay: TimeInterval = 2.0
    private let softDropDelayKey = "softDropDelay"

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Запускаем софт-дроп только после удержания дольше softDropHoldDelay.
        removeAction(forKey: softDropDelayKey)
        run(.sequence([
            .wait(forDuration: softDropHoldDelay),
            .run { [weak self] in self?.setSoftDrop(true) }
        ]), withKey: softDropDelayKey)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endHold()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endHold()
    }

    private func endHold() {
        removeAction(forKey: softDropDelayKey)   // отменяем отложенный запуск, если не дождались
        setSoftDrop(false)
    }

    @objc private func handleTap() { rotate() }

    @objc private func handleSwipe(_ r: UISwipeGestureRecognizer) {
        switch r.direction {
        case .left:  moveLeft()
        case .right: moveRight()
        case .down:  hardDrop()
        case .up:    rotate()
        default: break
        }
    }
}

// MARK: - Типы фигур

struct TetrisPoint: Equatable { var x: Int; var y: Int }

/// Тетромино: набор из 4 клеток (относительно origin), индекс цвета.
struct Tetromino: Equatable {
    var blocks: [TetrisPoint]
    var colorIndex: Int

    static let empty = Tetromino(blocks: [], colorIndex: 0)

    /// Высота ограничивающей рамки (для появления у верхнего края).
    var boundingHeight: Int {
        (blocks.map { $0.y }.max() ?? 0) + 1
    }

    /// Поворот на 90° по часовой относительно центра рамки.
    func rotated() -> Tetromino {
        guard !blocks.isEmpty else { return self }
        let maxY = blocks.map { $0.y }.max() ?? 0
        // (x, y) -> (y, maxY - x)
        let r = blocks.map { TetrisPoint(x: $0.y, y: maxY - $0.x) }
        return Tetromino(blocks: r, colorIndex: colorIndex)
    }

    // Семь канонических фигур. Координаты заданы так, что y растёт вверх.
    static func make(_ i: Int) -> Tetromino {
        switch i {
        case 0: // I
            return Tetromino(blocks: [.init(x:0,y:1),.init(x:1,y:1),.init(x:2,y:1),.init(x:3,y:1)], colorIndex: 0)
        case 1: // O
            return Tetromino(blocks: [.init(x:0,y:0),.init(x:1,y:0),.init(x:0,y:1),.init(x:1,y:1)], colorIndex: 1)
        case 2: // T
            return Tetromino(blocks: [.init(x:0,y:0),.init(x:1,y:0),.init(x:2,y:0),.init(x:1,y:1)], colorIndex: 2)
        case 3: // S
            return Tetromino(blocks: [.init(x:0,y:0),.init(x:1,y:0),.init(x:1,y:1),.init(x:2,y:1)], colorIndex: 3)
        case 4: // Z
            return Tetromino(blocks: [.init(x:1,y:0),.init(x:2,y:0),.init(x:0,y:1),.init(x:1,y:1)], colorIndex: 4)
        case 5: // J
            return Tetromino(blocks: [.init(x:0,y:0),.init(x:1,y:0),.init(x:2,y:0),.init(x:0,y:1)], colorIndex: 5)
        default: // L
            return Tetromino(blocks: [.init(x:0,y:0),.init(x:1,y:0),.init(x:2,y:0),.init(x:2,y:1)], colorIndex: 6)
        }
    }

    static func color(_ i: Int) -> SKColor {
        switch i {
        case 0: return SKColor(red: 0.0,  green: 0.78, blue: 0.85, alpha: 1) // I — голубой
        case 1: return SKColor(red: 0.98, green: 0.80, blue: 0.10, alpha: 1) // O — жёлтый
        case 2: return SKColor(red: 0.65, green: 0.32, blue: 0.90, alpha: 1) // T — фиолетовый
        case 3: return SKColor(red: 0.25, green: 0.78, blue: 0.35, alpha: 1) // S — зелёный
        case 4: return SKColor(red: 0.95, green: 0.27, blue: 0.27, alpha: 1) // Z — красный
        case 5: return SKColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1) // J — синий
        default: return SKColor(red: 1.0,  green: 0.50, blue: 0.10, alpha: 1) // L — оранжевый
        }
    }
}

// MARK: - Состояния (GameplayKit)

private final class TetrisPlayingState: GKState {
    unowned let scene: TetrisScene
    init(scene: TetrisScene) { self.scene = scene }
    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        stateClass == TetrisGameOverState.self
    }
}

private final class TetrisGameOverState: GKState {
    unowned let scene: TetrisScene
    init(scene: TetrisScene) { self.scene = scene }
    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        stateClass == TetrisPlayingState.self
    }
    override func didEnter(from previousState: GKState?) {
        scene.notifyGameOver()
    }
}
