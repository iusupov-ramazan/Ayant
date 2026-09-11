package kg.ayant.app.domain

import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenuePointsCard
import kotlinx.coroutines.flow.Flow

/*
 * Фича «Баллы САН»: состояние, намерения и контракт данных.
 * Имена полей совпадают с `Points.swift` в AyantDomain — это сознательно.
 */

/** Что произошло при списании (ответ `redeemVenuePoints`). */
data class RedeemReceipt(
    val redeemed: Int,
    val balance: Int,
    val rewardTitle: String,
    /** Скидка в сомах — только для награды типа `money`. */
    val somOff: Int? = null,
    /** `true` — запрос с этим ключом уже выполнялся, баллы повторно НЕ списаны. */
    val replayed: Boolean = false,
)

/**
 * Всё состояние экрана баллов — одним значением.
 *
 * Composable — чистая функция от него: никаких «а если карточки ещё null, но
 * ошибки уже нет». [cards] держит и загрузку, и ошибку (см. [LoadState]).
 */
data class PointsState(
    /** Пусто — гость не авторизован; копить и тратить баллы нельзя. */
    val userID: String = "",
    val cards: LoadState<List<VenuePointsCard>> = LoadState.Idle,
    val redeem: RedeemPhase = RedeemPhase.Idle,
) {
    val isSignedIn: Boolean get() = userID.isNotEmpty()

    fun card(venueID: String): VenuePointsCard? =
        cards.valueOrNull()?.firstOrNull { it.venueID == venueID }

    fun balance(venueID: String): Int = card(venueID)?.balance ?: 0

    /** Карты в порядке показа: сначала с большим балансом. */
    val sortedCards: List<VenuePointsCard>
        get() = (cards.valueOrNull() ?: emptyList()).sortedByDescending { it.balance }
}

/**
 * Фаза списания. Отдельно от [PointsState.cards], потому что список остаётся
 * видимым, пока идёт списание.
 */
sealed interface RedeemPhase {
    data object Idle : RedeemPhase
    data class Working(val rewardID: String) : RedeemPhase
    data class Done(val receipt: RedeemReceipt) : RedeemPhase
    data class Failed(val error: AppError) : RedeemPhase

    val isWorking: Boolean get() = this is Working
}

/**
 * Единственный вход во ViewModel. Composable не зовёт методы по одному — он
 * отправляет намерение, а ViewModel решает, что с ним делать.
 */
sealed interface PointsIntent {
    /** Подписаться на живые обновления карт гостя (заменяет опрос раз в 4 с). */
    data class Observe(val userID: String) : PointsIntent
    /** Отписаться (экран закрыт). */
    data object Stop : PointsIntent
    /** Списать баллы на награду. [pointsToSpend] важен только для `money`-награды. */
    data class Redeem(
        val venueID: String,
        val rewardID: String,
        val pointsToSpend: Int,
    ) : PointsIntent
    /** Закрыть результат/ошибку списания. */
    data object DismissRedeem : PointsIntent
}

/**
 * Источник карт баллов и операции списания.
 *
 * Чтение — поток: реализация на Firestore держит snapshot-листенер, поэтому
 * баланс обновляется сам, когда сотрудник просканировал QR. Никакого опроса.
 *
 * Запись идёт только через Cloud Function: `venuePoints` клиенту писать запрещено
 * правилами, и это единственная защита от накрутки баланса.
 */
interface PointsRepository {
    /** Живой поток карт гостя. Отменяется вместе со сборщиком. */
    fun cards(userID: String): Flow<Result<List<VenuePointsCard>>>

    /**
     * Списание баллов на награду.
     *
     * @param idempotencyKey генерируется клиентом ОДИН раз на попытку и
     *   переиспользуется при повторе. Сервер вернёт тот же результат вместо
     *   второго списания ([RedeemReceipt.replayed] == true).
     */
    suspend fun redeem(
        venueID: String,
        userID: String,
        rewardID: String,
        pointsToSpend: Int,
        idempotencyKey: String,
    ): Result<RedeemReceipt>
}

// MARK: - Одна механика лояльности на заведение

/**
 * Что именно заведение даёт гостю за визит. Зеркалит `LoyaltyKind` в `Points.swift`.
 *
 * Механика ровно ОДНА. Пока `pointsEnabled` и `loyaltyEnabled` были независимы,
 * заведение могло включить обе: гость видел и карточку баллов, и баннер штампов,
 * и по одному скану не мог понять, что ему начислили, — а заведение платило
 * дважды за один визит. Приоритет у баллов: их настраивает админ-панель и они
 * привязаны к деньгам (1 балл = 1 сом).
 */
enum class LoyaltyKind {
    POINTS, STAMPS, NONE;

    companion object {
        /**
         * Действующая механика заведения. Единственный источник правды для обеих
         * платформ и для Cloud Functions.
         */
        fun active(pointsEnabled: Boolean, loyaltyEnabled: Boolean): LoyaltyKind = when {
            pointsEnabled -> POINTS
            loyaltyEnabled -> STAMPS
            else -> NONE
        }
    }
}

/** Действующая механика лояльности этого заведения. */
val Venue.loyaltyKind: LoyaltyKind
    get() = LoyaltyKind.active(pointsEnabled, loyaltyEnabled)

/** Штампы работают, только если баллы выключены. */
val Venue.stampsActive: Boolean get() = loyaltyKind == LoyaltyKind.STAMPS

/** Баллы работают. */
val Venue.pointsActive: Boolean get() = loyaltyKind == LoyaltyKind.POINTS
