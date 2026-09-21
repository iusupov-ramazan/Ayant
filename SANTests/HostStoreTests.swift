import XCTest
@testable import SAN
import AyantDomain
import AyantFeatures

/// Кабинет хоста не должен терять заведения.
///
/// Реальный случай: заведение с двумя акциями «исчезло» после перевхода.
/// Запись в Firestore когда-то не прошла (ошибка глоталась `try?`), заведение
/// жило только в кэше телефона, а новая версия не смогла прочитать старый кэш.
/// Эти тесты пинят три защиты: терпимое чтение кэша, дозаливку того, чего
/// сервер не видел, и видимую ошибку записи.
@MainActor
final class HostStoreTests: XCTestCase {

    private var repo: FakeHostRepository!
    private var instagram: FakeInstagramService!
    private var owner = ""

    override func setUp() {
        super.setUp()
        repo = FakeHostRepository()
        instagram = FakeInstagramService()
        owner = "test_\(UUID().uuidString.prefix(8))"
    }

    override func tearDown() {
        // Стор пишет в UserDefaults.standard под ключами владельца — чистим.
        let d = UserDefaults.standard
        for base in ["san.host.profile", "san.host.venues", "san.host.deals", "san.host.campaigns",
                     "san.host.knownVenues", "san.host.knownDeals"] {
            d.removeObject(forKey: "\(base).\(owner)")
        }
        super.tearDown()
    }

    private func venue(_ id: String, name: String = "Тест") -> HostVenueDTO {
        HostVenueDTO(id: id, name: name, categoryRaw: "Кафе", district: "Центр", address: "Чуй 1",
                     phone: "", emoji: "☕️", latitude: 42.87, longitude: 74.59,
                     openHour: 9, closeHour: 22, todaySpecial: nil, isPaused: false, isVerified: false)
    }

    /// Кладёт в кэш владельца то, что «оставила прошлая версия приложения».
    private func seedCache(venues: [HostVenueDTO]) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(venues), forKey: "san.host.venues.\(owner)")
    }

    private func makeStore() -> HostStore {
        let store = HostStore(repo: repo, instagram: instagram,
                              clock: FixedClock(Date(timeIntervalSince1970: 1_700_000_000)))
        store.send(.configure(ownerID: owner))
        return store
    }

    /// Ждёт, пока фоновые задачи стора (запись на сервер) не выполнят условие.
    private func waitUntil(_ condition: @autoclosure () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: Кэш

    func testBrokenCacheElementDoesNotWipeTheOthers() throws {
        // Один элемент старой/битой схемы (без id) — остальные должны прочитаться.
        let good = try JSONSerialization.jsonObject(with: JSONEncoder().encode(venue("hv_ok")))
        let data = try JSONSerialization.data(withJSONObject: [good, ["foo": 1]])
        UserDefaults.standard.set(data, forKey: "san.host.venues.\(owner)")

        let store = makeStore()

        XCTAssertEqual(store.state.venues.map(\.id), ["hv_ok"])
    }

    // MARK: Синхронизация

    func testSyncUploadsVenueTheServerNeverSaw() async throws {
        try seedCache(venues: [venue("hv_local")])
        let store = makeStore()
        repo.remoteVenues = []

        await store.sync()
        await waitUntil(self.repo.savedVenues.contains { $0.id == "hv_local" })

        XCTAssertEqual(repo.savedVenues.map(\.id), ["hv_local"], "локальное заведение дозаливается")
        XCTAssertEqual(store.state.venues.map(\.id), ["hv_local"], "и остаётся на экране")
    }

    func testSyncDropsVenueDeletedOnServerAfterItWasKnown() async throws {
        let store = makeStore()
        repo.remoteVenues = [venue("hv_known")]
        await store.sync()
        XCTAssertEqual(store.state.venues.map(\.id), ["hv_known"])

        // Админ удалил заведение на сервере.
        repo.remoteVenues = []
        await store.sync()
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.state.venues, [], "известное серверу и удалённое там — уходит и локально")
        XCTAssertTrue(repo.savedVenues.isEmpty, "и не заливается обратно")
    }

    func testFailedRemoteSaveIsVisibleAndRetriedOnNextSync() async throws {
        try seedCache(venues: [venue("hv_local")])
        let store = makeStore()
        repo.saveError = NSError(domain: "FIRFirestoreErrorDomain", code: 7)   // permission denied

        await store.sync()
        await waitUntil({ if case .failed = store.state.sync { return true }; return false }())

        XCTAssertEqual(store.state.sync, .failed(.permissionDenied), "отказ сервера виден, а не проглочен")
        XCTAssertEqual(store.state.venues.map(\.id), ["hv_local"], "заведение не теряется")

        // Права починили — следующий синк дозаливает без участия пользователя.
        repo.saveError = nil
        await store.sync()
        await waitUntil(self.repo.savedVenues.contains { $0.id == "hv_local" })

        XCTAssertEqual(repo.savedVenues.map(\.id), ["hv_local"])
    }

    // MARK: Instagram

    private func igPost(_ id: String, caption: String = "Новое меню\nПриходите") -> InstagramPost {
        InstagramPost(id: id, caption: caption, kind: .image,
                      previewURL: "https://cdninstagram.test/\(id).jpg",
                      imageURLs: ["https://cdninstagram.test/\(id).jpg"],
                      permalink: "https://instagram.com/p/\(id)",
                      timestamp: Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testSyncInstagramFillsPosts() async {
        instagram.posts = [igPost("p1"), igPost("p2")]
        let store = makeStore()

        store.send(.syncInstagram(venueID: "hv_1"))
        await waitUntil(store.state.instagram(venueID: "hv_1").posts.count == 2)

        XCTAssertEqual(store.state.instagram(venueID: "hv_1").posts.map(\.id), ["p1", "p2"])
        XCTAssertFalse(store.state.instagram(venueID: "hv_1").sync.isSyncing)
    }

    /// Ошибка синхронизации не стирает уже показанные посты — она фаза поверх них.
    func testFailedSyncKeepsPostsAndShowsError() async {
        instagram.posts = [igPost("p1")]
        let store = makeStore()
        store.send(.syncInstagram(venueID: "hv_1"))
        await waitUntil(!store.state.instagram(venueID: "hv_1").posts.isEmpty)

        instagram.failure = .server(code: "reauth_required")
        store.send(.syncInstagram(venueID: "hv_1"))
        await waitUntil({ if case .failed = store.state.instagram(venueID: "hv_1").sync { return true }
                          return false }())

        XCTAssertEqual(store.state.instagram(venueID: "hv_1").sync, .failed(.server(code: "reauth_required")))
        XCTAssertEqual(store.state.instagram(venueID: "hv_1").posts.map(\.id), ["p1"])
    }

    /// Импорт отдаёт форме ПОСТОЯННЫЕ ссылки: у инстаграма они протухают за часы,
    /// и акция с оригинальной ссылкой осталась бы без фото на следующий день.
    func testImportReturnsRehostedImagesOnce() async {
        instagram.posts = [igPost("p1")]
        let store = makeStore()

        store.send(.importInstagramPost(venueID: "hv_1", postID: "p1"))
        await waitUntil(store.pendingImport != nil)

        let imported = store.consumeImport()
        XCTAssertEqual(imported?.postID, "p1")
        XCTAssertEqual(imported?.imageURLs, ["https://cdn.ayant.test/p1.jpg"])
        XCTAssertNil(store.pendingImport, "импорт забирают один раз — иначе форма откроется повторно")
        XCTAssertNil(store.state.instagram(venueID: "hv_1").importing)
    }

    /// Сохранённая из поста акция помечает пост добавленным — второй раз его
    /// не предложат импортировать.
    func testSavedImportedDealMarksPostAsImported() async {
        let store = makeStore()
        store.send(.saveDeal(existing: nil, fields: HostForms.DealFields(
            venueID: "hv_1", type: .novelty, title: "Новое меню", details: "",
            emoji: "🔥", newPrice: nil, discountPercent: nil, endDate: nil,
            isDraft: true, imageURLs: ["https://cdn.ayant.test/p1.jpg"],
            terms: [], sourcePostID: "p1")))

        XCTAssertTrue(store.state.importedPostIDs.contains("p1"))
        XCTAssertEqual(store.state.deals.first?.status, .draft, "импорт открывается черновиком")
    }

    /// Выход из аккаунта не должен оставлять посты чужого заведения на экране.
    func testChangingOwnerClearsInstagramState() async {
        instagram.posts = [igPost("p1")]
        let store = makeStore()
        store.send(.syncInstagram(venueID: "hv_1"))
        await waitUntil(!store.state.instagram(venueID: "hv_1").posts.isEmpty)

        store.send(.configure(ownerID: "someone_else"))

        XCTAssertTrue(store.state.instagram.isEmpty)
        XCTAssertNil(store.pendingImport)
    }

    func testSyncPrefersServerCopyForKnownVenue() async throws {
        try seedCache(venues: [venue("hv_1", name: "Старое имя")])
        let store = makeStore()
        repo.remoteVenues = [venue("hv_1", name: "Имя из админки")]

        await store.sync()

        XCTAssertEqual(store.state.venues.first?.name, "Имя из админки", "сервер — источник истины")
    }
}
