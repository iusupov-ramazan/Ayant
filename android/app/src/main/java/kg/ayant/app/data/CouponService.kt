package kg.ayant.app.data

import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kg.ayant.app.data.model.Coupon
import kg.ayant.app.data.model.LoyaltyCard
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.Date

/** Result of the scanCoupon Cloud Function. Mirrors ScanOutcome. */
data class ScanOutcome(
    val ok: Boolean,
    val title: String,
    val loyalty: Boolean,
    val stamps: Int,
    val goal: Int,
    val rewardIssued: Boolean,
    val rewardTitle: String,
    val errorCode: String?,
)

/** Backend coupon/loyalty tracking + venue scanner. Mirrors CouponService.swift. */
interface CouponService {
    suspend fun saveCoupon(coupon: Coupon, userID: String)
    suspend fun fetchCoupons(userID: String): List<Coupon>
    suspend fun fetchLoyaltyCards(userID: String): List<LoyaltyCard>
    suspend fun scanCoupon(code: String, venueID: String, idToken: String): ScanOutcome
}

class MockCouponService : CouponService {
    override suspend fun saveCoupon(coupon: Coupon, userID: String) {}
    override suspend fun fetchCoupons(userID: String): List<Coupon> = emptyList()
    override suspend fun fetchLoyaltyCards(userID: String): List<LoyaltyCard> = emptyList()
    override suspend fun scanCoupon(code: String, venueID: String, idToken: String): ScanOutcome =
        ScanOutcome(true, "Демо-купон", loyalty = true, stamps = 1, goal = 6, rewardIssued = false, rewardTitle = "", errorCode = null)
}

class FirebaseCouponService : CouponService {
    private val db = FirebaseFirestore.getInstance()
    private val scanURL = "https://us-central1-san-25d32.cloudfunctions.net/scanCoupon"

    override suspend fun saveCoupon(coupon: Coupon, userID: String) {
        db.collection("coupons").document(coupon.id).set(
            mapOf(
                "code" to coupon.code, "userID" to userID,
                "venueID" to coupon.venueID, "venueName" to coupon.venueName,
                "title" to coupon.title, "kind" to coupon.kind, "dealID" to coupon.dealID,
                "used" to coupon.used, "createdAt" to coupon.createdAt,
            ),
            com.google.firebase.firestore.SetOptions.merge(),
        ).await()
    }

    override suspend fun fetchCoupons(userID: String): List<Coupon> {
        val snap = db.collection("coupons").whereEqualTo("userID", userID).get().await()
        return snap.documents.map { d ->
            Coupon(
                id = d.id, title = d.getString("title") ?: "Купон", code = d.getString("code") ?: "",
                createdAt = d.getDate("createdAt") ?: Date(), used = d.getBoolean("used") ?: false,
                venueID = d.getString("venueID") ?: "", venueName = d.getString("venueName") ?: "",
                kind = d.getString("kind") ?: "bonus", dealID = d.getString("dealID") ?: "",
            )
        }
    }

    override suspend fun fetchLoyaltyCards(userID: String): List<LoyaltyCard> {
        val snap = db.collection("loyaltyCards").whereEqualTo("userID", userID).get().await()
        return snap.documents.map { d ->
            LoyaltyCard(
                venueID = d.getString("venueID") ?: "", venueName = d.getString("venueName") ?: "",
                stamps = (d.getLong("stamps") ?: 0).toInt(), completedRounds = (d.getLong("completedRounds") ?: 0).toInt(),
                goal = (d.getLong("goal") ?: 6).toInt(), reward = d.getString("reward") ?: "Награда за лояльность",
            )
        }
    }

    override suspend fun scanCoupon(code: String, venueID: String, idToken: String): ScanOutcome = withContext(Dispatchers.IO) {
        runCatching {
            val conn = (URL(scanURL).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Authorization", "Bearer $idToken")
                connectTimeout = 15000; readTimeout = 15000
            }
            conn.outputStream.use { it.write(JSONObject(mapOf("code" to code, "venueID" to venueID)).toString().toByteArray()) }
            val body = (if (conn.responseCode in 200..299) conn.inputStream else conn.errorStream)?.bufferedReader()?.readText() ?: "{}"
            val j = JSONObject(body)
            val ok = j.optBoolean("ok", false)
            ScanOutcome(
                ok = ok, title = j.optString("title"), loyalty = j.optBoolean("loyalty", false),
                stamps = j.optInt("stamps"), goal = j.optInt("goal", 6),
                rewardIssued = j.optBoolean("rewardIssued", false), rewardTitle = j.optString("rewardTitle"),
                errorCode = if (ok) null else j.optString("error", "scan_failed"),
            )
        }.getOrElse {
            ScanOutcome(false, "", loyalty = false, stamps = 0, goal = 6, rewardIssued = false, rewardTitle = "", errorCode = "network")
        }
    }
}
