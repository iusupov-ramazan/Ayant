package kg.ayant.app.ui.vm

import android.app.Application
import androidx.compose.runtime.mutableStateListOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kg.ayant.app.core.AppConfig
import kg.ayant.app.data.CouponService
import kg.ayant.app.data.model.Coupon
import kg.ayant.app.data.model.Reward
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject
import java.util.Date
import java.util.UUID

/**
 * Coupon wallet. Mirrors CouponStore.swift (local persistence via JSON in prefs).
 * DI: [backend] is an injectable constructor param (`@JvmOverloads` keeps the
 * `(Application)` constructor `viewModel()` relies on).
 */
class CouponViewModel @JvmOverloads constructor(
    app: Application,
    private val backend: CouponService = AppConfig.makeCouponService(),
) : AndroidViewModel(app) {

    private val prefs = app.getSharedPreferences("ayant.coupons", 0)
    val coupons = mutableStateListOf<Coupon>()
    var userID: String = ""
        private set

    val activeCount: Int get() = coupons.count { !it.used }

    init { load() }

    /** Merge backend coupons (used status, loyalty rewards) by code. Backend wins. */
    fun sync(uid: String) {
        userID = uid
        if (uid.isEmpty()) return
        viewModelScope.launch {
            val fetched = runCatching { backend.fetchCoupons(uid) }.getOrNull() ?: return@launch
            val map = LinkedHashMap<String, Coupon>()
            coupons.forEach { map[it.code] = it }
            fetched.forEach { map[it.code] = it }
            coupons.clear()
            coupons.addAll(map.values.sortedByDescending { it.createdAt })
            save()
        }
    }

    /** Spend bonuses and issue a coupon. Returns coupon or null (not enough bonuses). */
    fun redeem(reward: Reward, bonus: BonusViewModel): Coupon? {
        if (!bonus.spend(reward.cost)) return null
        val c = Coupon(
            id = "cp_${short()}", title = reward.title,
            code = "AYANT-${UUID.randomUUID().toString().take(6).uppercase()}",
            createdAt = Date(),
        )
        coupons.add(0, c)
        save()
        return c
    }

    /** Create a deal coupon (scanned by staff → loyalty stamp). */
    fun createDealCoupon(dealID: String, title: String, venueID: String, venueName: String): Coupon {
        coupons.firstOrNull { it.dealID == dealID && !it.used }?.let { return it }
        val c = Coupon(
            id = "cp_${short()}", title = title,
            code = "AYANT-${UUID.randomUUID().toString().take(6).uppercase()}",
            createdAt = Date(), used = false,
            venueID = venueID, venueName = venueName, kind = "deal", dealID = dealID,
        )
        coupons.add(0, c)
        save()
        val uid = userID
        viewModelScope.launch { runCatching { backend.saveCoupon(c, uid) } }   // so the venue can scan it
        return c
    }

    fun addGifted(title: String, code: String) {
        if (coupons.any { it.code == code }) return
        coupons.add(0, Coupon("cp_${short()}", title, code, Date()))
        save()
    }

    fun markUsed(coupon: Coupon) {
        val i = coupons.indexOfFirst { it.id == coupon.id }
        if (i >= 0) { coupons[i] = coupons[i].copy(used = true); save() }
    }

    fun coupon(id: String): Coupon? = coupons.firstOrNull { it.id == id }

    private fun short() = UUID.randomUUID().toString().take(8)

    private fun save() {
        val arr = JSONArray()
        coupons.forEach { c ->
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
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                coupons.add(
                    Coupon(
                        id = o.getString("id"), title = o.getString("title"), code = o.getString("code"),
                        createdAt = Date(o.getLong("createdAt")), used = o.optBoolean("used"),
                        venueID = o.optString("venueID"), venueName = o.optString("venueName"),
                        kind = o.optString("kind", "bonus"), dealID = o.optString("dealID"),
                    )
                )
            }
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
