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
        // Легаси-кэш без владельца (`san.host.venues` и т. п.) стор УСЫНОВЛЯЕТ
        // при первом входе и дозаливает на сервер — это нужная миграция, но в
        // тестах такой кэш оставляют другие классы (стор без `configure`) или
        // ручной запуск в симуляторе. Тогда «лишние» сохранения в `repo`
        // приходили не из проверяемого сценария, и тест падал через раз.
        for base in Self.cacheBases { UserDefaults.standard.removeObject(forKey: base) }
    }

    private static let cacheBases = ["san.host.profile", "san.host.venues", "san.host.deals",
                                     "san.host.campaigns", "san.host.couponOffers",
                                     "san.host.knownVenues", "san.host.knownDeals"]

    override func tearDown() {
        // Стор пишет в UserDefaults.standard под ключами владельца — чистим.
        let d = UserDefaults.standard
        for base in Self.cacheBases {
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
        // Только про это заведение: легаси-кэш симулятора без владельца стор
        // законно усыновляет и дозаливает (миграция), и `UserDefaults` не
        // всегда даёт его стереть из теста — те сохранения к сценарию не относятся.
        XCTAssertFalse(repo.savedVenues.contains { $0.id == "hv_known" }, "и не заливается обратно")
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

    // MARK: Купоны заведения

    private func couponFields(cost: Int = 500, stock: Int? = nil,
                              isPaused: Bool = false) -> HostForms.CouponFields {
        HostForms.CouponFields(venueID: "hv_1", venueName: "Кафе",
                               title: "Бесплатный капучино", details: "До 12:00",
                               emoji: "☕️", cost: cost, stock: stock, isPaused: isPaused)
    }

    func testSavedCouponOfferGoesToCacheAndServer() async {
        let store = makeStore()
        store.send(.saveCouponOffer(existing: nil, fields: couponFields()))

        XCTAssertEqual(store.state.couponOffers.count, 1)
        let offer = store.state.couponOffers[0]
        XCTAssertEqual(offer.cost, 500)
        XCTAssertEqual(offer.status, .pending, "новый купон уходит на модерацию")
        await waitUntil(self.repo.savedCouponOffers.count == 1)
        XCTAssertEqual(repo.savedCouponOffers.first?.title, "Бесплатный капучино")
    }

    /// Пауза — решение заведения и не трогает модерацию: иначе снятие с
    /// продажи на час стоило бы повторного одобрения.
    func testPauseKeepsModerationStatus() async {
        let store = makeStore()
        store.send(.saveCouponOffer(existing: nil, fields: couponFields()))
        let id = store.state.couponOffers[0].id

        store.send(.toggleCouponPause(id: id))

        XCTAssertTrue(store.state.couponOffers[0].isPaused)
        XCTAssertEqual(store.state.couponOffers[0].status, .pending)
    }

    /// Сервер знает `soldCount` и вердикт модерации — клиент их не выдумывает.
    /// Но купон, которого сервер ещё не видел (запись не дошла), не пропадает
    /// из кабинета, а остаётся и дозаливается — иначе он так и не попадёт в
    /// админ-панель на модерацию.
    func testSyncTakesServerCopyOfCouponsAndKeepsUnsent() async {
        let store = makeStore()
        store.send(.saveCouponOffer(existing: nil, fields: couponFields()))
        let localID = store.state.couponOffers[0].id
        await waitUntil(self.repo.savedCouponOffers.count == 1)
        repo.remoteCouponOffers = [CouponOffer(id: "co_server", venueID: "hv_1",
                                               venueName: "Кафе", title: "С сервера",
                                               cost: 900, stock: 50, soldCount: 12,
                                               statusRaw: ModerationStatus.approved.rawValue)]
        await store.sync()

        XCTAssertEqual(store.state.couponOffers.map(\.id), ["co_server", localID])
        XCTAssertEqual(store.state.couponOffers[0].soldCount, 12)
        XCTAssertEqual(store.state.couponOffers[0].remaining, 38)
        await waitUntil(self.repo.savedCouponOffers.count == 2)
        XCTAssertEqual(repo.savedCouponOffers.last?.id, localID, "неотправленный купон дозаливается")
    }

    /// Форма купона ждёт ответа сервера. Отказ правил (например, правка
    /// одобренного купона, которую сервер требует вернуть на модерацию) —
    /// не «сохранено»: форма получает ошибку, кабинет показывает плашку, а
    /// локальная копия откатывается к той, что лежит на сервере.
    func testDeniedCouponSaveIsReportedAndRolledBack() async {
        let store = makeStore()
        let saved = await store.saveCouponOffer(existing: nil, fields: couponFields(cost: 500))
        XCTAssertNil(saved)
        let original = store.state.couponOffers[0]

        repo.saveError = NSError(domain: "FIRFirestoreErrorDomain", code: 7)   // permission denied
        let error = await store.saveCouponOffer(existing: original, fields: couponFields(cost: 900))

        XCTAssertEqual(error, .permissionDenied, "форма узнаёт об отказе и не закрывается")
        XCTAssertEqual(store.state.couponOffers, [original], "правка, которую сервер не принял, не висит как сохранённая")
        XCTAssertEqual(store.state.sync, .failed(.server(code: HostStore.couponSaveDenied)),
                       "плашка говорит про купон, а не про права на заведение")
    }

    /// Новый купон, который сервер отверг, не остаётся в кабинете призраком.
    func testDeniedNewCouponIsRemoved() async {
        let store = makeStore()
        repo.saveError = NSError(domain: "FIRFirestoreErrorDomain", code: 7)
        let error = await store.saveCouponOffer(existing: nil, fields: couponFields())
        XCTAssertEqual(error, .permissionDenied)
        XCTAssertTrue(store.state.couponOffers.isEmpty)
    }

    /// Без сети купон остаётся на устройстве (новый дозальёт `sync()`), но
    /// форма всё равно узнаёт, что сервер его не получил.
    func testCouponSaveWithoutNetworkKeepsLocalCopyAndReportsIt() async {
        let store = makeStore()
        repo.saveError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let error = await store.saveCouponOffer(existing: nil, fields: couponFields())
        XCTAssertEqual(error, .network)
        XCTAssertEqual(store.state.couponOffers.count, 1)
        XCTAssertEqual(store.state.sync, .failed(.network))
    }

    func testDeletedCouponGoesToServer() async {
        let store = makeStore()
        _ = await store.saveCouponOffer(existing: nil, fields: couponFields())
        let id = store.state.couponOffers[0].id

        let error = await store.deleteCouponOffer(id: id)

        XCTAssertNil(error)
        XCTAssertTrue(store.state.couponOffers.isEmpty)
        XCTAssertEqual(repo.deletedCouponOfferIDs, [id])
    }

    /// Раньше удаление глоталось `try?`: купон пропадал из кабинета, а гости
    /// продолжали его покупать. Теперь он возвращается и ошибка видна.
    func testFailedCouponDeleteRestoresItAndIsVisible() async {
        let failing = CouponDeleteFailingRepository()
        let store = HostStore(repo: failing, instagram: instagram,
                              clock: FixedClock(Date(timeIntervalSince1970: 1_700_000_000)))
        store.send(.configure(ownerID: owner))
        _ = await store.saveCouponOffer(existing: nil, fields: couponFields())
        let offer = store.state.couponOffers[0]

        let error = await store.deleteCouponOffer(id: offer.id)

        XCTAssertEqual(error, .permissionDenied)
        XCTAssertEqual(store.state.couponOffers, [offer], "купон снова в списке — он всё ещё продаётся")
        XCTAssertEqual(store.state.sync, .failed(.server(code: HostStore.couponDeleteDenied)))
    }

    /// `boostedUntil` клиент писать не вправе (правила), и стор больше не
    /// делает вид, что буст включён: ни кэш, ни сервер не трогаются.
    func testBoostVenueDoesNotWriteBoostedUntil() async throws {
        try seedCache(venues: [venue("hv_1")])
        let store = makeStore()
        store.send(.boostVenue(id: "hv_1", until: Date(timeIntervalSince1970: 1_900_000_000)))
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNil(store.state.venues.first?.boostedUntil)
        XCTAssertTrue(repo.savedVenues.isEmpty)
    }

    func testCouponsAreListedPerVenue() {
        let store = makeStore()
        store.send(.saveCouponOffer(existing: nil, fields: couponFields(cost: 300)))
        var other = couponFields(cost: 900)
        other.venueID = "hv_2"
        store.send(.saveCouponOffer(existing: nil, fields: other))

        XCTAssertEqual(store.state.couponOffers(forVenue: "hv_1").map(\.cost), [300])
        XCTAssertEqual(store.state.couponOffers(forVenue: "hv_2").map(\.cost), [900])
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

/// Кабинет, где сервер отказывает в удалении купона (правила). Остальное —
/// пустые заглушки: тест про удаление.
@MainActor
private final class CouponDeleteFailingRepository: HostRepository {
    var offers: [CouponOffer] = []
    func saveVenue(_ dto: HostVenueDTO, ownerID: String) async throws {}
    func deleteVenue(id: String) async throws {}
    func saveDeal(_ dto: HostDealDTO, ownerID: String) async throws {}
    func deleteDeal(id: String) async throws {}
    func fetchOwnedVenues(ownerID: String) async throws -> [HostVenueDTO] { [] }
    func fetchOwnedDeals(ownerID: String) async throws -> [HostDealDTO] { [] }
    func saveCouponOffer(_ offer: CouponOffer, ownerID: String) async throws { offers.append(offer) }
    func deleteCouponOffer(id: String) async throws {
        throw NSError(domain: "FIRFirestoreErrorDomain", code: 7)
    }
    func fetchOwnedCouponOffers(ownerID: String) async throws -> [CouponOffer] { offers }
    func saveProfile(_ profile: HostProfile, ownerID: String) async throws {}
    func fetchProfile(ownerID: String) async throws -> HostProfile? { nil }
    func queuePushCampaign(headline: String, body: String, city: String,
                           category: String?, venueID: String, dealID: String?, ownerID: String) async throws {}
}
