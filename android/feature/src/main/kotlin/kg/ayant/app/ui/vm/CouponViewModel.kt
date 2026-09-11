package kg.ayant.app.ui.vm

import kg.ayant.app.domain.SystemClock
import kg.ayant.app.domain.Clock
import android.app.Application
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kg.ayant.app.domain.CodeGen
import kg.ayant.app.domain.contract.CouponService
import kg.ayant.app.domain.model.Coupon
import kg.ayant.app.domain.model.Reward
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.util.Date
import java.util.UUID

/**
 * Coupon wallet. Mirrors CouponStore.swift (local persistence via JSON in prefs).
 * DI: [backend] приходит параметром конструктора из композиционного корня.
 */
class CouponViewModel @JvmOverloads constructor(
    app: Application,
    private val backend: CouponService,
    /** «Сейчас» — из [clock]: иначе время-зависимую логику не проверить тестом. */
    private val clock: Clock = SystemClock,
) : AndroidViewModel(app) {

    private val prefs = app.getSharedPreferences("ayant.coupons", 0)

    /**
     * Купоны одним значением состояния (`StateFlow`, а не `mutableStateListOf`):
     * кошелёк живёт в ViewModel и не обязан знать про Compose — иначе фича-слой
     * тянул бы за собой UI-фреймворк (§2/§4 спеки).
     */
    private val _coupons = MutableStateFlow<List<Coupon>>(emptyList())
    val coupons: StateFlow<List<Coupon>> = _coupons.asStateFlow()
    var userID: String = ""
        private set

    val activeCount: Int get() = _coupons.value.count { !it.used }

    init { load() }

    /** Merge backend coupons (used status, loyalty rewards) by code. Backend wins. */
    fun sync(uid: String) {
        userID = uid
        if (uid.isEmpty()) return
        viewModelScope.launch {
            val fetched = runCatching { backend.fetchCoupons(uid) }.getOrNull() ?: return@launch
            val map = LinkedHashMap<String, Coupon>()
            _coupons.value.forEach { map[it.code] = it }
            fetched.forEach { map[it.code] = it }
            put(map.values.sortedByDescending { it.createdAt })
        }
    }

    /** Spend bonuses and issue a coupon. Returns coupon or null (not enough bonuses). */
    fun redeem(reward: Reward, bonus: BonusViewModel): Coupon? {
        if (!bonus.spend(reward.cost)) return null
        val c = Coupon(
            id = "cp_${short()}", title = reward.title,
            code = CodeGen.couponCode(),
            createdAt = Date(clock.nowMs),
        )
        put(listOf(c) + _coupons.value)
        return c
    }

    /** Create a deal coupon (scanned by staff → loyalty stamp). */
    fun createDealCoupon(dealID: String, title: String, venueID: String, venueName: String): Coupon {
        _coupons.value.firstOrNull { it.dealID == dealID && !it.used }?.let { return it }
        val c = Coupon(
            id = "cp_${short()}", title = title,
            code = CodeGen.couponCode(),
            createdAt = Date(clock.nowMs), used = false,
            venueID = venueID, venueName = venueName, kind = "deal", dealID = dealID,
        )
        put(listOf(c) + _coupons.value)
        val uid = userID
        viewModelScope.launch { runCatching { backend.saveCoupon(c, uid) } }   // so the venue can scan it
        return c
    }

    fun addGifted(title: String, code: String) {
        if (_coupons.value.any { it.code == code }) return
        put(listOf(Coupon("cp_${short()}", title, code, Date(clock.nowMs))) + _coupons.value)
    }

    fun markUsed(coupon: Coupon) {
        if (_coupons.value.none { it.id == coupon.id }) return
        put(_coupons.value.map { if (it.id == coupon.id) it.copy(used = true) else it })
    }

    fun coupon(id: String): Coupon? = _coupons.value.firstOrNull { it.id == id }

    /** Публикует новый список и сразу сохраняет его — состояние и диск не расходятся. */
    private fun put(next: List<Coupon>) {
        _coupons.value = next
        save()
    }

    /**
     * Очищает кошелёк купонов при смене пользователя: купоны лежат в
     * SharedPreferences устройства, и после выхода их увидел бы следующий
     * вошедший. Зеркалит `CouponStore.resetForNewUser()`.
     */
    fun resetForNewUser() {
        _coupons.value = emptyList()
        userID = ""
        prefs.edit().clear().apply()
    }

    private fun short() = UUID.randomUUID().toString().take(8)

    private fun save() {
        val arr = JSONArray()
        _coupons.value.forEach { c ->
            arr.put(JSONObject().apply {
                put("id", c.id); put("title", c.title); put("code", c.code)
                put("createdAt", c.createdAt.time); put("used", c.used)
                put("venueID", c.venueID); put("venueName", c.venueName)
                put("kind", c.kind); put("dealID", c.dealID)
            })
        }
        prefs.edit().putString("coupons", arr.toString()).apply()
    }

    private fun load() {
        val raw = prefs.getString("coupons", null) ?: return
        runCatching {
            val arr = JSONArray(raw)
            val loaded = ArrayList<Coupon>(arr.length())
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                loaded += Coupon(
                    id = o.getString("id"), title = o.getString("title"), code = o.getString("code"),
                    createdAt = Date(o.getLong("createdAt")), used = o.optBoolean("used"),
                    venueID = o.optString("venueID"), venueName = o.optString("venueName"),
                    kind = o.optString("kind", "bonus"), dealID = o.optString("dealID"),
                )
            }
            _coupons.value = loaded
        }
    }

    companion object {
        val catalog = listOf(
            Reward("disc10", "−10% к любой акции", 100, "🏷️"),
            Reward("coffee", "Бесплатный кофе у партнёра", 300, "☕️"),
            Reward("dessert", "Десерт в подарок", 400, "🍰"),
            Reward("vip", "VIP-доступ к новинкам", 500, "⭐️"),
        )
    }
}
