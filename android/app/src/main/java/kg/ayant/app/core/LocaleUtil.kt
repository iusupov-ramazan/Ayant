package kg.ayant.app.core

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

/**
 * Per-app language. Stores the choice in prefs and wraps the Activity's base
 * context so all @string resources resolve to the chosen locale (ru/en/ky).
 *
 * Локаль берётся с регионом (`ru_RU` / `en_US` / `ky_KG`) — как `AppLanguage`
 * на iOS — и публикуется в [AppLanguage.current], откуда её читают форматтеры
 * дат и чисел в `Format.kt`.
 */
object LocaleUtil {
    private const val PREFS = "ayant.locale"
    private const val KEY = "lang"

    @Volatile private var cached: Pair<String, Context>? = null

    fun currentLang(context: Context): String =
        context.getSharedPreferences(PREFS, 0).getString(KEY, AppLanguage.DEFAULT) ?: AppLanguage.DEFAULT

    fun setLang(context: Context, lang: String) {
        context.getSharedPreferences(PREFS, 0).edit().putString(KEY, lang).apply()
        AppLanguage.current = lang
        cached = null
    }

    fun wrap(base: Context): Context {
        val code = currentLang(base)
        AppLanguage.current = code
        // Обёртку над Application кэшируем: её дёргают форматтеры на каждый
        // ценник в списке, а конфигурация приложения между сменами языка не меняется.
        val isApp = base === base.applicationContext
        if (isApp) cached?.let { (c, ctx) -> if (c == code) return ctx }
        val locale = AppLanguage.localeFor(code)
        Locale.setDefault(locale)
        val config = Configuration(base.resources.configuration)
        config.setLocale(locale)
        val wrapped = base.createConfigurationContext(config)
        if (isApp) cached = code to wrapped
        return wrapped
    }
}
