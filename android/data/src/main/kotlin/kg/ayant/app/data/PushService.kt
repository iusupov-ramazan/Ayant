package kg.ayant.app.data

import kg.ayant.app.domain.contract.PushService

import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.tasks.await
import kg.ayant.app.data.firestore.FS
import java.util.Date

class MockPushService : PushService {
    override fun subscribeDefaults(citySlug: String) {}
    override fun subscribeVenue(venueID: String) {}
    override fun unsubscribeVenue(venueID: String) {}
    override fun registerToken(uid: String?, citySlug: String) {}
    override fun registerKnownToken(token: String, uid: String?, citySlug: String) {}
    override suspend fun unregisterDevice(citySlug: String) {}
    override fun queuePushCampaign(
        headline: String, body: String, citySlug: String,
        venueID: String, dealID: String?, ownerID: String,
    ) {}
}

class FirebasePushService : PushService {

    override fun subscribeDefaults(citySlug: String) {
        FirebaseMessaging.getInstance().subscribeToTopic(TOPIC_ALL)
        FirebaseMessaging.getInstance().subscribeToTopic("$TOPIC_CITY_PREFIX$citySlug")
    }

    override fun subscribeVenue(venueID: String) {
        FirebaseMessaging.getInstance().subscribeToTopic("$TOPIC_VENUE_PREFIX$venueID")
    }

    override fun unsubscribeVenue(venueID: String) {
        FirebaseMessaging.getInstance().unsubscribeFromTopic("$TOPIC_VENUE_PREFIX$venueID")
    }

    override fun registerToken(uid: String?, citySlug: String) {
        FirebaseMessaging.getInstance().token.addOnSuccessListener { token ->
            if (token.isNullOrEmpty()) return@addOnSuccessListener
            registerKnownToken(token, uid, citySlug)
        }
    }

    override fun registerKnownToken(token: String, uid: String?, citySlug: String) {
        if (token.isEmpty()) return
        val data = mutableMapOf<String, Any>(
            FS.UserTokenDoc.CITY to citySlug,
            // Date, а не millis: iOS пишет сюда Timestamp, и сервер сравнивает даты.
            FS.UserTokenDoc.UPDATED_AT to Date(),
        )
        if (uid != null) data[FS.UserTokenDoc.UID] = uid
        runCatching {
            FirebaseFirestore.getInstance()
                .collection(FS.Collection.USER_TOKENS).document(token).set(data)
        }
    }

    /**
     * Порядок важен: документ `userTokens/<token>` удаляем ПОКА пользователь ещё
     * авторизован (правило требует `request.auth != null`), и только потом
     * сбрасываем сам токен.
     */
    override suspend fun unregisterDevice(citySlug: String) {
        val fm = FirebaseMessaging.getInstance()
        runCatching { fm.unsubscribeFromTopic(TOPIC_ALL).await() }
        runCatching { fm.unsubscribeFromTopic("$TOPIC_CITY_PREFIX$citySlug").await() }
        val token = runCatching { fm.token.await() }.getOrNull()
        if (!token.isNullOrEmpty()) {
            runCatching {
                FirebaseFirestore.getInstance()
                    .collection(FS.Collection.USER_TOKENS).document(token).delete().await()
            }
        }
        runCatching { fm.deleteToken().await() }
    }

    override fun queuePushCampaign(
        headline: String, body: String, citySlug: String,
        venueID: String, dealID: String?, ownerID: String,
    ) {
        runCatching {
            FirebaseFirestore.getInstance().collection(FS.Collection.PUSH_CAMPAIGNS).add(
                mapOf(
                    FS.PushCampaignDoc.HEADLINE to headline,
                    FS.PushCampaignDoc.BODY to body,
                    FS.PushCampaignDoc.CITY to citySlug,
                    FS.PushCampaignDoc.VENUE_ID to venueID,
                    FS.PushCampaignDoc.DEAL_ID to (dealID ?: ""),
                    FS.PushCampaignDoc.OWNER_ID to ownerID,
                    // Date, а не millis: iOS пишет Timestamp, и админка форматирует дату.
                    FS.PushCampaignDoc.CREATED_AT to Date(),
                    FS.PushCampaignDoc.STATUS to FS.PushCampaignDoc.STATUS_PENDING,
                    FS.PushCampaignDoc.DELIVERED to false,
                )
            )
        }
    }

    private companion object {
        const val TOPIC_ALL = "all_users"
        const val TOPIC_CITY_PREFIX = "city_"
        const val TOPIC_VENUE_PREFIX = "venue_"
    }
}
