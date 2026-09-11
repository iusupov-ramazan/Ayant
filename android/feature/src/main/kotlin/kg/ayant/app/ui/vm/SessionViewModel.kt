package kg.ayant.app.ui.vm

import android.app.Application
import kg.ayant.app.domain.contract.AuthService
import kg.ayant.app.domain.model.AuthProvider
import kg.ayant.app.domain.model.AyantUser
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

/** Состояние сессии: кто вошёл, идёт ли операция, последняя ошибка. */
data class SessionState(
    val user: AyantUser? = null,
    val isWorking: Boolean = false,
    val errorMessage: String? = null,
) {
    val isSignedIn: Boolean get() = user != null
    val isGuest: Boolean get() = user?.provider == AuthProvider.GUEST
}

class SessionViewModel(
    app: Application,
    private val service: AuthService,
    /**
     * Восстанавливать ли пользователя из prefs, когда сервис молчит.
     *
     * С Firebase — нет: устаревший кэш оставил бы приложение «залогиненным» без
     * токена, и Firestore начал бы отвечать отказом. Оффлайн — да, иначе демо-
     * режим забывал бы вход. Флаг ставит композиционный корень.
     */
    private val restoreLocalUser: Boolean,
) : AndroidViewModel(app) {

    private val prefs = app.getSharedPreferences("ayant.session", 0)

    // Under Firebase, only trust a real Firebase session — a stale prefs cache would
    // leave the app "signed in" with no auth token, so Firestore reads get denied.
    /**
     * Состояние сессии одним значением. `StateFlow`, а не `mutableStateOf`:
     * переживает смерть процесса корректнее и тестируется без Compose (§4 спеки).
     */
    private val _state = MutableStateFlow(
        SessionState(user = service.currentUser() ?: if (restoreLocalUser) loadUser() else null)
    )
    val state: StateFlow<SessionState> = _state.asStateFlow()

    // Удобные чтения — экраны читают их через collectAsState на state.
    var user: AyantUser?
        get() = _state.value.user
        private set(v) { _state.update { it.copy(user = v) } }
    var isWorking: Boolean
        get() = _state.value.isWorking
        private set(v) { _state.update { it.copy(isWorking = v) } }
    var errorMessage: String?
        get() = _state.value.errorMessage
        set(v) { _state.update { it.copy(errorMessage = v) } }

    val isSignedIn: Boolean get() = _state.value.isSignedIn
    val isGuest: Boolean get() = _state.value.isGuest

    fun signInEmail(email: String, password: String) = run { service.signInEmail(email, password) }
    fun registerEmail(name: String, email: String, password: String) = run { service.registerEmail(name, email, password) }
    /** Real Google Sign-In (Credential Manager) when Firebase is on; mock otherwise. */
    fun signInGoogle(context: android.content.Context) = run {
        service.signInGoogle()
    }
    fun continueAsGuest() = run { service.continueAsGuest() }

    /**
     * Что нужно успеть сделать, ПОКА пользователь ещё авторизован: отписать
     * устройство от push (удаление `userTokens/<token>` требует `request.auth`)
     * и стереть локальные кошельки. Ставит композиционный корень; стор про push
     * и про кошельки ничего не знает.
     */
    var willSignOut: (suspend () -> Unit)? = null

    /**
     * Сменился пользователь БЕЗ выхода — гость вошёл в существующий аккаунт из
     * модального экрана. Локальные кошельки лежат на устройстве и принадлежат
     * прошлому uid, поэтому корень их стирает. Если uid сохранился (регистрация
     * гостя связывает запись), хук не зовётся: это тот же человек.
     *
     * Живёт в сторе, а не в composable: корень пересобирается на смене
     * пользователя, и его `remember` не смог бы запомнить прошлый uid.
     */
    var onUserSwitched: (suspend () -> Unit)? = null

    /**
     * Выход. Гостевую запись при этом УДАЛЯЕМ: войти в анонимный аккаунт
     * повторно нельзя, поэтому после выхода он — мусор в Firebase Auth.
     *
     * Порядок шагов важен: `willSignOut` обязан отработать ДО `signOut()`,
     * иначе запись в Firestore уже некому авторизовать.
     */
    fun signOut() {
        val wasGuest = isGuest
        isWorking = true
        viewModelScope.launch {
            willSignOut?.invoke()
            if (wasGuest) runCatching { service.discardGuestAccount() }
            service.signOut()
            prefs.edit().clear().apply()
            user = null
            errorMessage = null
            isWorking = false
        }
    }

    /**
     * Полное удаление аккаунта: данные в Firestore и запись в Firebase Auth.
     * `onFinish(null)` — успех, иначе текст ошибки для диалога.
     */
    fun deleteAccount(onFinish: (String?) -> Unit = {}) {
        isWorking = true
        errorMessage = null
        viewModelScope.launch {
            willSignOut?.invoke()
            try {
                service.deleteAccount()
                prefs.edit().clear().apply()
                user = null
                onFinish(null)
            } catch (e: Exception) {
                val text = e.localizedMessage ?: "Не удалось удалить аккаунт"
                errorMessage = text
                onFinish(text)
            }
            isWorking = false
        }
    }

    /**
     * Ждём ответ провайдера не дольше таймаута: Firebase не отваливается сам, и
     * при залипшей сети на экране оставался вечный спиннер без ошибки и без
     * возможности повторить. Зеркалит `SessionStore.authTimeout` на iOS.
     */
    private fun run(op: suspend () -> AyantUser) {
        isWorking = true
        errorMessage = null
        viewModelScope.launch {
            try {
                val user = withTimeout(AUTH_TIMEOUT_MS) { op() }
                applyUser(user)
            } catch (e: TimeoutCancellationException) {
                errorMessage = "Нет связи с сервером. Проверьте интернет."
            } catch (e: Exception) {
                errorMessage = e.localizedMessage ?: "Ошибка входа"
            }
            isWorking = false
        }
    }

    private companion object {
        const val AUTH_TIMEOUT_MS = 30_000L
    }

    private fun applyUser(u: AyantUser) {
        val previous = user?.id
        if (previous != null && previous != u.id) {
            viewModelScope.launch { onUserSwitched?.invoke() }
        }
        user = u
        errorMessage = null
        prefs.edit()
            .putString("id", u.id).putString("name", u.name)
            .putString("email", u.email).putString("provider", u.provider.name)
            .apply()
    }

    private fun loadUser(): AyantUser? {
        val id = prefs.getString("id", null) ?: return null
        return AyantUser(
            id = id,
            name = prefs.getString("name", "Вы") ?: "Вы",
            email = prefs.getString("email", null),
            provider = runCatching { AuthProvider.valueOf(prefs.getString("provider", "EMAIL") ?: "EMAIL") }.getOrDefault(AuthProvider.EMAIL),
        )
    }
}
