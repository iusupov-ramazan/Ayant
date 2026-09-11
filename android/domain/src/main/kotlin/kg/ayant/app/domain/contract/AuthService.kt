package kg.ayant.app.domain.contract

import kg.ayant.app.domain.model.AyantUser

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
    /**
     * Google Sign-In. Реализация на Firebase сама достаёт нужный Android-контекст —
     * домен про `Context` не знает.
     */
    suspend fun signInGoogle(): AyantUser
    suspend fun continueAsGuest(): AyantUser
    fun signOut()
    /**
     * Удаляет аккаунт целиком: данные в Firestore и запись в Firebase Auth.
     * Обычный выход оставляет и то и другое, поэтому «Удалить аккаунт» обязано
     * звать именно этот метод. Каскад делает Cloud Function `deleteAccount`.
     */
    suspend fun deleteAccount()
    /**
     * Гостевая (анонимная) запись после выхода никому не нужна: войти в неё
     * повторно невозможно, а в Firebase Auth она копится мусором.
     */
    suspend fun discardGuestAccount()
}

