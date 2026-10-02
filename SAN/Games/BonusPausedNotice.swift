import SwiftUI
import AyantDomain
import AyantFeatures

/// Плашка над игрой, когда она сейчас не платит: начисление выключено
/// удалённо (`ios_bonus_<game>_enabled`), исчерпан дневной лимит игры
/// (`ios_bonus_<game>_daily_cap`) или серверный дневной потолок кошелька
/// (`earnBonus` урезал начисление). Без неё игрок честно копил бы очки и не
/// понимал, почему баланс стоит.
private struct BonusPausedNotice: ViewModifier {
    let game: BonusGame
    @EnvironmentObject private var bonus: BonusEngine

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if let text = message {
                Label { Text(verbatim: text) } icon: { Image(systemName: "pause.circle.fill") }
                    .font(.golos(12.5, .semibold))
                    .foregroundStyle(Color(hex: 0xC26A00))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: 0xC26A00).opacity(0.1))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: message)
        // Закрыли игру — её плашка своё отслужила: в хабе и в следующей игре
        // она была бы про чужую партию.
        .onDisappear {
            if bonus.earnNotice?.source == game.source { bonus.clearEarnNotice() }
        }
    }

    private var message: String? {
        if !bonus.earnsBonus(game) { return LS("Бонусы за эту игру сейчас не начисляются — играть можно") }
        // Сервер больше не зачисляет сегодня — общий потолок кошелька, а не
        // лимит одной игры.
        if bonus.serverDailyCapReached { return LS("Лимит бонусов на сегодня — играть можно, бонусы завтра") }
        // Сервер начислил меньше, чем заработано в ЭТОЙ игре: честно говорим
        // сколько. Плашка другой игры или времени в приложении сюда не
        // попадает — «Начислено 3 из 4» над Змейкой про Diamond сбивало с толку.
        if let notice = bonus.earnNotice, notice.source == game.source {
            return LF("Начислено %lld из %lld — дневной лимит бонусов", notice.granted, notice.requested)
        }
        // У Diamond остаток лимита уже в счётчике игры — плашка дублировала бы его.
        if !game.isEndless, bonus.remainingToday(game) == 0 {
            return LS("Лимит бонусов за эту игру на сегодня собран — завтра снова")
        }
        return nil
    }
}

extension View {
    func bonusPausedNotice(_ game: BonusGame) -> some View {
        modifier(BonusPausedNotice(game: game))
    }
}

/// Озвучивает VoiceOver новый итог «+N бонусов» в игре или тост хаба:
/// цифра меняется беззвучно, и незрячий игрок не узнавал о начислении.
@MainActor
func announceBonus(_ total: Int) {
    guard total > 0 else { return }
    AccessibilityNotification.Announcement(LF("+%lld бонусов", total)).post()
}
