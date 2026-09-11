package kg.ayant.app.data

import com.google.firebase.auth.EmailAuthProvider
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthInvalidCredentialsException
import com.google.firebase.auth.FirebaseAuthInvalidUserException
import com.google.firebase.auth.FirebaseAuthRecentLoginRequiredException
import com.google.firebase.auth.FirebaseAuthUserCollisionException
import com.google.firebase.auth.FirebaseAuthWeakPasswordException
import com.google.firebase.FirebaseNetworkException
import com.google.firebase.FirebaseTooManyRequestsException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kg.ayant.app.domain.AuthValidation
import kg.ayant.app.domain.contract.AuthService
import kg.ayant.app.domain.model.AuthProvider
import kg.ayant.app.domain.model.AyantUser
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

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
    override suspend fun deleteAccount() {}
    override suspend fun discardGuestAccount() {}
    private fun nameFromEmail(e: String) = e.substringBefore("@").replaceFirstChar { it.uppercase() }
    private fun stableId(e: String) = "u_" + e.lowercase().hashCode().toUInt().toString(16)
}

/** Firebase Auth (email + anonymous). Google needs Credential Manager — falls back to mock. */
class FirebaseAuthService(
    /** Нужен Credential Manager для Google Sign-In; передаёт композиционный корень. */
    private val appContext: android.content.Context,
) : AuthService {
    private val auth = FirebaseAuth.getInstance()

    override fun currentUser(): AyantUser? = auth.currentUser?.let {
        val provider = when {
            it.isAnonymous -> AuthProvider.GUEST
            it.providerData.any { p -> p.providerId == "google.com" } -> AuthProvider.GOOGLE
            else -> AuthProvider.EMAIL
        }
        // Гостю подставляем «Гость», а не «Вы»: имя видно в профиле и на
        // гостевых заглушках (на iOS ровно та же подстановка).
        val fallback = if (provider == AuthProvider.GUEST) "Гость" else "Вы"
        AyantUser(it.uid, it.displayName ?: it.email?.substringBefore("@") ?: fallback,
            it.email, provider)
    }

    override suspend fun idToken(): String? =
        runCatching { auth.currentUser?.getIdToken(false)?.await()?.token }.getOrNull()

    override suspend fun signInEmail(email: String, password: String): AyantUser = translating {
        val clean = AuthValidation.normalizedEmail(email)
        val res = auth.signInWithEmailAndPassword(clean, password).await()
        val u = res.user!!
        AyantUser(u.uid, u.displayName ?: nameFromEmail(clean), u.email, AuthProvider.EMAIL)
    }

    /**
     * Регистрация. Если открыт ГОСТЕВОЙ сеанс — не создаём вторую запись, а
     * привязываем почту к текущей анонимной (`link`): uid сохраняется, поэтому
     * накопленное гостем не теряется, а в Auth не остаётся брошенной записи.
     * Зеркалит `registerWithEmail` на iOS.
     */
    override suspend fun registerEmail(name: String, email: String, password: String): AyantUser = translating {
        val clean = AuthValidation.normalizedEmail(email)
        val cleanName = AuthValidation.normalizedName(name)
        val guest = auth.currentUser?.takeIf { it.isAnonymous }
        val res = if (guest != null) {
            guest.linkWithCredential(EmailAuthProvider.getCredential(clean, password)).await()
        } else {
            auth.createUserWithEmailAndPassword(clean, password).await()
        }
        val u = res.user!!
        u.updateProfile(
            com.google.firebase.auth.UserProfileChangeRequest.Builder()
                .setDisplayName(cleanName).build()
        ).await()
        AyantUser(u.uid, cleanName, u.email, AuthProvider.EMAIL)
    }

    override suspend fun signInGoogle(): AyantUser =
        // Credential Manager нужен Android-контекст; берём его из AppConfig —
        // домен про Context не знает, поэтому контракт остаётся без параметров.
        GoogleAuth.signIn(appContext)

    override suspend fun continueAsGuest(): AyantUser = translating {
        val res = auth.signInAnonymously().await()
        AyantUser(res.user!!.uid, "Гость", null, AuthProvider.GUEST)
    }

    override fun signOut() { auth.signOut() }

    /**
     * Полное удаление аккаунта. Каскад по Firestore делает Cloud Function
     * (клиенту правила запрещают чистить `venuePoints`/`coupons`), она же
     * удаляет запись в Auth — локально остаётся только выйти.
     */
    override suspend fun deleteAccount() {
        val user = auth.currentUser ?: return
        if (user.isAnonymous) {                   // серверу чистить нечего
            translating { user.delete().await() }
            signOut()
            return
        }
        val token = runCatching { user.getIdToken(false).await()?.token }.getOrNull()
            ?: throw AuthException("Для удаления аккаунта войдите заново — так мы убеждаемся, что это вы.")
        val code = withContext(Dispatchers.IO) {
            val conn = (URL(DELETE_ACCOUNT_URL).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Authorization", "Bearer $token")
                connectTimeout = 15000; readTimeout = 15000
            }
            conn.outputStream.use { it.write("{}".toByteArray()) }
            runCatching { conn.responseCode }.getOrDefault(0).also { conn.disconnect() }
        }
        when (code) {
            200 -> signOut()
            401 -> throw AuthException("Для удаления аккаунта войдите заново — так мы убеждаемся, что это вы.")
            409 -> throw AuthException("Аккаунт управляет заведениями. Напишите в поддержку, чтобы передать их.")
            // 404 = функция ещё не развёрнута, 503 = недоступна. Для
            // пользователя это одно и то же: сервер молчит.
            404, 503, 0 -> throw AuthException("Сервис удаления недоступен. Попробуйте позже или напишите в поддержку (код $code).")
            else -> throw AuthException("Не удалось удалить аккаунт (код $code). Попробуйте позже.")
        }
    }

    override suspend fun discardGuestAccount() {
        val user = auth.currentUser ?: return
        if (!user.isAnonymous) return
        runCatching { user.delete().await() }
    }

    private fun nameFromEmail(e: String) = e.substringBefore("@").replaceFirstChar { it.uppercase() }

    /**
     * Переводит ошибку Firebase в русское сообщение. Без этого пользователь
     * видел «The password is invalid or the user does not have a password.».
     * Тексты совпадают с `AuthError` на iOS.
     */
    private suspend fun <T> translating(work: suspend () -> T): T =
        try { work() } catch (e: AuthException) { throw e } catch (e: Exception) { throw AuthException(message(e)) }

    private fun message(e: Exception): String = when (e) {
        is FirebaseAuthWeakPasswordException ->
            "Слишком простой пароль — нужно минимум ${AuthValidation.MIN_PASSWORD_LENGTH} символов"
        is FirebaseAuthUserCollisionException ->
            "Эта почта уже зарегистрирована. Войдите или восстановите пароль."
        is FirebaseAuthRecentLoginRequiredException ->
            "Для удаления аккаунта войдите заново — так мы убеждаемся, что это вы."
        is FirebaseAuthInvalidUserException -> when (e.errorCode) {
            "ERROR_USER_DISABLED" -> "Аккаунт заблокирован. Напишите в поддержку."
            else -> "Аккаунт с такой почтой не найден"
        }
        is FirebaseAuthInvalidCredentialsException -> when (e.errorCode) {
            "ERROR_INVALID_EMAIL" -> "Неверный формат почты"
            else -> "Неверная почта или пароль"
        }
        is FirebaseNetworkException -> "Нет связи с сервером. Проверьте интернет."
        is FirebaseTooManyRequestsException -> "Слишком много попыток. Попробуйте через несколько минут."
        else -> e.localizedMessage ?: "Не удалось войти"
    }

    private companion object {
        const val DELETE_ACCOUNT_URL = "https://us-central1-san-25d32.cloudfunctions.net/deleteAccount"
    }
}

/** Ошибка авторизации с готовым русским текстом — его и показывает экран. */
class AuthException(message: String) : Exception(message)
