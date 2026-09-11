package kg.ayant.app.ui.vm

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kg.ayant.app.domain.asAppError
import kg.ayant.app.domain.AppError
import kg.ayant.app.domain.Clock
import kg.ayant.app.domain.LoadState
import kg.ayant.app.domain.PointsIntent
import kg.ayant.app.domain.PointsRepository
import kg.ayant.app.domain.PointsState
import kg.ayant.app.domain.RedeemPhase
import kg.ayant.app.domain.SystemClock
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * ViewModel фичи «Баллы САН».
 *
 * Форма новая и намеренно отличается от остальных VM в проекте: наружу торчит
 * **одно значение состояния** ([state]) и **один вход** ([send]). Composable не
 * дёргает методы по одному и не держит собственных флагов «грузим / ошибка /
 * готово». Зеркалит `PointsStore.swift` на iOS.
 *
 * Что изменилось по сравнению со старым `VenuePointsViewModel`:
 *  • `StateFlow` вместо `mutableStateOf` — состояние переживает смерть процесса
 *    корректнее и тестируется без Compose;
 *  • баланс приходит живым потоком (snapshot-листенер) вместо опроса раз в 4 с;
 *  • ключ идемпотентности генерируется один раз на попытку списания, поэтому
 *    повторная отправка (ретрай, второй тап) не спишет баллы дважды.
 */
class PointsViewModel @JvmOverloads constructor(
    app: Application,
    private val repository: PointsRepository,
    private val clock: Clock = SystemClock,
) : AndroidViewModel(app) {

    private val _state = MutableStateFlow(PointsState())
    val state: StateFlow<PointsState> = _state.asStateFlow()

    private var observation: Job? = null

    /**
     * Ключ живёт, пока попытка не завершилась успехом: любой повтор уйдёт с тем
     * же ключом, и сервер вернёт первый результат вместо второго списания.
     */
    private val pendingRedeemKeys = mutableMapOf<String, String>()

    fun send(intent: PointsIntent) {
        when (intent) {
            is PointsIntent.Observe -> observe(intent.userID)
            is PointsIntent.Stop -> stopObserving()
            is PointsIntent.Redeem -> redeem(intent.venueID, intent.rewardID, intent.pointsToSpend)
            is PointsIntent.DismissRedeem -> _state.update { it.copy(redeem = RedeemPhase.Idle) }
        }
    }

    // ── Чтение ───────────────────────────────────────────────────────────────

    private fun observe(userID: String) {
        // Повторный вызов с тем же гостем — уже подписаны, второй листенер не нужен.
        if (_state.value.userID == userID && observation != null) return
        observation?.cancel()
        _state.update { it.copy(userID = userID) }

        if (userID.isEmpty()) {
            _state.update { it.copy(cards = LoadState.Loaded(emptyList())) }
            return
        }
        if (_state.value.cards.valueOrNull() == null) {
            _state.update { it.copy(cards = LoadState.Loading) }
        }

        observation = viewModelScope.launch {
            repository.cards(userID).collect { result ->
                result.fold(
                    onSuccess = { cards -> _state.update { it.copy(cards = LoadState.Loaded(cards)) } },
                    onFailure = { error ->
                        // Уже показанные карты не стираем: сеть моргнула — пусть
                        // гость видит последний известный баланс, а не пустой экран.
                        val known = _state.value.cards.valueOrNull()
                        _state.update {
                            it.copy(
                                cards = if (known != null) LoadState.Loaded(known)
                                else LoadState.Failed(error.asAppError())
                            )
                        }
                    },
                )
            }
        }
    }

    private fun stopObserving() {
        observation?.cancel()
        observation = null
    }

    // ── Списание ─────────────────────────────────────────────────────────────

    private fun redeem(venueID: String, rewardID: String, pointsToSpend: Int) {
        val current = _state.value
        if (!current.isSignedIn) {
            _state.update { it.copy(redeem = RedeemPhase.Failed(AppError.Unauthenticated)) }
            return
        }
        if (current.redeem.isWorking) return   // второй тап игнорируем

        val attemptID = "$venueID|$rewardID"
        val key = pendingRedeemKeys.getOrPut(attemptID) { newIdempotencyKey() }

        _state.update { it.copy(redeem = RedeemPhase.Working(rewardID)) }
        viewModelScope.launch {
            val result = repository.redeem(venueID, current.userID, rewardID, pointsToSpend, key)
            result.fold(
                onSuccess = { receipt ->
                    pendingRedeemKeys.remove(attemptID)   // попытка закрыта, дальше — новая
                    _state.update { it.copy(redeem = RedeemPhase.Done(receipt)) }
                    // Баланс приедет сам snapshot-листенером; ничего не перезапрашиваем.
                },
                onFailure = { error ->
                    // Ключ НЕ сбрасываем: повтор должен уйти с тем же ключом.
                    _state.update { it.copy(redeem = RedeemPhase.Failed(error.asAppError())) }
                },
            )
        }
    }

    /** Уникальный ключ попытки. Время берём из [Clock], чтобы тест был воспроизводим. */
    private fun newIdempotencyKey(): String = "${UUID.randomUUID()}-${clock.nowMs / 1000}"

    override fun onCleared() {
        stopObserving()
        super.onCleared()
    }
}
