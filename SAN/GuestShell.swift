import SwiftUI
import AyantDomain
import AyantFeatures

// Оболочка гостевого приложения: пять вкладок на СИСТЕМНОЙ панели.
//
// Что изменилось против первой версии редизайна: панель была нарисована руками
// ради выреза под центральный FAB с личным QR. На iOS 26 системный таб-бар сам
// приходит со стеклом, поэтому «Мой QR» стал обычной центральной вкладкой —
// то же место, тот же один тап, но без ручной панели и всего, что она тянула
// (нижние отступы, preference «спрятать панель», бесконечная пульсация FAB).
//
// Вкладки: Главная · Поиск · Мой QR · Бонусы · Профиль. «Сохранённое» живёт
// в шапке ленты и строкой в профиле.

enum GuestTab: Hashable {
    case home, search, qr, wallet, profile
}

/// Мгновенно меняет состояние, снимая с него текущую (в т. ч. бесконечную) анимацию.
func withoutAnimation(_ body: () -> Void) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction, body)
}

// MARK: - Корень гостевой навигации

/// Главная · Поиск · Мой QR · Бонусы · Профиль.
///
/// Панель — СИСТЕМНАЯ. Своя была нужна ради выреза под FAB и цветов подписи;
/// на iOS 26 системный таб-бар сам приходит со стеклом (Liquid Glass), а тон
/// подписи задаёт `tint`. Заодно уходят все костыли, которые эта панель за
/// собой тянула: ручной расчёт нижних отступов, preference для «спрятать
/// панель» и вечная пульсация вокруг FAB.
///
/// «Мой QR» переехал из FAB в центральную вкладку: действие осталось на том же
/// месте экрана и в один тап, но теперь это обычная вкладка, а не кнопка
/// поверх стекла.
struct RootView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var tab: GuestTab = .home
    @State private var showAuth = false

    /// Вкладки «Мой QR» и «Бонусы» гостю не работают: код привязан к аккаунту,
    /// баллы копятся на нём же. Вместо подмены содержимого заглушкой (вкладка
    /// открывалась «пустой») ПОКАЗЫВАЕМ экран входа поверх приложения, а сама
    /// вкладка не переключается — гость остаётся там, где стоял.
    private var selection: Binding<GuestTab> {
        Binding(
            get: { tab },
            set: { next in
                if session.isGuest, next == .qr || next == .wallet {
                    showAuth = true
                } else {
                    tab = next
                }
            }
        )
    }

    var body: some View {
        TabView(selection: selection) {
            HomeFeedView()
                .tabItem { Label("Главная", systemImage: "house.fill") }
                .tag(GuestTab.home)
            SearchView()
                .tabItem { Label("Поиск", systemImage: "magnifyingglass") }
                .tag(GuestTab.search)
            MyQRView(showsDone: false)
                .tabItem { Label("Мой QR", systemImage: "qrcode") }
                .tag(GuestTab.qr)
            BonusHubView()
                .tabItem { Label("Бонусы", systemImage: "creditcard.fill") }
                .tag(GuestTab.wallet)
            ProfileView()
                .tabItem { Label("Профиль", systemImage: "person.fill") }
                .tag(GuestTab.profile)
        }
        // Акцент как ТЕКСТ: подпись вкладки 11pt, заливочный `sanAccent` на
        // ней не проходит AA (см. правило в хендоффе).
        .tint(Color.sanAccentText)
        .authUpgradeCover(isPresented: $showAuth)
    }
}

#Preview {
    RootView()
        .environmentObject(AyantStores.app())
        .environmentObject(AyantStores.session())
        .environmentObject(AyantStores.bonus())
        .environmentObject(AyantStores.points())
        .environmentObject(AyantStores.theme())
        .environmentObject(LocationManager())
        .tint(.sanAccent)
}
