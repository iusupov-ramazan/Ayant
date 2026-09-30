import SwiftUI
import AyantDomain
import AyantFeatures

/// «2048». Правила — в `Game2048` (домен), здесь только отрисовка поля, свайпы
/// и начисление бонусов.
///
/// Никакого SpriteKit, как в тетрисе и «Три в ряд»: поле — это сетка, у которой
/// есть пара 1:1 в Compose, и порт на Android стоит дёшево.
///
/// Плавность держится на `Tile.id`: каждая плитка — отдельное вью со своей
/// личностью, поэтому SwiftUI сам анимирует её переезд. Если рисовать поле
/// строками чисел, всё, что покажет экран, — мигающую таблицу.
struct Game2048View: View {
    @EnvironmentObject private var bonus: BonusEngine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var state = Game2048.start(seed: UInt64(Date().timeIntervalSince1970))
    /// Пока проигрывается ход, ввод закрыт: иначе второй свайп применится к
    /// кадру доезда, которого на самом деле уже нет.
    @State private var busy = false
    /// Бонусы, которые игра уже предъявила движку, — чтобы не начислить дважды.
    @State private var credited = 0
    /// Сколько бонусов РЕАЛЬНО начислил `BonusEngine`: дневной лимит может
    /// урезать до нуля, и врать «+N» нельзя.
    @State private var awarded = 0
    @State private var banner: Milestone?
    @State private var nudge: Game2048.Direction?
    /// Номер партии. Ход проигрывается в отдельной задаче со сном между
    /// кадрами, а «Заново» обнуляет `credited` — и задача, проснувшись уже над
    /// новой партией, начисляла ту же ступень второй раз. Кнопку не блокируем
    /// (пауза короткая, но ждать её неприятно): задача сама проверяет, что
    /// партия ещё та же, и молча уходит, если нет.
    @State private var generation = 0

    private let spacing: CGFloat = 8

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                header
                Spacer(minLength: 0)
                board
                    .overlay { if state.isOver { gameOverOverlay } }
                    .overlay { bannerView }
                Spacer(minLength: 0)
                hint
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sanScreenBackground()
            .navigationTitle("2048")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Заново") { restart() }.font(.golos(16, .semibold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }.font(.golos(16, .semibold))
                }
            }
        }
    }

    // MARK: Ход

    /// Применяет ход и проигрывает оба кадра: доезд, потом слияние.
    ///
    /// `Game2048.move` возвращает пустой массив, если в эту сторону ничего не
    /// двигается, — такой свайп не засчитывается, и поле остаётся как было.
    private func play(_ direction: Game2048.Direction) {
        let frames = Game2048.move(state, direction)
        guard !frames.isEmpty else { return bounce(direction) }

        busy = true
        let bestBefore = state.bestTile
        let run = generation
        Task {
            withAnimation(slide) { state = frames[0] }
            if frames.count > 1 {
                try? await Task.sleep(for: .seconds(reduceMotion ? 0.05 : 0.11))
                guard run == generation else { return }
                withAnimation(pop) { state = frames[1] }
                if frames[1].score > frames[0].score { SanHaptics.selection() }
            }
            guard run == generation else { return }
            award(bestBefore: bestBefore)
            busy = false
        }
    }

    private var slide: Animation {
        reduceMotion ? .linear(duration: 0.08) : .spring(response: 0.22, dampingFraction: 0.85)
    }

    private var pop: Animation {
        reduceMotion ? .linear(duration: 0.08) : .spring(response: 0.3, dampingFraction: 0.62)
    }

    /// Свайп в стену: показываем толчок и возвращаем поле. Без него ход по
    /// правилам невозможный читается как «игра меня не услышала».
    private func bounce(_ direction: Game2048.Direction) {
        guard !state.isOver else { return }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { nudge = direction }
        Task {
            try? await Task.sleep(for: .seconds(0.14))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { nudge = nil }
        }
    }

    /// Начисляет бонусы за НОВЫЕ ступени: одна плитка от `bonusFromValue` —
    /// один бонус, дневной лимит держит `BonusEngine`.
    private func award(bestBefore: Int) {
        let earned = state.bonuses
        guard earned > credited else { return }
        let granted = bonus.awardGameplay(earned - credited)
        credited = earned
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            awarded += granted
            banner = Milestone(value: state.bestTile, bonus: granted,
                               won: state.hasWon && bestBefore < Game2048.winningValue)
        }
        SanHaptics.success()
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeOut(duration: 0.3)) { banner = nil }
        }
    }

    private func restart() {
        // Новая партия: всё, что доигрывает старую, обязано её пропустить.
        generation += 1
        busy = false
        credited = 0
        awarded = 0
        banner = nil
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            state = Game2048.start(seed: UInt64(Date().timeIntervalSince1970))
        }
    }

    // MARK: Разметка

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(state.score)")
                    .font(.golos(22, .heavy)).tracking(-0.6)
                    .foregroundStyle(Color.sanInk)
                    .contentTransition(.numericText())
                Text("+\(awarded) \(bonusWord(awarded))")
                    .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                    .contentTransition(.numericText())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("лучшая \(state.bestTile)")
                    .font(.golos(15, .bold)).foregroundStyle(Color.sanInk)
                    .contentTransition(.numericText())
                // Следующая ступень — единственная цель, которую игрок может
                // держать в голове. Без неё бонус выглядит случайной наградой.
                Text("плитка \(state.nextBonusValue) — бонус")
                    .font(.golos(12.5, .semibold))
                    .foregroundStyle(Color.sanInkSoft)
                    .contentTransition(.numericText())
            }
        }
    }

    private var board: some View {
        GeometryReader { geo in
            let side = (min(geo.size.width, geo.size.height)
                        - spacing * CGFloat(Game2048.size + 1)) / CGFloat(Game2048.size)
            let step = side + spacing
            let total = side * CGFloat(Game2048.size) + spacing * CGFloat(Game2048.size + 1)

            ZStack(alignment: .topLeading) {
                ForEach(0..<Game2048.size, id: \.self) { y in
                    ForEach(0..<Game2048.size, id: \.self) { x in
                        RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                            .fill(Color.sanTileEmpty)
                            .frame(width: side, height: side)
                            .offset(x: spacing + CGFloat(x) * step,
                                    y: spacing + CGFloat(y) * step)
                    }
                }
                // Поглощённая плитка рисуется ПЕРВОЙ, то есть под выжившей: на
                // кадре слияния обе стоят в одной клетке, и сверху должна
                // остаться та, что сейчас удвоится.
                ForEach(state.tiles.sorted { $0.absorbed && !$1.absorbed }) { tile in
                    // Переход ДО смещения: `.offset` не двигает рамку раскладки,
                    // и масштаб, навешенный после него, растил новую плитку из
                    // угловой клетки (0,0) — цифры «вылетали с угла». Так
                    // плитка растёт из центра своей собственной клетки.
                    TileView(tile: tile, side: side)
                        .transition(.asymmetric(insertion: .scale(scale: 0.2).combined(with: .opacity),
                                                removal: .opacity))
                        .offset(x: spacing + CGFloat(tile.x) * step,
                                y: spacing + CGFloat(tile.y) * step)
                }
            }
            .frame(width: total, height: total, alignment: .topLeading)
            .background(Color.sanSurface,
                        in: RoundedRectangle(cornerRadius: SanRadius.hero, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: SanRadius.hero, style: .continuous)
                .strokeBorder(Color.sanHairline, lineWidth: 0.5))
            .offset(x: nudgeOffset.width, y: nudgeOffset.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // Один жест на всё поле: направление определяет главная ось свайпа.
            .gesture(
                DragGesture(minimumDistance: 18)
                    .onEnded { value in
                        guard !busy, !state.isOver else { return }
                        let dx = value.translation.width, dy = value.translation.height
                        if abs(dx) > abs(dy) {
                            play(dx > 0 ? .right : .left)
                        } else {
                            play(dy > 0 ? .down : .up)
                        }
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Толчок в сторону невозможного хода — на восемь точек, не больше: это
    /// подсказка «стена», а не анимация.
    private var nudgeOffset: CGSize {
        guard let nudge, !reduceMotion else { return .zero }
        switch nudge {
        case .left:  return CGSize(width: -8, height: 0)
        case .right: return CGSize(width: 8, height: 0)
        case .up:    return CGSize(width: 0, height: -8)
        case .down:  return CGSize(width: 0, height: 8)
        }
    }

    @ViewBuilder private var bannerView: some View {
        if let banner {
            VStack(spacing: 4) {
                Text(banner.won ? "2048! 🎉" : "\(banner.value)")
                    .font(.golos(30, .heavy)).foregroundStyle(.white)
                // Дневной лимит мог срезать начисление до нуля — тогда ступень
                // всё равно событие, но обещать бонус нельзя.
                Text(banner.bonus > 0
                     ? "+\(banner.bonus) \(bonusWord(banner.bonus))"
                     : "лимит бонусов на сегодня")
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
            Text("Свайп сдвигает поле, одинаковые плитки сливаются")
            Text("Каждая новая плитка от \(Game2048.bonusFromValue) = 1 бонус")
        }
        .font(.caption)
        .multilineTextAlignment(.center)
        .foregroundStyle(.secondary)
    }

    private var gameOverOverlay: some View {
        VStack(spacing: 12) {
            Text("Ходов больше нет").font(.golos(20, .heavy)).foregroundStyle(.white)
            Text("Лучшая плитка \(state.bestTile), очков: \(state.score) → +\(awarded) \(bonusWord(awarded))")
                .font(.golos(14)).foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
            Button("Ещё раз") { restart() }
                .font(.golos(15, .bold)).foregroundStyle(Color.sanInk)
                .padding(.horizontal, 20).frame(height: 44)
                .background(Color.white, in: Capsule())
                .buttonStyle(.sanPress(0.94))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: SanRadius.hero, style: .continuous))
        .transition(.opacity.combined(with: .scale(scale: 1.05)))
    }

    /// «1 бонус», «2 бонуса», «5 бонусов» — русский счёт, а не «1 бонусов»:
    /// 11…14 всегда «бонусов», дальше решает последняя цифра.
    private func bonusWord(_ count: Int) -> String {
        let n = abs(count)
        if (11...14).contains(n % 100) { return "бонусов" }
        switch n % 10 {
        case 1: return "бонус"
        case 2...4: return "бонуса"
        default: return "бонусов"
        }
    }

    /// Взятая ступень: что показать в баннере и начислили ли за неё бонус.
    private struct Milestone: Equatable {
        let value: Int
        let bonus: Int
        let won: Bool
    }
}

// MARK: - Плитка

/// Одна плитка поля. Число рисуется одним `Text`, размер подбирается под
/// количество цифр — иначе «2048» не влезает в ту же клетку, что «2».
private struct TileView: View {
    let tile: Game2048.Tile
    let side: CGFloat
    /// Всплеск слияния живёт внутри плитки: родителю не нужно помнить фазу
    /// каждой из шестнадцати.
    @State private var pop = false

    var body: some View {
        let skin = TilePalette.of(tile.value)
        RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
            .fill(skin.background)
            .overlay {
                Text("\(tile.value)")
                    .font(.golos(fontSize, .heavy))
                    .tracking(-0.8)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .foregroundStyle(skin.ink)
            }
            .frame(width: side, height: side)
            .shadow(color: skin.glow.opacity(0.35), radius: 8, y: 2)
            .scaleEffect(pop ? 1.14 : 1)
            // Слияние «выстреливает» и ОСЕДАЕТ обратно. Держать увеличение,
            // пока `born` истинно, нельзя: флаг живёт до следующего хода, и
            // свежая плитка так и осталась бы на 14% больше соседей.
            //
            // Ловим только переход false → true: так всплеск достаётся
            // слиянию (плитка пережила кадр доезда с `born == false`), а
            // досыпанная приходит уже рождённой и въезжает своим переходом.
            .onChange(of: tile.born) { was, now in
                guard !was, now else { return }
                withAnimation(.spring(response: 0.17, dampingFraction: 0.5)) { pop = true }
                Task {
                    try? await Task.sleep(for: .seconds(0.17))
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.65)) { pop = false }
                }
            }
    }

    private var fontSize: CGFloat {
        switch tile.value {
        case ..<100:    return side * 0.42
        case ..<1000:   return side * 0.34
        case ..<10000:  return side * 0.26
        default:        return side * 0.21
        }
    }
}

/// Цвета плиток живут в UI: домен про них ничего не знает (как и у
/// `Venue.gradient` и у камней «Три в ряд»).
///
/// Гамма — тёплая, приложения, а не классическая бежево-оранжевая: 2 и 4
/// почти неотличимы от поля, дальше плитка «разогревается» к акценту, а от
/// 1024 уходит в глубокий тон, чтобы старшие читались с одного взгляда.
private enum TilePalette {
    struct Skin {
        let background: LinearGradient
        let ink: Color
        let glow: Color
    }

    static func of(_ value: Int) -> Skin {
        switch value {
        case 2:    return flat(light: 0xE6E0D6, dark: 0x3A352F)
        case 4:    return flat(light: 0xD8CDBB, dark: 0x4C443A)
        case 8:    return ramp(0xFFC46B, 0xFFA83D)
        case 16:   return ramp(0xFFA53D, 0xFF8A1F)
        case 32:   return ramp(0xFF8A2B, 0xFF6A12)
        case 64:   return ramp(0xFF6F2B, 0xFF4D0F)
        case 128:  return ramp(0xFF5A1F, 0xE83A2B)
        case 256:  return ramp(0xEE3B4E, 0xD01F58)
        case 512:  return ramp(0xC92E76, 0xA02794)
        case 1024: return ramp(0x8B3BC9, 0x5C3BD6)
        default:   return ramp(0x4A46D8, 0x2C7BE8)
        }
    }

    /// Младшие плитки держатся тона поля, поэтому их подложка ДИНАМИЧЕСКАЯ.
    /// Со статичной светлой подложкой и `sanInk` сверху тёмная тема давала
    /// белые цифры на бежевом — «2» и «4» просто пропадали с доски.
    private static func flat(light: UInt, dark: UInt) -> Skin {
        let fill = Color.sanDynamic(light: light, dark: dark)
        return Skin(background: LinearGradient(colors: [fill, fill],
                                               startPoint: .top, endPoint: .bottom),
                    ink: .sanInk, glow: .clear)
    }

    private static func ramp(_ from: UInt32, _ to: UInt32) -> Skin {
        Skin(background: LinearGradient(colors: [Color(hex: from), Color(hex: to)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing),
             ink: .white, glow: Color(hex: to))
    }
}

#Preview {
    Game2048View().environmentObject(AyantStores.bonus())
}
