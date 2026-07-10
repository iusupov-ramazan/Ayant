package kg.ayant.app.push

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kg.ayant.app.MainActivity
import kg.ayant.app.R
import kotlin.random.Random

/**
 * Receives FCM messages and shows a notification. Tapping it deep-links to the
 * venue/deal carried in the data payload (venueID / dealID). Mirrors the iOS
 * AppDelegate push-tap handling.
 */
class AyantMessagingService : FirebaseMessagingService() {

    override fun onNewToken(token: String) {
        // Persist so the backend can target this device (city added on sign-in too).
        val prefs = getSharedPreferences("ayant.store", 0)
        val city = prefs.getString("san.city", "bishkek") ?: "bishkek"
        runCatching {
            FirebaseFirestore.getInstance().collection("userTokens").document(token)
                .set(mapOf("city" to city, "updatedAt" to System.currentTimeMillis()))
        }
    }

    @SuppressLint("MissingPermission")
    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        val title = message.notification?.title ?: data["title"] ?: "Ayant"
        val body = message.notification?.body ?: data["body"] ?: ""

        // Build a deep link from the payload.
        val deepLink: Uri? = when {
            !data["venueID"].isNullOrEmpty() -> Uri.parse("ayant://venue/${data["venueID"]}")
            !data["dealID"].isNullOrEmpty() -> Uri.parse("ayant://deal/${data["dealID"]}")
            else -> null
        }

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            if (deepLink != null) this.data = deepLink
        }
        val pending = PendingIntent.getActivity(
            this, Random.nextInt(), intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(this, Push.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()

        runCatching {
            NotificationManagerCompat.from(this).notify(Random.nextInt(), notification)
        }
    }
}
