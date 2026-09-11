import Foundation
import AyantDomain
import AyantData

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
    /// Адрес живёт в слое данных (`AyantBackend`); здесь — привычная точка вызова.
    static let functionsBaseURL = AyantBackend.functionsBaseURL
    static func functionURL(_ name: String) -> String { AyantBackend.functionURL(name) }

    static func makeAuthService() -> AuthService {
        useFirebase ? FirebaseAuthService() : MockAuthService()
    }

    static func makeDataRepository() -> DataRepository {
        useFirebase ? FirebaseDataRepository() : MockDataRepository()
    }

    static func makeHostRepository() -> HostRepository {
        useFirebase ? FirebaseHostRepository() : MockHostRepository()
    }

    /// ВРЕМЕННО: показывать в «Аналитике» сгенерированные ряды вместо реальных.
    ///
    /// Пока у заведений нет трафика, настоящие счётчики — нули, и экран
    /// выглядит сломанным. События при этом продолжают писаться в настоящий
    /// сервис, поэтому выключение флага вернёт накопленные данные, а не пустоту.
    static let useDemoAnalytics = true

    static func makeAnalyticsService() -> AnalyticsService {
        let real: AnalyticsService = useFirebase ? FirebaseAnalyticsService() : MockAnalyticsService()
        return useDemoAnalytics ? DemoAnalyticsService(wrapping: real) : real
    }

    static func makeRankingEventService() -> RankingEventService {
        useFirebase ? FirebaseRankingEventService() : MockRankingEventService()
    }

    static func makePushService() -> PushService {
        useFirebase ? FirebasePushService() : MockPushService()
    }

    static func makeCouponService() -> CouponService {
        useFirebase ? FirebaseCouponService() : MockCouponService()
    }

    /// Продуктовая аналитика (DAU/воронки). Вне Firebase — печать в консоль.
    static func makeProductAnalytics() -> ProductAnalytics {
        useFirebase ? FirebaseProductAnalytics() : ConsoleProductAnalytics()
    }

    /// Живой источник карт баллов (snapshot-листенер вместо опроса) + списание.
    static func makePointsRepository() -> PointsRepository {
        useFirebase
            ? FirebasePointsRepository(backend: makeCouponService(), auth: makeAuthService())
            : MockPointsRepository(cards: MockData.pointsCards)
    }
}
