import SwiftUI

/// «Обновите приложение» — экран, закрывающий сборку ниже `ios_min_version`
/// (Firebase Remote Config, см. `RemoteSettingsStore`).
///
/// Закрыть его нельзя намеренно: показываем его, только когда старая версия
/// опасна (портит данные, ходит в отключённый API). Для «просто есть новая
/// версия» он не нужен — для этого есть App Store.
struct AppUpdateRequiredView: View {
    let updateURL: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            SanIconTile(systemName: "arrow.down.app.fill", filled: true, size: 72)
            Text("Обновите приложение")
                .font(.golos(22, .heavy)).foregroundStyle(Color.sanInk)
                .multilineTextAlignment(.center)
            Text("Эта версия Ayant больше не поддерживается. Обновление займёт минуту — ваши бонусы, баллы и купоны сохранятся.")
                .font(.golos(15)).foregroundStyle(Color.sanInkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Обновить") {
                let link = updateURL.trimmingCharacters(in: .whitespaces)
                if let url = URL(string: link.isEmpty ? AppConfig.appStoreFallbackURL : link) {
                    openURL(url)
                }
            }
            .buttonStyle(SanPrimaryButton())
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.sanCanvas.ignoresSafeArea())
        // Поверх всего и без «назад»: экран не должен пропускать касания вниз.
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isModal)
    }
}
