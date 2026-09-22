import SwiftUI
import AyantDomain
import AyantFeatures

/// «Три в ряд». Правила — в `Match3` (домен), здесь только отрисовка поля,
/// ввод и начисление бонусов. Камни рисует `GemView`.
///
/// Никакого SpriteKit, как и в тетрисе: поле — это сетка, у которой есть
/// пара 1:1 в Compose, и порт на Android стоит дёшево.
///
/// Плавность держится на `Tile.id`: каждая фишка — отдельное вью со своей
/// личностью, поэтому SwiftUI сам анимирует её переезд вниз, а досыпанные
/// падают сверху. Если бы поле рисовалось строками, всё, что мог бы показать
/// экран, — мгновенную подмену сетки.
struct Match3GameView: View {
    @EnvironmentObject private var bonus: BonusEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var state = Match3.start(seed: UInt64(Date().timeIntervalSince1970))
    @State private var selected: Match3.Point?
    /// Пока проигрывается каскад, ввод закрыт: иначе второй ход применится
    /// к промежуточному кадру, которого на самом деле уже нет.
    @State private var busy = false
    /// Бонусы, которые игра уже предъявила движку, — чтобы не начислить дважды.
    @State private var credited = 0
    /// Сколько бонусов РЕАЛЬНО начислил `BonusEngine`: дневной лимит может
    /// урезать до нуля, и врать «+N» нельзя.
    @State private var awarded = 0

    // Украшения, живущие только в вью.
    @State private var sparks: [Spark] = []
    @State private var popups: [ScorePopup] = []
    @State private var levelBanner: Int?
    @State private var shimmer: CGFloat = -1
    @State private var wiggle: Match3.Point?

    private let spacing: CGFloat = 5

    var body: some View {
        NavigationStack {
            // Шапка сверху, подсказка снизу, поле по центру: без распорок
            // VStack сжимается по контенту и вся эта стопка висит в середине
            // экрана, а тёплый фон не доходит до краёв.
            VStack(spacing: 14) {
                header
                Spacer(minLength: 0)
                board
                    .overlay { if state.isOver { gameOverOverlay } }
                    .overlay { levelBannerView }
                Spacer(minLength: 0)
                hint
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sanScreenBackground()
            .navigationTitle("Три в ряд")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }.font(.golos(16, .semibold))
                }
            }
        }
        .task { await runShimmer() }
        // Уровень растёт внутри каскада, а не по кнопке, — иначе это событие
        // проходит незамеченным: цифра в шапке молча меняется.
        .onChange(of: state.level) { previous, current in
            guard current > previous else { return }
            SanHaptics.success()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { levelBanner = current }
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                withAnimation(.easeOut(duration: 0.3)) { levelBanner = nil }
            }
        }
    }

    // MARK: Ход

    /// Применяет ход и проигрывает каскад кадр за кадром.
    ///
    /// `Match3.swap` возвращает пустой массив, если обмен ничего не собирает, —
    /// такой ход не засчитывается и поле остаётся как было.
    private func play(_ a: Match3.Point, _ b: Match3.Point) {
        let frames = Match3.swap(state, a, b)
        selected = nil
        guard !frames.isEmpty else { return bounce(a, b) }

        busy = true
        Task {
            var cascade = 0
            for (index, frame) in frames.enumerated() {
                let burning = frame.clearing
                let scoreBefore = state.score

                withAnimation(step(for: index)) { state = frame }

                if !burning.isEmpty {
                    cascade += 1
                    lastBurnCenter = centre(of: burning)
                    SanHaptics.selection()
                    burst(burning, cascade: cascade)
                } else if index > 0, frame.score > scoreBefore {
                    // Кадр падения приносит очки предыдущей вспышки — показываем
                    // их там же, где горело, пока искры ещё в воздухе.
                    popScore(frame.score - scoreBefore, cascade: cascade)
                }

                if index < frames.count - 1 {
                    try? await Task.sleep(for: .seconds(pause(for: index, of: frames)))
                }
            }
            award()
            busy = false
        }
    }

    /// Вспышка резкая, падение пружинит: это разные движения, и одна кривая на
    /// оба делает каскад либо вязким, либо дёрганым.
    private func step(for index: Int) -> Animation? {
        if reduceMotion { return .linear(duration: 0.12) }
        return index % 2 == 1
            ? .easeOut(duration: 0.13)
            : .spring(response: 0.34, dampingFraction: 0.72)
    }

    private func pause(for index: Int, of frames: [Match3.State]) -> Double {
        if reduceMotion { return 0.06 }
        return frames[index].clearing.isEmpty ? 0.2 : 0.16
    }

    /// Обмен, который ничего не собрал: показываем его и возвращаем фишки на
    /// место. Без этого свайп молча ничего не делает и читается как «игра меня
    /// не услышала», хотя ход просто не по правилам.
    private func bounce(_ a: Match3.Point, _ b: Match3.Point) {
        guard let swapped = Match3.exchanged(state, a, b) else { return }
        let before = state
        busy = true
        wiggle = a
        Task {
            withAnimation(.easeOut(duration: 0.13)) { state = swapped }
            try? await Task.sleep(for: .seconds(0.15))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { state = before }
            try? await Task.sleep(for: .seconds(0.2))
            wiggle = nil
            busy = false
        }
    }

    /// Начисляет бонусы за НОВЫЕ совпадения — по одному за каждые
    /// `Match3.matchesPerBonus`, дневной лимит держит `BonusEngine`.
    private func award() {
        let earned = state.bonuses
        guard earned > credited else { return }
        let granted = bonus.awardGameplay(earned - credited)
        credited = earned
        guard granted > 0 else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { awarded += granted }
        SanHaptics.success()
    }

    private func tap(_ point: Match3.Point) {
        if let current = selected {
            if current == point { selected = nil }
            else if Match3.areAdjacent(current, point) { play(current, point) }
            else { selected = point }
        } else {
            selected = point
        }
        SanHaptics.save()
    }

    private func restart() {
        credited = 0
        awarded = 0
        selected = nil
        sparks = []
        popups = []
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            state = Match3.start(seed: UInt64(Date().timeIntervalSince1970))
        }
    }

    // MARK: Искры и всплывающие очки

    /// Искры из сгоревших клеток. Живут полсекунды и удаляются пачкой —
    /// накапливать их нельзя, иначе за партию на поле повиснут сотни вью.
    private func burst(_ cells: Set<Match3.Point>, cascade: Int) {
        guard !reduceMotion else { return }
        let fresh = cells.flatMap { point -> [Spark] in
            let color = GemPalette.of(state.board[point.y][point.x].kind).glow
            return (0..<4).map { i in
                Spark(point: point,
                      angle: Double(i) / 4 * 2 * .pi + Double.random(in: -0.4...0.4),
                      distance: CGFloat.random(in: 18...34),
                      color: color)
            }
        }
        sparks.append(contentsOf: fresh)
        let ids = Set(fresh.map(\.id))
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            sparks.removeAll { ids.contains($0.id) }
        }
    }

    private func popScore(_ amount: Int, cascade: Int) {
        guard let anchor = lastBurnCenter else { return }
        let popup = ScorePopup(point: anchor, amount: amount, cascade: cascade)
        popups.append(popup)
        Task {
            try? await Task.sleep(for: .seconds(0.9))
            popups.removeAll { $0.id == popup.id }
        }
    }

    /// Середина последней вспышки — над ней всплывают очки.
    @State private var lastBurnCenter: Match3.Point?

    private func centre(of cells: Set<Match3.Point>) -> Match3.Point? {
        guard !cells.isEmpty else { return nil }
        let x = cells.map(\.x).reduce(0, +) / cells.count
        let y = cells.map(\.y).reduce(0, +) / cells.count
        return Match3.Point(x: x, y: y)
    }

    // MARK: Разметка

    private var header: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Уровень \(state.level)")
                        .font(.golos(17, .bold)).foregroundStyle(Color.sanInk)
                        .contentTransition(.numericText())
                    Text("+\(awarded) бонусов")
                        .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(state.score) / \(state.goal)")
                        .font(.golos(15, .bold)).foregroundStyle(Color.sanInk)
                        .contentTransition(.numericText())
                    Text("ходов: \(state.movesLeft)")
                        .font(.golos(12.5, .semibold))
                        .foregroundStyle(state.movesLeft <= 3 ? Color(hex: 0xE8556B) : Color.sanInkSoft)
                        .contentTransition(.numericText())
                        .scaleEffect(state.movesLeft <= 3 ? 1.08 : 1)
                }
            }
            progressBar
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.sanSurfaceMuted)
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: Palette.orange), Color(hex: Palette.accent)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geo.size.width * state.levelProgress))
                    .shadow(color: Color(hex: Palette.accent).opacity(0.5), radius: 4, y: 1)
            }
        }
        .frame(height: 6)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: state.score)
    }

    private var board: some View {
        GeometryReader { geo in
            let side = (min(geo.size.width, geo.size.height)
                        - spacing * CGFloat(Match3.columns - 1)) / CGFloat(Match3.columns)
            let step = side + spacing
            let total = side * CGFloat(Match3.columns) + spacing * CGFloat(Match3.columns - 1)

            ZStack(alignment: .topLeading) {
                // Слой фишек обрезан по полю: досыпанные начинают путь выше
                // верхнего края, и без обрезки они летят поверх шапки — видно,
                // как камни висят в воздухе над игрой.
                ZStack(alignment: .topLeading) {
                    ForEach(placedTiles, id: \.id) { placed in
                        gem(placed, side: side)
                            .frame(width: side, height: side)
                            .offset(x: CGFloat(placed.x) * step, y: CGFloat(placed.y) * step)
                            // Новая фишка падает сверху, сгоревшая схлопывается.
                            .transition(.asymmetric(
                                insertion: .offset(y: -step * 3).combined(with: .opacity),
                                removal: .scale(scale: 0.15).combined(with: .opacity)))
                    }
                }
                .frame(width: total, height: total, alignment: .topLeading)
                .clipped()

                // Искры и очки рисуются поверх и НЕ обрезаются: они специально
                // вылетают за границы поля.
                ForEach(sparks) { spark in
                    SparkView(spark: spark)
                        .position(x: CGFloat(spark.point.x) * step + side / 2,
                                  y: CGFloat(spark.point.y) * step + side / 2)
                }
                ForEach(popups) { popup in
                    ScorePopupView(popup: popup)
                        .position(x: CGFloat(popup.point.x) * step + side / 2,
                                  y: CGFloat(popup.point.y) * step + side / 2)
                }
            }
            .frame(width: total, height: total, alignment: .topLeading)
            .overlay { shimmerSweep(total: total) }
            .contentShape(Rectangle())
            // Один жест на всё поле: короткое касание — выбор фишки, свайп —
            // обмен с соседом. Два отдельных жеста на ячейках дрались бы между
            // собой, и свайп через границу клетки терялся.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard !busy, !state.isOver,
                              let from = cell(at: value.startLocation, side: side) else { return }
                        let dx = value.translation.width, dy = value.translation.height
                        if max(abs(dx), abs(dy)) < side * 0.4 {
                            tap(from)
                        } else if abs(dx) > abs(dy) {
                            play(from, Match3.Point(x: from.x + (dx > 0 ? 1 : -1), y: from.y))
                        } else {
                            play(from, Match3.Point(x: from.x, y: from.y + (dy > 0 ? 1 : -1)))
                        }
                    }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Фишки поля с координатами — плоским списком, чтобы `ForEach` мог вести
    /// каждую по её `id`.
    private var placedTiles: [PlacedTile] {
        (0..<Match3.rows).flatMap { y in
            (0..<Match3.columns).map { x in
                PlacedTile(tile: state.board[y][x], x: x, y: y)
            }
        }
    }

    private func gem(_ placed: PlacedTile, side: CGFloat) -> some View {
        let point = Match3.Point(x: placed.x, y: placed.y)
        let burning = state.clearing.contains(point)
        let picked = selected == point
        return GemView(kind: placed.tile.kind, power: placed.tile.power,
                       flare: burning ? 1 : 0)
            .scaleEffect(burning ? 1.28 : (picked ? 1.12 : 1))
            .rotationEffect(.degrees(wiggle == point ? 8 : 0))
            .overlay {
                if picked {
                    RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 2.5)
                        .shadow(color: .white.opacity(0.6), radius: 6)
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.6), value: picked)
    }

    private func cell(at location: CGPoint, side: CGFloat) -> Match3.Point? {
        let step = side + spacing
        let point = Match3.Point(x: Int(location.x / step), y: Int(location.y / step))
        return Match3.inside(point) ? point : nil
    }

    /// Блик, медленно проезжающий по полю. Экран без движения выглядит
    /// замершим, даже когда игрок просто думает над ходом.
    @ViewBuilder private func shimmerSweep(total: CGFloat) -> some View {
        if !reduceMotion {
            LinearGradient(colors: [.clear, .white.opacity(0.22), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: total * 0.5, height: total * 1.6)
                .rotationEffect(.degrees(65))
                .offset(x: shimmer * total * 1.3)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
                .clipped()
        }
    }

    private func runShimmer() async {
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3.4))
            guard !Task.isCancelled else { return }
            shimmer = -1
            withAnimation(.easeInOut(duration: 1.5)) { shimmer = 1 }
        }
    }

    @ViewBuilder private var levelBannerView: some View {
        if let level = levelBanner {
            VStack(spacing: 4) {
                Text("Уровень \(level)")
                    .font(.golos(26, .heavy)).foregroundStyle(.white)
                Text("+\(Match3.movesPerLevel) ходов")
                    .font(.golos(14, .semibold)).foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 26).padding(.vertical, 16)
            .background(LinearGradient(colors: [Color(hex: Palette.orange), Color(hex: Palette.accent)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Color(hex: Palette.accent).opacity(0.5), radius: 18, y: 6)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    private var hint: some View {
        VStack(spacing: 2) {
            Text("Меняй соседние камни местами: 4 в ряд — полоска, 5 — бомба")
            Text("\(Match3.matchesPerBonus) совпадений = 1 бонус · до \(bonus.dailyGameplayCap)/день")
        }
        .font(.caption)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
    }

    private var gameOverOverlay: some View {
        VStack(spacing: 12) {
            Text("Ходы закончились").font(.golos(20, .heavy)).foregroundStyle(.white)
            Text("Уровень \(state.level), очков: \(state.score) → +\(awarded) бонусов")
                .font(.golos(14)).foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
            Button("Ещё раз") { restart() }
                .font(.golos(15, .bold)).foregroundStyle(Color.sanInk)
                .padding(.horizontal, 20).frame(height: 44)
                .background(Color.white, in: Capsule())
                .buttonStyle(.sanPress(0.94))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55))
        .transition(.opacity.combined(with: .scale(scale: 1.05)))
    }
}

// MARK: - Мелкие типы вью

/// Фишка вместе с местом на поле: `id` берётся у фишки, поэтому SwiftUI ведёт
/// её от клетки к клетке, а не рисует заново.
private struct PlacedTile: Identifiable {
    let tile: Match3.Tile
    let x: Int
    let y: Int
    var id: Int { tile.id }
}

private struct Spark: Identifiable {
    let id = UUID()
    let point: Match3.Point
    let angle: Double
    let distance: CGFloat
    let color: Color
}

/// Искра разлетается сама: анимация живёт внутри, поэтому родителю не нужно
/// хранить фазу каждой частицы.
private struct SparkView: View {
    let spark: Spark
    @State private var flown = false

    var body: some View {
        Circle()
            .fill(spark.color)
            .frame(width: 7, height: 7)
            .shadow(color: spark.color.opacity(0.8), radius: 4)
            .scaleEffect(flown ? 0.2 : 1)
            .opacity(flown ? 0 : 0.95)
            .offset(x: flown ? cos(spark.angle) * spark.distance : 0,
                    y: flown ? sin(spark.angle) * spark.distance : 0)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.55)) { flown = true }
            }
    }
}

private struct ScorePopup: Identifiable {
    let id = UUID()
    let point: Match3.Point
    let amount: Int
    let cascade: Int
}

private struct ScorePopupView: View {
    let popup: ScorePopup
    @State private var risen = false

    var body: some View {
        VStack(spacing: 0) {
            Text("+\(popup.amount)")
                .font(.golos(19, .heavy))
            if popup.cascade > 1 {
                Text("×\(popup.cascade)")
                    .font(.golos(12, .bold))
                    .foregroundStyle(Color(hex: Palette.accent))
            }
        }
        .foregroundStyle(Color.sanInk)
        .shadow(color: .white.opacity(0.9), radius: 4)
        .scaleEffect(risen ? 1 : 0.5)
        .opacity(risen ? 0 : 1)
        .offset(y: risen ? -46 : 0)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.85)) { risen = true }
        }
    }
}

#Preview {
    Match3GameView().environmentObject(AyantStores.bonus())
}
