import SwiftUI
import AyantDomain
import AyantFeatures

/// Тетрис. Правила — в `Tetris` (домен), здесь только отрисовка сетки и ввод.
///
/// Никакого SpriteKit, в отличие от прошлой версии: поле — это сетка
/// прямоугольников, поэтому у экрана есть 1:1 пара в Compose и порт стоит
/// дёшево. Ровно из-за движка старый тетрис в своё время и выпилили.
struct TetrisGameView: View {
    @EnvironmentObject private var bonus: BonusEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var state = Tetris.start(seed: UInt64(Date().timeIntervalSince1970))
    @State private var awarded = 0
    /// Скорость падения растёт с числом линий — иначе игра не кончается.
    private var tickInterval: Double { max(0.16, 0.6 - Double(state.lines) * 0.02) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                header
                board
                    .overlay { if state.isOver { gameOverOverlay } }
                controls
                Text("1 линия = \(Tetris.bonusPerLine) бонусов · до \(bonus.dailyGameplayCap)/день")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .sanScreenBackground()
            .navigationTitle("Тетрис")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { finish() }.font(.golos(16, .semibold))
                }
            }
        }
        .task(id: state.isOver) { await run() }
    }

    // MARK: Игровой цикл

    /// Один таймер на партию: `Task.sleep` вместо `Timer`, чтобы цикл сам
    /// останавливался вместе с экраном и не тикал за закрытой игрой.
    private func run() async {
        while !state.isOver && !Task.isCancelled {
            try? await Task.sleep(for: .seconds(tickInterval))
            guard !Task.isCancelled else { return }
            step { Tetris.tick($0) }
        }
    }

    /// Применяет ход и начисляет бонусы за НОВЫЕ линии — по одной штуке за
    /// линию, дневной лимит держит `BonusEngine`, своей экономики у игры нет.
    private func step(_ transform: (Tetris.State) -> Tetris.State) {
        let before = state.lines
        state = transform(state)
        let gained = state.lines - before
        if gained > 0 {
            awarded += bonus.awardGameplay(gained * Tetris.bonusPerLine)
            SanHaptics.selection()
        }
    }

    private func finish() { dismiss() }

    // MARK: Разметка

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Линий: \(state.lines)")
                    .font(.golos(17, .bold)).foregroundStyle(Color.sanInk)
                Text("+\(awarded) бонусов")
                    .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
            }
            Spacer()
            nextPreview
        }
    }

    private var nextPreview: some View {
        VStack(spacing: 4) {
            Text("Дальше").textCase(.uppercase).sanEyebrowText()
                .foregroundStyle(Color(hex: 0x9A9188))
            let cells = Tetris.cells(state.next, rotation: 0)
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                ForEach(0..<2, id: \.self) { y in
                    GridRow {
                        ForEach(0..<4, id: \.self) { x in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(cells.contains { $0.x == x && $0.y == y }
                                      ? color(state.next) : Color.sanSurfaceMuted)
                                .frame(width: 10, height: 10)
                        }
                    }
                }
            }
        }
    }

    private var board: some View {
        GeometryReader { geo in
            let side = min(geo.size.width / CGFloat(Tetris.columns),
                           geo.size.height / CGFloat(Tetris.rows))
            let filled = occupiedByPiece
            VStack(spacing: 1) {
                ForEach(0..<Tetris.rows, id: \.self) { y in
                    HStack(spacing: 1) {
                        ForEach(0..<Tetris.columns, id: \.self) { x in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(cellColor(x: x, y: y, moving: filled))
                                .frame(width: side - 1, height: side - 1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(CGFloat(Tetris.columns) / CGFloat(Tetris.rows), contentMode: .fit)
    }

    /// Клетки падающей фигуры — считаем один раз на кадр, а не на каждую ячейку.
    private var occupiedByPiece: [Int: Tetris.Shape] {
        guard let p = state.piece else { return [:] }
        var map: [Int: Tetris.Shape] = [:]
        for cell in p.occupied where cell.y >= 0 {
            map[cell.y * Tetris.columns + cell.x] = p.shape
        }
        return map
    }

    private func cellColor(x: Int, y: Int, moving: [Int: Tetris.Shape]) -> Color {
        if let shape = moving[y * Tetris.columns + x] { return color(shape) }
        if let shape = state.board[y][x] { return color(shape) }
        return Color.sanSurfaceMuted
    }

    /// Цвета живут в UI: домен про них ничего не знает (как и у `Venue.gradient`).
    private func color(_ shape: Tetris.Shape) -> Color {
        switch shape {
        case .i: return Color(hex: 0x2FA88C)
        case .o: return Color(hex: Palette.orange)
        case .t: return Color(hex: 0x7C6BE8)
        case .s: return Color(hex: 0x2FA24C)
        case .z: return Color(hex: 0xE8556B)
        case .j: return Color(hex: 0x3D7BE8)
        case .l: return Color(hex: Palette.accent)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            controlButton("arrow.left") { step { Tetris.move($0, dx: -1) } }
            controlButton("arrow.clockwise") { step { Tetris.rotate($0) } }
            controlButton("arrow.right") { step { Tetris.move($0, dx: 1) } }
            controlButton("arrow.down.to.line") { step { Tetris.hardDrop($0) } }
        }
    }

    private func controlButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.sanInk)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.sanSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.sanPress(0.94))
        .disabled(state.isOver)
    }

    private var gameOverOverlay: some View {
        VStack(spacing: 12) {
            Text("Игра окончена").font(.golos(20, .heavy)).foregroundStyle(.white)
            Text("Линий: \(state.lines) → +\(awarded) бонусов")
                .font(.golos(14)).foregroundStyle(.white.opacity(0.85))
            Button("Ещё раз") {
                awarded = 0
                state = Tetris.start(seed: UInt64(Date().timeIntervalSince1970))
            }
            .font(.golos(15, .bold)).foregroundStyle(Color.sanInk)
            .padding(.horizontal, 20).frame(height: 44)
            .background(Color.white, in: Capsule())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55))
    }
}

#Preview {
    TetrisGameView().environmentObject(AyantStores.bonus())
}
