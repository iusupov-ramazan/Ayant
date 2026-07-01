import SwiftUI
import UIKit
import UserNotifications
import FirebaseMessaging
import FirebaseAuth

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

    /// Домен для Universal Links — бесплатный домен Firebase Hosting
    /// (AASA размещён в web/.well-known/apple-app-site-association).
    static let domain = "san-25d32.web.app"

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
    static func venueURL(_ id: String) -> URL { URL(string: "https://\(domain)/venue/\(id)")! }
    static func dealURL(_ id: String) -> URL { URL(string: "https://\(domain)/deal/\(id)")! }
    static func referralURL(_ code: String) -> URL { URL(string: "https://\(domain)/ref/\(code)")! }
    static func giftURL(_ code: String) -> URL { URL(string: "https://\(domain)/gift/\(code)")! }

    // MARK: Рефералка
    static let pendingReferrerKey = "san.referrer.pending"

    static let pendingGiftKey = "san.gift.pending"
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
            AnalyticsLog.log(.referralJoin, ["referrer_id": code])
        }
    }
}

// MARK: - AppDelegate: обработка тапа по push-уведомлению

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    private let push = AppConfig.makePushService()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        return true
    }

    // APNs-токен устройства → ОБЯЗАТЕЛЬНО передаём в FCM, иначе токен FCM не
    // получить (ошибка 505 "No APNS token specified before fetching FCM Token").
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ APNs registration failed: \(error.localizedDescription)")
    }

    // FCM-токен устройства → пишем в Firestore (userTokens) для адресной рассылки.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        let city = UserDefaults.standard.string(forKey: "san.city") ?? City.bishkek.id
        push.registerToken(token, city: city, uid: Auth.auth().currentUser?.uid)
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
        let dealID = info["dealID"] as? String ?? ""
        let venueID = info["venueID"] as? String ?? ""
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
