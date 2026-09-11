package kg.ayant.app.domain.contract

import kg.ayant.app.domain.model.Coupon
import kg.ayant.app.domain.model.LoyaltyCard
import kg.ayant.app.domain.model.VenuePointsCard
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf

/*
 * Контракт бэкенда купонов/лояльности/баллов. Реализации (Mock/Firebase) —
 * в модуле :data; фича знает только этот интерфейс.
 */

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
    // Начисление баллов САН (Ветка C). points=true ⇒ это баллы, не штамп.
    val points: Boolean = false,
    val awarded: Int = 0,
    val balance: Int = 0,
    /** true — запрос с этим idempotencyKey уже выполнялся; ничего не начислено повторно. */
    val replayed: Boolean = false,
)

/** Result of the redeemVenuePoints Cloud Function. Mirrors RedeemOutcome. */
data class RedeemOutcome(
    val ok: Boolean,
    val redeemed: Int,
    val balance: Int,
    val rewardTitle: String,
    val somOff: Int?,
    val errorCode: String?,
    /** true — запрос с этим idempotencyKey уже выполнялся, баллы НЕ списаны повторно. */
    val replayed: Boolean = false,
)

/** Backend coupon/loyalty tracking + venue scanner. Mirrors CouponService.swift. */
interface CouponService {
    suspend fun saveCoupon(coupon: Coupon, userID: String)
    suspend fun fetchCoupons(userID: String): List<Coupon>
    suspend fun fetchLoyaltyCards(userID: String): List<LoyaltyCard>
    /**
     * Живой поток карт лояльности: штампы меняет сканер заведения, и экран
     * должен увидеть это сразу, без опроса. Реализация на Firestore держит
     * snapshot-листенер; он снимается вместе со сборщиком потока.
     */
    fun loyaltyCards(userID: String): Flow<List<LoyaltyCard>> = flowOf(emptyList())
    suspend fun fetchVenuePoints(userID: String): List<VenuePointsCard>
    /**
     * @param idempotencyKey один на распознанный QR, повторяется при ретрае:
     *   сервер вернёт исходный результат вместо второго штампа/начисления.
     */
    suspend fun scanCoupon(code: String, venueID: String, idToken: String,
                           billAmount: Int? = null, bandIndex: Int? = null,
                           idempotencyKey: String = ""): ScanOutcome
    /**
     * @param idempotencyKey генерируется вызывающим ОДИН раз на попытку и повторяется
     *   при ретрае — сервер вернёт тот же результат вместо второго списания.
     */
    suspend fun redeemVenuePoints(venueID: String, userID: String, rewardId: String,
                                  pointsToSpend: Int, idToken: String,
                                  idempotencyKey: String = ""): RedeemOutcome
}

