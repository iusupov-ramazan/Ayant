import Foundation

/// Единая точка переключения между mock-реализацией и Firebase.
///
/// Когда будешь готов подключить Firebase:
/// 1. Добавь пакет firebase-ios-sdk (SPM) и GoogleService-Info.plist.
/// 2. Раскомментируй Firebase-ветки ниже и в FirebaseServices.swift.
/// 3. Поставь useFirebase = true.
enum AppConfig {

    /// Переключатель mock ⇄ Firebase. Ставь true, когда настроишь консоль/ключи.
    static let useFirebase = true

    /// Базовый URL Cloud Functions — одно место вместо разбросанных по коду ссылок.
    /// При смене региона/проекта/бэкенда правится только здесь.
    static let functionsBaseURL = "https://us-central1-san-25d32.cloudfunctions.net"
    static func functionURL(_ name: String) -> String { "\(functionsBaseURL)/\(name)" }

    static func makeAuthService() -> AuthService {
        useFirebase ? FirebaseAuthService() : MockAuthService()
    }

    static func makeDataRepository() -> DataRepository {
        useFirebase ? FirebaseDataRepository() : MockDataRepository()
    }

    static func makeHostRepository() -> HostRepository {
        useFirebase ? FirebaseHostRepository() : MockHostRepository()
    }

    static func makeAnalyticsService() -> AnalyticsService {
        useFirebase ? FirebaseAnalyticsService() : MockAnalyticsService()
    }

    static func makePushService() -> PushService {
        useFirebase ? FirebasePushService() : MockPushService()
    }

    static func makeCouponService() -> CouponService {
        useFirebase ? FirebaseCouponService() : MockCouponService()
    }
}
