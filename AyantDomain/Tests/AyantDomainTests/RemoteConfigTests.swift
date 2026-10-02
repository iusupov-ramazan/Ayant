import XCTest
@testable import AyantDomain

final class RemoteConfigTests: XCTestCase {

    // MARK: Сравнение версий — ошибка здесь запирает приложение всем

    func testVersionComparesNumbersNotStrings() {
        XCTAssertTrue(AppVersion.isBelow("1.9", minimum: "1.10"), "1.9 < 1.10 по версии, хотя строкой больше")
        XCTAssertFalse(AppVersion.isBelow("1.10", minimum: "1.9"))
    }

    func testVersionMissingPartsCountAsZero() {
        XCTAssertFalse(AppVersion.isBelow("1.0", minimum: "1.0.0"))
        XCTAssertFalse(AppVersion.isBelow("1.0.0", minimum: "1"))
        XCTAssertTrue(AppVersion.isBelow("1.0", minimum: "1.0.1"))
        XCTAssertFalse(AppVersion.isBelow("1.0.1", minimum: "1.0.1"), "равная версия не блокируется")
    }

    func testBadOrEmptyMinimumNeverLocksAnyone() {
        XCTAssertFalse(AppVersion.isBelow("1.0", minimum: ""))
        XCTAssertFalse(AppVersion.isBelow("1.0", minimum: "  "))
        XCTAssertFalse(AppVersion.isBelow("1.0", minimum: "2.x"), "опечатка в консоли — не повод запереть всех")
        XCTAssertFalse(AppVersion.isBelow("1.0", minimum: "-2"))
        XCTAssertFalse(AppVersion.isBelow("1.0", minimum: "2..0"))
    }

    func testUnreadableCurrentVersionIsNotLocked() {
        XCTAssertFalse(AppVersion.isBelow("", minimum: "2.0"))
    }

    // MARK: Снимок настроек

    func testDefaultsAllowEverythingAndNeverForceUpdate() {
        let s = RemoteSettings.defaults
        for f in RemoteFeature.allCases { XCTAssertTrue(s.isEnabled(f)) }
        XCTAssertFalse(s.requiresUpdate(currentVersion: "0.1"))
    }

    func testDisabledFeatureAndMinimumVersion() {
        let s = RemoteSettings(disabled: [.couponShopPurchase], minimumVersion: "1.1")
        XCTAssertFalse(s.isEnabled(.couponShopPurchase))
        XCTAssertTrue(s.isEnabled(.globalBonusWallet))
        XCTAssertTrue(s.requiresUpdate(currentVersion: "1.0.1"))
        XCTAssertFalse(s.requiresUpdate(currentVersion: "1.1.0"))
    }

    func testRemoteKeysAreStable() {
        // Ключи прописаны в консоли Firebase: переименование молча снимет выключатель.
        XCTAssertEqual(RemoteFeature.couponShopPurchase.remoteKey, "ios_couponShopPurchase_enabled")
        XCTAssertEqual(RemoteSettings.Key.minimumVersion, "ios_min_version")
    }

    // MARK: Выключатели начисления по играм

    func testBonusGameKeysAndSourcesAreStable() {
        // source уходит на сервер (`BONUS_SOURCE_DAILY_CAPS` режет «game:diamond»),
        // ключ — в консоль Remote Config: оба нельзя переименовывать.
        XCTAssertEqual(BonusGame.allCases.map(\.source),
                       ["game:snake", "game:tetris", "game:diamond", "game:2048"])
        XCTAssertEqual(BonusGame.game2048.remoteKey, "ios_bonus_2048_enabled")
        XCTAssertEqual(BonusGame.diamond.remoteKey, "ios_bonus_diamond_enabled")
    }

    func testBonusGameParsesOnlyKnownGameSources() {
        for game in BonusGame.allCases { XCTAssertEqual(BonusGame(source: game.source), game) }
        XCTAssertNil(BonusGame(source: "game"))
        XCTAssertNil(BonusGame(source: "time"))
        XCTAssertNil(BonusGame(source: "game:chess"))
    }

    func testBonusPausedSnapshot() {
        let s = RemoteSettings(bonusPaused: [.tetris])
        XCTAssertFalse(s.earnsBonus(.tetris))
        XCTAssertTrue(s.earnsBonus(.snake))
        XCTAssertTrue(RemoteSettings.defaults.earnsBonus(.diamond))
    }

    // MARK: Дневные лимиты по играм

    func testDailyCapRule() {
        XCTAssertEqual(BonusCaps.effective(.snake, remote: 50), 50)
        XCTAssertNil(BonusCaps.effective(.snake, remote: nil), "ключа нет — обычная игра без лимита")
        XCTAssertNil(BonusCaps.effective(.tetris, remote: 0), "0 — без лимита")
        XCTAssertNil(BonusCaps.effective(.game2048, remote: -3))
        XCTAssertEqual(BonusCaps.effective(.diamond, remote: 12), 12)
        XCTAssertEqual(BonusCaps.effective(.diamond, remote: 0), GameEconomy.endlessDailyBonusCap,
                       "бесконечную игру опечаткой в консоли не открыть")
        XCTAssertEqual(BonusCaps.effective(.diamond, remote: nil), GameEconomy.endlessDailyBonusCap)
    }

    func testDefaultsCapOnlyDiamond() {
        XCTAssertEqual(RemoteSettings.defaults.bonusDailyCaps, [.diamond: GameEconomy.endlessDailyBonusCap])
        XCTAssertEqual(BonusGame.game2048.dailyCapKey, "ios_bonus_2048_daily_cap")
    }

    // MARK: Выключатель начисления за время

    func testTimeEarningOnByDefaultAndKeyIsStable() {
        XCTAssertFalse(RemoteSettings.defaults.timeEarningPaused)
        XCTAssertTrue(RemoteSettings(timeEarningPaused: true).timeEarningPaused)
        XCTAssertEqual(RemoteSettings.Key.timeEarningEnabled, "ios_bonus_time_enabled")
    }
}
