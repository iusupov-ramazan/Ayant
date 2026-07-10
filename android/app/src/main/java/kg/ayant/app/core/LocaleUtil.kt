package kg.ayant.app.core

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

/**
 * Per-app language. Stores the choice in prefs and wraps the Activity's base
 * context so all @string resources resolve to the chosen locale (ru/en/ky).
 */
object LocaleUtil {
    private const val PREFS = "ayant.locale"
    private const val KEY = "lang"

    fun currentLang(context: Context): String =
        context.getSharedPreferences(PREFS, 0).getString(KEY, "ru") ?: "ru"

    fun setLang(context: Context, lang: String) {
        context.getSharedPreferences(PREFS, 0).edit().putString(KEY, lang).apply()
    }

    fun wrap(base: Context): Context {
        val locale = Locale(currentLang(base))
        Locale.setDefault(locale)
        val config = Configuration(base.resources.configuration)
        config.setLocale(locale)
        return base.createConfigurationContext(config)
    }
}
