import SpriteKit
import GameplayKit

/// Змейка на SpriteKit: единый игровой цикл update(_:),
/// GameplayKit для состояний (GKStateMachine) и честного рандома (GKRandomSource),
/// SKEmitterNode-«сок» при сборе яблока.
final class SnakeScene: SKScene {

    // Колбэки наружу (в SwiftUI)
    var onScoreChange: ((Int) -> Void)?
    var onGameOver: ((Int) -> Void)?

    // Сетка
    private let cols = 15
    private let rows = 20
    private var cell: CGFloat = 20
    private var origin: CGPoint = .zero

    // Состояние игры
    private var snake: [Point] = []
    private var food = Point(x: 0, y: 0)
    private var dir: Direction = .right
    private var pendingDir: Direction = .right
    private(set) var score = 0

    // Игровой цикл
    private let moveInterval: TimeInterval = 0.16
    private var accumulator: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0

    // Узлы
    private let gridLayer = SKNode()
    private let snakeLayer = SKNode()
    private let foodNode = SKShapeNode()

    // GameplayKit
    private let random = GKRandomSource.sharedRandom()
    private lazy var stateMachine = GKStateMachine(states: [
        PlayingState(scene: self),
        GameOverState(scene: self)
    ])

    // MARK: Жизненный цикл

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        addChild(gridLayer)
        addChild(snakeLayer)
        addChild(foodNode)
        computeGrid()
        addSwipeRecognizers(to: view)
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
        // эллипс центрируем относительно узла, иначе еда смещается к краю клетки
        let d = cell - 3
        foodNode.path = CGPath(ellipseIn: CGRect(x: -d / 2, y: -d / 2, width: d, height: d),
                               transform: nil)
        foodNode.fillColor = SKColor(red: 1, green: 0.30, blue: 0.16, alpha: 1)
        foodNode.strokeColor = .clear
        buildGrid(boardW: boardW, boardH: boardH)
    }

    /// Скруглённый фон поля + залитые клетки (шахматка) + водяной знак.
    private func buildGrid(boardW: CGFloat, boardH: CGFloat) {
        gridLayer.removeAllChildren()
        let boardRect = CGRect(x: origin.x, y: origin.y, width: boardW, height: boardH)

        // фон поля
        let bg = SKShapeNode(rect: boardRect, cornerRadius: 12)
        bg.fillColor = SKColor.systemGray6
        bg.strokeColor = .clear
        gridLayer.addChild(bg)

        // залитые клетки в шахматном порядке — квадраты читаются чётко
        for r in 0..<rows {
            for c in 0..<cols where (r + c) % 2 == 0 {
                let tile = SKShapeNode(rect: CGRect(
                    x: origin.x + CGFloat(c) * cell,
                    y: origin.y + CGFloat(r) * cell,
                    width: cell, height: cell), cornerRadius: 2)
                tile.fillColor = SKColor.gray.withAlphaComponent(0.12)
                tile.strokeColor = .clear
                gridLayer.addChild(tile)
            }
        }

        // тонкие линии сетки поверх плиток
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
        lines.strokeColor = SKColor.gray.withAlphaComponent(0.3)
        lines.lineWidth = 1
        gridLayer.addChild(lines)

        // водяной знак по центру поля
        let watermark = SKLabelNode(text: "Здесь может быть ваша реклама")
        watermark.fontName = "AvenirNext-Bold"
        watermark.fontSize = min(boardW, boardH) * 0.11
        watermark.fontColor = SKColor.gray.withAlphaComponent(0.18)
        watermark.verticalAlignmentMode = .center
        watermark.horizontalAlignmentMode = .center
        watermark.position = CGPoint(x: origin.x + boardW / 2,
                                     y: origin.y + boardH / 2)
        gridLayer.addChild(watermark)
    }

    // MARK: Управление игрой

    func startGame() {
        snake = [Point(x: cols / 3, y: rows / 2)]
        dir = .right; pendingDir = .right
        score = 0
        onScoreChange?(0)
        placeFood()
        accumulator = 0
        stateMachine.enter(PlayingState.self)
        redraw()
    }

    func turn(_ d: Direction) {
        guard stateMachine.currentState is PlayingState, d != dir.opposite else { return }
        pendingDir = d
    }

    // MARK: Игровой цикл

    override func update(_ currentTime: TimeInterval) {
        guard stateMachine.currentState is PlayingState else { return }
        if lastUpdate == 0 { lastUpdate = currentTime }
        let delta = currentTime - lastUpdate
        lastUpdate = currentTime

        accumulator += delta
        while accumulator >= moveInterval {
            accumulator -= moveInterval
            step()
        }
    }

    private func step() {
        dir = pendingDir
        var head = snake[0]
        switch dir {
        case .up: head.y += 1
        case .down: head.y -= 1
        case .left: head.x -= 1
        case .right: head.x += 1
        }

        if head.x < 0 || head.y < 0 || head.x >= cols || head.y >= rows
            || snake.contains(head) {
            stateMachine.enter(GameOverState.self)
            return
        }

        snake.insert(head, at: 0)
        if head == food {
            score += 1
            onScoreChange?(score)
            burst(at: head)
            placeFood()
        } else {
            snake.removeLast()
        }
        redraw()
    }

    private func placeFood() {
        // Не ставим еду на самую кромку поля — отступ в одну клетку.
        var p: Point
        repeat {
            p = Point(x: 1 + random.nextInt(upperBound: cols - 2),
                      y: 1 + random.nextInt(upperBound: rows - 2))
        } while snake.contains(p)
        food = p
    }

    // MARK: Отрисовка

    private func point(_ p: Point) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(p.x) * cell + cell / 2,
                y: origin.y + CGFloat(p.y) * cell + cell / 2)
    }

    private func redraw() {
        foodNode.position = point(food)

        snakeLayer.removeAllChildren()
        for (i, seg) in snake.enumerated() {
            let node = SKShapeNode(rectOf: CGSize(width: cell - 2, height: cell - 2),
                                   cornerRadius: i == 0 ? 5 : 3)
            node.position = point(seg)
            node.strokeColor = .clear
            node.fillColor = i == 0
                ? SKColor.systemGreen
                : SKColor.systemGreen.withAlphaComponent(0.7)
            snakeLayer.addChild(node)
        }
    }

    /// «Сок»: вспышка частиц при сборе яблока
    private func burst(at p: Point) {
        let emitter = SKEmitterNode()
        emitter.particleTexture = nil
        emitter.particleColor = SKColor(red: 1, green: 0.30, blue: 0.16, alpha: 1)
        emitter.particleColorBlendFactor = 1
        emitter.particleBirthRate = 600
        emitter.numParticlesToEmit = 18
        emitter.particleLifetime = 0.4
        emitter.particleSpeed = 90
        emitter.particleSpeedRange = 40
        emitter.emissionAngleRange = .pi * 2
        emitter.particleScale = 0.25
        emitter.particleScaleRange = 0.1
        emitter.particleAlphaSpeed = -2.5
        emitter.position = point(p)
        emitter.zPosition = 5
        addChild(emitter)
        emitter.run(.sequence([.wait(forDuration: 0.5), .removeFromParent()]))
    }

    fileprivate func notifyGameOver() {
        onGameOver?(score)
    }

    // MARK: Свайпы

    private func addSwipeRecognizers(to view: SKView) {
        let dirs: [(UISwipeGestureRecognizer.Direction, Direction)] = [
            (.up, .up), (.down, .down), (.left, .left), (.right, .right)
        ]
        for (uiDir, gameDir) in dirs {
            let r = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            r.direction = uiDir
            r.name = "\(gameDir)"
            view.addGestureRecognizer(r)
        }
    }

    @objc private func handleSwipe(_ r: UISwipeGestureRecognizer) {
        switch r.direction {
        case .up: turn(.up)
        case .down: turn(.down)
        case .left: turn(.left)
        case .right: turn(.right)
        default: break
        }
    }
}

// MARK: - Состояния (GameplayKit)

private final class PlayingState: GKState {
    unowned let scene: SnakeScene
    init(scene: SnakeScene) { self.scene = scene }
    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        stateClass == GameOverState.self
    }
}

private final class GameOverState: GKState {
    unowned let scene: SnakeScene
    init(scene: SnakeScene) { self.scene = scene }
    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        stateClass == PlayingState.self
    }
    override func didEnter(from previousState: GKState?) {
        scene.notifyGameOver()
    }
}
