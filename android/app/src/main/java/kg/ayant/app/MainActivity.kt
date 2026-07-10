package kg.ayant.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.viewmodel.compose.viewModel
import kg.ayant.app.core.LocaleUtil
import kg.ayant.app.ui.RootGate
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.AppTheme
import kg.ayant.app.ui.vm.SessionViewModel
import kg.ayant.app.ui.vm.ThemeViewModel

class MainActivity : ComponentActivity() {

    // Holds the current deep-link route; updated on launch and on a new intent
    // (e.g. tapping a push while the app is already running).
    private val deepLink = mutableStateOf<String?>(null)

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(LocaleUtil.wrap(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        deepLink.value = routeFrom(intent?.data)
        setContent {
            val theme: ThemeViewModel = viewModel()
            val dark = when (theme.theme) {
                AppTheme.LIGHT -> false
                AppTheme.DARK -> true
                AppTheme.SYSTEM -> isSystemInDarkTheme()
            }
            AyantTheme(darkTheme = dark) {
                val session: SessionViewModel = viewModel()
                val link by deepLink
                RootGate(session = session, initialDeepLink = link, theme = theme)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        routeFrom(intent.data)?.let { deepLink.value = it }
    }

    /**
     * Maps a deep link to a nav route. Handles both:
     *   ayant://venue/<id>          (scheme=ayant, host=venue, path=/<id>)
     *   https://ayant.kg/venue/<id> (path=/venue/<id>)
     */
    private fun routeFrom(uri: Uri?): String? {
        uri ?: return null
        val segs = uri.pathSegments
        val kind: String
        val id: String
        if (uri.scheme == "ayant") {
            kind = uri.host ?: return null
            id = segs.firstOrNull() ?: return null
        } else {
            if (segs.size < 2) return null
            kind = segs[0]; id = segs[1]
        }
        return when (kind) {
            "venue" -> "venue/$id"
            "deal" -> "deal/$id"
            "invite" -> { deeplinkPrefs().edit().putString("pendingReferrer", id).apply(); null }
            "gift" -> { deeplinkPrefs().edit().putString("pendingGift", id).apply(); null }
            else -> null
        }
    }

    private fun deeplinkPrefs() = getSharedPreferences("ayant.deeplink", 0)
}
