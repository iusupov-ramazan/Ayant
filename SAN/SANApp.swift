import SwiftUI
import UIKit
import FirebaseCore
import FirebaseMessaging
#if canImport(GoogleSignIn)
import GoogleSignIn
import AyantFeatures
import AyantDomain
#endif

@main
struct SANApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var router = DeepLinkRouter.shared

    init() {
        AyantStores.installAnalytics()
        // Кэш изображений в памяти и на диске — лента не перезагружает фото при скролле.
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024,
                                   diskCapacity: 256 * 1024 * 1024)
        if AppConfig.useFirebase {
            FirebaseApp.configure()
        }
    }

    @StateObject private var store = AyantStores.app()
    @StateObject private var session = AyantStores.session()
    @StateObject private var bonus = AyantStores.bonus()
    @StateObject private var coupons = AyantStores.coupons()
    @StateObject private var loyalty = AyantStores.loyalty()
    @StateObject private var points = AyantStores.points()
    @StateObject private var themeStore = AyantStores.theme()
    @StateObject private var location = LocationManager()
    @StateObject private var hostStore = AyantStores.host()
    private let pushService = AppConfig.makePushService()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("san.language") private var appLanguage = "ru"   // ru | en

    /// Языки, у которых строковый каталог заполнен целиком. Кыргызский переведён
    /// частично, и если оставить его выбранным, экран получится из двух языков
    /// сразу — поэтому старую настройку «ky» тихо считаем русским, пока
    /// `Localizable.xcstrings` не дозаполнят. На Android ресурсы полные.
    private static let completeLanguages: Set<String> = ["ru", "en"]
    private var effectiveLanguage: String {
        Self.completeLanguages.contains(appLanguage) ? appLanguage : "ru"
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isSignedIn {
                    SignedInRootView()
                        // Смена пользователя пересобирает корень: вкладки, стеки
                        // навигации и экранное состояние принадлежали прошлому
                        // аккаунту (гость, вошедший из закрытой вкладки, иначе
                        // остался бы на «Главной» со старым состоянием вкладок).
                        // В ключ входит и гостевой статус: регистрация гостя
                        // сохраняет uid (запись связывается), но приложение
                        // после неё — другое, с открытыми QR и бонусами.
                        .id("\(session.user?.id ?? "signed-in")-\(session.isGuest)")
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    AuthView()
                        .transition(.opacity)
                }
            }
            // Подмена корня — анимированная: вход и выход не должны выглядеть
            // как мгновенная перерисовка экрана.
            .animation(.smooth(duration: 0.35), value: session.isSignedIn)
            .animation(.smooth(duration: 0.35), value: session.user?.id)
            .animation(.smooth(duration: 0.35), value: session.isGuest)
            .overlay(alignment: .top) { AppToast() }
            .environmentObject(store)
            .environmentObject(session)
            .environmentObject(bonus)
            .environmentObject(coupons)
            .environmentObject(loyalty)
            .environmentObject(points)
            .environmentObject(store.feed)
            .environmentObject(themeStore)
            .environmentObject(location)
            .environmentObject(hostStore)
            .tint(.sanAccent)
            .environment(\.locale, Locale(identifier: effectiveLanguage))
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
                    .environmentObject(coupons)
                    .environmentObject(loyalty)
                    .environmentObject(points)
                    .environmentObject(store.feed)
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
                    startBonusIfAllowed()
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
                    startBonusIfAllowed()
                    hostStore.send(.configure(ownerID: session.user?.id))
                    Task { hostStore.send(.sync) }
                    syncBackendCoupons()
                } else {
                    signOutCleanup()
                }
            }
            // Сменился пользователь БЕЗ выхода (гость вошёл в существующий
            // аккаунт из модального экрана): локальные кошельки лежат на
            // устройстве и принадлежат прошлому uid — стираем их здесь, как при
            // выходе. Если uid сохранился (регистрация гостя связывает запись),
            // ничего не трогаем: это тот же человек с теми же баллами.
            .onChange(of: session.user?.id) { old, new in
                guard let old, let new, old != new else { return }
                store.setCurrentUser(id: new, name: session.user?.name, isGuest: session.isGuest)
                resetLocalWallets()
                syncBackendCoupons()
            }
            .onChange(of: bonus.reachedGoalToday) { _, reached in
                NotificationManager.refresh(reachedGoalToday: reached)
            }
            .task {
                AnalyticsLog.log(.appOpen)
                await CategoryStore.shared.load()   // гибкие категории из бэкенда
                hostStore.bind(store)
                // Отписка от push должна успеть ДО закрытия сессии — правила
                // `userTokens` требуют авторизации, поэтому это хук в сторе,
                // а не код в `onChange(isSignedIn)` (тот срабатывает уже после).
                session.willSignOut = { [pushService, store] in
                    await pushService.unregisterDevice(
                        topics: ["all_users", "city_\(store.selectedCitySlug)"])
                }
                hostStore.send(.configure(ownerID: session.user?.id))
                await store.load()
                store.setCurrentUser(id: session.user?.id, name: session.user?.name, isGuest: session.isGuest)
                store.grantPendingReferral(bonus: bonus)
                store.claimReferralBonuses(bonus: bonus)
                store.claimPendingGift(into: coupons)
                hostStore.send(.sync)
                syncBackendCoupons()
                startBonusIfAllowed()
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

    /// Выход из аккаунта: гасим таймеры и СТИРАЕМ всё, что принадлежало
    /// вышедшему пользователю. (Отписка от push — в `session.willSignOut`:
    /// она обязана произойти раньше, пока сессия ещё жива.)
    ///
    /// Локальные кошельки лежат в `UserDefaults`/`@AppStorage`, то есть на
    /// устройстве, а не в аккаунте: без этой чистки следующий вошедший (и сам
    /// вышедший гость) видел чужой баланс бонусов, купоны, штампы и
    /// сохранённые места.
    private func signOutCleanup() {
        bonus.pause()
        // Кэш заведений владельца из памяти (данные остаются в Firestore под
        // ownerID и вернутся при следующем входе).
        hostStore.send(.configure(ownerID: nil))
        resetLocalWallets()
        store.resetForNewUser()
    }

    /// Бонус-движок работает только у настоящего аккаунта.
    ///
    /// Гостю бонусы недоступны целиком: экран «Бонусы», игры и обмен наград ему
    /// закрыты, — значит и копиться им не должно. Раньше таймер активности тикал
    /// и гостю: он «зарабатывал» в запись, которая исчезает вместе с выходом.
    private func startBonusIfAllowed() {
        guard session.isSignedIn, !session.isGuest else { bonus.pause(); return }
        bonus.start()
    }

    /// Стирает кошельки, которые лежат на УСТРОЙСТВЕ, а не в аккаунте:
    /// бонусы, купоны, карты лояльности и личную библиотеку.
    private func resetLocalWallets() {
        points.send(.stop)
        loyalty.stopObserving()
        bonus.resetForNewUser()
        coupons.resetForNewUser()
        loyalty.resetForNewUser()
    }

    /// Берёт текущий FCM-токен и пишет его в userTokens уже под авторизацией
    /// (правило userTokens требует request.auth != null).
    private func registerPushToken() {
        Messaging.messaging().token { token, _ in
            guard let token else { return }
            pushService.registerToken(token, city: store.selectedCitySlug, uid: session.user?.id)
        }
    }

    /// Синк купонов и карт лояльности из Firestore (used-статус, новые награды, штампы).
    private func syncBackendCoupons() {
        guard let uid = session.user?.id, !session.isGuest else { return }
        points.send(.observe(userID: uid))   // живой поток; опрос больше не нужен
        Task {
            await coupons.sync(userID: uid)
            await loyalty.sync(userID: uid)
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
        if hostMode && host.state.hasAccount {
            HostRootView()
        } else if onboarded {
            RootView()
        } else {
            OnboardingView { onboarded = true }
        }
    }
}

// Пользовательская навигация переехала в `GuestShell.swift`:
// Главная · Поиск · [QR] · Кошелёк · Профиль — своя панель вкладок с FAB.
