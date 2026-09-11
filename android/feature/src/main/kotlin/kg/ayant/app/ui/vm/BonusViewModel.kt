package kg.ayant.app.ui.vm

import kg.ayant.app.domain.SystemClock
import kg.ayant.app.domain.Clock
import android.app.Application
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Awards bonuses for ACTIVE time in the app + gameplay, with daily anti-farm caps.
 * Mirrors BonusEngine.swift.
 */
class BonusViewModel @JvmOverloads constructor(
    app: Application,
    /** «Сейчас» — из [clock]: иначе время-зависимую логику не проверить тестом. */
    private val clock: Clock = SystemClock,
) : AndroidViewModel(app) {

    private val prefs = app.getSharedPreferences("ayant.bonus", 0)

    // Глобальный кошелёк намеренно почти «не минтит» — награды близки к нулю
    // (реальная ценность — per-venue баллы САН). Mirrors BonusEngine.swift.
    val goalSeconds = 30 * 60
    val rewardPerGoal = 1
    private val dailyGoalCap = 4
    private val dailyGameplayCap = 3
    private val idleTimeoutMs = 25_000L

    // Кошелёк и прогресс — StateFlow: без Compose-состояния во ViewModel (§4 спеки).
    private val _balance = MutableStateFlow(prefs.getInt("balance", 0))
    val balanceFlow: StateFlow<Int> = _balance.asStateFlow()
    var balance: Int
        get() = _balance.value
        private set(v) { _balance.value = v }

    private val _completedCycles = MutableStateFlow(prefs.getInt("cycles", 0))
    val completedCyclesFlow: StateFlow<Int> = _completedCycles.asStateFlow()
    var completedCycles: Int
        get() = _completedCycles.value
        private set(v) { _completedCycles.value = v }

    private val _activeSeconds = MutableStateFlow(prefs.getInt("activeSeconds", 0))
    val activeSecondsFlow: StateFlow<Int> = _activeSeconds.asStateFlow()
    var activeSeconds: Int
        get() = _activeSeconds.value
        private set(v) { _activeSeconds.value = v }
    /** Прогресс мини-игры. `StateFlow`, а не `mutableStateOf` (§4 спеки). */
    private val _isCounting = MutableStateFlow(false)
    val isCountingFlow: StateFlow<Boolean> = _isCounting.asStateFlow()
    var isCounting: Boolean
        get() = _isCounting.value
        private set(v) { _isCounting.value = v }

    private val _lastReward = MutableStateFlow<Int?>(null)
    val lastRewardFlow: StateFlow<Int?> = _lastReward.asStateFlow()
    var lastReward: Int?
        get() = _lastReward.value
        set(v) { _lastReward.value = v }

    private var awardsToday = prefs.getInt("awardsToday", 0)
    private var gameEarnedToday = prefs.getInt("gameEarnedToday", 0)
    private var counterDate = prefs.getString("counterDate", "") ?: ""
    private var lastInteraction = clock.nowMs
    private var running = false

    val progress: Float get() = activeSeconds.toFloat() / goalSeconds
    val remaining: String
        get() {
            val left = maxOf(0, goalSeconds - activeSeconds)
            return "%02d:%02d".format(left / 60, left % 60)
        }
    val remainingGameplayToday: Int get() = maxOf(0, dailyGameplayCap - gameEarnedToday)

    fun registerInteraction() { lastInteraction = clock.nowMs }

    fun start() {
        if (running) return
        running = true
        viewModelScope.launch {
            while (isActive && running) {
                delay(1000)
                tick()
            }
        }
    }

    fun pause() {
        running = false
        isCounting = false
        prefs.edit().putInt("activeSeconds", activeSeconds).apply()
    }

    private fun tick() {
        resetDailyIfNeeded()
        if (awardsToday >= dailyGoalCap) { isCounting = false; return }
        val active = clock.nowMs - lastInteraction < idleTimeoutMs
        isCounting = active
        if (!active) return
        activeSeconds += 1
        if (activeSeconds >= goalSeconds) award()
        if (activeSeconds % 15 == 0) prefs.edit().putInt("activeSeconds", activeSeconds).apply()
    }

    private fun award() {
        resetDailyIfNeeded()
        activeSeconds = 0
        prefs.edit().putInt("activeSeconds", 0).apply()
        if (awardsToday >= dailyGoalCap) return
        balance += rewardPerGoal
        awardsToday += 1
        completedCycles += 1
        lastReward = rewardPerGoal
        persist()
    }

    /** Gameplay bonuses with daily cap. Returns actually granted. */
    fun awardGameplay(amount: Int): Int {
        if (amount <= 0) return 0
        resetDailyIfNeeded()
        val grant = minOf(amount, maxOf(0, dailyGameplayCap - gameEarnedToday))
        if (grant <= 0) { lastReward = 0; return 0 }
        gameEarnedToday += grant
        balance += grant
        lastReward = grant
        persist()
        return grant
    }

    /** Direct grant without cap — referral/server rewards only. */
    fun addFromServer(amount: Int) {
        if (amount <= 0) return
        balance += amount
        lastReward = amount
        persist()
    }

    fun spend(amount: Int): Boolean {
        if (balance < amount) return false
        balance -= amount
        persist()
        return true
    }

    fun clearRewardFlag() { lastReward = null }

    /**
     * Обнуляет кошелёк при смене пользователя (выход, удаление аккаунта).
     *
     * Хранилище здесь — SharedPreferences, то есть УСТРОЙСТВО, а не аккаунт:
     * без сброса гость выходил, заходил снова — и видел свой прежний баланс,
     * дневные лимиты и прогресс. Зеркалит `BonusEngine.resetForNewUser()`.
     */
    fun resetForNewUser() {
        pause()
        balance = 0
        completedCycles = 0
        activeSeconds = 0
        awardsToday = 0
        gameEarnedToday = 0
        counterDate = ""
        lastReward = null
        prefs.edit().clear().apply()
    }

    private fun resetDailyIfNeeded() {
        val key = dayKey()
        if (counterDate != key) {
            counterDate = key
            awardsToday = 0
            gameEarnedToday = 0
        }
    }

    private fun dayKey() = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(clock.nowMs))

    private fun persist() {
        prefs.edit()
            .putInt("balance", balance).putInt("cycles", completedCycles)
            .putInt("awardsToday", awardsToday).putInt("gameEarnedToday", gameEarnedToday)
            .putString("counterDate", counterDate)
            .apply()
    }
}
