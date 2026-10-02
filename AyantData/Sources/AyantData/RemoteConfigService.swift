import Foundation
import FirebaseRemoteConfig
import AyantDomain

// MARK: - Remote Config: выключатели функций и минимальная версия
//
// Ключи в консоли Firebase (Remote Config):
// • `ios_<feature>_enabled` (Boolean, по умолчанию true) — по одному на
//   `RemoteFeature`; false прячет функцию сразу — экраны перерисовываются.
// • `ios_bonus_<game>_enabled` (Boolean, по умолчанию true) — по одному на
//   `BonusGame` (snake, tetris, diamond, 2048); false — игра перестаёт
//   начислять бонусы сразу после загрузки, сама игра остаётся.
// • `ios_bonus_<game>_daily_cap` (Number) — сколько бонусов одна игра может
//   дать игроку за день. 0 / нет ключа — без лимита, кроме Diamond (там 30,
//   см. `BonusCaps`). Применяется сразу после загрузки.
// • Курс игр (Number, `GameRates.Key`): `ios_bonus_minutes_per_bonus` (якорь),
//   `ios_bonus_snake_apples_per_bonus`, `ios_bonus_tetris_lines_per_bonus`,
//   `ios_bonus_diamond_matches_per_bonus`, `ios_bonus_2048_first_tile`,
//   `ios_bonus_time_goal_minutes`, `ios_bonus_time_reward`,
//   `ios_bonus_time_goals_per_day`. 0 / нет ключа — как собрано
//   (`GameRates.resolve`). Применяется сразу после загрузки.
// • `ios_bonus_time_enabled` (Boolean, по умолчанию true) — false выключает
//   начисление за время в приложении сразу; игры не затрагивает.
// • `ios_min_version` (String, «1.0.2») — ниже этой версии приложение
//   закрыто экраном «Обновите приложение» сразу после загрузки.
// • `ios_update_url` (String) — ссылка кнопки «Обновить»; пусто — App Store.
//
// Значения по умолчанию заданы здесь же: без сети и до первой загрузки
// приложение ведёт себя ровно как собрано.

public final class FirebaseRemoteConfigService: RemoteConfigService {
    private let config: RemoteConfig

    /// - Parameter minimumFetchInterval: как часто реально ходить на сервер.
    ///   В отладке 0 (видно правку из консоли сразу), в релизе — час: Remote
    ///   Config ограничивает частоту запросов, а выключатель — не чат.
    public init(minimumFetchInterval: TimeInterval) {
        config = RemoteConfig.remoteConfig()
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = minimumFetchInterval
        config.configSettings = settings
        var defaults: [String: NSObject] = [
            RemoteSettings.Key.minimumVersion: "" as NSString,
            RemoteSettings.Key.updateURL: "" as NSString,
            RemoteSettings.Key.timeEarningEnabled: true as NSNumber,
        ]
        for feature in RemoteFeature.allCases { defaults[feature.remoteKey] = true as NSNumber }
        for game in BonusGame.allCases { defaults[game.remoteKey] = true as NSNumber }
        config.setDefaults(defaults)
    }

    public func current() -> RemoteSettings { snapshot() }

    public func refresh() async -> RemoteSettings? {
        do {
            _ = try await config.fetchAndActivate()
            return snapshot()
        } catch {
            return nil
        }
    }

    /// Слушатель Remote Config в реальном времени: сервер сам сообщает об
    /// опубликованной правке, мы активируем её и отдаём новый снимок.
    public func updates() -> AsyncStream<RemoteSettings> {
        AsyncStream { continuation in
            let registration = config.addOnConfigUpdateListener { [weak self] _, error in
                guard let self, error == nil else { return }
                self.config.activate { _, _ in
                    continuation.yield(self.snapshot())
                }
            }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    private func snapshot() -> RemoteSettings {
        let disabled = RemoteFeature.allCases.filter { !config.configValue(forKey: $0.remoteKey).boolValue }
        let paused = BonusGame.allCases.filter { !config.configValue(forKey: $0.remoteKey).boolValue }
        var caps: [BonusGame: Int] = [:]
        for game in BonusGame.allCases {
            // Значения по умолчанию у ключа нет намеренно: «не задан в
            // консоли» (`.static`) отличается от «задан 0».
            let value = config.configValue(forKey: game.dailyCapKey)
            let remote = value.source == .static ? nil : value.numberValue.intValue
            caps[game] = BonusCaps.effective(game, remote: remote)
        }
        var rates: [String: Double] = [:]
        for key in GameRates.Key.all {
            let value = config.configValue(forKey: key)
            if value.source != .static { rates[key] = value.numberValue.doubleValue }
        }
        return RemoteSettings(
            disabled: Set(disabled),
            bonusPaused: Set(paused),
            bonusDailyCaps: caps,
            gameRates: GameRates.resolve(rates),
            timeEarningPaused: !config.configValue(forKey: RemoteSettings.Key.timeEarningEnabled).boolValue,
            minimumVersion: config.configValue(forKey: RemoteSettings.Key.minimumVersion).stringValue,
            updateURL: config.configValue(forKey: RemoteSettings.Key.updateURL).stringValue)
    }
}

/// Мок: всё включено, обновляться не нужно. Тесты подставляют свои значения.
public final class MockRemoteConfigService: RemoteConfigService {
    public var settings: RemoteSettings
    public init(settings: RemoteSettings = .defaults) { self.settings = settings }
    public func current() -> RemoteSettings { settings }
    public func refresh() async -> RemoteSettings? { settings }
    public func updates() -> AsyncStream<RemoteSettings> { AsyncStream { $0.finish() } }
}
