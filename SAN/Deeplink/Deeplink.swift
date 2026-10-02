import SwiftUI
import UIKit
import UserNotifications
import FirebaseMessaging
import AyantDomain
import AyantData
import AyantFeatures

// MARK: - Маршрут диплинка

enum DeepRoute: Identifiable, Equatable {
    case venue(String)
    case deal(String)

    var id: String {
        switch self {
        case .venue(let v): return "v_\(v)"
        case .deal(let d): return "d_\(d)"
        }
    }
}

// MARK: - Роутер диплинков (singleton — доступен и из AppDelegate)

@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()
    @Published var route: DeepRoute?

    private init() {}

    static let domain = "ayant.kg"

    /// Парсит san://venue/<id> (кастомная схема) и https://<domain>/venue/<id> (Universal Link).
    func handle(url: URL) {
        if url.scheme == "san" {
            let id = url.lastPathComponent
            switch url.host {
            case "venue": route = .venue(id)
            case "deal": route = .deal(id)
            case "ref": Self.setPendingReferrer(id)
            case "gift": Self.setPendingGift(id)
            default: break
            }
        } else if url.scheme == "https" {
            let comps = url.pathComponents.filter { $0 != "/" }
            guard comps.count >= 2 else { return }
            switch comps[0] {
            case "venue": route = .venue(comps[1])
            case "deal": route = .deal(comps[1])
            case "ref": Self.setPendingReferrer(comps[1])
            case "gift": Self.setPendingGift(comps[1])
            default: break
            }
        }
    }

    func openVenue(_ id: String) { if !id.isEmpty { route = .venue(id) } }
    func openDeal(_ id: String) { if !id.isEmpty { route = .deal(id) } }

    // Ссылки для шаринга — Universal Links (открываются в приложении при установленном app).
    // Адреса и ключи живут в домене (`DeepLinks`) — их зовут и сторы; здесь
    // остаются привычные точки вызова.
    static func venueURL(_ id: String) -> URL { DeepLinks.venueURL(id) }
    static func dealURL(_ id: String) -> URL { DeepLinks.dealURL(id) }
    static func referralURL(_ code: String) -> URL { DeepLinks.referralURL(code) }
    static func giftURL(_ code: String) -> URL { DeepLinks.giftURL(code) }

    // MARK: Рефералка
    static let pendingReferrerKey = DeepLinks.pendingReferrerKey

    static let pendingGiftKey = DeepLinks.pendingGiftKey
    /// Запоминаем код подарка из ссылки. Забираем купон после входа.
    static func setPendingGift(_ code: String) {
        guard !code.isEmpty else { return }
        UserDefaults.standard.set(code, forKey: pendingGiftKey)
    }

    /// Запоминаем, кто пригласил (если ещё не записано). Привязка и бонус — после входа.
    static func setPendingReferrer(_ code: String) {
        guard !code.isEmpty else { return }
        let d = UserDefaults.standard
        if (d.string(forKey: pendingReferrerKey) ?? "").isEmpty {
            d.set(code, forKey: pendingReferrerKey)
            AnalyticsLog.log(.referralJoin, ["stage": "link"])   // без кода пригласившего — это его идентификатор
        }
    }
}

// MARK: - Рекламные push: только с согласия (App Review 4.5.4)

/// Топики `all_users`/`city_*` — это рассылки заведений, то есть маркетинг.
/// Раньше на них подписывалось каждое устройство при запуске, даже без
/// разрешения на уведомления. Теперь подписка — только когда (1) система
/// разрешила уведомления и (2) включена настройка «Новости и акции заведений»
/// (Профиль). По умолчанию настройка включена: согласие человек дал в
/// системном диалоге онбординга. Адресные пуши по токену это не трогает.
enum MarketingPush {
    /// Ключ load-bearing: хранит выбор пользователя между запусками.
    static let defaultsKey = "san.push.marketing"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    static func topics(city: String) -> [String] { ["all_users", "city_\(city)"] }

    /// Город — тот же ключ, что у `AppStore` (`san.city`).
    static var currentCity: String {
        UserDefaults.standard.string(forKey: "san.city") ?? City.bishkek.id
    }

    /// Разрешены ли уведомления системой.
    static func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    /// Приводит подписку на топики в соответствие с разрешением и настройкой.
    /// Идемпотентно — зовётся на старте, при возврате в приложение, после
    /// входа и при переключении настройки.
    static func sync(push: PushService = AppConfig.makePushService(),
                     city: String = currentCity) async {
        let subscribe = isEnabled ? await isAuthorized() : false
        for topic in topics(city: city) {
            if subscribe { push.subscribe(topic: topic) } else { push.unsubscribe(topic: topic) }
        }
    }

    /// Снимает счётчик на иконке, когда приложение открыто.
    static func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
}

// MARK: - AppDelegate: обработка тапа по push-уведомлению

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    private let push = AppConfig.makePushService()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if AppConfig.useFirebase { Messaging.messaging().delegate = self }
        return true
    }

    // APNs-токен устройства → ОБЯЗАТЕЛЬНО передаём в FCM, иначе токен FCM не
    // получить (ошибка 505 "No APNS token specified before fetching FCM Token").
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        if AppConfig.useFirebase { Messaging.messaging().apnsToken = deviceToken }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ APNs registration failed: \(error.localizedDescription)")
    }

    // FCM-токен устройства → пишем в Firestore (userTokens) для адресной рассылки.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        let city = UserDefaults.standard.string(forKey: "san.city") ?? City.bishkek.id
        push.registerToken(token, city: city, uid: AppConfig.makeAuthService().currentUser()?.id)
    }

    // Показывать уведомление, когда приложение на переднем плане.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // Тап по уведомлению → открываем предложение (если буст деала) или заведение.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let dealID = info[FS.PushPayload.dealID] as? String ?? ""
        let venueID = info[FS.PushPayload.venueID] as? String ?? ""
        Task { @MainActor in
            if !dealID.isEmpty { DeepLinkRouter.shared.openDeal(dealID) }
            else if !venueID.isEmpty { DeepLinkRouter.shared.openVenue(venueID) }
        }
        completionHandler()
    }
}

// MARK: - Экран назначения диплинка (модально)

struct DeepLinkDestination: View {
    let route: DeepRoute
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch route {
        case .venue(let id):
            NavigationStack {
                Group {
                    if let v = store.venue(id: id) {
                        VenueDetailView(venue: v)
                    } else {
                        ContentUnavailableView("Заведение не найдено", systemImage: "mappin.slash")
                    }
                }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Закрыть") { dismiss() } } }
            }
        case .deal(let id):
            if let d = store.deals.first(where: { $0.id == id }) {
                DealDetailView(deal: d)   // у него своя NavigationStack + «Готово»
            } else {
                NavigationStack {
                    ContentUnavailableView("Предложение не найдено", systemImage: "tag.slash")
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Закрыть") { dismiss() } } }
                }
            }
        }
    }
}
