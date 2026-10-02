import XCTest
@testable import SAN
import AyantDomain
import AyantFeatures

/// Денежные пути после ревью 2026-10-01: то, что ломалось молча.
///
/// • Повторный скан уже погашенного QR награды — предупреждение, а не «выдайте».
/// • Точка отсчёта «Начислено» — только серверный снимок, не кэш SDK.
/// • Опоздавший ответ списания не всплывает в следующей шторке; второе
///   списание той же награды не уходит параллельно.
/// • Ключ попытки не живёт вечно; `key_reused` не зацикливает «Повторить».
/// • Известное серверу заведение не воскрешается; запись купона без сети
///   не вешает форму.
@MainActor
final class MoneyPathFixesTests: XCTestCase {

    private func waitUntil(_ condition: @autoclosure () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func uid() -> String { "mp_\(UUID().uuidString.prefix(8))" }

    override func setUp() {
        super.setUp()
        // Легаси-кэш кабинета без владельца стор усыновляет и дозаливает —
        // чужие «сохранения» в дубле репозитория путали бы проверки.
        for base in ["san.host.profile", "san.host.venues", "san.host.deals", "san.host.campaigns",
                     "san.host.couponOffers", "san.host.knownVenues", "san.host.knownDeals"] {
            UserDefaults.standard.removeObject(forKey: base)
        }
    }

    override func tearDown() {
        let d = UserDefaults.standard
        for key in d.dictionaryRepresentation().keys where key.hasPrefix("san.points.redeemKeys.mp_") {
            d.removeObject(forKey: key)
        }
        super.tearDown()
    }

    // MARK: Сканер: повтор награды

    func testReplayedRedeemIsAWarningWithReceipt() {
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let replay = ScanResultUI.redeemed(RedeemOutcome(
            ok: true, redeemed: 100, balance: 20, rewardTitle: "Капучино", somOff: nil, errorCode: nil,
            replayed: true, receiptCode: "K7Q2M9", redeemedAt: at))
        XCTAssertTrue(replay.isWarning)
        XCTAssertEqual(replay.title, LS("Эта награда уже выдана"))
        let sub = replay.subtitle ?? ""
        XCTAssertTrue(sub.contains("K7Q2M9"), sub)
        XCTAssertTrue(sub.contains(LS("Не выдавайте награду повторно.")), sub)
        XCTAssertFalse(sub.contains(LS("Выдайте награду гостю")), "повтор не должен звать выдать награду")

        let fresh = ScanResultUI.redeemed(RedeemOutcome(
            ok: true, redeemed: 100, balance: 20, rewardTitle: "Капучино", somOff: nil, errorCode: nil))
        XCTAssertFalse(fresh.isWarning)
        XCTAssertTrue(fresh.ok)
    }

    // MARK: Шторка награды: списание сотрудником

    func testStaffRedeemCountsOnlyExpectedDrop() {
        XCTAssertEqual(StaffRedeemWatch.observe(baseline: 250, balance: 150, expected: [100]), .redeemed(100))
        XCTAssertEqual(StaffRedeemWatch.observe(baseline: 500, balance: 260, expected: [100]), .none,
                       "падение не на цену награды — чужое списание или сгорание")
        XCTAssertEqual(StaffRedeemWatch.observe(baseline: 500, balance: 300, expected: [100, 200]), .redeemed(200),
                       "сумма одного из показанных QR")
        XCTAssertEqual(StaffRedeemWatch.observe(baseline: 250, balance: 300, expected: [100]), .rebase(300))
        XCTAssertEqual(StaffRedeemWatch.observe(baseline: 10, balance: 10, expected: [0]), .none)
    }

    // MARK: Баллы: точка отсчёта

    func testCachedSnapshotIsNotEarnBaseline() async {
        let repo = ControlledPointsRepository()
        let store = PointsStore(repository: repo, clock: FixedClock(Date(timeIntervalSince1970: 1_800_000_000)))
        store.send(.observe(userID: uid()))
        await waitUntil(repo.hasListener)

        repo.emit([], fromCache: true)                         // пустой кэш SDK
        repo.emit([card(balance: 500)], fromCache: false)     // сервер: карта давно есть
        await waitUntil(store.state.cards.value?.first?.balance == 500)
        XCTAssertNil(store.state.pendingEarn, "сервер подтвердил то, что было, — это не начисление")

        repo.emit([card(balance: 530)], fromCache: false)
        await waitUntil(store.state.pendingEarn != nil)
        XCTAssertEqual(store.state.pendingEarn?.delta, 30)
        store.send(.stop)
    }

    func testFirstServerSnapshotWithoutCardStillDetectsFirstEarn() async {
        let repo = ControlledPointsRepository()
        let store = PointsStore(repository: repo, clock: FixedClock(Date(timeIntervalSince1970: 1_800_000_000)))
        store.send(.observe(userID: uid()))
        await waitUntil(repo.hasListener)
        repo.emit([], fromCache: false)
        await waitUntil(store.state.cards.value != nil)
        repo.emit([card(balance: 40)], fromCache: false)
        await waitUntil(store.state.pendingEarn != nil)
        XCTAssertEqual(store.state.pendingEarn?.delta, 40, "первый скан в заведении — тоже «Начислено»")
        store.send(.stop)
    }

    // MARK: Баллы: списание

    func testLateRedeemResponseAfterDismissIsDropped() async {
        let repo = ControlledPointsRepository()
        repo.holdRedeem = true
        let store = PointsStore(repository: repo, clock: FixedClock(Date(timeIntervalSince1970: 1_800_000_000)))
        store.send(.observe(userID: uid()))
        store.send(.redeem(venueID: "v1", rewardID: "r1", pointsToSpend: 0))
        await waitUntil(repo.redeemKeys.count == 1)

        store.send(.dismissRedeem)                              // шторку закрыли посреди запроса
        repo.release(.success(RedeemReceipt(redeemed: 100, balance: 0, rewardTitle: "Кофе")))
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(store.state.redeem, .idle, "итог закрытой шторки не всплывает в следующей")
        store.send(.stop)
    }

    func testSecondRedeemOfSameRewardWaitsForFirst() async {
        let repo = ControlledPointsRepository()
        repo.holdRedeem = true
        let store = PointsStore(repository: repo, clock: FixedClock(Date(timeIntervalSince1970: 1_800_000_000)))
        store.send(.observe(userID: uid()))
        store.send(.redeem(venueID: "v1", rewardID: "r1", pointsToSpend: 0))
        await waitUntil(repo.redeemKeys.count == 1)
        store.send(.dismissRedeem)
        store.send(.redeem(venueID: "v1", rewardID: "r1", pointsToSpend: 0))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(repo.redeemKeys.count, 1, "параллельного второго списания нет")
        XCTAssertTrue(store.state.redeem.isWorking, "экран снова ждёт первое")

        repo.release(.success(RedeemReceipt(redeemed: 100, balance: 0, rewardTitle: "Кофе")))
        await waitUntil({ if case .done = store.state.redeem { return true }; return false }())
        if case .done = store.state.redeem {} else { XCTFail("ответ первой попытки показан") }
        store.send(.stop)
    }

    func testAbandonedRedeemKeyExpires() async {
        let repo = ControlledPointsRepository()
        repo.result = .failure(.network)
        let clock = FixedClock(Date(timeIntervalSince1970: 1_800_000_000))
        let store = PointsStore(repository: repo, clock: clock)
        store.send(.observe(userID: uid()))

        store.send(.redeem(venueID: "v1", rewardID: "r1", pointsToSpend: 0))
        await waitUntil(repo.redeemKeys.count == 1)
        await waitUntil({ if case .failed = store.state.redeem { return true }; return false }())
        store.send(.redeem(venueID: "v1", rewardID: "r1", pointsToSpend: 0))
        await waitUntil(repo.redeemKeys.count == 2)
        XCTAssertEqual(repo.redeemKeys[0], repo.redeemKeys[1], "повтор в окне — тот же ключ")
        await waitUntil({ if case .failed = store.state.redeem { return true }; return false }())

        clock.advance(by: 31 * 60)
        store.send(.redeem(venueID: "v1", rewardID: "r1", pointsToSpend: 0))
        await waitUntil(repo.redeemKeys.count == 3)
        XCTAssertNotEqual(repo.redeemKeys[2], repo.redeemKeys[0], "брошенная попытка — новый ключ")
        store.send(.stop)
    }

    func testKeyReusedRetryUsesFreshKey() async {
        let repo = ControlledPointsRepository()
        repo.result = .failure(.server(code: "key_reused"))
        let store = PointsStore(repository: repo, clock: FixedClock(Date(timeIntervalSince1970: 1_800_000_000)))
        store.send(.observe(userID: uid()))
        store.send(.redeem(venueID: "v1", rewardID: "r1", pointsToSpend: 0))
        await waitUntil({ if case .failed = store.state.redeem { return true }; return false }())
        store.send(.redeem(venueID: "v1", rewardID: "r1", pointsToSpend: 0))
        await waitUntil(repo.redeemKeys.count == 2)
        XCTAssertNotEqual(repo.redeemKeys[0], repo.redeemKeys[1])
        store.send(.stop)
    }

    // MARK: Штампы: точка отсчёта

    func testLoyaltyCachedSnapshotIsNotBaseline() async {
        UserDefaults.standard.removeObject(forKey: "san.loyalty")
        let backend = LiveLoyaltyCouponService()
        let store = LoyaltyStore(backend: backend)
        store.observe(userID: uid())
        await waitUntil(backend.hasListener)

        backend.emit([], fromCache: true)
        backend.emit([LoyaltyCard(venueID: "v1", venueName: "Кафе", stamps: 3, goal: 6)], fromCache: false)
        await waitUntil(store.cards.first?.stamps == 3)
        XCTAssertNil(store.pendingStamp, "серверный снимок после пустого кэша — не штамп")

        backend.emit([LoyaltyCard(venueID: "v1", venueName: "Кафе", stamps: 4, goal: 6)], fromCache: false)
        await waitUntil(store.pendingStamp != nil)
        XCTAssertEqual(store.pendingStamp?.stamps, 4)
        store.resetForNewUser()
    }

    // MARK: Кабинет хоста

    func testKnownVenueIsNotRecreatedWhenDeletedOnServer() async throws {
        let owner = "mp_owner_\(UUID().uuidString.prefix(6))"
        defer {
            for base in ["san.host.venues", "san.host.knownVenues", "san.host.knownDeals", "san.host.deals",
                         "san.host.couponOffers", "san.host.profile", "san.host.campaigns"] {
                UserDefaults.standard.removeObject(forKey: "\(base).\(owner)")
            }
        }
        let repo = CreateAwareHostRepository()
        repo.remoteVenues = [venue("hv_1")]
        let store = HostStore(repo: repo, instagram: FakeInstagramService(),
                              clock: FixedClock(Date(timeIntervalSince1970: 1_700_000_000)))
        store.send(.configure(ownerID: owner))
        await store.sync()                                  // сервер отдал hv_1 → «известно»

        repo.remoteVenues = []                              // админ удалил
        store.send(.togglePause(venueID: "hv_1"))
        await waitUntil(repo.allowCreateByID["hv_1"] != nil)
        XCTAssertEqual(repo.allowCreateByID["hv_1"], false, "известное заведение не создаётся заново")
        await waitUntil(store.state.sync == .failed(.server(code: HostStore.venueDeletedOnServer)))
        XCTAssertFalse(store.state.venues.contains { $0.id == "hv_1" }, "sync убрал удалённое заведение")
    }

    func testCouponSaveWithoutNetworkDoesNotHangForm() async {
        let owner = "mp_owner_\(UUID().uuidString.prefix(6))"
        defer {
            for base in ["san.host.couponOffers", "san.host.venues", "san.host.knownVenues", "san.host.knownDeals",
                         "san.host.deals", "san.host.profile", "san.host.campaigns"] {
                UserDefaults.standard.removeObject(forKey: "\(base).\(owner)")
            }
        }
        let repo = CreateAwareHostRepository()
        repo.hangCouponWrites = true
        let store = HostStore(repo: repo, instagram: FakeInstagramService(),
                              clock: FixedClock(Date(timeIntervalSince1970: 1_700_000_000)))
        store.send(.configure(ownerID: owner))
        store.couponWriteTimeout = 0.1
        let fields = HostForms.CouponFields(venueID: "hv_1", venueName: "Кафе", title: "Кофе", details: "",
                                            emoji: "☕️", imageURL: "", cost: 300, stock: nil,
                                            expiresAt: nil, isPaused: false)
        let result = await store.saveCouponOffer(existing: nil, fields: fields)
        XCTAssertEqual(result, .server(code: HostStore.couponWriteQueued))
        XCTAssertEqual(store.state.couponOffers.count, 1, "купон остаётся в кабинете, запись в очереди")
        XCTAssertEqual(store.state.sync, .failed(.server(code: HostStore.couponWriteQueued)))
    }

    // MARK: Помощники

    private func card(balance: Int) -> VenuePointsCard {
        VenuePointsCard(venueID: "v1", venueName: "Кафе", balance: balance)
    }

    private func venue(_ id: String) -> HostVenueDTO {
        HostVenueDTO(id: id, name: "Тест", categoryRaw: "Кафе", district: "Центр", address: "Чуй 1",
                     phone: "", emoji: "☕️", latitude: 42.87, longitude: 74.59,
                     openHour: 9, closeHour: 22, todaySpecial: nil, isPaused: false, isVerified: false)
    }
}

// MARK: - Дубли

/// Баллы: снимки с пометкой «из кэша» и списание, которое тест отпускает сам.
@MainActor
private final class ControlledPointsRepository: PointsRepository {
    private var continuation: AsyncStream<Result<LiveSnapshot<[VenuePointsCard]>, AppError>>.Continuation?
    var hasListener: Bool { continuation != nil }
    var redeemKeys: [String] = []
    var result: Result<RedeemReceipt, AppError> = .success(RedeemReceipt(redeemed: 10, balance: 0, rewardTitle: "Т"))
    var holdRedeem = false
    private var held: CheckedContinuation<Result<RedeemReceipt, AppError>, Never>?

    nonisolated func cards(userID: String) -> AsyncStream<Result<[VenuePointsCard], AppError>> {
        AsyncStream { $0.finish() }
    }

    nonisolated func liveCards(userID: String) -> AsyncStream<Result<LiveSnapshot<[VenuePointsCard]>, AppError>> {
        AsyncStream { continuation in
            Task { @MainActor in self.continuation = continuation }
        }
    }

    func emit(_ cards: [VenuePointsCard], fromCache: Bool) {
        continuation?.yield(.success(LiveSnapshot(value: cards, isFromCache: fromCache)))
    }

    func redeem(venueID: String, userID: String, rewardID: String,
                pointsToSpend: Int, idempotencyKey: String) async -> Result<RedeemReceipt, AppError> {
        redeemKeys.append(idempotencyKey)
        guard holdRedeem else { return result }
        return await withCheckedContinuation { held = $0 }
    }

    func release(_ value: Result<RedeemReceipt, AppError>) {
        held?.resume(returning: value)
        held = nil
    }

    func ledger(userID: String, venueID: String, limit: Int) async -> Result<[PointsLedgerEntry], AppError> {
        .success([])
    }
}

/// Купоны/штампы: живой поток штампов с пометкой «из кэша».
private final class LiveLoyaltyCouponService: CouponService {
    private var continuation: AsyncStream<LiveSnapshot<[LoyaltyCard]>>.Continuation?
    var hasListener: Bool { continuation != nil }
    func emit(_ cards: [LoyaltyCard], fromCache: Bool) {
        continuation?.yield(LiveSnapshot(value: cards, isFromCache: fromCache))
    }
    func liveLoyaltyCards(userID: String) -> AsyncStream<LiveSnapshot<[LoyaltyCard]>> {
        AsyncStream { self.continuation = $0 }
    }

    func saveCoupon(_ coupon: Coupon, userID: String) async throws {}
    func fetchGlobalRewards() async throws -> [Reward] { [] }
    func fetchCouponOffers(venueID: String) async throws -> [CouponOffer] { [] }
    func fetchApprovedCouponOffers() async throws -> [CouponOffer] { [] }
    func fetchCoupons(userID: String) async throws -> [Coupon] { [] }
    func coupons(userID: String) -> AsyncStream<[Coupon]> { AsyncStream { $0.finish() } }
    func fetchLoyaltyCards(userID: String) async throws -> [LoyaltyCard] { [] }
    func loyaltyCards(userID: String) -> AsyncStream<[LoyaltyCard]> { AsyncStream { $0.finish() } }
    func fetchVenuePoints(userID: String) async throws -> [VenuePointsCard] { [] }
    func scanCoupon(code: String, venueID: String, idToken: String,
                    billAmount: Int?, bandIndex: Int?, idempotencyKey: String,
                    cardID: String?) async throws -> ScanOutcome {
        throw URLError(.unsupportedURL)
    }
    func redeemVenuePoints(venueID: String, userID: String, rewardId: String,
                           pointsToSpend: Int, idToken: String,
                           idempotencyKey: String, nonce: String?) async throws -> RedeemOutcome {
        throw URLError(.unsupportedURL)
    }
}

/// Кабинет: записывает `allowCreate`, «удаляет» заведения и умеет «висеть»
/// без сети на записи купона (как Firestore, пока сервер не подтвердил).
@MainActor
private final class CreateAwareHostRepository: HostRepository {
    var remoteVenues: [HostVenueDTO] = []
    var allowCreateCalls: [Bool] = []
    var allowCreateByID: [String: Bool] = [:]
    var hangCouponWrites = false

    func saveVenue(_ dto: HostVenueDTO, ownerID: String) async throws {
        try await saveVenue(dto, ownerID: ownerID, allowCreate: true)
    }
    func saveVenue(_ dto: HostVenueDTO, ownerID: String, allowCreate: Bool) async throws {
        allowCreateCalls.append(allowCreate)
        allowCreateByID[dto.id] = allowCreate
        if !allowCreate, !remoteVenues.contains(where: { $0.id == dto.id }) { throw AppError.notFound }
    }
    func deleteVenue(id: String) async throws {}
    func saveDeal(_ dto: HostDealDTO, ownerID: String) async throws {}
    func deleteDeal(id: String) async throws {}
    func fetchOwnedVenues(ownerID: String) async throws -> [HostVenueDTO] { remoteVenues }
    func fetchOwnedDeals(ownerID: String) async throws -> [HostDealDTO] { [] }
    func saveCouponOffer(_ offer: CouponOffer, ownerID: String) async throws {
        if hangCouponWrites { try await Task.sleep(nanoseconds: 5_000_000_000) }
    }
    func deleteCouponOffer(id: String) async throws {}
    func fetchOwnedCouponOffers(ownerID: String) async throws -> [CouponOffer] { [] }
    func saveProfile(_ profile: HostProfile, ownerID: String) async throws {}
    func fetchProfile(ownerID: String) async throws -> HostProfile? { nil }
    func queuePushCampaign(headline: String, body: String, city: String,
                           category: String?, venueID: String, dealID: String?, ownerID: String) async throws {}
}
