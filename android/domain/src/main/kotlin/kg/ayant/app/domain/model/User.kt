package kg.ayant.app.domain.model

/*
 * Пользователь и способ входа. Раньше жили в `ui/vm/SessionViewModel.kt`, из-за
 * чего слой данных (AuthService) зависел от слоя фич. Зеркалит `SANUser` на iOS.
 */

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
