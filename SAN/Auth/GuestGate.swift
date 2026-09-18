import SwiftUI
import AyantFeatures

/// Единый отказ гостю: объяснение + экран входа ПОВЕРХ приложения.
///
/// Раньше «Войти» звало `session.signOut()` — гость вылетал в корневой экран
/// входа, терял место, где стоял, и видел там кнопку «зайти как гость», которая
/// возвращала его в ту же точку. Теперь `AuthView(presentation: .upgrade)`
/// показывается модально: под ним остаётся приложение, а после входа экран
/// закрывается сам и корень пересобирается под новый аккаунт.
struct GuestGate {
    /// Тексты для разных мест — чтобы гость понимал, что именно он теряет.
    /// Ключи каталога (`LocalizedStringKey`), а не `String`: иначе алерт
    /// оставался русским на английском и кыргызском интерфейсе.
    static let saveVenue: LocalizedStringKey = "Гостям доступен только просмотр. Войдите, чтобы сохранять места."
    static let saveDeal: LocalizedStringKey = "Гостям доступен только просмотр. Войдите, чтобы сохранять предложения."
    static let like: LocalizedStringKey = "Войдите, чтобы отмечать предложения — они переедут с вами на другое устройство."
    static let qr: LocalizedStringKey = "Личный QR привязан к аккаунту: по нему заведение начисляет баллы. Войдите или создайте аккаунт."
    static let bonuses: LocalizedStringKey = "Баллы, купоны и карты лояльности копятся в аккаунте. Войдите или создайте аккаунт."
    static let game: LocalizedStringKey = "Награды за игру начисляются в аккаунт. Войдите или создайте аккаунт."
    static let coupon: LocalizedStringKey = "Войдите в аккаунт, чтобы получить купон."
    static let review: LocalizedStringKey = "Войдите в аккаунт, чтобы оставлять отзывы."
}

// MARK: - Экран входа поверх приложения

private struct AuthUpgradeCover: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) {
            AuthView(presentation: .upgrade)
        }
    }
}

extension View {
    /// Показывает экран входа поверх текущего — для гостя, упёршегося в
    /// закрытую функцию. Приложение под ним остаётся на месте.
    func authUpgradeCover(isPresented: Binding<Bool>) -> some View {
        modifier(AuthUpgradeCover(isPresented: isPresented))
    }
}

// MARK: - Алерт

private struct GuestAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: LocalizedStringKey
    @State private var showAuth = false

    func body(content: Content) -> some View {
        content
            .alert("Нужен аккаунт", isPresented: $isPresented) {
                Button("Войти или создать аккаунт") { showAuth = true }
                Button("Не сейчас", role: .cancel) {}
            } message: {
                Text(message)
            }
            .authUpgradeCover(isPresented: $showAuth)
    }
}

extension View {
    /// Стандартный отказ гостю: объяснение и переход к входу поверх экрана.
    func guestAlert(isPresented: Binding<Bool>, message: LocalizedStringKey) -> some View {
        modifier(GuestAlertModifier(isPresented: isPresented, message: message))
    }
}
