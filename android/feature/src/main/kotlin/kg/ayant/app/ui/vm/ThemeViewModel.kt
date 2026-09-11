package kg.ayant.app.ui.vm

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** App theme preference. Mirrors ThemeStore / AppTheme (system/light/dark). */
enum class AppTheme(val title: String) { SYSTEM("Системная"), LIGHT("Светлая"), DARK("Тёмная") }

/**
 * Тема оформления. `StateFlow`, а не `mutableStateOf`: состояние переживает
 * смерть процесса корректнее и читается в тесте без Compose (см. §4 спеки).
 */
class ThemeViewModel(app: Application) : AndroidViewModel(app) {
    private val prefs = app.getSharedPreferences("ayant.theme", 0)

    private val _theme = MutableStateFlow(load())
    val theme: StateFlow<AppTheme> = _theme.asStateFlow()

    fun set(t: AppTheme) {
        _theme.value = t
        prefs.edit().putString("theme", t.name).apply()
    }

    private fun load(): AppTheme =
        runCatching { AppTheme.valueOf(prefs.getString("theme", "SYSTEM") ?: "SYSTEM") }
            .getOrDefault(AppTheme.SYSTEM)
}
