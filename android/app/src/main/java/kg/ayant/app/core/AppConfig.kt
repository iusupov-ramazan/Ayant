package kg.ayant.app.core

import android.content.Context
import kg.ayant.app.data.DataRepository
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
        // if (useFirebase) FirebaseDataRepository() else MockDataRepository()
        MockDataRepository()
}
