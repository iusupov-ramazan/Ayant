package kg.ayant.app.domain.model

import kg.ayant.app.domain.PointsMath

/**
 * Глобальные настройки приложения, которые правит администратор в панели
 * (Firestore `config/appSettings`). Mirrors `AppSettings.swift`.
 *
 * Имена полей — контракт с iOS, `functions/src/types.ts` (`AppSettingsDoc`)
 * и `docs/admin/index.html` («Настройки»).
 */
data class AppSettings(
    /**
     * Пауза между штампами лояльности на одного гостя в одном заведении, мин.
     * `0` — без паузы. Читает **сервер** (`scanCoupon`, ветка A); клиент держит
     * значение только для подсказок.
     */
    val stampCooldownMinutes: Int = PointsMath.DEFAULT_STAMP_COOLDOWN_MINUTES,
    /** Текст рекламного плейсхолдера (водяной знак «Змейки»). Пусто — локализованный дефолт. */
    val adPlaceholderText: String = "",
) {
    companion object {
        val STAMP_COOLDOWN_RANGE = 0..1440
        val DEFAULT = AppSettings()

        /** Нормализация как в Swift `init`: клэмп паузы, трим текста. */
        fun of(stampCooldownMinutes: Int, adPlaceholderText: String) = AppSettings(
            stampCooldownMinutes = stampCooldownMinutes.coerceIn(STAMP_COOLDOWN_RANGE),
            adPlaceholderText = adPlaceholderText.trim(),
        )
    }
}
