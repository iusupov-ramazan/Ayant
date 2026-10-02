import Foundation

/// «2048» — правила игры, чистые и общие для обеих платформ.
///
/// Живёт в домене по той же причине, что `Tetris`, `Match3` и `PointsMath`:
/// это арифметика без экрана, её надо считать одинаково на iOS и Android и
/// покрывать тестами. Вью остаётся только нарисовать `State` и слать свайпы.
///
/// Цветов здесь нет: плитка — это число, а чем её красить, решает слой UI
/// (как и с `Venue.gradient`).
public enum Game2048 {
    public static let size = 4

    /// Плитка, с которой начинается «победа». Партия на ней НЕ заканчивается —
    /// классика позволяет играть дальше, и отнимать это у человека незачем.
    public static let winningValue = 2048

    /// С какой плитки начинаются бонусы.
    ///
    /// Бонус даёт КАЖДАЯ новая максимальная плитка от этого значения — 128,
    /// 256, 512. Дневного потолка у мини-игр больше нет, поэтому порог и
    /// удвоение — единственный тормоз, который у этой игры есть.
    ///
    /// Ступенька — не анти-фарм от перезапусков, как считалось раньше. Плитки
    /// рождаются в основном двойками, поэтому 128 — это ~58 ходов, 512 — ~233:
    /// три партии «до 128» (~174 хода) БЫСТРЕЕ одной до 512, и выгоднее всего
    /// перезапускать после 128–256 (аудит 2026-10-01). Это не дыра: первый
    /// бонус и так стоит около минуты, то есть в общем курсе (`GameEconomy`).
    /// Удвоение лишь делает длинную партию хуже оплачиваемой — до 2048 платит
    /// ~втрое хуже курса. Защищает от фарма здесь сам порог: начни с 64 — и
    /// бонус стоил бы секунды. Порог настраивается из Remote Config
    /// (`GameRates.game2048FirstTile`), дневной лимит игры — `BonusCaps`.
    public static let bonusFromValue = 128

    public enum Direction: Sendable, CaseIterable {
        case left, right, up, down
    }

    /// Плитка поля.
    ///
    /// `id` — постоянная личность плитки, и держится он по той же причине, что
    /// и `Match3.Tile.id`: без него вью видит только «в клетке было 2, стало 4»
    /// и может лишь мгновенно перерисовать сетку. С `id` та же плитка узнаётся
    /// на новом месте, и ход превращается в скольжение, а не в подмену. В 2048
    /// это вся игра: убери `id` — и останется мигающая таблица чисел.
    public struct Tile: Identifiable, Equatable, Sendable {
        public var id: Int
        public var value: Int
        public var x: Int
        public var y: Int
        /// Плитка поглощена слиянием: она уже доехала до клетки-цели, но на
        /// следующем кадре исчезнет. Нужна только вью — показать, как две
        /// плитки съезжаются в одну, а не как одна пропадает на старом месте.
        public var absorbed: Bool
        /// Появилась на этом кадре — слиянием или досыпкой. Вью показывает
        /// «пульс» для слияния и рождение для новой.
        public var born: Bool

        public init(id: Int, value: Int, x: Int, y: Int,
                    absorbed: Bool = false, born: Bool = false) {
            self.id = id; self.value = value; self.x = x; self.y = y
            self.absorbed = absorbed; self.born = born
        }
    }

    public struct State: Equatable, Sendable {
        /// Плитки плоским списком, а не сеткой: на кадре слияния две плитки
        /// стоят в одной клетке, и `[[Tile?]]` такого состояния не выразит.
        public var tiles: [Tile]
        public var score: Int
        /// Наибольшая плитка, собранная за партию. Из неё считаются бонусы,
        /// поэтому она монотонна и не падает, даже если плитка уже слилась
        /// дальше.
        public var bestTile: Int
        public var moves: Int
        public var isOver: Bool
        /// Когда-нибудь в этой партии собиралась плитка 2048.
        public var hasWon: Bool
        /// Свой генератор, чтобы состояние оставалось воспроизводимым в тестах.
        public var seed: UInt64
        /// Следующий свободный `Tile.id`. Растёт и никогда не переиспользуется:
        /// повторный id заставил бы вью «телепортировать» новую плитку на место
        /// исчезнувшей вместо появления.
        public var nextID: Int

        public init(tiles: [Tile], score: Int, bestTile: Int, moves: Int,
                    isOver: Bool, hasWon: Bool, seed: UInt64, nextID: Int) {
            self.tiles = tiles; self.score = score; self.bestTile = bestTile
            self.moves = moves; self.isOver = isOver; self.hasWon = hasWon
            self.seed = seed; self.nextID = nextID
        }

        /// Поле без поглощённых плиток — то, что игра считает настоящим.
        public var grid: [[Tile?]] {
            var g = [[Tile?]](repeating: [Tile?](repeating: nil, count: Game2048.size),
                              count: Game2048.size)
            for tile in tiles where !tile.absorbed { g[tile.y][tile.x] = tile }
            return g
        }

        /// Заработанные бонусы (до дневного лимита — его считает `BonusEngine`).
        /// 128 → 1, 256 → 2, 512 → 3, дальше по одному за каждое удвоение.
        public var bonuses: Int { bonuses(from: Game2048.bonusFromValue) }

        /// То же с порогом из Remote Config (`GameRates.game2048FirstTile`).
        public func bonuses(from firstTile: Int) -> Int {
            let first = max(2, firstTile)
            guard bestTile >= first else { return 0 }
            var count = 0
            var step = first
            while step <= bestTile { count += 1; step *= 2 }
            return count
        }

        /// Плитка, за которую дадут следующий бонус, — её и показывает экран.
        public var nextBonusValue: Int { nextBonusValue(from: Game2048.bonusFromValue) }

        public func nextBonusValue(from firstTile: Int) -> Int {
            max(firstTile, bestTile * 2)
        }
    }

    // MARK: - Старт и случайность

    public static func start(seed: UInt64 = 0x9E3779B97F4A7C15) -> State {
        var state = State(tiles: [], score: 0, bestTile: 0, moves: 0,
                          isOver: false, hasWon: false, seed: seed, nextID: 1)
        spawn(&state)
        spawn(&state)
        state.bestTile = state.tiles.map(\.value).max() ?? 0
        return state
    }

    /// Линейный конгруэнтный генератор: нужен воспроизводимый, а не «настоящий»
    /// рандом — иначе тест на конкретную раскладку не написать.
    private static func random(_ seed: inout UInt64) -> UInt64 {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return seed >> 33
    }

    /// Досыпает плитку в свободную клетку: 2 в девяти случаях из десяти.
    private static func spawn(_ state: inout State) {
        let taken = Set(state.tiles.filter { !$0.absorbed }.map { $0.y * size + $0.x })
        let free = (0..<size * size).filter { !taken.contains($0) }
        guard !free.isEmpty else { return }
        var seed = state.seed
        let cell = free[Int(random(&seed) % UInt64(free.count))]
        let value = random(&seed) % 10 == 0 ? 4 : 2
        state.tiles.append(Tile(id: state.nextID, value: value,
                                x: cell % size, y: cell / size, born: true))
        state.nextID += 1
        state.seed = seed
    }

    // MARK: - Проверки

    /// Есть ли вообще ход: свободная клетка или пара одинаковых соседей.
    public static func canMove(_ state: State) -> Bool {
        let g = state.grid
        for y in 0..<size {
            for x in 0..<size {
                guard let tile = g[y][x] else { return true }
                if x + 1 < size, g[y][x + 1]?.value == tile.value { return true }
                if y + 1 < size, g[y + 1][x]?.value == tile.value { return true }
            }
        }
        return false
    }

    // MARK: - Ход

    /// Ход игрока: сдвигает всё поле в одну сторону.
    ///
    /// Возвращает два кадра — «доехали» и «слились» — или пустой массив, если
    /// в эту сторону ничего не двигается: такой свайп не засчитывается, и вью
    /// просто ничего не применяет.
    ///
    /// Два кадра, а не один, именно ради слияния: на первом обе плитки стоят в
    /// одной клетке со старыми значениями, на втором поглощённая исчезает, а
    /// выжившая удваивается. Одним кадром это выглядело бы как «плитка пропала
    /// на старом месте, соседняя сама поменяла число».
    public static func move(_ state: State, _ direction: Direction) -> [State] {
        guard !state.isOver else { return [] }

        let grid = state.grid
        var placements: [Placement] = []
        var moved = false
        var gained = 0

        for line in 0..<size {
            // Плитки линии в порядке «ближе к стене — раньше»: так слияние
            // всегда достаётся той, что уже ближе, и вторая въезжает в неё.
            var queue: [Tile] = []
            for slot in 0..<size {
                let c = cell(direction, line: line, slot: slot)
                if let tile = grid[c.y][c.x] { queue.append(tile) }
            }

            var slot = 0
            var i = 0
            while i < queue.count {
                let survivor = queue[i]
                let c = cell(direction, line: line, slot: slot)
                var absorbed: Tile?
                // Каждая плитка участвует в слиянии не больше одного раза за
                // ход — иначе 2·2·2·2 схлопнулось бы сразу в 8.
                if i + 1 < queue.count, queue[i + 1].value == survivor.value {
                    absorbed = queue[i + 1]
                    gained += survivor.value * 2
                    i += 2
                } else {
                    i += 1
                }
                // Ход состоялся, если хоть что-то сдвинулось или слилось.
                if absorbed != nil { moved = true }
                if survivor.x != c.x || survivor.y != c.y { moved = true }
                placements.append(Placement(survivor: survivor, absorbed: absorbed,
                                            x: c.x, y: c.y))
                slot += 1
            }
        }

        guard moved else { return [] }

        // Кадр 1: все доехали, значения прежние, поглощённые стоят на цели.
        var slid = state
        slid.moves += 1
        slid.tiles = placements.flatMap { placement -> [Tile] in
            var survivor = placement.survivor
            survivor.x = placement.x; survivor.y = placement.y
            survivor.born = false; survivor.absorbed = false
            guard var eaten = placement.absorbed else { return [survivor] }
            eaten.x = placement.x; eaten.y = placement.y
            eaten.born = false; eaten.absorbed = true
            return [survivor, eaten]
        }.sorted { $0.id < $1.id }

        // Кадр 2: поглощённые исчезают, выжившие удваиваются, приходит новая.
        var settled = slid
        settled.tiles = placements.map { placement -> Tile in
            var tile = placement.survivor
            tile.x = placement.x; tile.y = placement.y
            tile.absorbed = false
            tile.born = placement.absorbed != nil
            if placement.absorbed != nil { tile.value *= 2 }
            return tile
        }.sorted { $0.id < $1.id }
        settled.score += gained
        settled.bestTile = max(state.bestTile, settled.tiles.map(\.value).max() ?? 0)
        if settled.bestTile >= winningValue { settled.hasWon = true }
        spawn(&settled)
        settled.tiles.sort { $0.id < $1.id }
        settled.isOver = !canMove(settled)

        return [slid, settled]
    }

    /// Плитка вместе с тем, кого она поглотила, и клеткой, куда обе едут.
    private struct Placement {
        var survivor: Tile
        var absorbed: Tile?
        var x: Int
        var y: Int
    }

    /// Клетка по номеру линии и месту в ней, считая от стены, к которой едем.
    /// Одна функция и для сбора плиток, и для расстановки — поэтому порядок
    /// сбора и порядок укладки не могут разойтись.
    private static func cell(_ direction: Direction, line: Int, slot: Int) -> (x: Int, y: Int) {
        switch direction {
        case .left:  return (slot, line)
        case .right: return (size - 1 - slot, line)
        case .up:    return (line, slot)
        case .down:  return (line, size - 1 - slot)
        }
    }
}
