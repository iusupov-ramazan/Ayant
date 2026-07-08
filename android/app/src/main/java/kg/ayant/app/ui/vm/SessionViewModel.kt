package kg.ayant.app.ui.vm

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import java.util.UUID

enum class AuthProvider { EMAIL, GOOGLE, GUEST }

data class AyantUser(
    val id: String,
    val name: String,
    val email: String?,
    val provider: AuthProvider,
)

/**
 * Auth state. Mirrors SessionStore.swift. The UI only reads this and doesn't know
 * the implementation. Backed by a mock now; swap in FirebaseAuth once
 * google-services.json is added.
 */
class SessionViewModel(app: Application) : AndroidViewModel(app) {

    private val prefs = app.getSharedPreferences("ayant.session", 0)

    var user by mutableStateOf<AyantUser?>(loadUser())
        private set
    var isWorking by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)

    val isSignedIn: Boolean get() = user != null
    val isGuest: Boolean get() = user?.provider == AuthProvider.GUEST

    fun signInEmail(email: String, password: String) {
        if (email.isBlank() || password.isBlank()) {
            errorMessage = "Введите почту и пароль"; return
        }
        setUser(AyantUser(stableId(email), nameFromEmail(email), email, AuthProvider.EMAIL))
    }

    fun registerEmail(name: String, email: String, password: String) {
        if (name.isBlank() || email.isBlank() || password.isBlank()) {
            errorMessage = "Заполните все поля"; return
        }
        setUser(AyantUser(stableId(email), name, email, AuthProvider.EMAIL))
    }

    fun signInGoogle() {
        // Stub — wire Google Sign-In / Firebase Auth once configured.
        setUser(AyantUser(UUID.randomUUID().toString(), "Пользователь Google", null, AuthProvider.GOOGLE))
    }

    fun continueAsGuest() {
        setUser(AyantUser("guest_${UUID.randomUUID().toString().take(8)}", "Гость", null, AuthProvider.GUEST))
    }

    fun signOut() {
        user = null
        errorMessage = null
        prefs.edit().clear().apply()
    }

    private fun setUser(u: AyantUser) {
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
            provider = AuthProvider.valueOf(prefs.getString("provider", "EMAIL") ?: "EMAIL"),
        )
    }

    private fun nameFromEmail(email: String) = email.substringBefore("@").replaceFirstChar { it.uppercase() }
    private fun stableId(email: String) = "u_" + email.lowercase().hashCode().toUInt().toString(16)
}
