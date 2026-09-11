package kg.ayant.app.ui

import androidx.compose.animation.Crossfade
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.key
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import kg.ayant.app.ui.auth.AuthScreen
import kg.ayant.app.ui.navigation.RootScaffold
import kg.ayant.app.ui.onboarding.OnboardingScreen
import kg.ayant.app.ui.vm.SessionViewModel
import kg.ayant.app.ui.vm.ThemeViewModel

/**
 * Top-level gate: Auth → Onboarding → main app. Mirrors SANApp gating
 * (isSignedIn ? SignedInRootView : AuthView) and the onboarded flag.
 */
@Composable
fun RootGate(session: SessionViewModel, initialDeepLink: String? = null, theme: ThemeViewModel? = null) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("ayant.flags", 0) }
    var onboarded by rememberSaveable { mutableStateOf(prefs.getBoolean("onboarded", false)) }
    // Именно collectAsState: `session.isSignedIn` — обычный getter по
    // `_state.value`, чтение которого НЕ подписывает композицию. Выход теперь
    // асинхронный (сначала отписка от push, потом Firebase), и без подписки
    // экран остался бы висеть на уже закрытой сессии.
    val state by session.state.collectAsState()

    // Ключ пересборки корня: пользователь и его гостевой статус. Регистрация
    // гостя сохраняет uid (запись связывается), но приложение после неё —
    // другое, с открытыми QR и бонусами, поэтому статус входит в ключ.
    // Crossfade даёт анимированную подмену вместо мгновенной перерисовки.
    val rootKey = "${state.user?.id ?: "none"}-${state.isSignedIn}-${state.isGuest}"

    Crossfade(targetState = rootKey, label = "root") { key ->
        // Ветку выбираем по СОСТОЯНИЮ, а не по ключу: key нужен только чтобы
        // Crossfade понял, что корень сменился.
        when {
            !state.isSignedIn -> AuthScreen(session)
            !onboarded -> OnboardingScreen {
                prefs.edit().putBoolean("onboarded", true).apply()
                onboarded = true
            }
            else -> key(key) {
                RootScaffold(session, initialDeepLink = initialDeepLink, theme = theme)
            }
        }
    }
}
