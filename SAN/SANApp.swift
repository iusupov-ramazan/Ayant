import SwiftUI
import UIKit
import FirebaseCore
import FirebaseMessaging
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct SANApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var router = DeepLinkRouter.shared

    init() {
        // Кэш изображений в памяти и на диске — лента не перезагружает фото при скролле.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024,
                                   diskCapacity: 256 * 1024 * 1024)
        if AppConfig.useFirebase {
            FirebaseApp.configure()
        }
    }

    @StateObject private var store = AppStore()
    @StateObject private var session = SessionStore()
    @StateObject private var bonus = BonusEngine()
    @StateObject private var coupons = CouponStore()
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
            .overlay(alignment: .top) { AppToast() }
            .environmentObject(store)
            .environmentObject(session)
            .environmentObject(bonus)
            .environmentObject(coupons)
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
                store.claimPendingGift(into: coupons)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL {
                    router.handle(url: url)
                    store.claimPendingGift(into: coupons)
                }
            }
            .sheet(item: $router.route) { route in
                DeepLinkDestination(route: route)
                    .environmentObject(store)
                    .environmentObject(session)
                    .environmentObject(location)
                    .environmentObject(bonus)
                    .environmentObject(themeStore)
                    .environmentObject(hostStore)
                    .tint(.sanAccent)
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
                    store.grantPendingReferral(bonus: bonus)
                    store.claimReferralBonuses(bonus: bonus)
                    store.claimPendingGift(into: coupons)
                    registerPushToken()      // токен пишем уже под авторизацией
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
                AnalyticsLog.log(.appOpen)
                hostStore.bind(store)
                hostStore.configure(ownerID: session.user?.id)
                await store.load()
                store.setCurrentUser(id: session.user?.id, name: session.user?.name, isGuest: session.isGuest)
                store.grantPendingReferral(bonus: bonus)
                store.claimReferralBonuses(bonus: bonus)
                store.claimPendingGift(into: coupons)
                await hostStore.sync()
                if session.isSignedIn { bonus.start() }
                // Регистрация для remote-уведомлений → APNs-токен уходит в FCM
                // (нужно для доставки топик-сообщений). Идемпотентно.
                UIApplication.shared.registerForRemoteNotifications()
                // Подписка на топики FCM — чтобы получать рекламные push-кампании.
                pushService.subscribe(topic: "all_users")
                pushService.subscribe(topic: "city_\(store.selectedCitySlug)")
                if session.isSignedIn { registerPushToken() }
            }
        }
    }

    /// Берёт текущий FCM-токен и пишет его в userTokens уже под авторизацией
    /// (правило userTokens требует request.auth != null).
    private func registerPushToken() {
        Messaging.messaging().token { token, _ in
            guard let token else { return }
            pushService.registerToken(token, city: store.selectedCitySlug, uid: session.user?.id)
        }
    }
}

/// Всплывающее уведомление (подарки, ошибки и т. п.) поверх всего приложения.
struct AppToast: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        ZStack {
            if let msg = store.toastMessage {
                Text(msg)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color.black.opacity(0.85), in: Capsule())
                    .padding(.horizontal, 24).padding(.top, 8)
                    .shadow(radius: 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: msg) {
                        try? await Task.sleep(nanoseconds: 2_800_000_000)
                        store.toastMessage = nil
                    }
            }
        }
        .animation(.spring(response: 0.35), value: store.toastMessage)
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
