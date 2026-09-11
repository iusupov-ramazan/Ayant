package kg.ayant.app.data
import kg.ayant.app.domain.contract.CouponService
import kg.ayant.app.domain.contract.AuthService

import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import kg.ayant.app.data.firestore.FS
import kg.ayant.app.data.firestore.toVenuePointsCard
import kg.ayant.app.domain.AppError
import kg.ayant.app.domain.AppErrorException
import kg.ayant.app.domain.PointsRepository
import kg.ayant.app.domain.RedeemReceipt
import kg.ayant.app.domain.model.VenuePointsCard
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOf

/**
 * Живой источник карт баллов на Firestore. Зеркалит `FirebasePointsRepository.swift`.
 *
 * Раньше экран баллов опрашивал бэкенд раз в 4 секунды, пока был открыт: баланс
 * менялся на сервере (сотрудник сканировал QR), а клиент узнавал об этом в
 * среднем через две секунды и делал ~15 лишних запросов в минуту на каждого
 * открывшего экран. Здесь вместо опроса — `addSnapshotListener` внутри
 * [callbackFlow]: сервер сам присылает изменение, трафика меньше, задержка
 * близка к нулю.
 *
 * `awaitClose` снимает листенер, когда сборщик потока отменён, — время жизни
 * подписки равно времени жизни экрана.
 */
class FirebasePointsRepository(
    // Зависимости приходят из композиционного корня (:app/AppConfig): слой данных
    // наверх не смотрит, иначе :data зависел бы от :app.
    private val backend: CouponService,
    private val auth: AuthService,
) : PointsRepository {

    private val db = FirebaseFirestore.getInstance()

    override fun cards(userID: String): Flow<Result<List<VenuePointsCard>>> {
        if (userID.isEmpty()) return flowOf(Result.success(emptyList()))
        return callbackFlow {
            val registration = db.collection(FS.Collection.VENUE_POINTS)
                .whereEqualTo(FS.VenuePointsDoc.USER_ID, userID)
                .addSnapshotListener { snapshot, error ->
                    if (error != null) {
                        trySend(Result.failure(AppErrorException(error.toAppError())))
                        return@addSnapshotListener
                    }
                    val cards = snapshot?.documents?.map { it.toVenuePointsCard() } ?: emptyList()
                    trySend(Result.success(cards))
                }
            awaitClose { registration.remove() }
        }
    }

    override suspend fun redeem(
        venueID: String,
        userID: String,
        rewardID: String,
        pointsToSpend: Int,
        idempotencyKey: String,
    ): Result<RedeemReceipt> {
        if (userID.isEmpty()) return Result.failure(AppErrorException(AppError.Unauthenticated))
        val token = auth.idToken().orEmpty()
        if (token.isEmpty()) return Result.failure(AppErrorException(AppError.Unauthenticated))
        val out = runCatching {
            backend.redeemVenuePoints(venueID, userID, rewardID, pointsToSpend, token, idempotencyKey)
        }.getOrElse { return Result.failure(AppErrorException(AppError.Network)) }

        if (!out.ok) {
            return Result.failure(AppErrorException(AppError.Server(out.errorCode ?: "redeem_failed")))
        }
        return Result.success(
            RedeemReceipt(out.redeemed, out.balance, out.rewardTitle, out.somOff, out.replayed)
        )
    }
}

/**
 * Оффлайн-источник: отдаёт то, что положили в конструктор, и «списывает» локально.
 * Нужен, чтобы приложение работало и тестировалось без Firebase (`AppConfig.useFirebase`).
 */
class MockPointsRepository(cards: List<VenuePointsCard> = emptyList()) : PointsRepository {
    private val stored = cards.toMutableList()

    override fun cards(userID: String): Flow<Result<List<VenuePointsCard>>> =
        flowOf(Result.success(if (userID.isEmpty()) emptyList() else stored.toList()))

    override suspend fun redeem(
        venueID: String,
        userID: String,
        rewardID: String,
        pointsToSpend: Int,
        idempotencyKey: String,
    ): Result<RedeemReceipt> {
        if (userID.isEmpty()) return Result.failure(AppErrorException(AppError.Unauthenticated))
        val spend = maxOf(pointsToSpend, 1)
        val index = stored.indexOfFirst { it.venueID == venueID }
        if (index < 0 || stored[index].balance < spend) {
            return Result.failure(AppErrorException(AppError.Server("insufficient")))
        }
        stored[index] = stored[index].copy(
            balance = stored[index].balance - spend,
            lifetimeRedeemed = stored[index].lifetimeRedeemed + spend,
        )
        return Result.success(RedeemReceipt(spend, stored[index].balance, "Демо-награда"))
    }
}

/** Граница слоя Data: выше неё исключений Firestore уже не встречается. */
internal fun Throwable.toAppError(): AppError = when ((this as? FirebaseFirestoreException)?.code) {
    FirebaseFirestoreException.Code.PERMISSION_DENIED -> AppError.PermissionDenied
    FirebaseFirestoreException.Code.UNAUTHENTICATED -> AppError.Unauthenticated
    FirebaseFirestoreException.Code.UNAVAILABLE,
    FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> AppError.Network
    FirebaseFirestoreException.Code.NOT_FOUND -> AppError.NotFound
    else -> AppError.Unknown
}
