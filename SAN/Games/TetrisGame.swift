import SwiftUI
import SpriteKit

// MARK: - Экран игры (SwiftUI-обёртка над SpriteKit-сценой)

struct TetrisGameView: View {
    @EnvironmentObject private var bonus: BonusEngine
    @StateObject private var bridge = TetrisBridge()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                header

                GeometryReader { geo in
                    SpriteView(scene: bridge.makeScene(size: geo.size), options: [.allowsTransparency])
                }
                .aspectRatio(10.0 / 20.0, contentMode: .fit)
                .overlay { if bridge.isOver { gameOverOverlay } }

                controls

                Text("Свайп ←/→ — двигать · вверх — сбросить · вниз — вниз · тап — поворот")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .navigationTitle("Тетрис")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
            }
            .onChange(of: bridge.didFinish) { _, finished in
                if finished, bridge.finalLines > 0 {
                    bonus.awardGameplay(bridge.finalLines * 5)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Label("\(bridge.score)", systemImage: "star.fill")
                .font(.headline).foregroundStyle(Color.sanAccent)
            Spacer()
            Label("\(bridge.lines)", systemImage: "square.stack.3d.up.fill")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text("1 линия = 5 бонусов · до \(bonus.dailyGameplayCap)/день")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // Кнопки-дубль к свайпам — удобнее для точных ходов.
    private var controls: some View {
        HStack(spacing: 12) {
            ctrlButton(system: "arrow.left") { bridge.moveLeft() }
            ctrlButton(system: "arrow.clockwise") { bridge.rotate() }
            ctrlButton(system: "arrow.right") { bridge.moveRight() }
            ctrlButton(system: "arrow.down.to.line") { bridge.hardDrop() }
        }
    }

    private func ctrlButton(system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.sanAccent)
    }

    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 10) {
                Text("Игра окончена").font(.title3.bold()).foregroundStyle(.white)
                Text("Линий: \(bridge.finalLines) → +\(bridge.finalLines * 5) бонусов")
                    .foregroundStyle(.white)
                Text("Очки: \(bridge.score)")
                    .font(.caption).foregroundStyle(.white.opacity(0.85))
                Button("Ещё раз") { bridge.restart() }
                    .buttonStyle(.borderedProminent).tint(.sanAccent)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Мост между SpriteKit-сценой и SwiftUI: публикует счёт и состояние.
@MainActor
final class TetrisBridge: ObservableObject {
    @Published var score = 0
    @Published var lines = 0
    @Published var finalLines = 0
    @Published var isOver = false
    @Published var didFinish = false   // импульс для начисления бонусов

    private var scene: TetrisScene?

    func makeScene(size: CGSize) -> TetrisScene {
        if let scene { return scene }
        let s = TetrisScene(size: size)
        s.scaleMode = .resizeFill
        s.onScoreChange = { [weak self] in self?.score = $0 }
        s.onLinesChange = { [weak self] in self?.lines = $0 }
        s.onGameOver = { [weak self] _, finalLines in
            guard let self else { return }
            self.finalLines = finalLines
            self.isOver = true
            self.didFinish = true
        }
        scene = s
        return s
    }

    func moveLeft()  { scene?.moveLeft() }
    func moveRight() { scene?.moveRight() }
    func rotate()    { scene?.rotate() }
    func hardDrop()  { scene?.hardDrop() }

    func restart() {
        isOver = false
        didFinish = false
        finalLines = 0
        score = 0
        lines = 0
        scene?.startGame()
    }
}

#Preview {
    NavigationStack { TetrisGameView() }
        .environmentObject(BonusEngine())
        .tint(.sanAccent)
}
