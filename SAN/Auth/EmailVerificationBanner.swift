import SwiftUI
import AyantFeatures

/// Плашка «Подтвердите email» для почтовых аккаунтов без подтверждённого адреса.
///
/// Кошелёк бонусов и покупка купонов отказывают таким аккаунтам
/// (`403 email_not_verified`) — иначе каждая выдуманная почта становится
/// новым кошельком. Плашка объясняет это до первого отказа и даёт два
/// действия: отправить письмо ещё раз и «Я подтвердил» (перечитать
/// пользователя и обновить токен, чтобы сервер увидел подтверждение).
///
/// Показывается сама, только когда `session.needsEmailVerification`; в любом
/// другом случае — пустое место. Ставится в «Профиль» и «Бонусы».
struct EmailVerificationBanner: View {
    @EnvironmentObject private var session: SessionStore
    @State private var busy = false
    @State private var status: LocalizedStringKey?

    var body: some View {
        if session.needsEmailVerification {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.sanAccentText)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Подтвердите email, чтобы копить и тратить бонусы")
                            .font(.golos(15, .bold)).foregroundStyle(Color.sanInk)
                        if let email = session.user?.email {
                            Text(LF("Мы отправили письмо со ссылкой на %@", email))
                                .font(.golos(13, .regular)).foregroundStyle(Color.sanInkSoft)
                        }
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        run { await session.resendVerificationEmail()
                            ? "Письмо отправлено. Проверьте почту и папку «Спам»."
                            : "Не удалось отправить письмо. Попробуйте позже." }
                    } label: {
                        Text("Отправить письмо ещё раз").font(.golos(13, .semibold))
                    }
                    .buttonStyle(.bordered)
                    Button {
                        run { await session.confirmEmailVerified()
                            ? "Почта подтверждена"
                            : "Почта ещё не подтверждена. Откройте ссылку из письма и попробуйте снова." }
                    } label: {
                        Text("Я подтвердил").font(.golos(13, .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.sanAccent)
                    if busy { ProgressView().controlSize(.small) }
                }
                .disabled(busy)
                if let status {
                    Text(status).font(.golos(12.5, .medium)).foregroundStyle(Color.sanInkSoft)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sanGroupCard()
        }
    }

    private func run(_ action: @escaping () async -> LocalizedStringKey) {
        busy = true
        status = nil
        Task {
            let text = await action()
            status = text
            busy = false
        }
    }
}
