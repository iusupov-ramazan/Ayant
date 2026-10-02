import Foundation

// MARK: - Удалённые настройки: выключатели и минимальная версия
//
// Две вещи, которые нужно уметь сделать БЕЗ релиза в App Store:
//
// 1. **Выключить сломанную функцию.** `ReleaseFlags` — константы сборки: чтобы
//    спрятать упавший магазин купонов, раньше нужен был новый билд и сутки
//    ревью. Теперь у каждой функции есть удалённый выключатель.
// 2. **Заставить обновиться.** Если старая сборка портит данные (например,
//    пишет поле, которое сервер уже понимает иначе), её можно закрыть экраном
//    «Обновите приложение».
//
// Выключатель может только ВЫКЛЮЧИТЬ функцию, включённую в сборке, — не
// включить спрятанную. Спрятанное спрятано не просто так (у «Продвижения» нет
// оплаты, у Wallet — сертификата), и удалённая галочка не должна открывать
// гостям то, что не готово.

/// Функции, которые можно выключить удалённо. `rawValue` — часть ключа в
/// Firebase Remote Config: `ios_<rawValue>_enabled`. Ключи — данные
/// установленных приложений: не переименовывать.
public enum RemoteFeature: String, CaseIterable, Sendable {
    case searchTab
    case globalBonusWallet
    case referrals
    case promote
    case appleWallet
    case couponShopPurchase
    case instagramImport
    case menuImport

    public var remoteKey: String { "ios_\(rawValue)_enabled" }
}

/// Мини-игры, приносящие бонусы. У каждой — свой удалённый выключатель
/// начисления `ios_bonus_<rawValue>_enabled`: игра остаётся, перестаёт платить.
/// Нужен, когда одну игру начали фармить (нашли дыру в правилах) — гасим
/// только её, не трогая остальные три и весь кошелёк.
///
/// `source` — та же строка, что уходит в `earnBonus` и на сервере режется
/// своими потолками (`BONUS_SOURCE_DAILY_CAPS`): не переименовывать.
public enum BonusGame: String, CaseIterable, Sendable {
    case snake, tetris, diamond
    case game2048 = "2048"

    public var source: String { "game:\(rawValue)" }
    public var remoteKey: String { "ios_bonus_\(rawValue)_enabled" }
    /// Дневной лимит бонусов за эту игру (Number): `ios_bonus_<game>_daily_cap`.
    public var dailyCapKey: String { "ios_bonus_\(rawValue)_daily_cap" }

    /// Бесконечная партия (Diamond) сама не кончается — без лимита она станок
    /// для бонусов, поэтому «без лимита» для неё не бывает.
    public var isEndless: Bool { self == .diamond }

    public init?(source: String) {
        guard source.hasPrefix("game:"),
              let game = BonusGame(rawValue: String(source.dropFirst(5))) else { return nil }
        self = game
    }
}

/// Дневные лимиты бонусов по играм.
///
/// Правило одно для консоли и для кода: положительное число — лимит;
/// 0, отрицательное, мусор или отсутствие ключа — «без лимита», КРОМЕ
/// бесконечных игр: им — лимит по умолчанию (`GameEconomy.endlessDailyBonusCap`).
/// Опечатка в консоли не должна превратить Diamond в ферму.
///
/// Сервер режет независимо (`BONUS_SOURCE_DAILY_CAPS`, `BONUS_DAILY_EARN_CAP`):
/// поднять здесь лимит выше серверного нельзя — сервер не зачислит лишнее.
public enum BonusCaps {
    public static func defaultCap(_ game: BonusGame) -> Int? {
        game.isEndless ? GameEconomy.endlessDailyBonusCap : nil
    }

    /// Лимит игры из значения в консоли (`nil` — ключа нет).
    public static func effective(_ game: BonusGame, remote: Int?) -> Int? {
        if let remote, remote > 0 { return remote }
        return defaultCap(game)
    }

    /// Лимиты без удалённых настроек: только Diamond, 30 в день.
    public static var defaults: [BonusGame: Int] {
        var caps: [BonusGame: Int] = [:]
        for game in BonusGame.allCases { caps[game] = defaultCap(game) }
        return caps
    }
}

/// Снимок удалённых настроек. По умолчанию — «всё разрешено, обновляться не
/// нужно»: если Remote Config недоступен (нет сети, мок-режим), приложение
/// ведёт себя ровно как собрано.
public struct RemoteSettings: Equatable, Sendable {
    /// Функции, выключенные удалённо.
    public var disabled: Set<RemoteFeature>
    /// Игры, за которые бонусы сейчас не начисляются.
    public var bonusPaused: Set<BonusGame>
    /// Дневной лимит бонусов по играм; игры нет в словаре — без лимита.
    public var bonusDailyCaps: [BonusGame: Int]
    /// Курс игр и времени в приложении (`GameRates.Key`). Применяется сразу
    /// после загрузки, но каждая игра берёт снимок в начале партии.
    public var gameRates: GameRates
    /// Начисление за время в приложении выключено (`ios_bonus_time_enabled`
    /// = false). Аварийный выключатель «времени» отдельно от игр: таймер
    /// перестаёт копить, начислений «time» нет, игры платят как прежде.
    public var timeEarningPaused: Bool
    /// Версия (`CFBundleShortVersionString`), ниже которой приложение закрыто
    /// экраном обновления. Пусто — без ограничения.
    public var minimumVersion: String
    /// Куда ведёт кнопка «Обновить». Пусто — страница в App Store по умолчанию.
    public var updateURL: String

    public init(disabled: Set<RemoteFeature> = [], bonusPaused: Set<BonusGame> = [],
                bonusDailyCaps: [BonusGame: Int] = BonusCaps.defaults,
                gameRates: GameRates = .defaults,
                timeEarningPaused: Bool = false,
                minimumVersion: String = "", updateURL: String = "") {
        self.disabled = disabled
        self.bonusPaused = bonusPaused
        self.bonusDailyCaps = bonusDailyCaps
        self.gameRates = gameRates
        self.timeEarningPaused = timeEarningPaused
        self.minimumVersion = minimumVersion
        self.updateURL = updateURL
    }

    public static let defaults = RemoteSettings()

    public func isEnabled(_ feature: RemoteFeature) -> Bool { !disabled.contains(feature) }
    public func earnsBonus(_ game: BonusGame) -> Bool { !bonusPaused.contains(game) }

    /// Нужно ли закрыть эту сборку экраном обновления.
    public func requiresUpdate(currentVersion: String) -> Bool {
        AppVersion.isBelow(currentVersion, minimum: minimumVersion)
    }

    public enum Key {
        public static let minimumVersion = "ios_min_version"
        public static let updateURL = "ios_update_url"
        /// Boolean, по умолчанию true; false — время в приложении не платит.
        public static let timeEarningEnabled = "ios_bonus_time_enabled"
    }
}

/// Сравнение версий вида «1.2.10». Отдельно и чисто, потому что ошибка здесь
/// закрывает приложение всем пользователям: «1.10» < «1.9» строкой, но не
/// версией.
public enum AppVersion {
    /// `true`, только если `current` строго меньше `minimum`. Пустой или
    /// нечитаемый минимум — не ограничение: опечатка в консоли Firebase не
    /// должна запирать всех.
    public static func isBelow(_ current: String, minimum: String) -> Bool {
        guard let min = parts(minimum), let cur = parts(current) else { return false }
        let count = max(min.count, cur.count)
        for i in 0..<count {
            let a = i < cur.count ? cur[i] : 0
            let b = i < min.count ? min[i] : 0
            if a != b { return a < b }
        }
        return false
    }

    /// «1.2.3» → [1, 2, 3]; «», «1.x», «-1» → nil.
    static func parts(_ version: String) -> [Int]? {
        let trimmed = version.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let comps = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        var out: [Int] = []
        for c in comps {
            guard let n = Int(c), n >= 0 else { return nil }
            out.append(n)
        }
        return out
    }
}

/// Источник удалённых настроек. Реализации — `FirebaseRemoteConfigService` и
/// `MockRemoteConfigService` в AyantData.
public protocol RemoteConfigService: AnyObject {
    /// Значения, активированные в прошлый раз (SDK хранит их на диске) —
    /// синхронно, до показа первого экрана.
    func current() -> RemoteSettings
    /// Скачать и активировать свежие значения. `nil` — не получилось
    /// (нет сети, лимит запросов); тогда остаётся `current()`.
    func refresh() async -> RemoteSettings?
    /// Изменения в реальном времени: опубликовали в консоли — открытое
    /// приложение получает новые значения за секунды, без ожидания часового
    /// интервала загрузки. Поток не кончается, пока его слушают.
    func updates() -> AsyncStream<RemoteSettings>
}
