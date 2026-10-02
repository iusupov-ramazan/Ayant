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

    /// Переключатель mock ⇄ Firebase. В витринном режиме (`-screenshots`,
    /// см. `ScreenshotFixtures`) приложение целиком живёт на выдуманном
    /// каталоге и Firebase не инициализирует.
    static let useFirebase = ScreenshotFixtures.mode == nil

    /// Базовый URL Cloud Functions — одно место вместо разбросанных по коду ссылок.
    /// При смене региона/проекта/бэкенда правится только здесь.
    /// Адрес живёт в слое данных (`AyantBackend`); здесь — привычная точка вызова.
    static let functionsBaseURL = AyantBackend.functionsBaseURL
    static func functionURL(_ name: String) -> String { AyantBackend.functionURL(name) }

    static func makeAuthService() -> AuthService {
        if let shots = ScreenshotFixtures.mode { return MockAuthService(presetUser: shots.user) }
        return useFirebase ? FirebaseAuthService() : MockAuthService()
    }

    static func makeDataRepository() -> DataRepository {
        if let shots = ScreenshotFixtures.mode {
            return MockDataRepository(venues: shots.venues, deals: shots.deals, reviews: shots.reviews)
        }
        return useFirebase ? FirebaseDataRepository() : MockDataRepository()
    }

    static func makeHostRepository() -> HostRepository {
        useFirebase ? FirebaseHostRepository() : MockHostRepository()
    }

    /// Instagram заведения: живой сервис ходит в наши Cloud Functions, мок
    /// отдаёт выдуманные посты — так экран импорта работает и без аккаунта Meta.
    static func makeInstagramService() -> InstagramService {
        useFirebase ? FirebaseInstagramService(auth: makeAuthService()) : MockInstagramService()
    }

    /// Разбор файла меню — на устройстве в любом режиме: ни сети, ни
    /// бэкенда ему не нужно, так что мок не нужен тоже.
    static func makeMenuParsingService() -> MenuParsingService {
        OnDeviceMenuParsingService()
    }

    /// Показывать в «Аналитике» сгенерированные ряды вместо реальных.
    ///
    /// Выключено к релизу: хост должен видеть свои настоящие цифры, даже если
    /// первые недели они близки к нулю (пустое состояние экрана это объясняет).
    /// Оставлено как отладочный режим для скриншотов и демо — включать только
    /// в локальной сборке, в продакшене это подделка статистики.
    static let useDemoAnalytics = false

    static func makeAnalyticsService() -> AnalyticsService {
        let real: AnalyticsService = useFirebase ? FirebaseAnalyticsService() : MockAnalyticsService()
        return useDemoAnalytics ? DemoAnalyticsService(wrapping: real) : real
    }

    static func makeRankingEventService() -> RankingEventService {
        useFirebase ? FirebaseRankingEventService() : MockRankingEventService()
    }

    /// Удалённые выключатели и минимальная версия. В отладке ходим за
    /// значениями без задержки, чтобы правку в консоли было видно сразу.
    static func makeRemoteConfigService() -> RemoteConfigService {
        guard useFirebase else { return MockRemoteConfigService() }
        #if DEBUG
        return FirebaseRemoteConfigService(minimumFetchInterval: 0)
        #else
        return FirebaseRemoteConfigService(minimumFetchInterval: 3600)
        #endif
    }

    /// Версия сборки для сравнения с `ios_min_version`.
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// Куда вести «Обновить», если `ios_update_url` в Remote Config пуст:
    /// поиск в App Store. Поставьте ссылку на страницу приложения
    /// (`https://apps.apple.com/app/id…`) в консоли, когда появится id.
    static let appStoreFallbackURL =
        "itms-apps://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?media=software&term=Ayant"

    static func makePushService() -> PushService {
        useFirebase ? FirebasePushService() : MockPushService()
    }

    /// Серверный кошелёк бонусов. В мок-режиме — `nil`: `BonusEngine` и
    /// `CouponStore` тогда считают бонусы на устройстве, как раньше, и
    /// приложение целиком работает без сети.
    static func makeBonusWallet() -> BonusWalletService? {
        useFirebase ? FirebaseBonusWalletService(auth: makeAuthService()) : nil
    }

    static func makeCouponService() -> CouponService {
        if let shots = ScreenshotFixtures.mode {
            return MockCouponService(coupons: shots.coupons, loyaltyCards: shots.loyaltyCards)
        }
        return useFirebase ? FirebaseCouponService() : MockCouponService()
    }

    /// Продуктовая аналитика (DAU/воронки). Вне Firebase — печать в консоль.
    static func makeProductAnalytics() -> ProductAnalytics {
        useFirebase ? FirebaseProductAnalytics() : ConsoleProductAnalytics()
    }

    /// Живой источник карт баллов (snapshot-листенер вместо опроса) + списание.
    static func makePointsRepository() -> PointsRepository {
        if let shots = ScreenshotFixtures.mode {
            return MockPointsRepository(cards: shots.pointsCards,
                                        laterEarn: shots.earn ? (delay: 2.5, points: 50) : nil)
        }
        return useFirebase
            ? FirebasePointsRepository(backend: makeCouponService(), auth: makeAuthService())
            : MockPointsRepository(cards: MockData.pointsCards)
    }
}
