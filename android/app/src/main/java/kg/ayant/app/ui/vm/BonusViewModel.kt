package kg.ayant.app.ui.vm

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
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
class BonusViewModel(app: Application) : AndroidViewModel(app) {

    private val prefs = app.getSharedPreferences("ayant.bonus", 0)

    val goalSeconds = 30 * 60
    val rewardPerGoal = 20
    private val dailyGoalCap = 4
    private val dailyGameplayCap = 30
    private val idleTimeoutMs = 25_000L

    var balance by mutableIntStateOf(prefs.getInt("balance", 0)); private set
    var completedCycles by mutableIntStateOf(prefs.getInt("cycles", 0)); private set
    var activeSeconds by mutableIntStateOf(prefs.getInt("activeSeconds", 0)); private set
    var isCounting by mutableStateOf(false); private set
    var lastReward by mutableStateOf<Int?>(null)

    private var awardsToday = prefs.getInt("awardsToday", 0)
    private var gameEarnedToday = prefs.getInt("gameEarnedToday", 0)
    private var counterDate = prefs.getString("counterDate", "") ?: ""
    private var lastInteraction = System.currentTimeMillis()
    private var running = false

    val progress: Float get() = activeSeconds.toFloat() / goalSeconds
    val remaining: String
        get() {
            val left = maxOf(0, goalSeconds - activeSeconds)
            return "%02d:%02d".format(left / 60, left % 60)
        }
    val remainingGameplayToday: Int get() = maxOf(0, dailyGameplayCap - gameEarnedToday)

    fun registerInteraction() { lastInteraction = System.currentTimeMillis() }

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
        val active = System.currentTimeMillis() - lastInteraction < idleTimeoutMs
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

    private fun resetDailyIfNeeded() {
        val key = dayKey()
        if (counterDate != key) {
            counterDate = key
            awardsToday = 0
            gameEarnedToday = 0
        }
    }

    private fun dayKey() = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    private fun persist() {
        prefs.edit()
            .putInt("balance", balance).putInt("cycles", completedCycles)
            .putInt("awardsToday", awardsToday).putInt("gameEarnedToday", gameEarnedToday)
            .putString("counterDate", counterDate)
            .apply()
    }
}
