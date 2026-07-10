package kg.ayant.app.push

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import kg.ayant.app.MainActivity
import kg.ayant.app.R
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

/**
 * Periodic re-engagement nudge: if the user hasn't earned their bonus goal today,
 * remind them to open the app. Mirrors NotificationManager's goal reminders.
 */
class BonusReminderWorker(ctx: Context, params: WorkerParameters) : Worker(ctx, params) {

    @SuppressLint("MissingPermission")
    override fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences("ayant.bonus", 0)
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val reachedToday = prefs.getString("counterDate", "") == today && prefs.getInt("awardsToday", 0) > 0
        if (reachedToday) return Result.success()

        if (ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED && android.os.Build.VERSION.SDK_INT >= 33
        ) return Result.success()

        val intent = Intent(applicationContext, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending = android.app.PendingIntent.getActivity(
            applicationContext, 0, intent,
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE,
        )
        val n = NotificationCompat.Builder(applicationContext, Push.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle("Не забудь про бонусы 🎁")
            .setContentText("Загляни в Ayant — новые акции и бонусы ждут.")
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        runCatching { NotificationManagerCompat.from(applicationContext).notify(4321, n) }
        return Result.success()
    }

    companion object {
        fun schedule(context: Context) {
            val request = PeriodicWorkRequestBuilder<BonusReminderWorker>(6, TimeUnit.HOURS).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                "ayant_bonus_reminder",
                androidx.work.ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
        }
    }
}
