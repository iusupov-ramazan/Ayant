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
    /// Бонусы, уже предъявленные движку за эту партию. Начисление идёт по ходу
    /// игры, на каждом полном «пакете» яблок: раньше всё платилось только в
    /// конце, и крестик посреди партии стирал заработанное.
    @State private var credited = 0
    /// Курс на эту партию (Remote Config): снимок в начале партии.
    @State private var partyRates: GameRates?
    private var rates: GameRates { partyRates ?? bonus.gameRates }

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

                // Курс — внизу, как во всех четырёх играх.
                VStack(spacing: 2) {
                    Text("Свайпайте, чтобы поворачивать")
                    Text("\(rates.applesPerBonus) 🍎 = 1 бонус")
                }
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Змейка")
            .bonusPausedNotice(.snake)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Выход — как во всех играх: «Готово» справа.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }.font(.golos(16, .semibold))
                }
            }
            // Слушаем номер партии, а не счёт: две партии подряд с одинаковым
            // счётом не меняют `finalScore`, и `onChange` по нему не сработал бы.
            .onAppear { if partyRates == nil { partyRates = bonus.gameRates } }
            // Яблоки переводятся в бонусы по ходу партии. Неполный «пакет» в
            // конце пропадает — его не за что засчитать.
            .onChange(of: bridge.score) { _, score in award(score: score) }
            .onChange(of: bridge.gamesFinished) { _, _ in
                award(score: bridge.finalScore)
                AnalyticsLog.log(.gamePlayed, ["game": BonusGame.snake.rawValue])
            }
        }
    }

    /// Предъявляет движку бонусы за новые полные «пакеты» яблок. `awarded` —
    /// то, что движок реально начислил (лимит может урезать).
    private func award(score: Int) {
        let perBonus = rates.applesPerBonus
        let due = BatchPayout.newBonuses(units: score, unitsPerBonus: perBonus, alreadyCredited: credited)
        guard due > 0 else { return }
        let granted = bonus.awardGameplay(due, source: BonusGame.snake.source)
        credited = BatchPayout.fullBatches(units: score, unitsPerBonus: perBonus)
        if granted > 0 { awarded += granted; announceBonus(awarded) }
    }

    /// Шапка — как у Тетриса и Diamond: счёт крупно, бонусы партии под ним.
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Счёт: \(bridge.score)")
                    .font(.golos(17, .bold)).foregroundStyle(Color.sanInk)
                    .contentTransition(.numericText())
                Text("+\(awarded) бонусов")
                    .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                    .contentTransition(.numericText())
            }
            Spacer()
        }
    }

    /// Итог партии — та же плашка, что в Тетрисе и 2048: шрифт Golos и
    /// белая капсула «Ещё раз».
    private var gameOverOverlay: some View {
        VStack(spacing: 12) {
            Text("Игра окончена").font(.golos(20, .heavy)).foregroundStyle(.white)
            Text("Счёт: \(bridge.finalScore)")
                .font(.golos(14)).foregroundStyle(.white.opacity(0.85))
            Text("+\(awarded) бонусов")
                .font(.golos(14, .bold)).foregroundStyle(.white)
            Button("Ещё раз") {
                partyRates = bonus.gameRates
                credited = 0
                awarded = 0
                bridge.restart()
            }
            .font(.golos(15, .bold)).foregroundStyle(Color.sanInk)
            .padding(.horizontal, 20).frame(minHeight: 44)
            .background(Color.white, in: Capsule())
            .buttonStyle(.sanPress(0.94))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.55))
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
