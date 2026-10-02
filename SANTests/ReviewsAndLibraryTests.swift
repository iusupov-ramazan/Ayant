import XCTest
@testable import SAN
import AyantDomain
import AyantFeatures

// Отзывы (модерация, id, скрытые авторы), библиотека в аккаунте и очередь
// записей заведения в кабинете хоста.

// MARK: - Очередь записей заведения

/// Запись заведения «висит», пока тест её не отпустит, — так видно, сколько
/// записей одновременно в полёте и в каком порядке они дошли.
@MainActor
private final class GatedHostRepository: HostRepository {
    /// Отслеживаемое заведение: его записи «висят» до `releaseOne()`.
    /// Остальные (легаси-кэш, который пишет приложение-хост тестов) проходят сразу.
    var trackedName = ""
    var trackedID = ""
    private(set) var saved: [HostVenueDTO] = []
    private(set) var inFlight = 0
    private(set) var maxInFlight = 0
    private var gates: [CheckedContinuation<Void, Never>] = []
    var waiting: Int { gates.count }

    func releaseOne() {
        guard !gates.isEmpty else { return }
        gates.removeFirst().resume()
    }

    func saveVenue(_ dto: HostVenueDTO, ownerID: String) async throws {
        guard dto.id == trackedID || (!trackedName.isEmpty && dto.name == trackedName) else { return }
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        await withCheckedContinuation { gates.append($0) }
        saved.append(dto)
        inFlight -= 1
    }
    func deleteVenue(id: String) async throws {}
    func saveDeal(_ dto: HostDealDTO, ownerID: String) async throws {}
    func deleteDeal(id: String) async throws {}
    func fetchOwnedVenues(ownerID: String) async throws -> [HostVenueDTO] { [] }
    func fetchOwnedDeals(ownerID: String) async throws -> [HostDealDTO] { [] }
    func saveCouponOffer(_ offer: CouponOffer, ownerID: String) async throws {}
    func deleteCouponOffer(id: String) async throws {}
    func fetchOwnedCouponOffers(ownerID: String) async throws -> [CouponOffer] { [] }
    func saveProfile(_ profile: HostProfile, ownerID: String) async throws {}
    func fetchProfile(ownerID: String) async throws -> HostProfile? { nil }
    func queuePushCampaign(headline: String, body: String, city: String,
                           category: String?, venueID: String, dealID: String?, ownerID: String) async throws {}
}

@MainActor
final class HostVenueWriteQueueTests: XCTestCase {

    private var owner = ""
    private static let cacheBases = ["san.host.profile", "san.host.venues", "san.host.deals",
                                     "san.host.campaigns", "san.host.couponOffers",
                                     "san.host.knownVenues", "san.host.knownDeals"]

    override func setUp() {
        super.setUp()
        owner = "queue_\(UUID().uuidString.prefix(8))"
        for base in Self.cacheBases { UserDefaults.standard.removeObject(forKey: base) }
    }

    override func tearDown() {
        for base in Self.cacheBases { UserDefaults.standard.removeObject(forKey: "\(base).\(owner)") }
        super.tearDown()
    }

    private func waitUntil(_ condition: @autoclosure () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func venueFields(name: String) -> HostForms.VenueFields {
        HostForms.VenueFields(name: name, category: .cafe, district: "Центр", address: "Чуй 1",
                              phone: "", emoji: "☕️", latitude: 42.87, longitude: 74.59,
                              openHour: 9, closeHour: 22, imageURL: "", weekHours: Venue.defaultWeek(),
                              pdfMenuURL: "", whatsapp: "", instagram: "", telegram: "",
                              branches: [], loyaltyEnabled: false, loyaltyGoal: 6,
                              loyaltyReward: "", couponsEnabled: false)
    }

    /// Три быстрые правки, пока первая запись в полёте: на сервер уходит
    /// первая и ПОСЛЕДНЯЯ (средняя схлопнута), строго по очереди.
    func testRapidEditsAreSerializedAndCoalesced() async throws {
        let repo = GatedHostRepository()
        repo.trackedName = "Первое"
        let store = HostStore(repo: repo, instagram: FakeInstagramService(),
                              clock: FixedClock(Date(timeIntervalSince1970: 1_700_000_000)))
        store.send(.configure(ownerID: owner))

        store.send(.saveVenue(existing: nil, fields: venueFields(name: "Первое")))
        await waitUntil(repo.waiting == 1)
        let created = try XCTUnwrap(store.state.venues.first { $0.name == "Первое" })
        repo.trackedID = created.id

        store.send(.togglePause(venueID: created.id))              // правка 2
        store.send(.setTodaySpecial(venueID: created.id, text: "Плов"))  // правка 3
        // Пока первая не дошла, вторая не стартует.
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(repo.waiting, 1)

        repo.releaseOne()
        await waitUntil(repo.waiting == 1 && repo.saved.count == 1)
        repo.releaseOne()
        await waitUntil(!store.hasPendingVenueWrites)

        XCTAssertEqual(repo.maxInFlight, 1, "записи одного заведения не должны идти параллельно")
        XCTAssertEqual(repo.saved.count, 2, "промежуточная правка схлопывается в последнюю")
        XCTAssertEqual(repo.saved.first?.name, "Первое")
        XCTAssertEqual(repo.saved.last?.isPaused, true)
        XCTAssertEqual(repo.saved.last?.todaySpecial, "Плов")
    }
}

// MARK: - Библиотека в аккаунте

@MainActor
private final class FakeLibraryRepo: UserLibrarySyncing {
    var remote: [String: UserLibrary] = [:]
    private(set) var writes: [(String, UserLibrary)] = []
    var failFetch = false

    func fetchUserLibrary(userID: String) async throws -> UserLibrary? {
        if failFetch { throw AppError.network }
        return remote[userID]
    }
    func saveUserLibrary(_ library: UserLibrary, userID: String) async throws {
        writes.append((userID, library))
        remote[userID] = library
    }
}

private final class MemoryProfileStorage: ProfileStorage {
    var sets: [String: Set<String>] = [:]
    func loadIDs(key: String) -> Set<String> { sets[key] ?? [] }
    func saveIDs(_ ids: Set<String>, key: String) { sets[key] = ids }
}

@MainActor
final class ProfileLibrarySyncTests: XCTestCase {

    private func makeStore(_ storage: MemoryProfileStorage, _ repo: FakeLibraryRepo) -> ProfileStore {
        ProfileStore(storage: storage, library: repo, writeDelay: .zero)
    }

    func testCleanDeviceTakesServerLibrary() async {
        let storage = MemoryProfileStorage()
        storage.sets[ProfileStorageKey.savedVenues] = ["stale"]
        storage.sets["san.library.owner"] = ["u1"]   // уже сведено раньше, правок нет
        let repo = FakeLibraryRepo()
        repo.remote["u1"] = UserLibrary(savedVenueIDs: ["v1", "v2"], blockedAuthorIDs: ["troll"])
        let store = makeStore(storage, repo)
        store.send(.setUser(id: "u1", name: "А", isGuest: false))
        await store.syncLibrary()

        XCTAssertEqual(store.state.savedVenueIDs, ["v1", "v2"], "удалённое на другом устройстве не воскресает")
        XCTAssertEqual(store.blockedAuthorIDs, ["troll"])
        XCTAssertTrue(repo.writes.isEmpty)
    }

    func testLegacyLocalLibraryIsMergedAndUploaded() async {
        let storage = MemoryProfileStorage()
        storage.sets[ProfileStorageKey.savedVenues] = ["local"]   // версия до синхронизации
        let repo = FakeLibraryRepo()
        repo.remote["u1"] = UserLibrary(savedVenueIDs: ["remote"])
        let store = makeStore(storage, repo)
        store.send(.setUser(id: "u1", name: "А", isGuest: false))
        await store.syncLibrary()

        XCTAssertEqual(store.state.savedVenueIDs, ["local", "remote"])
        XCTAssertEqual(repo.remote["u1"]?.savedVenueIDs, ["local", "remote"])
    }

    func testAnotherUsersLocalLibraryIsNotMerged() async {
        let storage = MemoryProfileStorage()
        storage.sets[ProfileStorageKey.savedVenues] = ["someone-elses"]
        storage.sets["san.library.owner"] = ["u0"]
        storage.sets["san.library.dirty"] = ["1"]
        let repo = FakeLibraryRepo()
        let store = makeStore(storage, repo)
        store.send(.setUser(id: "u1", name: "Б", isGuest: false))
        await store.syncLibrary()

        XCTAssertTrue(store.state.savedVenueIDs.isEmpty)
        XCTAssertNil(repo.remote["u1"]?.savedVenueIDs.first)
    }

    func testChangesAfterSyncAreWrittenAndSignOutDoesNotWipeTheAccount() async {
        let storage = MemoryProfileStorage()
        let repo = FakeLibraryRepo()
        repo.remote["u1"] = UserLibrary()
        let store = makeStore(storage, repo)
        store.send(.setUser(id: "u1", name: "А", isGuest: false))
        await store.syncLibrary()

        store.send(.toggleSave(venueID: "v9"))
        store.blockAuthor(id: "troll", name: "Тролль")
        await store.flushLibrary()
        XCTAssertEqual(repo.remote["u1"]?.savedVenueIDs, ["v9"])
        XCTAssertEqual(repo.remote["u1"]?.blockedAuthorIDs, ["troll"])

        let writesBefore = repo.writes.count
        store.resetForNewUser()                       // выход
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertTrue(store.state.savedVenueIDs.isEmpty)
        XCTAssertEqual(repo.writes.count, writesBefore, "выход не пишет пустую библиотеку в аккаунт")

        // Повторный вход возвращает сохранённое.
        store.send(.setUser(id: "u1", name: "А", isGuest: false))
        await store.syncLibrary()
        XCTAssertEqual(store.state.savedVenueIDs, ["v9"])
        XCTAssertEqual(store.blockedAuthorIDs, ["troll"])
    }

    func testOfflineEditBeforeSyncIsNotLost() async {
        let storage = MemoryProfileStorage()
        storage.sets["san.library.owner"] = ["u1"]
        let repo = FakeLibraryRepo()
        repo.failFetch = true
        repo.remote["u1"] = UserLibrary(favoriteDealIDs: ["d1"])
        let store = makeStore(storage, repo)
        store.send(.setUser(id: "u1", name: "А", isGuest: false))
        await store.syncLibrary()                       // сеть упала
        store.send(.toggleFavorite(dealID: "d2"))       // правка офлайн
        XCTAssertTrue(repo.writes.isEmpty, "до сведения с сервером не пишем")

        repo.failFetch = false
        await store.syncLibrary()
        XCTAssertEqual(store.state.favoriteDealIDs, ["d1", "d2"])
        XCTAssertEqual(repo.remote["u1"]?.favoriteDealIDs, ["d1", "d2"])
    }

    func testCapKeepsListsWithinRuleLimit() {
        let big = Set((0..<600).map { "v\($0)" })
        XCTAssertEqual(UserLibrary(savedVenueIDs: big).capped.savedVenueIDs.count, UserLibrary.maxItems)
    }
}

// MARK: - Отзывы в AppStore

@MainActor
private final class ReviewStubRepo: DataRepository, PhotoReporting {
    var venues: [Venue] = []
    var reviewsByVenue: [Review] = []
    private(set) var savedReviews: [Review] = []
    private(set) var photoReports: [PhotoReport] = []
    var saveError: Error?

    func fetchVenues() async throws -> [Venue] { venues }
    func fetchDeals() async throws -> [Deal] { [] }
    func fetchReviews(venueID: String, limit: Int) async throws -> [Review] {
        reviewsByVenue.filter { $0.venueID == venueID }
    }
    func fetchReviews(venueIDs: [String], limit: Int) async throws -> [Review] { [] }
    func fetchReviews(authorID: String, limit: Int) async throws -> [Review] { [] }
    func saveReview(_ review: Review) async throws {
        if let saveError { throw saveError }
        savedReviews.append(review)
    }
    func deleteReview(id: String) async throws {}
    func updateReviewReply(reviewID: String, reply: HostReply?) async throws {}
    func reportReview(_ report: ReviewReport) async throws {}
    func logRedemption(userID: String, dealID: String, venueID: String) async throws {}
    func recordReferral(inviteeID: String, referrerID: String) async throws {}
    func claimBonusGrants(userID: String) async throws -> Int { 0 }
    func createGiftCoupon(title: String, code: String, fromName: String) async throws {}
    func claimGiftCoupon(code: String) async throws -> GiftInfo? { nil }
    func fetchCategories() async throws -> [RemoteCategory] { [] }
    func reportPhoto(_ report: PhotoReport) async throws { photoReports.append(report) }
}

private final class MemoryPreferences: LocalPreferencesStore {
    private var sets: [String: Set<String>] = [:]
    private var strings: [String: String] = [:]
    func stringSet(forKey key: String) -> Set<String> { sets[key] ?? [] }
    func setStringSet(_ value: Set<String>, forKey key: String) { sets[key] = value }
    func string(forKey key: String) -> String? { strings[key] }
    func setString(_ value: String, forKey key: String) { strings[key] = value }
}

@MainActor
final class ReviewModerationTests: XCTestCase {

    private var repo: ReviewStubRepo!
    private var store: AppStore!

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "san.userReviews")
        UserDefaults.standard.removeObject(forKey: "san.hostReplies")
        repo = ReviewStubRepo()
        repo.venues = [Venue(id: "v1", name: "Navat", category: .cafe, district: "", address: "",
                             phone: "", emoji: "🍽", gradient: [0], rating: 4.5, reviewCount: 2)]
        repo.reviewsByVenue = [
            Review(id: "r_troll", venueID: "v1", authorID: "troll", authorName: "Тролль",
                   rating: 1, text: "плохо", photoEmojis: [], createdAt: .now, updatedAt: .now,
                   photos: ["https://img/troll.jpg"]),
            Review(id: "r_ok", venueID: "v1", authorID: "kind", authorName: "Добрый",
                   rating: 5, text: "хорошо", photoEmojis: [], createdAt: .now, updatedAt: .now),
        ]
        store = AppStore(repository: repo, analytics: FakeAnalyticsService(), push: FakePushService(),
                         rankingLog: FakeRankingEventService(), prefs: MemoryPreferences())
        await store.load()
        store.setCurrentUser(id: "me1", name: "Я", isGuest: false)
        await store.loadReviews(for: repo.venues[0])
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "san.userReviews")
        UserDefaults.standard.removeObject(forKey: "san.hostReplies")
        super.tearDown()
    }

    func testProfanityIsNotPublished() {
        let violation = store.saveReview(venueID: "v1", rating: 1, text: "полная хуйня", photos: [])
        XCTAssertEqual(violation, .profanity)
        XCTAssertNil(store.myReview(venueID: "v1", itemID: nil))
    }

    func testNewReviewUsesDeterministicIDAndNoLocalVerifiedBadge() async {
        XCTAssertNil(store.saveReview(venueID: "v1", rating: 5, text: "Отлично", photos: []))
        let mine = store.myReview(for: repo.venues[0])
        XCTAssertEqual(mine?.id, "me1_v1_venue")
        XCTAssertEqual(mine?.verifiedVisit, false)

        XCTAssertNil(store.saveReview(venueID: "v1", rating: 4, text: "Плов", photos: [],
                                      itemID: "dish", itemName: "Плов"))
        XCTAssertEqual(store.myReview(venueID: "v1", itemID: "dish")?.id, "me1_v1_dish")
        // Отзыв о заведении не перезаписан отзывом о блюде.
        XCTAssertEqual(store.myReview(for: repo.venues[0])?.rating, 5)
    }

    func testFailedPublishRollsBack() async {
        repo.saveError = AppError.network
        XCTAssertNil(store.saveReview(venueID: "v1", rating: 5, text: "Отлично", photos: []))
        let deadline = Date().addingTimeInterval(2)
        while store.myReview(venueID: "v1", itemID: nil) != nil && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNil(store.myReview(venueID: "v1", itemID: nil))
        XCTAssertNotNil(store.toastMessage)
    }

    func testBlockedAuthorIsHiddenEverywhere() {
        let troll = store.reviews.first { $0.authorID == "troll" }!
        store.blockAuthor(of: troll)
        XCTAssertFalse(store.reviews.contains { $0.authorID == "troll" })
        XCTAssertEqual(store.reviews(for: repo.venues[0]).map(\.id), ["r_ok"])
        store.unblockAuthor(id: "troll")
        XCTAssertTrue(store.reviews.contains { $0.authorID == "troll" })
    }

    func testPhotoReportIsSentAndLinkedToItsReview() async {
        store.reportPhoto("https://img/troll.jpg", venueID: "v1", reason: .offensive)
        let deadline = Date().addingTimeInterval(2)
        while repo.photoReports.isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(repo.photoReports.first?.reviewID, "r_troll")
        XCTAssertEqual(repo.photoReports.first?.photoReason, .offensive)
        XCTAssertEqual(repo.photoReports.first?.reporterID, "me1")
    }

    func testSignOutClearsLocalReviewCaches() {
        store.saveReview(venueID: "v1", rating: 5, text: "Отлично", photos: [])
        XCTAssertNotNil(UserDefaults.standard.data(forKey: "san.userReviews"))
        store.resetForNewUser()
        XCTAssertNil(UserDefaults.standard.data(forKey: "san.userReviews"))
        XCTAssertNil(UserDefaults.standard.data(forKey: "san.hostReplies"))
    }
}
