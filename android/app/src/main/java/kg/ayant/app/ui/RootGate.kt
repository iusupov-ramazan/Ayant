package kg.ayant.app.ui

import androidx.compose.runtime.Composable
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

    when {
        !session.isSignedIn -> AuthScreen(session)
        !onboarded -> OnboardingScreen {
            prefs.edit().putBoolean("onboarded", true).apply()
            onboarded = true
        }
        else -> RootScaffold(session, initialDeepLink = initialDeepLink, theme = theme)
    }
}
