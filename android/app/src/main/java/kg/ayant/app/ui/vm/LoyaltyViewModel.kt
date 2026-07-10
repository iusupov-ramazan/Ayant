package kg.ayant.app.ui.vm

import android.app.Application
import androidx.compose.runtime.mutableStateListOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kg.ayant.app.core.AppConfig
import kg.ayant.app.data.CouponService
import kg.ayant.app.data.model.LoyaltyCard
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/**
 * Loyalty cards. Stamps are added by the venue scanner (a Cloud Function in prod);
 * the client displays them. Mirrors LoyaltyStore.swift.
 * DI: [backend] is an injectable constructor param (`@JvmOverloads` keeps the
 * `(Application)` constructor `viewModel()` relies on).
 */
class LoyaltyViewModel @JvmOverloads constructor(
    app: Application,
    private val backend: CouponService = AppConfig.makeCouponService(),
) : AndroidViewModel(app) {

    private val prefs = app.getSharedPreferences("ayant.loyalty", 0)
    val cards = mutableStateListOf<LoyaltyCard>()
    var userID: String = ""
        private set

    init { load() }

    /** Merge loyalty cards from Firestore (stamps written by the scanner Cloud Function). */
    fun sync(uid: String) {
        userID = uid
        if (uid.isEmpty()) return
        viewModelScope.launch {
            val fetched = runCatching { backend.fetchLoyaltyCards(uid) }.getOrNull() ?: return@launch
            val map = LinkedHashMap<String, LoyaltyCard>()
            cards.forEach { map[it.venueID] = it }
            fetched.forEach { map[it.venueID] = it }   // backend is source of truth
            cards.clear()
            cards.addAll(map.values.sortedByDescending { it.stamps })
            save()
        }
    }

    fun card(venueID: String): LoyaltyCard? = cards.firstOrNull { it.venueID == venueID }

    fun cardOrNew(venueID: String, venueName: String, goal: Int, reward: String): LoyaltyCard =
        card(venueID) ?: LoyaltyCard(venueID, venueName, goal = maxOf(goal, 2), reward = reward)

    /** Demo: add a stamp locally (in prod the venue scanner does this server-side). */
    fun addStampDemo(venueID: String, venueName: String, goal: Int, reward: String) {
        val i = cards.indexOfFirst { it.venueID == venueID }
        if (i >= 0) {
            val c = cards[i]
            var stamps = c.stamps + 1
            var rounds = c.completedRounds
            if (stamps >= c.goal) { stamps = 0; rounds += 1 }
            cards[i] = c.copy(stamps = stamps, completedRounds = rounds)
        } else {
            cards.add(LoyaltyCard(venueID, venueName, stamps = 1, goal = maxOf(goal, 2), reward = reward))
        }
        save()
    }

    private fun save() {
        val arr = JSONArray()
        cards.forEach { c ->
            arr.put(JSONObject().apply {
                put("venueID", c.venueID); put("venueName", c.venueName)
                put("stamps", c.stamps); put("completedRounds", c.completedRounds)
                put("goal", c.goal); put("reward", c.reward)
            })
        }
        prefs.edit().putString("cards", arr.toString()).apply()
    }

    private fun load() {
        val raw = prefs.getString("cards", null) ?: return
        runCatching {
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                cards.add(
                    LoyaltyCard(
                        venueID = o.getString("venueID"), venueName = o.getString("venueName"),
                        stamps = o.optInt("stamps"), completedRounds = o.optInt("completedRounds"),
                        goal = o.optInt("goal", 6), reward = o.optString("reward", "Награда за лояльность"),
                    )
                )
            }
        }
    }
}
