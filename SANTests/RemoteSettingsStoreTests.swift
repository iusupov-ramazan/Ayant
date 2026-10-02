import XCTest
import AyantDomain
@testable import AyantFeatures

@MainActor
final class RemoteSettingsStoreTests: XCTestCase {

    private final class FakeRemoteConfig: RemoteConfigService {
        var cached: RemoteSettings
        var fresh: RemoteSettings?
        var pushed: [RemoteSettings]
        init(cached: RemoteSettings = .defaults, fresh: RemoteSettings? = nil, pushed: [RemoteSettings] = []) {
            self.cached = cached; self.fresh = fresh; self.pushed = pushed
        }
        func current() -> RemoteSettings { cached }
        func refresh() async -> RemoteSettings? { fresh }
        func updates() -> AsyncStream<RemoteSettings> {
            let items = pushed
            return AsyncStream { c in items.forEach { c.yield($0) }; c.finish() }
        }
    }

    func testCachedMinimumVersionBlocksOnLaunch() {
        let store = RemoteSettingsStore(
            service: FakeRemoteConfig(cached: RemoteSettings(minimumVersion: "1.1")),
            currentVersion: "1.0.1")
        XCTAssertTrue(store.updateRequired, "старая сборка закрыта уже на старте, без сети")
    }

    func testFreshMinimumVersionBlocksImmediately() async {
        let store = RemoteSettingsStore(
            service: FakeRemoteConfig(fresh: RemoteSettings(minimumVersion: "2.0")),
            currentVersion: "1.0.1")
        XCTAssertFalse(store.updateRequired)
        await store.refresh()
        XCTAssertTrue(store.updateRequired, "экран обновления — сразу после загрузки, не со следующего запуска")
    }

    func testKillSwitchAppliesWithoutRelaunch() async {
        let store = RemoteSettingsStore(
            service: FakeRemoteConfig(fresh: RemoteSettings(disabled: [.referrals])),
            currentVersion: "1.0.1")
        XCTAssertTrue(store.latest.isEnabled(.referrals))
        await store.refresh()
        XCTAssertFalse(store.latest.isEnabled(.referrals), "выключили в консоли — пропало сразу, не со следующего запуска")
    }

    func testRealtimeUpdateIsApplied() async {
        let store = RemoteSettingsStore(
            service: FakeRemoteConfig(pushed: [RemoteSettings(disabled: [.menuImport]),
                                               RemoteSettings(minimumVersion: "5.0")]),
            currentVersion: "1.0.1")
        await store.listen()
        XCTAssertTrue(store.latest.isEnabled(.menuImport), "последняя публикация вернула функцию")
        XCTAssertTrue(store.updateRequired, "минимальная версия из потока применилась")
    }

    func testFailedRefreshKeepsUpdateScreen() async {
        let store = RemoteSettingsStore(
            service: FakeRemoteConfig(cached: RemoteSettings(minimumVersion: "9.0"), fresh: nil),
            currentVersion: "1.0.1")
        await store.refresh()
        XCTAssertTrue(store.updateRequired, "нет сети — экран обновления не снимается")
    }
}
