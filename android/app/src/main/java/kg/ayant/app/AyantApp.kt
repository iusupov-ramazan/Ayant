package kg.ayant.app

import android.app.Application
import kg.ayant.app.core.AppConfig

/**
 * Application entry point. Mirrors SANApp.init() on iOS.
 * Firebase is initialised lazily by the Firebase SDK's content provider when
 * google-services.json is present; when AppConfig.useFirebase is false the app
 * runs entirely on MockData.
 */
class AyantApp : Application() {
    override fun onCreate() {
        super.onCreate()
        AppConfig.applicationContext = applicationContext
    }
}
