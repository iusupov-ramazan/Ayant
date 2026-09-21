package kg.ayant.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
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
    // Растёт на каждую входящую ссылку (в т. ч. реферал/подарок, у которых нет
    // маршрута): по нему корень забирает отложенные коды сразу, как `onOpenURL`
    // на iOS, а не при следующей смене пользователя.
    private val linkEpoch = mutableIntStateOf(0)

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(LocaleUtil.wrap(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        intent?.data?.let { uri ->
            deepLink.value = routeFrom(uri)
            linkEpoch.intValue++
        }
        setContent {
            val theme: ThemeViewModel = viewModel(factory = kg.ayant.app.core.ayantFactory())
            val themeMode by theme.theme.collectAsState()
            val dark = when (themeMode) {
                AppTheme.LIGHT -> false
                AppTheme.DARK -> true
                AppTheme.SYSTEM -> isSystemInDarkTheme()
            }
            AyantTheme(darkTheme = dark) {
                val session: SessionViewModel = viewModel(factory = kg.ayant.app.core.ayantFactory())
                val link by deepLink
                val epoch by linkEpoch
                RootGate(session = session, initialDeepLink = link, theme = theme, linkEpoch = epoch)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.data?.let { uri ->
            routeFrom(uri)?.let { deepLink.value = it }
            linkEpoch.intValue++
        }
    }

    /**
     * Maps a deep link to a nav route. Mirrors `DeepLinkRouter.handle(url:)`:
     *   ayant://venue/<id> · san://venue/<id>   (custom scheme, host = kind)
     *   https://ayant.kg/venue/<id>             (App Link, path = /kind/<id>)
     * Kinds: `venue`, `deal` → route; `ref` (iOS-share form; `invite` — older
     * Android form) и `gift` → отложенные коды, забираются после входа.
     */
    private fun routeFrom(uri: Uri?): String? {
        uri ?: return null
        val segs = uri.pathSegments
        val kind: String
        val id: String
        if (uri.scheme == "ayant" || uri.scheme == "san") {
            kind = uri.host ?: return null
            id = segs.firstOrNull() ?: return null
        } else {
            if (segs.size < 2) return null
            kind = segs[0]; id = segs[1]
        }
        if (id.isEmpty()) return null
        return when (kind) {
            "venue" -> "venue/$id"
            "deal" -> "deal/$id"
            "ref", "invite" -> { setPendingReferrer(id); null }
            "gift" -> { deeplinkPrefs().edit().putString("pendingGift", id).apply(); null }
            else -> null
        }
    }

    /** Запоминаем, кто пригласил (если ещё не записано). Привязка и бонус — после входа. */
    private fun setPendingReferrer(code: String) {
        val prefs = deeplinkPrefs()
        if (prefs.getString("pendingReferrer", null).isNullOrEmpty()) {
            prefs.edit().putString("pendingReferrer", code).apply()
        }
    }

    private fun deeplinkPrefs() = getSharedPreferences("ayant.deeplink", 0)
}
