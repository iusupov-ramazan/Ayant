import SwiftUI
import SpriteKit
import AyantDomain
import AyantFeatures

// MARK: - Общие игровые типы (используются сценой SpriteKit)

struct Point: Equatable { var x: Int; var y: Int }

enum Direction {
    case up, down, left, right
    var opposite: Direction {
        switch self {
        case .up: return .down; case .down: return .up
        case .left: return .right; case .right: return .left
        }
    }
}

// MARK: - Экран игры (SwiftUI-обёртка над SpriteKit-сценой)

struct SnakeGameView: View {
    @EnvironmentObject private var bonus: BonusEngine
    /// Текст водяного знака берётся из настроек панели (`AppStore.settings`).
    @EnvironmentObject private var store: AppStore
    @StateObject private var bridge = SnakeBridge()
    @Environment(\.dismiss) private var dismiss
    /// Сколько бонусов РЕАЛЬНО начислил `BonusEngine` за последнюю партию —
    /// дневной лимит может урезать до нуля, и врать «+N» нельзя.
    @State private var awarded = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                header

                GeometryReader { geo in
                    SpriteView(scene: bridge.makeScene(size: geo.size,
                                                       watermark: store.settings.adPlaceholderText),
                               options: [.allowsTransparency])
                }
                .aspectRatio(15.0 / 20.0, contentMode: .fit)
                .overlay { if bridge.isOver { gameOverOverlay } }

                Text("Свайпай, чтобы поворачивать")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Змейка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            // Слушаем номер партии, а не счёт: две партии подряд с одинаковым
            // счётом не меняют `finalScore`, и `onChange` по нему не сработал бы.
            .onChange(of: bridge.gamesFinished) { _, _ in
                // Яблоки переводятся в бонусы по общему курсу мини-игр.
                // Остаток партии пропадает: начисление здесь одно, в конце
                // игры, и переносить хвост некуда.
                let earned = bridge.finalScore / GameEconomy.applesPerBonus
                awarded = earned > 0 ? bonus.awardGameplay(earned) : 0
            }
        }
    }

    private var header: some View {
        HStack {
            Label("\(bridge.score)", systemImage: "star.fill")
                .font(.headline).foregroundStyle(Color.sanAccentText)
            Spacer()
            Text("\(GameEconomy.applesPerBonus) 🍎 = 1 бонус")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var gameOverOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 10) {
                Text("Игра окончена").font(.title3.bold()).foregroundStyle(.white)
                Text("Счёт: \(bridge.finalScore) → +\(awarded) бонусов")
                    .foregroundStyle(.white)
                Button("Ещё раз") { bridge.restart() }
                    .buttonStyle(.borderedProminent).tint(.sanAccent)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Мост между SpriteKit-сценой и SwiftUI: публикует счёт и состояние.
@MainActor
final class SnakeBridge: ObservableObject {
    @Published var score = 0
    @Published var finalScore = 0
    @Published var isOver = false
    /// Счётчик завершённых партий — меняется на каждом «game over», даже если
    /// счёт совпал с прошлым.
    @Published var gamesFinished = 0

    private var scene: SnakeScene?

    func makeScene(size: CGSize, watermark: String) -> SnakeScene {
        // Настройки могут приехать после первого кадра — обновляем текст на живой сцене.
        if let scene { scene.watermarkText = watermark; return scene }
        let s = SnakeScene(size: size)
        s.scaleMode = .resizeFill
        s.watermarkText = watermark
        s.onScoreChange = { [weak self] in self?.score = $0 }
        s.onGameOver = { [weak self] final in
            self?.finalScore = final
            self?.isOver = true
            self?.gamesFinished += 1
        }
        scene = s
        return s
    }

    func restart() {
        isOver = false
        finalScore = 0
        score = 0
        scene?.startGame()
    }
}

#Preview {
    NavigationStack { SnakeGameView() }
        .environmentObject(AyantStores.bonus())
        .environmentObject(AyantStores.app())
        .tint(.sanAccent)
}
