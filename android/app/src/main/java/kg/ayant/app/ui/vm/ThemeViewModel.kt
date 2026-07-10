package kg.ayant.app.ui.vm

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel

/** App theme preference. Mirrors ThemeStore / AppTheme (system/light/dark). */
enum class AppTheme(val title: String) { SYSTEM("Системная"), LIGHT("Светлая"), DARK("Тёмная") }

class ThemeViewModel(app: Application) : AndroidViewModel(app) {
    private val prefs = app.getSharedPreferences("ayant.theme", 0)

    var theme by mutableStateOf(load())
        private set

    fun set(t: AppTheme) {
        theme = t
        prefs.edit().putString("theme", t.name).apply()
    }

    private fun load(): AppTheme =
        runCatching { AppTheme.valueOf(prefs.getString("theme", "SYSTEM") ?: "SYSTEM") }.getOrDefault(AppTheme.SYSTEM)
}
