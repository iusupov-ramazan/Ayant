package kg.ayant.app.data

import com.google.firebase.auth.FirebaseAuth
import kotlinx.coroutines.tasks.await
import kg.ayant.app.ui.vm.AuthProvider
import kg.ayant.app.ui.vm.AyantUser
import java.util.UUID

/**
 * Auth abstraction. MockAuthService works offline; FirebaseAuthService uses the
 * shared san-25d32 Auth. Mirrors AuthService.swift (Apple omitted — iOS-only).
 */
interface AuthService {
    fun currentUser(): AyantUser?
    /** Firebase ID token for authorizing Cloud Function calls (scanCoupon). */
    suspend fun idToken(): String?
    suspend fun signInEmail(email: String, password: String): AyantUser
    suspend fun registerEmail(name: String, email: String, password: String): AyantUser
    suspend fun signInGoogle(): AyantUser
    suspend fun continueAsGuest(): AyantUser
    fun signOut()
}

/** Offline mock — accepts any input, derives a stable id from email. */
class MockAuthService : AuthService {
    override fun currentUser(): AyantUser? = null
    override suspend fun idToken(): String? = "mock-token"
    override suspend fun signInEmail(email: String, password: String): AyantUser {
        require(email.isNotBlank() && password.isNotBlank()) { "Введите почту и пароль" }
        return AyantUser(stableId(email), nameFromEmail(email), email, AuthProvider.EMAIL)
    }
    override suspend fun registerEmail(name: String, email: String, password: String): AyantUser {
        require(name.isNotBlank() && email.isNotBlank() && password.isNotBlank()) { "Заполните все поля" }
        return AyantUser(stableId(email), name, email, AuthProvider.EMAIL)
    }
    override suspend fun signInGoogle(): AyantUser =
        AyantUser(UUID.randomUUID().toString(), "Пользователь Google", null, AuthProvider.GOOGLE)
    override suspend fun continueAsGuest(): AyantUser =
        AyantUser("guest_${UUID.randomUUID().toString().take(8)}", "Гость", null, AuthProvider.GUEST)
    override fun signOut() {}
    private fun nameFromEmail(e: String) = e.substringBefore("@").replaceFirstChar { it.uppercase() }
    private fun stableId(e: String) = "u_" + e.lowercase().hashCode().toUInt().toString(16)
}

/** Firebase Auth (email + anonymous). Google needs Credential Manager — falls back to mock. */
class FirebaseAuthService : AuthService {
    private val auth = FirebaseAuth.getInstance()

    override fun currentUser(): AyantUser? = auth.currentUser?.let {
        AyantUser(it.uid, it.displayName ?: it.email?.substringBefore("@") ?: "Вы", it.email,
            if (it.isAnonymous) AuthProvider.GUEST else AuthProvider.EMAIL)
    }

    override suspend fun idToken(): String? =
        runCatching { auth.currentUser?.getIdToken(false)?.await()?.token }.getOrNull()

    override suspend fun signInEmail(email: String, password: String): AyantUser {
        val res = auth.signInWithEmailAndPassword(email, password).await()
        val u = res.user!!
        return AyantUser(u.uid, u.displayName ?: nameFromEmail(email), u.email, AuthProvider.EMAIL)
    }

    override suspend fun registerEmail(name: String, email: String, password: String): AyantUser {
        val res = auth.createUserWithEmailAndPassword(email, password).await()
        val u = res.user!!
        return AyantUser(u.uid, name, u.email, AuthProvider.EMAIL)
    }

    override suspend fun signInGoogle(): AyantUser =
        // Google Sign-In (Credential Manager) is a later pass; use anonymous for now.
        continueAsGuest()

    override suspend fun continueAsGuest(): AyantUser {
        val res = auth.signInAnonymously().await()
        return AyantUser(res.user!!.uid, "Гость", null, AuthProvider.GUEST)
    }

    override fun signOut() { auth.signOut() }

    private fun nameFromEmail(e: String) = e.substringBefore("@").replaceFirstChar { it.uppercase() }
}
