package kg.ayant.app.core

import android.content.Context
import kg.ayant.app.data.AnalyticsService
import kg.ayant.app.data.AuthService
import kg.ayant.app.data.CouponService
import kg.ayant.app.data.DataRepository
import kg.ayant.app.data.FirebaseAnalyticsService
import kg.ayant.app.data.FirebaseAuthService
import kg.ayant.app.data.FirebaseCouponService
import kg.ayant.app.data.FirebaseDataRepository
import kg.ayant.app.data.MockAnalyticsService
import kg.ayant.app.data.MockAuthService
import kg.ayant.app.data.MockCouponService
import kg.ayant.app.data.MockDataRepository

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
        if (useFirebase) FirebaseAuthService() else MockAuthService()

    fun makeAnalyticsService(): AnalyticsService =
        if (useFirebase) FirebaseAnalyticsService() else MockAnalyticsService()

    fun makeCouponService(): CouponService =
        if (useFirebase) FirebaseCouponService() else MockCouponService()
}
