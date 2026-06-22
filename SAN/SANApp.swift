import SwiftUI
import UIKit
import FirebaseCore
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct SANApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var router = DeepLinkRouter.shared

    init() {
        if AppConfig.useFirebase {
            FirebaseApp.configure()
        }
    }

    @StateObject private var store = AppStore()
    @StateObject private var session = SessionStore()
    @StateObject private var bonus = BonusEngine()
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var location = LocationManager()
    @StateObject private var hostStore = HostStore()
    private let pushService = AppConfig.makePushService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isSignedIn {
                    SignedInRootView()
                } else {
                    AuthView()
                }
            }
            .environmentObject(store)
            .environmentObject(session)
            .environmentObject(bonus)
            .environmentObject(themeStore)
            .environmentObject(location)
            .environmentObject(hostStore)
            .tint(.sanAccent)
            .preferredColorScheme(themeStore.theme.colorScheme)
            .onOpenURL { url in
                #if canImport(GoogleSignIn)
                GIDSignIn.sharedInstance.handle(url)
                #endif
                router.handle(url: url)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL { router.handle(url: url) }
            }
            .sheet(item: $router.route) { route in
                DeepLinkDestination(route: route)
            }
            // Любой тап продлевает «активность» для бонус-движка.
            // Через ActivityTracker (UIKit, cancelsTouchesInView=false), чтобы НЕ
            // перехватывать нажатия кнопок SwiftUI (.onTapGesture на корне их ломал).
            .background(ActivityTracker { bonus.registerInteraction() })
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    location.refresh()
                    store.setCurrentUser(id: session.user?.id, name: session.user?.name, isGuest: session.isGuest)
                    if session.isSignedIn { bonus.start() }
                    NotificationManager.refresh(reachedGoalToday: bonus.reachedGoalToday)
                default:
                    bonus.pause()
                }
            }
            .onChange(of: session.isSignedIn) { _, signedIn in
                store.setCurrentUser(id: session.user?.id, name: session.user?.name, isGuest: session.isGuest)
                if signedIn {
                    bonus.start()
                    hostStore.configure(ownerID: session.user?.id)
                    Task { await hostStore.sync() }
                } else {
                    bonus.pause()
                }
            }
            .onChange(of: bonus.reachedGoalToday) { _, reached in
                NotificationManager.refresh(reachedGoalToday: reached)
            }
            .task {
                hostStore.bind(store)
                hostStore.configure(ownerID: session.user?.id)
                await store.load()
                store.setCurrentUser(id: session.user?.id, name: session.user?.name, isGuest: session.isGuest)
                await hostStore.sync()
                if session.isSignedIn { bonus.start() }
                // Регистрация для remote-уведомлений → APNs-токен уходит в FCM
                // (нужно для доставки топик-сообщений). Идемпотентно.
                UIApplication.shared.registerForRemoteNotifications()
                // Подписка на топики FCM — чтобы получать рекламные push-кампании.
                pushService.subscribe(topic: "all_users")
                pushService.subscribe(topic: "city_\(store.selectedCitySlug)")
            }
        }
    }
}

/// Гейт онбординга + переключение пользователь/хост.
struct SignedInRootView: View {
    @EnvironmentObject private var host: HostStore
    @AppStorage("san.onboarded") private var onboarded = false
    @AppStorage("san.hostMode") private var hostMode = false

    var body: some View {
        if hostMode && host.hasAccount {
            HostRootView()
        } else if onboarded {
            RootView()
        } else {
            OnboardingView { onboarded = true }
        }
    }
}

/// Пользовательская навигация: Главная · Поиск · Бонусы (центр) · Сохранённое · Профиль.
/// «Бонусы» — 3-я из 5 вкладок (центральная), index 2.
struct RootView: View {
    var body: some View {
        TabView {
            HomeFeedView()
                .tabItem { Label("Главная", systemImage: "house.fill") }
            SearchView()
                .tabItem { Label("Поиск", systemImage: "magnifyingglass") }
            BonusHubView()
                .tabItem { Label("Бонусы", systemImage: "gift.fill") }
            SavedView()
                .tabItem { Label("Сохранённое", systemImage: "bookmark.fill") }
            ProfileView()
                .tabItem { Label("Профиль", systemImage: "person.fill") }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppStore())
        .environmentObject(SessionStore())
        .environmentObject(BonusEngine())
        .environmentObject(ThemeStore())
        .environmentObject(LocationManager())
        .tint(.sanAccent)
}
