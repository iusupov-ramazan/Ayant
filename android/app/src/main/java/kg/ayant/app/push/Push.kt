package kg.ayant.app.push

import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.messaging.FirebaseMessaging
import kg.ayant.app.core.AppConfig

/**
 * Push topics + token registration. Mirrors PushService.swift.
 * All calls are no-ops when Firebase isn't configured.
 */
object Push {
    const val CHANNEL_ID = "ayant_deals"

    /** Subscribe to city-wide broadcast topics (ad campaigns). */
    fun subscribeDefaults(citySlug: String) {
        if (!AppConfig.useFirebase) return
        FirebaseMessaging.getInstance().subscribeToTopic("all_users")
        FirebaseMessaging.getInstance().subscribeToTopic("city_$citySlug")
    }

    fun subscribeVenue(venueID: String) {
        if (!AppConfig.useFirebase) return
        FirebaseMessaging.getInstance().subscribeToTopic("venue_$venueID")
    }

    fun unsubscribeVenue(venueID: String) {
        if (!AppConfig.useFirebase) return
        FirebaseMessaging.getInstance().unsubscribeFromTopic("venue_$venueID")
    }

    /** Write this device's FCM token to userTokens/{token} for targeted delivery. */
    fun registerToken(uid: String?, citySlug: String) {
        if (!AppConfig.useFirebase) return
        FirebaseMessaging.getInstance().token.addOnSuccessListener { token ->
            if (token.isNullOrEmpty()) return@addOnSuccessListener
            val data = mutableMapOf<String, Any>("city" to citySlug, "updatedAt" to System.currentTimeMillis())
            if (uid != null) data["uid"] = uid
            FirebaseFirestore.getInstance().collection("userTokens").document(token).set(data)
        }
    }
}
