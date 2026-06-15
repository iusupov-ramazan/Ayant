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

    /// Домен для Universal Links (замени на свой; нужен размещённый AASA-файл).
    static let domain = "san.kg"

    /// Парсит san://venue/<id> (кастомная схема) и https://<domain>/venue/<id> (Universal Link).
    func handle(url: URL) {
        if url.scheme == "san" {
            let id = url.lastPathComponent
            switch url.host {
            case "venue": route = .venue(id)
            case "deal": route = .deal(id)
            default: break
            }
        } else if url.scheme == "https" {
            let comps = url.pathComponents.filter { $0 != "/" }
            guard comps.count >= 2 else { return }
            switch comps[0] {
            case "venue": route = .venue(comps[1])
            case "deal": route = .deal(comps[1])
            default: break
            }
        }
    }

    func openVenue(_ id: String) { if !id.isEmpty { route = .venue(id) } }
    func openDeal(_ id: String) { if !id.isEmpty { route = .deal(id) } }

    // Ссылки для шаринга — Universal Links (открываются в приложении при установленном app).
    static func venueURL(_ id: String) -> URL { URL(string: "https://\(domain)/venue/\(id)")! }
    static func dealURL(_ id: String) -> URL { URL(string: "https://\(domain)/deal/\(id)")! }
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

    // Тап по уведомлению → открываем целевое заведение из payload (venueID).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let vid = info["venueID"] as? String, !vid.isEmpty {
            Task { @MainActor in DeepLinkRouter.shared.openVenue(vid) }
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
