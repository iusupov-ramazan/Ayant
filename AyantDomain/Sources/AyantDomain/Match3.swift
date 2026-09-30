import Foundation

/// «Три в ряд» — правила игры, чистые и общие для обеих платформ.
///
/// Живёт в домене по той же причине, что `Tetris` и `PointsMath`: это
/// арифметика без экрана, её надо считать одинаково на iOS и Android и покрывать
/// тестами. Вью остаётся только нарисовать `State` и слать ходы.
///
/// Никаких эмодзи и цветов здесь нет: `Kind` — это идентичность фишки, а чем её
/// рисовать, решает слой UI (как и с `Venue.gradient`).
public enum Match3 {
    public static let columns = 7
    public static let rows = 7

    // Лимита ходов нет: партия бесконечная и заканчивается, только когда игрок
    // выходит. Застрять нельзя — поле без ходов перемешивается (`shuffled`).
    // Заработок за бесконечную игру ограничивает дневной потолок
    // `GameEconomy.endlessDailyBonusCap`, который держит `BonusEngine`.

    /// Сколько совпадений даёт один бонус — из общего курса мини-игр.
    ///
    /// Своего числа у игры больше нет: цена выводится из `GameEconomy`, иначе
    /// игры снова разъедутся по курсу, как разъехались под дневным потолком.
    public static var matchesPerBonus: Int { GameEconomy.matchesPerBonus }

    /// Очков за одну сгоревшую фишку (до множителя каскада).
    public static let pointsPerTile = 10

    /// Виды фишек. Шесть — меньше делает поле слишком «самособирающимся»,
    /// больше — превращает поиск хода в работу.
    ///
    /// Названия — камни, а не еда: на поле рисуются самоцветы. Домен по-прежнему
    /// не знает ни цветов, ни картинок — это просто шесть разных личностей,
    /// а чем их рисовать, решает слой UI.
    public enum Kind: Int, CaseIterable, Sendable {
        case ruby, amethyst, rose, gold, emerald, sapphire
    }

    /// Спецсвойство фишки. Срабатывает, когда фишка сгорает в совпадении, —
    /// отдельного «тапа по бомбе» нет, иначе ход перестаёт быть одним обменом.
    public enum Power: Equatable, Sendable {
        case none
        /// Полоска из четвёрки: сжигает ряд, в котором собралась.
        case line(horizontal: Bool)
        /// Бомба из пятёрки: сжигает квадрат 3×3 вокруг себя.
        case bomb
    }

    public struct Tile: Equatable, Identifiable, Sendable {
        /// Постоянная личность фишки: она переживает падение и досыпку.
        ///
        /// Без неё вью видит только «в клетке (2,5) была пицца, стала кола» и
        /// может лишь мгновенно перерисовать сетку. С `id` та же фишка узнаётся
        /// на новом месте, и падение становится движением, а не подменой.
        public var id: Int
        public var kind: Kind
        public var power: Power

        public init(id: Int, kind: Kind, power: Power = .none) {
            self.id = id; self.kind = kind; self.power = power
        }
    }

    public struct Point: Hashable, Sendable {
        public var x: Int
        public var y: Int
        public init(x: Int, y: Int) { self.x = x; self.y = y }
    }

    /// Одно совпадение: подряд идущие фишки одного вида.
    public struct Group: Equatable, Sendable {
        public var points: [Point]
        public var horizontal: Bool

        public init(points: [Point], horizontal: Bool) {
            self.points = points; self.horizontal = horizontal
        }
    }

    public struct State: Equatable, Sendable {
        /// Поле `rows` × `columns`. Пустых клеток не бывает: всё, что сгорело,
        /// в том же шаге досыпается сверху.
        public var board: [[Tile]]
        public var score: Int
        public var level: Int
        /// Сколько совпадений собрано за партию — из этого считаются бонусы.
        public var matches: Int
        /// Свой генератор, чтобы состояние оставалось воспроизводимым в тестах.
        public var seed: UInt64
        /// Клетки, которые сгорают на этом кадре. Нужны только вью — показать
        /// вспышку до того, как фишки исчезнут.
        public var clearing: Set<Point>
        /// Следующий свободный `Tile.id`. Растёт и никогда не переиспользуется:
        /// повторный id заставил бы вью «телепортировать» новую фишку на место
        /// сгоревшей вместо падения сверху.
        public var nextID: Int

        public init(board: [[Tile]], score: Int, level: Int,
                    matches: Int, seed: UInt64, clearing: Set<Point>,
                    nextID: Int = 1) {
            self.board = board; self.score = score
            self.level = level; self.matches = matches
            self.seed = seed; self.clearing = clearing; self.nextID = nextID
        }

        /// Цель текущего уровня (очки копятся за партию, а не за уровень).
        public var goal: Int { Match3.goal(forLevel: level) }

        /// Заработанные бонусы (до дневного потолка — его держит `BonusEngine`).
        public var bonuses: Int { matches / Match3.matchesPerBonus }

        /// Прогресс внутри уровня, 0…1. Очки копятся за партию, поэтому
        /// отсчёт идёт от цели предыдущего уровня, а не от нуля.
        public var levelProgress: Double {
            let from = level > 1 ? Match3.goal(forLevel: level - 1) : 0
            let span = goal - from
            guard span > 0 else { return 1 }
            return min(1, max(0, Double(score - from) / Double(span)))
        }
    }

    /// Суммарная цель к концу уровня: 800, затем +400 за каждый следующий.
    public static func goal(forLevel level: Int) -> Int {
        let l = max(1, level)
        var total = 0
        for step in 1...l { total += 800 + 400 * (step - 1) }
        return total
    }

    // MARK: - Старт и случайность

    public static func start(seed: UInt64 = 0x9E3779B97F4A7C15) -> State {
        var s = seed
        var id = 1
        var board: [[Tile]] = []
        for y in 0..<rows {
            var row: [Tile] = []
            for x in 0..<columns {
                var kind = randomKind(&s)
                // Стартовое поле не должно собираться само: иначе первый же
                // кадр — каскад из ниоткуда, за который игрок ничего не делал.
                var guard_ = 0
                while completesRun(kind, x: x, y: y, row: row, board: board), guard_ < 16 {
                    kind = randomKind(&s); guard_ += 1
                }
                row.append(Tile(id: id, kind: kind))
                id += 1
            }
            board.append(row)
        }
        var state = State(board: board, score: 0, level: 1,
                          matches: 0, seed: s, clearing: [], nextID: id)
        if !hasMoves(state) { state = shuffled(state) }
        return state
    }

    /// Линейный конгруэнтный генератор: нужен воспроизводимый, а не «настоящий»
    /// рандом — иначе тест на конкретную раскладку не написать.
    private static func randomKind(_ seed: inout UInt64) -> Kind {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Kind(rawValue: Int((seed >> 33) % UInt64(Kind.allCases.count))) ?? .ruby
    }

    /// Достроит ли фишка тройку при заполнении поля слева направо, сверху вниз.
    private static func completesRun(_ kind: Kind, x: Int, y: Int,
                                     row: [Tile], board: [[Tile]]) -> Bool {
        if x >= 2, row[x - 1].kind == kind, row[x - 2].kind == kind { return true }
        if y >= 2, board[y - 1][x].kind == kind, board[y - 2][x].kind == kind { return true }
        return false
    }

    // MARK: - Совпадения

    public static func inside(_ p: Point) -> Bool {
        p.x >= 0 && p.x < columns && p.y >= 0 && p.y < rows
    }

    public static func areAdjacent(_ a: Point, _ b: Point) -> Bool {
        abs(a.x - b.x) + abs(a.y - b.y) == 1
    }

    /// Все совпадения на поле: ряды и столбцы по три и длиннее.
    ///
    /// Пересекающиеся (буква «Г») остаются двумя группами — клетки всё равно
    /// складываются в множество, зато длина каждой группы честная, и по ней
    /// понятно, родится полоска или бомба.
    public static func matches(on board: [[Tile]]) -> [Group] {
        var groups: [Group] = []
        for y in 0..<rows {
            var start = 0
            for x in 1...columns {
                let same = x < columns && board[y][x].kind == board[y][start].kind
                if !same {
                    if x - start >= 3 {
                        groups.append(Group(points: (start..<x).map { Point(x: $0, y: y) },
                                            horizontal: true))
                    }
                    start = x
                }
            }
        }
        for x in 0..<columns {
            var start = 0
            for y in 1...rows {
                let same = y < rows && board[y][x].kind == board[start][x].kind
                if !same {
                    if y - start >= 3 {
                        groups.append(Group(points: (start..<y).map { Point(x: x, y: $0) },
                                            horizontal: false))
                    }
                    start = y
                }
            }
        }
        return groups
    }

    /// Есть ли вообще ход. Если нет — поле надо перемешать, иначе партия
    /// молча зависает на «живом» экране.
    public static func hasMoves(_ state: State) -> Bool {
        for y in 0..<rows {
            for x in 0..<columns {
                for delta in [(1, 0), (0, 1)] {
                    let a = Point(x: x, y: y)
                    let b = Point(x: x + delta.0, y: y + delta.1)
                    guard inside(b) else { continue }
                    var board = state.board
                    board[a.y][a.x] = state.board[b.y][b.x]
                    board[b.y][b.x] = state.board[a.y][a.x]
                    if !matches(on: board).isEmpty { return true }
                }
            }
        }
        return false
    }

    /// Перемешивает поле, сохраняя набор фишек: ходы появились, самосборов нет.
    public static func shuffled(_ state: State) -> State {
        var next = state
        var seed = state.seed
        var tiles = next.board.flatMap { $0 }
        for attempt in 0..<40 {
            // Тасование Фишера—Йетса на том же генераторе.
            for i in stride(from: tiles.count - 1, to: 0, by: -1) {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let j = Int((seed >> 33) % UInt64(i + 1))
                tiles.swapAt(i, j)
            }
            for y in 0..<rows {
                for x in 0..<columns { next.board[y][x] = tiles[y * columns + x] }
            }
            next.seed = seed
            if matches(on: next.board).isEmpty && hasMoves(next) { return next }
            // Совсем упрямый набор фишек (например, почти все одного вида) —
            // раздаём поле заново, лишь бы экран не оставался без ходов.
            if attempt == 39 {
                var fresh = start(seed: seed)
                fresh.score = state.score
                fresh.level = state.level; fresh.matches = state.matches
                return fresh
            }
        }
        return next
    }

    // MARK: - Ход

    /// Ход игрока: меняет две соседние фишки местами.
    ///
    /// Возвращает кадры анимации — обмен, вспышка, падение, следующий каскад…
    /// Последний кадр и есть новое состояние. Пустой массив значит, что ход
    /// запрещён или не собирает ни одной тройки: такой обмен не засчитывается
    /// и фишки остаются на местах (вью просто ничего не применяет).
    public static func swap(_ state: State, _ a: Point, _ b: Point) -> [State] {
        guard let swapped = exchanged(state, a, b) else { return [] }
        guard !matches(on: swapped.board).isEmpty else { return [] }
        return [swapped] + resolve(swapped, origin: [a, b])
    }

    /// Поле с переставленными фишками — без сгорания и каскадов.
    ///
    /// Нужно вью: обмен, который ничего не собрал, надо показать и вернуть
    /// назад, иначе свайп выглядит как «приложение меня не услышало». Ни ходов,
    /// ни очков здесь не меняется — это не ход.
    public static func exchanged(_ state: State, _ a: Point, _ b: Point) -> State? {
        guard inside(a), inside(b), areAdjacent(a, b) else { return nil }
        var next = state
        next.clearing = []
        next.board[a.y][a.x] = state.board[b.y][b.x]
        next.board[b.y][b.x] = state.board[a.y][a.x]
        return next
    }

    /// Каскады: жжём совпадения, роняем, досыпаем — пока поле не успокоится.
    private static func resolve(_ start: State, origin: [Point]) -> [State] {
        var frames: [State] = []
        var state = start
        var cascade = 0

        while true {
            let groups = matches(on: state.board)
            if groups.isEmpty { break }
            cascade += 1

            var cleared = Set<Point>()
            for group in groups { cleared.formUnion(group.points) }
            cleared = detonate(cleared, on: state.board)

            // Кадр-вспышка: поле ещё целое, но видно, что именно сгорит.
            var flash = state
            flash.clearing = cleared
            frames.append(flash)

            // Длинные совпадения оставляют спецфишку. Кладём её туда, куда
            // игрок вёл ход, — иначе награда появляется в случайном месте.
            var spawn: [Point: Tile] = [:]
            for group in groups where group.points.count >= 4 {
                let at = group.points.first(where: { origin.contains($0) })
                    ?? group.points[group.points.count / 2]
                // id остаётся прежним: фишка не исчезла, она «выросла» в
                // спецэлемент на том же месте — вью покажет превращение, а не
                // подмену.
                let tile = state.board[at.y][at.x]
                spawn[at] = Tile(id: tile.id, kind: tile.kind,
                                 power: group.points.count >= 5
                                     ? .bomb
                                     : .line(horizontal: group.horizontal))
            }

            state.score += cleared.count * pointsPerTile * cascade
            state.matches += groups.count
            state = collapse(state, cleared: cleared, spawn: spawn)
            frames.append(state)
        }

        var final = frames.last ?? state
        final.clearing = []
        // Цель взята — следующий уровень. Уровни теперь только прогресс:
        // ходов они не выдают, потому что ходов больше не считают.
        while final.score >= goal(forLevel: final.level) {
            final.level += 1
        }
        // Бесконечной партии нельзя застревать: поле без ходов перемешиваем.
        if !hasMoves(final) { final = shuffled(final) }
        if frames.last != final { frames.append(final) }
        return frames
    }

    /// Цепная реакция: сгоревшая спецфишка тянет за собой свои клетки, те —
    /// свои. Считается до упора, поэтому бомба рядом с полоской срабатывает.
    private static func detonate(_ cleared: Set<Point>, on board: [[Tile]]) -> Set<Point> {
        var result = cleared
        var queue = Array(cleared)
        var fired = Set<Point>()
        while let p = queue.popLast() {
            guard !fired.contains(p) else { continue }
            fired.insert(p)
            switch board[p.y][p.x].power {
            case .none:
                continue
            case .line(let horizontal):
                let cells = horizontal
                    ? (0..<columns).map { Point(x: $0, y: p.y) }
                    : (0..<rows).map { Point(x: p.x, y: $0) }
                for cell in cells where !result.contains(cell) {
                    result.insert(cell); queue.append(cell)
                }
            case .bomb:
                for dy in -1...1 {
                    for dx in -1...1 {
                        let cell = Point(x: p.x + dx, y: p.y + dy)
                        guard inside(cell), !result.contains(cell) else { continue }
                        result.insert(cell); queue.append(cell)
                    }
                }
            }
        }
        return result
    }

    /// Убирает сгоревшее, роняет уцелевшее и досыпает новые фишки сверху.
    private static func collapse(_ state: State, cleared: Set<Point>,
                                 spawn: [Point: Tile]) -> State {
        var next = state
        next.clearing = []
        var holes = cleared
        for (point, tile) in spawn {
            holes.remove(point)                 // спецфишка остаётся на месте
            next.board[point.y][point.x] = tile
        }
        var seed = next.seed
        var id = next.nextID
        for x in 0..<columns {
            var survivors: [Tile] = []
            for y in stride(from: rows - 1, through: 0, by: -1)
            where !holes.contains(Point(x: x, y: y)) {
                survivors.append(next.board[y][x])
            }
            var y = rows - 1
            for tile in survivors { next.board[y][x] = tile; y -= 1 }
            while y >= 0 {
                next.board[y][x] = Tile(id: id, kind: randomKind(&seed))
                id += 1
                y -= 1
            }
        }
        next.seed = seed
        next.nextID = id
        return next
    }
}
