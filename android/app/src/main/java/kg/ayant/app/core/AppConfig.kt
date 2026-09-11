package kg.ayant.app.core
import kg.ayant.app.data.FirebasePointsRepository
import kg.ayant.app.data.MockPointsRepository
import kg.ayant.app.data.FirebaseFileUploadService
import kg.ayant.app.data.MockFileUploadService
import kg.ayant.app.data.FirebasePushService
import kg.ayant.app.data.MockPushService
import kg.ayant.app.data.MockDataRepository

import android.content.Context
import kg.ayant.app.domain.contract.AnalyticsService
import kg.ayant.app.domain.contract.AuthService
import kg.ayant.app.domain.contract.CouponService
import kg.ayant.app.domain.DataRepository
import kg.ayant.app.data.DemoAnalyticsService
import kg.ayant.app.data.FirebaseAnalyticsService
import kg.ayant.app.data.FirebaseAuthService
import kg.ayant.app.data.FirebaseCouponService
import kg.ayant.app.data.FirebaseDataRepository
import kg.ayant.app.data.FirebaseRankingEventService
import kg.ayant.app.data.MockAnalyticsService
import kg.ayant.app.data.MockAuthService
import kg.ayant.app.data.MockCouponService
import kg.ayant.app.data.MockRankingEventService
import kg.ayant.app.domain.contract.RankingEventService

/**
 * Single switch between Mock and Firebase, mirroring AppConfig.swift.
 *
 * To go live on the shared Firebase project (san-25d32):
 *  1. In the Firebase console, add an Android app with package kg.ayant.app.
 *  2. Download google-services.json into android/app/.
 *  3. Flip useFirebase to true and uncomment the Firebase branch below +
 *     the deps in app/build.gradle.kts (already present).
 */
object AppConfig {
    var useFirebase = false

    lateinit var applicationContext: Context

    fun makeDataRepository(): DataRepository =
        if (useFirebase) FirebaseDataRepository() else MockDataRepository()

    fun makeAuthService(): AuthService =
        if (useFirebase) FirebaseAuthService(applicationContext) else MockAuthService()

    /**
     * ВРЕМЕННО: показывать в «Аналитике» сгенерированные ряды вместо реальных.
     *
     * События при этом продолжают писаться в настоящий сервис, поэтому
     * выключение флага вернёт накопленные данные, а не пустоту.
     */
    const val useDemoAnalytics = true

    fun makeAnalyticsService(): AnalyticsService {
        val real = if (useFirebase) FirebaseAnalyticsService() else MockAnalyticsService()
        return if (useDemoAnalytics) DemoAnalyticsService(real) else real
    }

    fun makeRankingEventService(): RankingEventService =
        if (useFirebase) FirebaseRankingEventService() else MockRankingEventService()

    /** Push-темы и регистрация токена. Вне Firebase — заглушка. */
    fun makePushService(): kg.ayant.app.domain.contract.PushService =
        if (useFirebase) kg.ayant.app.data.FirebasePushService()
        else kg.ayant.app.data.MockPushService()

    /** Загрузка файлов (фото заведений, PDF-меню). Вне Firebase — заглушка. */
    fun makeFileUploadService(): kg.ayant.app.domain.contract.FileUploadService =
        if (useFirebase) kg.ayant.app.data.FirebaseFileUploadService()
        else kg.ayant.app.data.MockFileUploadService()

    /** Живой источник карт баллов (snapshot-листенер вместо опроса) + списание. */
    fun makePointsRepository(): kg.ayant.app.domain.PointsRepository =
        if (useFirebase) kg.ayant.app.data.FirebasePointsRepository(makeCouponService(), makeAuthService())
        else kg.ayant.app.data.MockPointsRepository(kg.ayant.app.domain.MockData.pointsCards)

    fun makeCouponService(): CouponService =
        if (useFirebase) FirebaseCouponService() else MockCouponService()
}
