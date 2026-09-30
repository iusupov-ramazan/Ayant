import XCTest
@testable import SAN
import AyantDomain
import AyantFeatures

/// Клиент серверного кошелька бонусов: перенос баланса, очередь начислений,
/// покупка через сервер и ключ идемпотентности при обрыве сети.
///
/// Сам сервер проверяется в `functions/test/bonusWallet.test.js`; здесь —
/// что клиент ничего не решает сам: не списывает локально и не теряет
/// начисления, если сеть пропала.
@MainActor
final class BonusWalletTests: XCTestCase {

    private var wallet: FakeBonusWallet!
    private var engine: BonusEngine!

    override func setUp() {
        super.setUp()
        wallet = FakeBonusWallet()
        engine = BonusEngine(clock: FixedClock(Date(timeIntervalSince1970: 1_700_000_000)), wallet: wallet)
        // Кошелёк и очередь лежат в UserDefaults — начинаем с чистого.
        engine.resetForNewUser()
    }

    private func waitUntil(_ condition: @autoclosure () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testAttachMigratesDeviceBalanceOnce() async {
        engine.balance = 250          // баланс, накопленный до серверного кошелька
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.syncCalls.count == 1)
        XCTAssertEqual(wallet.syncCalls, [250])
        XCTAssertEqual(engine.balance, 250)
    }

    func testGameplayGoesToServerNotToTheDevice() async {
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        XCTAssertEqual(engine.awardGameplay(5, source: "game:snake"), 5)
        XCTAssertEqual(engine.balance, 5, "«+5» видно сразу, до ответа сервера")
        await waitUntil(self.wallet.earnCalls.count == 1)
        XCTAssertEqual(wallet.earnCalls.first?.amount, 5)
        XCTAssertEqual(wallet.earnCalls.first?.source, "game:snake")
        await waitUntil(self.engine.balance == 5 && self.wallet.serverBalance == 5)
    }

    func testServerCapCorrectsOptimisticBalance() async {
        wallet.earnCap = 3
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        engine.awardGameplay(10)
        await waitUntil(self.wallet.earnCalls.count == 1)
        // Сервер дал 3 из 10 — на экране то, что дал сервер.
        await waitUntil(self.engine.balance == 3)
        XCTAssertEqual(engine.balance, 3)
    }

    func testEarnSurvivesNetworkLossAndRetriesWithSameKey() async {
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        wallet.offline = true
        engine.awardGameplay(4)
        await waitUntil(self.wallet.earnCalls.count == 1)
        XCTAssertEqual(wallet.serverBalance, 0, "без сети сервер ничего не получил")
        let firstKey = wallet.earnCalls[0].key

        wallet.offline = false
        engine.retryPending()
        await waitUntil(self.wallet.serverBalance == 4)
        XCTAssertEqual(wallet.earnCalls.last?.key, firstKey, "повтор — с тем же ключом")
        XCTAssertEqual(engine.balance, 4)
    }

    func testServerErrorKeepsEarnQueued() async {
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        wallet.earnError = "earn_failed"          // 500 на сервере — не повод терять бонусы
        engine.awardGameplay(6, source: "game:tetris")
        await waitUntil(self.wallet.earnCalls.count == 1)
        wallet.earnError = nil
        engine.retryPending()
        await waitUntil(self.wallet.serverBalance == 6)
        XCTAssertEqual(wallet.serverBalance, 6)
        XCTAssertEqual(wallet.earnCalls.map(\.key).count, 2)
        XCTAssertEqual(wallet.earnCalls[0].key, wallet.earnCalls[1].key)
    }

    func testGiftIsClaimedThroughServerWithVenue() async {
        let store = CouponStore(backend: StubCouponService(), wallet: wallet)
        store.resetForNewUser()
        let result = await store.claimGift(code: "GIFT-ABCDEFGH")
        guard case .coupon(let c)? = result else { return XCTFail("ожидался купон") }
        XCTAssertEqual(c.venueID, "v9", "подарок гасится у заведения")
        XCTAssertEqual(store.coupons.first?.code, c.code)
    }

    func testLocalSpendIsDisabledWithServerWallet() {
        engine.balance = 500
        XCTAssertFalse(engine.spend(100), "списание только на сервере")
        XCTAssertEqual(engine.balance, 500)
    }

    func testReferralBonusIsNotAddedLocally() {
        engine.addFromGame(100)
        XCTAssertEqual(engine.balance, 0, "грант зачисляет сервер (bonusWalletSync)")
    }

    // MARK: Покупка

    private let offer = CouponOffer(id: "co1", venueID: "v1", venueName: "Кафе", title: "Капучино",
                                    cost: 120, statusRaw: ModerationStatus.approved.rawValue)

    func testBuyGoesThroughServerAndAddsCoupon() async {
        let store = CouponStore(backend: StubCouponService(), wallet: wallet)
        store.resetForNewUser()
        wallet.buyOutcome = BonusPurchaseOutcome(
            ok: true,
            coupon: Coupon(id: "c1", title: "Капучино", code: "AYANT-ABC123", createdAt: .now,
                           venueID: "v1", venueName: "Кафе", kind: "offer"),
            balance: 80)
        let result = await store.buy(offer, bonus: engine)
        XCTAssertEqual(result, .coupon(wallet.buyOutcome!.coupon!))
        XCTAssertEqual(store.coupons.first?.code, "AYANT-ABC123")
        XCTAssertEqual(engine.balance, 80, "баланс — из ответа сервера")
        XCTAssertEqual(wallet.buyCalls.first?.purchase, .offer(id: "co1"))
    }

    func testBuyFailureReportsServerCode() async {
        let store = CouponStore(backend: StubCouponService(), wallet: wallet)
        store.resetForNewUser()
        wallet.buyOutcome = BonusPurchaseOutcome(ok: false, errorCode: "sold_out")
        let result = await store.buy(offer, bonus: engine)
        XCTAssertEqual(result, .failed("sold_out"))
        XCTAssertTrue(store.coupons.isEmpty)
    }

    func testBuyRetryAfterNetworkLossReusesKey() async {
        let store = CouponStore(backend: StubCouponService(), wallet: wallet)
        store.resetForNewUser()
        wallet.offline = true
        let first = await store.buy(offer, bonus: engine)
        XCTAssertEqual(first, .failed("network"))

        wallet.offline = false
        wallet.buyOutcome = BonusPurchaseOutcome(ok: true, coupon: Coupon(
            id: "c1", title: "Капучино", code: "AYANT-ABC123", createdAt: .now, venueID: "v1"), balance: 0)
        _ = await store.buy(offer, bonus: engine)
        XCTAssertEqual(wallet.buyCalls.count, 2)
        XCTAssertEqual(wallet.buyCalls[0].key, wallet.buyCalls[1].key,
                       "ответ мог потеряться после списания — повтор с тем же ключом не купит второй раз")

        // Следующая, новая покупка — уже с новым ключом.
        _ = await store.buy(offer, bonus: engine)
        XCTAssertNotEqual(wallet.buyCalls[2].key, wallet.buyCalls[1].key)
    }
}

// MARK: - Фейки

/// Кошелёк в памяти: ведёт баланс как сервер (перенос один раз, потолок
/// начисления), умеет «терять сеть».
final class FakeBonusWallet: BonusWalletService {
    var serverBalance = 0
    var hasWallet = false
    var offline = false
    var earnCap = Int.max
    var buyOutcome: BonusPurchaseOutcome?
    private(set) var syncCalls: [Int] = []
    private(set) var earnCalls: [(amount: Int, source: String, key: String)] = []
    private(set) var buyCalls: [(purchase: BonusPurchase, key: String)] = []
    private var seenEarnKeys: Set<String> = []

    func balance(userID: String) -> AsyncStream<Int> { AsyncStream { $0.finish() } }

    func sync(localBalance: Int) async throws -> Int {
        if offline { throw URLError(.notConnectedToInternet) }
        syncCalls.append(localBalance)
        if !hasWallet { hasWallet = true; serverBalance = localBalance }
        return serverBalance
    }

    func earn(amount: Int, source: String, idempotencyKey: String) async throws -> BonusEarnOutcome {
        earnCalls.append((amount, source, idempotencyKey))
        if offline { throw URLError(.notConnectedToInternet) }
        guard hasWallet else { return BonusEarnOutcome(ok: false, errorCode: "no_wallet") }
        if let earnError { return BonusEarnOutcome(ok: false, errorCode: earnError) }
        if seenEarnKeys.insert(idempotencyKey).inserted {
            serverBalance += min(amount, earnCap)
        }
        return BonusEarnOutcome(ok: true, granted: min(amount, earnCap), balance: serverBalance)
    }

    func buy(_ purchase: BonusPurchase, idempotencyKey: String) async throws -> BonusPurchaseOutcome {
        buyCalls.append((purchase, idempotencyKey))
        if offline { throw URLError(.notConnectedToInternet) }
        return buyOutcome ?? BonusPurchaseOutcome(ok: false, errorCode: "buy_failed")
    }

    var earnError: String?
    func claimGift(code: String) async throws -> BonusPurchaseOutcome {
        if offline { throw URLError(.notConnectedToInternet) }
        return BonusPurchaseOutcome(ok: true, coupon: Coupon(
            id: "g1", title: "Подарок", code: "AYANT-GIFT01", createdAt: .now, venueID: "v9", kind: "gift"))
    }
}

/// `CouponStore` без сети: ему нужен только `saveCoupon`/`fetch…` на старте.
final class StubCouponService: CouponService {
    func saveCoupon(_ coupon: Coupon, userID: String) async throws {}
    func fetchGlobalRewards() async throws -> [Reward] { [] }
    func fetchCouponOffers(venueID: String) async throws -> [CouponOffer] { [] }
    func fetchCoupons(userID: String) async throws -> [Coupon] { [] }
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
                           idempotencyKey: String) async throws -> RedeemOutcome {
        throw URLError(.unsupportedURL)
    }
}
