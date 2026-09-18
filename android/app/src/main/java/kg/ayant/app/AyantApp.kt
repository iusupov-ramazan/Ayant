package kg.ayant.app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import com.google.firebase.FirebaseApp
import kg.ayant.app.core.AppConfig
import kg.ayant.app.push.Push
import kg.ayant.app.core.AppLanguage

/**
 * Application entry point. Mirrors SANApp.init() on iOS.
 *
 * Firebase auto-initialises (via its content provider) only when
 * google-services.json is present. We detect that here and switch the app to the
 * live backend automatically — no manual flag to flip. Without the file the app
 * runs entirely on MockData.
 */
class AyantApp : Application() {
    override fun onCreate() {
        super.onCreate()
        AppConfig.applicationContext = applicationContext
        // If google-services.json was bundled, FirebaseApp is already initialised.
        AppConfig.useFirebase = FirebaseApp.getApps(this).isNotEmpty()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(NotificationManager::class.java)
            mgr?.createNotificationChannel(
                // Канал создаётся на языке ПРИЛОЖЕНИЯ: Application живёт в системной локали.
                NotificationChannel(Push.CHANNEL_ID, AppLanguage.context.getString(R.string.notif_channel_name), NotificationManager.IMPORTANCE_DEFAULT)
                    .apply { description = AppLanguage.context.getString(R.string.notif_channel_desc) }
            )
        }
        // Periodic bonus-goal reminder (skips days the goal was already reached).
        kg.ayant.app.push.BonusReminderWorker.schedule(this)
    }
}
