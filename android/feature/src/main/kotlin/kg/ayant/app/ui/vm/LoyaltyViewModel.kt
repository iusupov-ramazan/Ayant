package kg.ayant.app.ui.vm

import android.app.Application
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kg.ayant.app.domain.contract.CouponService
import kg.ayant.app.domain.model.LoyaltyCard
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/**
 * Loyalty cards. Stamps are added by the venue scanner (a Cloud Function in prod);
 * the client displays them. Mirrors LoyaltyStore.swift.
 * DI: [backend] приходит параметром конструктора из композиционного корня.
 */
class LoyaltyViewModel @JvmOverloads constructor(
    app: Application,
    private val backend: CouponService,
) : AndroidViewModel(app) {

    private val prefs = app.getSharedPreferences("ayant.loyalty", 0)

    /** Карты одним значением состояния — по тем же причинам, что и купоны. */
    private val _cards = MutableStateFlow<List<LoyaltyCard>>(emptyList())
    val cards: StateFlow<List<LoyaltyCard>> = _cards.asStateFlow()
    var userID: String = ""
        private set

    init { load() }

    override fun onCleared() {
        stopObserving()
        super.onCleared()
    }

    private var observation: Job? = null

    /**
     * Подписка на живой поток карт лояльности.
     *
     * Штампы начисляет сканер заведения (Cloud Function по QR карты). Раньше
     * экран опрашивал бэкенд раз в 4 секунды, пока был открыт; теперь Firestore
     * сам присылает изменение snapshot-листенером — тот же приём, что у баллов
     * ([PointsViewModel]). Листенер снимается вместе с подпиской.
     */
    fun observe(uid: String) {
        if (userID == uid && observation != null) return
        observation?.cancel()
        userID = uid
        if (uid.isEmpty()) return
        observation = viewModelScope.launch {
            backend.loyaltyCards(uid).collect { fetched -> merge(fetched) }
        }
    }

    fun stopObserving() {
        observation?.cancel()
        observation = null
    }

    /** Разовый синк — для мест, где живой поток избыточен (запуск приложения). */
    fun sync(uid: String) {
        userID = uid
        if (uid.isEmpty()) return
        viewModelScope.launch {
            val fetched = runCatching { backend.fetchLoyaltyCards(uid) }.getOrNull() ?: return@launch
            merge(fetched)
        }
    }

    private fun merge(fetched: List<LoyaltyCard>) {
        val map = LinkedHashMap<String, LoyaltyCard>()
        _cards.value.forEach { map[it.venueID] = it }
        fetched.forEach { map[it.venueID] = it }   // backend is source of truth
        put(map.values.sortedByDescending { it.stamps })
    }

    fun card(venueID: String): LoyaltyCard? = _cards.value.firstOrNull { it.venueID == venueID }

    fun cardOrNew(venueID: String, venueName: String, goal: Int, reward: String): LoyaltyCard =
        card(venueID) ?: LoyaltyCard(venueID, venueName, goal = maxOf(goal, 2), reward = reward)

    /** Demo: add a stamp locally (in prod the venue scanner does this server-side). */
    fun addStampDemo(venueID: String, venueName: String, goal: Int, reward: String) {
        val current = _cards.value
        val existing = current.firstOrNull { it.venueID == venueID }
        val next = if (existing != null) {
            var stamps = existing.stamps + 1
            var rounds = existing.completedRounds
            if (stamps >= existing.goal) { stamps = 0; rounds += 1 }
            val updated = existing.copy(stamps = stamps, completedRounds = rounds)
            current.map { if (it.venueID == venueID) updated else it }
        } else {
            current + LoyaltyCard(venueID, venueName, stamps = 1, goal = maxOf(goal, 2), reward = reward)
        }
        put(next)
    }

    /** Очищает карты штампов при смене пользователя (см. `CouponViewModel`). */
    fun resetForNewUser() {
        stopObserving()
        _cards.value = emptyList()
        userID = ""
        prefs.edit().clear().apply()
    }

    /** Публикует новый список и сразу сохраняет его. */
    private fun put(next: List<LoyaltyCard>) {
        _cards.value = next
        save()
    }

    private fun save() {
        val arr = JSONArray()
        _cards.value.forEach { c ->
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
            val loaded = ArrayList<LoyaltyCard>(arr.length())
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                loaded += LoyaltyCard(
                    venueID = o.getString("venueID"), venueName = o.getString("venueName"),
                    stamps = o.optInt("stamps"), completedRounds = o.optInt("completedRounds"),
                    goal = o.optInt("goal", 6), reward = o.optString("reward", "Награда за лояльность"),
                )
            }
            _cards.value = loaded
        }
    }
}
