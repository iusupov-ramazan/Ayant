package kg.ayant.app.ui.vm

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kg.ayant.app.core.AppConfig
import kotlinx.coroutines.launch

enum class AuthProvider { EMAIL, GOOGLE, GUEST }

data class AyantUser(
    val id: String,
    val name: String,
    val email: String?,
    val provider: AuthProvider,
)

/**
 * Auth state. Mirrors SessionStore.swift — delegates to AuthService (Mock/Firebase
 * via AppConfig) and caches the signed-in user in prefs for offline start.
 */
class SessionViewModel(app: Application) : AndroidViewModel(app) {

    private val prefs = app.getSharedPreferences("ayant.session", 0)
    private val service = AppConfig.makeAuthService()

    // Under Firebase, only trust a real Firebase session — a stale prefs cache would
    // leave the app "signed in" with no auth token, so Firestore reads get denied.
    var user by mutableStateOf(service.currentUser() ?: if (AppConfig.useFirebase) null else loadUser())
        private set
    var isWorking by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)

    val isSignedIn: Boolean get() = user != null
    val isGuest: Boolean get() = user?.provider == AuthProvider.GUEST

    fun signInEmail(email: String, password: String) = run { service.signInEmail(email, password) }
    fun registerEmail(name: String, email: String, password: String) = run { service.registerEmail(name, email, password) }
    /** Real Google Sign-In (Credential Manager) when Firebase is on; mock otherwise. */
    fun signInGoogle(context: android.content.Context) = run {
        if (AppConfig.useFirebase) kg.ayant.app.data.GoogleAuth.signIn(context) else service.signInGoogle()
    }
    fun continueAsGuest() = run { service.continueAsGuest() }

    fun signOut() {
        service.signOut()
        user = null
        errorMessage = null
        prefs.edit().clear().apply()
    }

    private fun run(op: suspend () -> AyantUser) {
        isWorking = true
        errorMessage = null
        viewModelScope.launch {
            try {
                applyUser(op())
            } catch (e: Exception) {
                errorMessage = e.localizedMessage ?: "Ошибка входа"
            }
            isWorking = false
        }
    }

    private fun applyUser(u: AyantUser) {
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
