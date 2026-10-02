import SwiftUI
import UIKit
import FirebaseCore
import FirebaseCrashlytics
import FirebaseMessaging
import AyantData
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
            // App Check — до configure(): провайдер выбирается при старте SDK.
            AyantAppCheck.install()
            FirebaseApp.configure()
            #if DEBUG
            // Падения при разработке не должны размывать crash-free rate
            // релиза: отчёты шлёт только релизная сборка.
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
            #else
            // Флаг сохраняется на устройстве: отладочная сборка, однажды
            // поставленная на этот же телефон, оставляла `false` и релизу —
            // падения из TestFlight молча не доходили. Включаем явно.
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
            #endif
        }
        // Выключатели функций — из кэша до первого экрана; дальше обновляются
        // на лету (`RemoteSettingsEffects`).
        ReleaseFlags.apply(AyantStores.remoteConfig.current())
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
    @StateObject private var remoteSettings = AyantStores.remoteSettings()
    private let pushService = AppConfig.makePushService()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("san.language") private var appLanguage = "ru"   // ru | en | ky

    /// Языки, у которых строковый каталог заполнен целиком. Неизвестное значение
    /// настройки тихо считаем русским — иначе экран собрался бы из двух языков.
    private static let completeLanguages: Set<String> = ["ru", "en", "ky"]
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
            .modifier(RemoteSettingsEffects(remote: remoteSettings, bonus: bonus,
                                            onBonusWalletFlagChange: {
                                                startBonusIfAllowed()
                                                refreshBonusReminder()
                                            },
                                            onReminderInputsChange: { refreshBonusReminder() }))
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
                    // Лист диплинка — отдельное окно презентации: без этого он
                    // брал язык системы, и русское приложение показывало
                    // «Posts / Reviews / Show QR» на английском симуляторе.
                    .environment(\.locale, Locale(identifier: effectiveLanguage))
            }
            // Любой тап продлевает «активность» для бонус-движка.
            // Через ActivityTracker (UIKit, cancelsTouchesInView=false), чтобы НЕ
            // перехватывать нажатия кнопок SwiftUI (.onTapGesture на корне их ломал).
            .background(ActivityTracker { bonus.registerInteraction() })
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    location.refresh()
                    Task { await remoteSettings.refresh() }
                    store.setCurrentUser(id: session.user?.id, name: session.user?.name, isGuest: session.isGuest)
                    // Полночь по Бишкеку могла пройти в фоне — снимаем вчерашние
                    // «лимит на сегодня» сразу, а не с первой наградой.
                    bonus.refreshDay()
                    startBonusIfAllowed(sceneActive: true)
                    refreshBonusReminder()
                    // Счётчик на иконке — прочитано, раз приложение открыто.
                    MarketingPush.clearBadge()
                    // Разрешение могли сменить в Настройках iOS — сверяем топики.
                    Task { await MarketingPush.sync(push: pushService, city: store.selectedCitySlug) }
                    // Подтверждение почты могло случиться в почтовом клиенте.
                    session.refreshEmailVerification()
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
                    // Выход отписал топики (`willSignOut`) — после входа в той
                    // же сессии подписываем снова, если есть согласие.
                    Task { await MarketingPush.sync(push: pushService, city: store.selectedCitySlug) }
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
                // Кабинет хоста тоже привязан к uid: без переключения он
                // оставался на кэше прошлого аккаунта (гость, вошедший в
                // существующий аккаунт, видел бы чужой или пустой кабинет
                // до перезапуска).
                hostStore.send(.configure(ownerID: new))
                hostStore.send(.sync)
                // Кошелёк нового uid: без этого бонус-движок оставался
                // выключенным до следующего возврата в приложение.
                startBonusIfAllowed()
                refreshBonusReminder()
                // Токен устройства — под новым uid, иначе адресные пуши уходят
                // прошлому аккаунту.
                registerPushToken()
            }
            // Гость ЗАРЕГИСТРИРОВАЛСЯ (uid тот же, isGuest сменился): ни один
            // обработчик выше не срабатывал, и бонусы не копились до перезапуска.
            .onChange(of: session.isGuest) { _, _ in
                startBonusIfAllowed()
                refreshBonusReminder()
                if session.isSignedIn { registerPushToken() }
            }
            // Штампы пришли листенером: если карта заполнилась, сервер выдал
            // купон-награду — подтягиваем купоны сразу, не дожидаясь запуска.
            // Сам момент показывает экран «Начислено» из `SignedInRootView`.
            .onChange(of: loyalty.cards) { _, _ in
                guard let uid = session.user?.id, !session.isGuest else { return }
                Task { await coupons.sync(userID: uid) }
            }
            .onChange(of: bonus.reachedGoalToday) { _, _ in refreshBonusReminder() }
            .task {
                AnalyticsLog.log(.appOpen)
                // Гибкие категории из бэкенда — параллельно с каталогом, не перед
                // ним: раньше лента ждала лишний сетевой круг на холодном старте.
                Task { await CategoryStore.shared.load() }
                hostStore.bind(store)
                // Отписка от push должна успеть ДО закрытия сессии — правила
                // `userTokens` требуют авторизации, поэтому это хук в сторе,
                // а не код в `onChange(isSignedIn)` (тот срабатывает уже после).
                session.willSignOut = { [pushService, store] in
                    // Правка сохранённых за последние 0,8 с иначе не дошла бы
                    // до аккаунта: запись библиотеки отложенная.
                    await store.profile.flushLibrary()
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
                // Рекламные топики FCM — только с согласия (4.5.4): разрешение
                // системы + настройка «Новости и акции заведений».
                await MarketingPush.sync(push: pushService, city: store.selectedCitySlug)
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
        // Напоминание про бонусы принадлежало вышедшему: следующему (или
        // экрану входа) оно ни к чему.
        NotificationManager.cancelReminder()
        // Кэш заведений владельца из памяти (данные остаются в Firestore под
        // ownerID и вернутся при следующем входе).
        hostStore.send(.configure(ownerID: nil))
        resetLocalWallets()
        store.resetForNewUser()
    }

    /// Локальное напоминание про бонусы за активное время — раз в день, днём.
    /// Числа в тексте — из действующего курса (Remote Config), а не литерал:
    /// раньше пуш обещал «+50 бонусов», когда цикл приносил 1. Пока
    /// глобальный кошелёк скрыт (`ReleaseFlags.globalBonusWallet`), пуш вёл бы
    /// в никуда — напоминание снято.
    private func refreshBonusReminder() {
        // Гостю и вышедшему бонусы недоступны, при выключенном начислении за
        // время напоминать не о чем.
        if ReleaseFlags.globalBonusWallet, session.isSignedIn, !session.isGuest, !bonus.timeEarningPaused {
            NotificationManager.refresh(
                reachedGoalToday: bonus.reachedGoalToday,
                title: LS("Бонусы ждут 🎁"),
                body: LF("Загляните в Ayant — за %lld активных минут +%lld бонус", bonus.goalSeconds / 60, bonus.rewardPerGoal),
                now: bonus.now)
        } else {
            NotificationManager.cancelReminder()
        }
    }

    /// Бонус-движок работает только у настоящего аккаунта.
    ///
    /// Гостю бонусы недоступны целиком: экран «Бонусы», игры и обмен наград ему
    /// закрыты, — значит и копиться им не должно. Раньше таймер активности тикал
    /// и гостю: он «зарабатывал» в запись, которая исчезает вместе с выходом.
    /// `sceneActive` — вызов из перехода в `.active` (фаза в этот момент уже
    /// известна). Таймер активного времени запускается только на переднем
    /// плане: включённое удалённо начисление за время иначе тикало бы в фоне.
    private func startBonusIfAllowed(sceneActive: Bool = false) {
        guard session.isSignedIn, !session.isGuest else { bonus.pause(); return }
        // Кошелёк выключен (сборкой или удалённо) — ни таймера, ни кошелька:
        // выключатель должен останавливать начисление, а не только прятать экран.
        guard ReleaseFlags.globalBonusWallet else { bonus.pause(); return }
        // Серверный кошелёк: подключаем (один раз на пользователя; там же
        // единственный за сессию `bonusWalletSync`) и досылаем начисления,
        // которые не ушли из-за сети. В мок-режиме — ничего.
        if let id = session.user?.id {
            bonus.attach(userID: id)
            bonus.retryPending()
        }
        if sceneActive || scenePhase == .active { bonus.start() }
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
        guard AppConfig.useFirebase else { return }
        Messaging.messaging().token { token, _ in
            guard let token else { return }
            pushService.registerToken(token, city: store.selectedCitySlug, uid: session.user?.id)
        }
    }

    /// Синк купонов и карт лояльности из Firestore (used-статус, новые награды, штампы).
    private func syncBackendCoupons() {
        guard let uid = session.user?.id, !session.isGuest else { return }
        points.send(.observe(userID: uid))   // живой поток; опрос больше не нужен
        loyalty.observe(userID: uid)         // и штампы — живьём, ради экрана «Начислено»
        coupons.observe(userID: uid)         // и купоны: погашенный у стойки — сразу «Использован»
    }
}

/// Всплывающее уведомление (подарки, ошибки и т. п.) поверх всего приложения.
struct AppToast: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        ZStack {
            if let msg = store.toastMessage {
                // Тост приходит из `AppStore` (пакет AyantFeatures) русской
                // строкой-ключом; переводит каталог приложения, как и у
                // статусов домена.
                Text(L(msg))
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
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var points: PointsStore
    @EnvironmentObject private var loyalty: LoyaltyStore
    @AppStorage("san.onboarded") private var onboarded = false
    @AppStorage("san.hostMode") private var hostMode = false
    /// Заведение, о котором гость решил оставить отзыв с экрана «Начислено».
    @State private var reviewVenue: Venue?
    @State private var pendingReviewVenueID: String?

    /// Что показать: баллы или штамп. Одновременно приходит редко; баллы первее.
    private struct Earned: Identifiable, Equatable {
        let id: String
        let venueID: String
        let venueName: String
        let content: EarnedContent
    }

    private var earned: Earned? {
        guard !(hostMode && host.state.hasAccount) else { return nil }
        if let e = points.state.pendingEarn {
            return Earned(id: "pts-" + e.id, venueID: e.venueID, venueName: e.venueName,
                          content: .points(delta: e.delta, newBalance: e.newBalance))
        }
        if let e = loyalty.pendingStamp {
            // У заведения может быть несколько карт — называем, на какую лёг штамп.
            let name = e.cardTitle.isEmpty ? e.venueName : "\(e.venueName) · \(e.cardTitle)"
            return Earned(id: "stamp-" + e.id, venueID: e.venueID, venueName: name,
                          content: .stamp(stamps: e.stamps, goal: e.goal,
                                          rewardIssued: e.rewardIssued, reward: e.reward))
        }
        return nil
    }

    private func dismissEarned() {
        if points.state.pendingEarn != nil { points.send(.dismissEarn) } else { loyalty.dismissStamp() }
    }

    /// Отзыв предлагаем, когда заведение в каталоге и отзыва ещё нет.
    private func reviewAction(for venueID: String) -> (() -> Void)? {
        guard !store.isGuest, let venue = store.venue(id: venueID), store.myReview(for: venue) == nil else { return nil }
        return {
            pendingReviewVenueID = venueID
            dismissEarned()
        }
    }

    var body: some View {
        Group {
            if hostMode && host.state.hasAccount {
                HostRootView()
            } else if onboarded {
                RootView()
            } else {
                OnboardingView { onboarded = true }
            }
        }
        // «Начислено» — над всем приложением, на какой бы вкладке гость ни был.
        // Событие живёт в состоянии стора и снимается только кнопкой «Отлично»:
        // перерисовка вкладок, смена экрана, новый снимок баланса его не закрывают.
        .fullScreenCover(item: Binding(get: { earned }, set: { if $0 == nil { dismissEarned() } })) { event in
            PointsEarnedView(content: event.content,
                             venueName: event.venueName,
                             venueSubtitle: store.venue(id: event.venueID)?.district ?? store.selectedCity.name,
                             onDone: { dismissEarned() },
                             onReview: reviewAction(for: event.venueID))
        }
        // Лист отзыва открываем после того, как экран «Начислено» закрылся:
        // два модальных окна одновременно SwiftUI не покажет.
        .onChange(of: earned?.id) { _, new in
            guard new == nil, let id = pendingReviewVenueID else { return }
            pendingReviewVenueID = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                reviewVenue = store.venue(id: id)
            }
        }
        .sheet(item: $reviewVenue) { venue in
            WriteReviewView(venue: venue, existing: nil)
        }
    }
}

// Пользовательская навигация переехала в `GuestShell.swift`:
// Главная · Поиск · [QR] · Кошелёк · Профиль — своя панель вкладок с FAB.

/// Всё, что делают удалённые настройки на корне приложения. Отдельным
/// модификатором: в `SANApp.body` компилятор уже не успевает вывести типы.
private struct RemoteSettingsEffects: ViewModifier {
    @ObservedObject var remote: RemoteSettingsStore
    let bonus: BonusEngine
    /// Кошелёк включили/выключили удалённо: остановить или запустить движок и
    /// пересчитать напоминание — решает корень, у него есть сессия.
    let onBonusWalletFlagChange: () -> Void
    /// Сменился курс времени (цикл, награда) — текст напоминания называет эти
    /// числа, его надо пересобрать.
    let onReminderInputsChange: () -> Void

    func body(content: Content) -> some View {
        content
            // Экран обновления — поверх всего, включая вход: старую сборку
            // закрываем и для тех, кто ещё не вошёл.
            .overlay {
                if remote.updateRequired {
                    AppUpdateRequiredView(updateURL: remote.latest.updateURL)
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.3), value: remote.updateRequired)
            .task {
                apply(remote.latest)
                await remote.refresh()
            }
            // Публикации в консоли — в реальном времени, пока приложение открыто.
            .task { await remote.listen() }
            // Всё применяется сразу: выключатели функций, начисление за игры,
            // дневные лимиты.
            .onChange(of: remote.latest) { _, settings in apply(settings) }
    }

    private func apply(_ settings: RemoteSettings) {
        let walletWas = ReleaseFlags.globalBonusWallet
        let timeWas = bonus.timeEarningPaused
        let goalWas = bonus.goalSeconds
        let rewardWas = bonus.rewardPerGoal
        ReleaseFlags.apply(settings)
        bonus.setBonusPaused(settings.bonusPaused)
        bonus.setBonusDailyCaps(settings.bonusDailyCaps)
        bonus.setGameRates(settings.gameRates)
        bonus.setTimeEarningPaused(settings.timeEarningPaused)
        if ReleaseFlags.globalBonusWallet != walletWas || bonus.timeEarningPaused != timeWas {
            if !ReleaseFlags.globalBonusWallet { bonus.pause() }
            onBonusWalletFlagChange()
        } else if bonus.goalSeconds != goalWas || bonus.rewardPerGoal != rewardWas {
            onReminderInputsChange()
        }
    }
}
