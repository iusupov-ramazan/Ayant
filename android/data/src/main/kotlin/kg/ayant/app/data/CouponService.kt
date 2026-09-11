package kg.ayant.app.data

import kg.ayant.app.domain.contract.CouponService
import kg.ayant.app.domain.contract.RedeemOutcome
import kg.ayant.app.domain.contract.ScanOutcome

import kg.ayant.app.domain.model.Coupon
import kg.ayant.app.domain.model.LoyaltyCard
import kg.ayant.app.domain.model.VenuePointsCard

import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOf
import com.google.firebase.firestore.SetOptions
import kg.ayant.app.data.firestore.FS
import kg.ayant.app.data.firestore.toCoupon
import kg.ayant.app.data.firestore.toFirestoreMap
import kg.ayant.app.data.firestore.toLoyaltyCard
import kg.ayant.app.data.firestore.toVenuePointsCard
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.Date

class MockCouponService : CouponService {
    override suspend fun saveCoupon(coupon: Coupon, userID: String) {}
    override suspend fun fetchCoupons(userID: String): List<Coupon> = emptyList()
    override suspend fun fetchLoyaltyCards(userID: String): List<LoyaltyCard> = emptyList()
    override suspend fun fetchVenuePoints(userID: String): List<VenuePointsCard> = emptyList()
    override suspend fun scanCoupon(code: String, venueID: String, idToken: String,
                                    billAmount: Int?, bandIndex: Int?,
                                    idempotencyKey: String): ScanOutcome =
        ScanOutcome(true, "Демо-купон", loyalty = true, stamps = 1, goal = 6, rewardIssued = false, rewardTitle = "", errorCode = null)
    override suspend fun redeemVenuePoints(venueID: String, userID: String, rewardId: String,
                                           pointsToSpend: Int, idToken: String,
                                           idempotencyKey: String): RedeemOutcome =
        RedeemOutcome(true, if (pointsToSpend > 0) pointsToSpend else 100, 0, "Демо-награда", null, null)
}

class FirebaseCouponService : CouponService {
    private val db = FirebaseFirestore.getInstance()
    private val functionsBase = "https://us-central1-san-25d32.cloudfunctions.net"
    private val scanURL = "$functionsBase/scanCoupon"
    private val redeemURL = "$functionsBase/redeemVenuePoints"

    override suspend fun saveCoupon(coupon: Coupon, userID: String) {
        db.collection(FS.Collection.COUPONS).document(coupon.id)
            .set(coupon.toFirestoreMap(userID), SetOptions.merge()).await()
    }

    override suspend fun fetchCoupons(userID: String): List<Coupon> =
        db.collection(FS.Collection.COUPONS).whereEqualTo(FS.CouponDoc.USER_ID, userID)
            .get().await().documents.map { it.toCoupon() }

    override suspend fun fetchLoyaltyCards(userID: String): List<LoyaltyCard> =
        db.collection(FS.Collection.LOYALTY_CARDS).whereEqualTo(FS.LoyaltyCardDoc.USER_ID, userID)
            .get().await().documents.map { it.toLoyaltyCard() }

    /**
     * Живой поток: штамп начисляет Cloud Function, а Firestore сам присылает
     * изменение. Заменяет опрос раз в 4 с, который был на экранах лояльности.
     */
    override fun loyaltyCards(userID: String): Flow<List<LoyaltyCard>> {
        if (userID.isEmpty()) return flowOf(emptyList())
        return callbackFlow {
            val registration = db.collection(FS.Collection.LOYALTY_CARDS)
                .whereEqualTo(FS.LoyaltyCardDoc.USER_ID, userID)
                .addSnapshotListener { snapshot, error ->
                    if (error != null) return@addSnapshotListener   // сеть моргнула — держим последнее
                    trySend(snapshot?.documents?.map { it.toLoyaltyCard() } ?: emptyList())
                }
            awaitClose { registration.remove() }
        }
    }

    override suspend fun fetchVenuePoints(userID: String): List<VenuePointsCard> =
        db.collection(FS.Collection.VENUE_POINTS).whereEqualTo(FS.VenuePointsDoc.USER_ID, userID)
            .get().await().documents.map { it.toVenuePointsCard() }

    override suspend fun scanCoupon(code: String, venueID: String, idToken: String,
                                    billAmount: Int?, bandIndex: Int?,
                                    idempotencyKey: String): ScanOutcome = withContext(Dispatchers.IO) {
        runCatching {
            val conn = (URL(scanURL).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Authorization", "Bearer $idToken")
                connectTimeout = 15000; readTimeout = 15000
            }
            val payload = JSONObject(mapOf(FS.ScanResponse.CODE to code, FS.ScanResponse.VENUE_ID to venueID))
            if (billAmount != null) payload.put(FS.ScanResponse.BILL_AMOUNT, billAmount)
            if (bandIndex != null) payload.put(FS.ScanResponse.BAND_INDEX, bandIndex)
            if (idempotencyKey.isNotEmpty()) payload.put(FS.ScanResponse.IDEMPOTENCY_KEY, idempotencyKey)
            conn.outputStream.use { it.write(payload.toString().toByteArray()) }
            val body = (if (conn.responseCode in 200..299) conn.inputStream else conn.errorStream)?.bufferedReader()?.readText() ?: "{}"
            val j = JSONObject(body)
            val ok = j.optBoolean(FS.ScanResponse.OK, false)
            ScanOutcome(
                ok = ok,
                title = j.optString(FS.ScanResponse.TITLE),
                loyalty = j.optBoolean(FS.ScanResponse.LOYALTY, false),
                stamps = j.optInt(FS.ScanResponse.STAMPS),
                goal = j.optInt(FS.ScanResponse.GOAL, 6),
                rewardIssued = j.optBoolean(FS.ScanResponse.REWARD_ISSUED, false),
                rewardTitle = j.optString(FS.ScanResponse.REWARD_TITLE),
                errorCode = if (ok) null else j.optString(FS.ScanResponse.ERROR, "scan_failed"),
                points = j.optBoolean(FS.ScanResponse.POINTS, false),
                awarded = j.optInt(FS.ScanResponse.AWARDED),
                balance = j.optInt(FS.ScanResponse.BALANCE),
                replayed = j.optBoolean(FS.ScanResponse.REPLAYED, false),
            )
        }.getOrElse {
            ScanOutcome(false, "", loyalty = false, stamps = 0, goal = 6, rewardIssued = false, rewardTitle = "", errorCode = "network")
        }
    }

    override suspend fun redeemVenuePoints(venueID: String, userID: String, rewardId: String,
                                           pointsToSpend: Int, idToken: String,
                                           idempotencyKey: String): RedeemOutcome = withContext(Dispatchers.IO) {
        runCatching {
            val conn = (URL(redeemURL).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Authorization", "Bearer $idToken")
                connectTimeout = 15000; readTimeout = 15000
            }
            val payload = JSONObject(mapOf(
                FS.RedeemResponse.VENUE_ID to venueID, FS.RedeemResponse.REWARD_ID to rewardId,
            ))
            if (userID.isNotEmpty()) payload.put(FS.RedeemResponse.USER_ID, userID)
            if (pointsToSpend > 0) payload.put(FS.RedeemResponse.POINTS_TO_SPEND, pointsToSpend)
            if (idempotencyKey.isNotEmpty()) payload.put(FS.RedeemResponse.IDEMPOTENCY_KEY, idempotencyKey)
            conn.outputStream.use { it.write(payload.toString().toByteArray()) }
            val body = (if (conn.responseCode in 200..299) conn.inputStream else conn.errorStream)?.bufferedReader()?.readText() ?: "{}"
            val j = JSONObject(body)
            val ok = j.optBoolean(FS.RedeemResponse.OK, false)
            RedeemOutcome(
                ok = ok,
                redeemed = j.optInt(FS.RedeemResponse.REDEEMED),
                balance = j.optInt(FS.RedeemResponse.BALANCE),
                rewardTitle = j.optString(FS.RedeemResponse.REWARD_TITLE),
                somOff = if (j.has(FS.RedeemResponse.SOM_OFF) && !j.isNull(FS.RedeemResponse.SOM_OFF))
                    j.optInt(FS.RedeemResponse.SOM_OFF) else null,
                errorCode = if (ok) null else j.optString(FS.RedeemResponse.ERROR, "redeem_failed"),
                replayed = j.optBoolean(FS.RedeemResponse.REPLAYED, false),
            )
        }.getOrElse {
            RedeemOutcome(false, 0, 0, "", null, "network")
        }
    }
}
