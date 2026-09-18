import Foundation

/// Глобальные настройки приложения, которые правит администратор в панели
/// (Firestore `config/appSettings`). Один документ на весь продукт — в отличие
/// от конфига баллов, который живёт на заведении.
///
/// Зеркало: `android/domain/.../model/AppSettings.kt`, `functions/src/types.ts`
/// (`AppSettingsDoc`), `docs/admin/index.html` («Настройки»). Имена полей —
/// контракт для всех четырёх.
public struct AppSettings: Equatable, Sendable {
    /// Пауза между штампами лояльности на одного гостя в одном заведении, мин.
    /// `0` — без паузы. Читает **сервер** (`scanCoupon`, ветка A); клиент
    /// держит значение только для подсказок. Дефолт —
    /// `PointsMath.defaultStampCooldownMinutes`, как и в фикстуре.
    public var stampCooldownMinutes: Int

    /// Текст рекламного плейсхолдера (водяной знак на поле «Змейки»,
    /// рекламный слот). Пусто — экран показывает локализованный дефолт.
    public var adPlaceholderText: String

    public static let stampCooldownRange = 0...1440

    public static let `default` = AppSettings(
        stampCooldownMinutes: PointsMath.defaultStampCooldownMinutes,
        adPlaceholderText: ""
    )

    public init(stampCooldownMinutes: Int, adPlaceholderText: String) {
        self.stampCooldownMinutes = min(max(stampCooldownMinutes, Self.stampCooldownRange.lowerBound),
                                        Self.stampCooldownRange.upperBound)
        self.adPlaceholderText = adPlaceholderText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
