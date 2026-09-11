import Foundation
import AyantDomain
import AyantData
import AyantFeatures

/// Композиционный корень: единственное место, где сторы встречаются со своими
/// зависимостями.
///
/// Раньше каждый стор подставлял `AppConfig.make*()` дефолтом параметра —
/// удобно, но это обратная зависимость: слой фич знал про сборку приложения и
/// не мог жить отдельным модулем. Теперь `AyantFeatures` принимает готовые
/// контракты домена, а какие за ними реализации, решают эти фабрики.
///
/// Зеркалит `core/AyantViewModels.kt` на Android.
@MainActor
enum AyantStores {

    /// Локальные настройки — один экземпляр на приложение: их читают и `AppStore`,
    /// и профиль, и разъезжаться им нельзя.
    static let preferences: LocalPreferencesStore = UserDefaultsPreferencesStore()

    /// Подключает реальную отправку продуктовых событий. Зовётся один раз на
    /// старте: до этого `AnalyticsLog` пишет в никуда, а не тянет Firebase.
    static func installAnalytics() {
        AnalyticsLog.backend = AppConfig.makeProductAnalytics()
    }

    static func app() -> AppStore {
        AppStore(
            repository: AppConfig.makeDataRepository(),
            analytics: AppConfig.makeAnalyticsService(),
            push: AppConfig.makePushService(),
            rankingLog: AppConfig.makeRankingEventService(),
            prefs: preferences
        )
    }

    static func session() -> SessionStore { SessionStore(service: AppConfig.makeAuthService()) }
    static func coupons() -> CouponStore { CouponStore(backend: AppConfig.makeCouponService()) }
    static func loyalty() -> LoyaltyStore { LoyaltyStore(backend: AppConfig.makeCouponService()) }
    static func points() -> PointsStore { PointsStore(repository: AppConfig.makePointsRepository()) }
    static func host() -> HostStore { HostStore(repo: AppConfig.makeHostRepository()) }

    /// Без внешних зависимостей: состояние берут из хранилища устройства.
    static func bonus() -> BonusEngine { BonusEngine() }
    static func theme() -> ThemeStore { ThemeStore() }
}
