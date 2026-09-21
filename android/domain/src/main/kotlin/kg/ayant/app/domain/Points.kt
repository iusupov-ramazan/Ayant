package kg.ayant.app.domain

import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenuePointsCard
import kotlinx.coroutines.flow.Flow
import java.util.Date

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
 * Одна запись журнала `venuePoints/{card}/ledger` — пишет только сервер.
 * Зеркалит `PointsLedgerEntry` в `Points.swift`.
 */
data class PointsLedgerEntry(
    val id: String,
    val kind: Kind,
    /** Со знаком: начисление положительное, списание и сгорание — отрицательные. */
    val points: Int,
    val at: Date,
    /** Сумма чека при начислении (кэшбэк/диапазоны); у фикса — null. */
    val billAmount: Int? = null,
    /** Награда при списании; название подставляет экран по конфигу заведения. */
    val rewardID: String? = null,
) {
    enum class Kind(val raw: String) {
        EARN("earn"), REDEEM("redeem"), EXPIRE("expire"), UNKNOWN("unknown");

        companion object {
            fun from(raw: String?): Kind = entries.firstOrNull { it.raw == raw } ?: UNKNOWN
        }
    }
}

/**
 * Начисление, которое гость ещё не видел: snapshot-листенер принёс баланс
 * больше прежнего. Живёт в состоянии, пока экран «Начислено» не закрыт
 * ([PointsIntent.DismissEarn]). Зеркалит `PointsEarnEvent` в `Points.swift`.
 */
data class PointsEarnEvent(
    val id: String,
    val venueID: String,
    val venueName: String,
    val delta: Int,
    val newBalance: Int,
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
    /**
     * История по заведениям, новые сверху. Грузится по запросу экрана
     * ([PointsIntent.LoadHistory]), а не вместе с картами: журнал длиннее и нужен реже.
     */
    val history: Map<String, LoadState<List<PointsLedgerEntry>>> = emptyMap(),
    /** Непоказанное начисление. Пока не null, экран «Начислено» открыт. */
    val pendingEarn: PointsEarnEvent? = null,
) {
    val isSignedIn: Boolean get() = userID.isNotEmpty()

    fun history(venueID: String): LoadState<List<PointsLedgerEntry>> =
        history[venueID] ?: LoadState.Idle

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
    /** Загрузить (или обновить) историю начислений и списаний по заведению. */
    data class LoadHistory(val venueID: String) : PointsIntent
    /** Гость закрыл экран «Начислено». */
    data object DismissEarn : PointsIntent
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

    /**
     * Журнал карты `venuePoints/{userID}_{venueID}/ledger`, новые сверху, не
     * больше [limit] записей. Зеркалит `PointsRepository.ledger` на iOS.
     *
     * Реализация по умолчанию отвечает ошибкой `ledger_unavailable`, а не пустым
     * списком: пустой список экран показал бы как «операций пока нет», и это
     * было бы ложью. `FirebasePointsRepository` / `MockPointsRepository`
     * обязаны переопределить.
     */
    suspend fun ledger(userID: String, venueID: String, limit: Int): Result<List<PointsLedgerEntry>> =
        Result.failure(AppErrorException(AppError.Server("ledger_unavailable")))
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
