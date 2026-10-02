import XCTest
@testable import SAN
import AyantDomain
import AyantFeatures

/// Безопасность серверного кошелька на клиенте (аудит 2026-10-01): выход
/// посреди запроса, честный итог урезанного начисления, слияние очереди,
/// ключи покупок и списаний, переживающие убийство приложения.
@MainActor
final class BonusEngineSafetyTests: XCTestCase {

    private var clock: FixedClock!
    private var wallet: GatedBonusWallet!
    private var engine: BonusEngine!

    override func setUp() {
        super.setUp()
        clock = FixedClock(Date(timeIntervalSince1970: 1_700_000_000))
        purgeBonusUserDefaults()
        wallet = GatedBonusWallet()
        engine = BonusEngine(clock: clock, wallet: wallet)
        engine.resetForNewUser()
    }

    override func tearDown() {
        engine.resetForNewUser()
        purgeBonusUserDefaults()
        super.tearDown()
    }

    private func waitUntil(_ condition: @autoclosure () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: Выход посреди запроса

    func testSignOutDuringInFlightEarnNeitherCrashesNorLeaks() async {
        engine.attach(userID: "uA")
        await waitUntil(self.wallet.hasWallet)
        wallet.gated = true
        engine.awardGameplay(5, source: "game:snake")
        await waitUntil(self.wallet.earnCalls.count == 1)

        engine.resetForNewUser()          // выход, пока earn «в сети»
        wallet.gated = false              // ответ пришёл уже после выхода
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(engine.balance, 0, "ответ для A не попадает на экран после выхода")
        XCTAssertEqual(engine.syncingAmount, 0)

        wallet.reset(serverBalance: 0)
        engine.attach(userID: "uB")
        await waitUntil(self.wallet.syncCalls.count == 1)
        XCTAssertEqual(wallet.syncCalls, [0], "баланс A не переносится в кошелёк B")
        XCTAssertTrue(wallet.earnCalls.isEmpty, "начисление A не уходит под токеном B")
    }

    // MARK: Честный итог

    func testCappedGrantPublishesNoticeAndStopsFurtherQueuing() async {
        wallet.earnCap = 3
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        XCTAssertEqual(engine.awardGameplay(10, source: "game:snake"), 10)
        await waitUntil(self.engine.earnNotice != nil)

        XCTAssertEqual(engine.earnNotice?.requested, 10)
        XCTAssertEqual(engine.earnNotice?.granted, 3)
        XCTAssertEqual(engine.earnNotice?.daily, true)
        XCTAssertTrue(engine.serverDailyCapReached)
        XCTAssertEqual(engine.balance, 3)

        XCTAssertEqual(engine.awardGameplay(5, source: "game:tetris"), 0, "сегодня сервер больше не зачислит")
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(wallet.earnCalls.count, 1, "в очередь ничего не встало")

        engine.clearEarnNotice()
        XCTAssertNil(engine.earnNotice)
    }

    func testDiamondSourceCapDoesNotBlockOtherGames() async {
        wallet.earnCap = 2
        wallet.capReason = .source
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        engine.awardGameplay(5, source: BonusGame.diamond.source)
        await waitUntil(self.engine.earnNotice != nil)
        XCTAssertFalse(engine.serverDailyCapReached, "потолок Diamond — свой, не общий")
        XCTAssertEqual(engine.awardGameplay(2, source: BonusGame.diamond.source), 0)
        wallet.earnCap = .max
        XCTAssertEqual(engine.awardGameplay(4, source: "game:snake"), 4)
    }

    func testServerCapResetsWithBishkekDay() async {
        wallet.earnCap = 0
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        engine.awardGameplay(3, source: "game:snake")
        await waitUntil(self.engine.serverDailyCapReached)
        XCTAssertEqual(engine.awardGameplay(3, source: "game:snake"), 0)

        clock.advance(by: 86_400)
        wallet.earnCap = .max
        XCTAssertEqual(engine.awardGameplay(3, source: "game:snake"), 3, "новые сутки — снова платит")
        XCTAssertFalse(engine.serverDailyCapReached)
    }

    func testPermanentRejectionRemovesOptimisticBonus() async {
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        wallet.earnError = "bad_source"
        engine.awardGameplay(6, source: "game:snake")
        XCTAssertEqual(engine.balance, 6)
        await waitUntil(self.engine.syncingAmount == 0)
        XCTAssertEqual(engine.balance, 0, "отказ навсегда — «+6» убран")
    }

    // MARK: Слияние очереди

    func testUnsentEarnsOfOneSourceAreCoalesced() async {
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        wallet.gated = true
        engine.awardGameplay(1, source: "game:snake")
        await waitUntil(self.wallet.earnCalls.count == 1)
        engine.awardGameplay(1, source: "game:snake")
        engine.awardGameplay(1, source: "game:snake")
        engine.awardGameplay(1, source: "game:snake")
        wallet.gated = false
        await waitUntil(self.wallet.serverBalance == 4)
        XCTAssertEqual(wallet.earnCalls.map(\.amount), [1, 3], "три яблока — один запрос")
        XCTAssertEqual(engine.balance, 4)
    }

    func testSentEarnIsNeverMergedAndKeepsItsKey() async {
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        wallet.offline = true
        engine.awardGameplay(2, source: "game:snake")
        await waitUntil(self.wallet.earnCalls.count == 1)
        let firstKey = wallet.earnCalls[0].key
        engine.awardGameplay(3, source: "game:snake")
        wallet.offline = false
        engine.retryPending()
        await waitUntil(self.wallet.serverBalance == 5)
        let sent = wallet.earnCalls.filter { !$0.offline }
        XCTAssertEqual(sent.first?.key, firstKey)
        XCTAssertEqual(sent.first?.amount, 2, "отправленное (возможно, зачисленное) не сливается")
    }

    func testRetryPendingDoesNotResyncAnAttachedWallet() async {
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.syncCalls.count == 1)
        engine.retryPending()
        engine.retryPending()
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(wallet.syncCalls.count, 1, "bonusWalletSync — один раз за сессию")
    }

    // MARK: Чей потолок — говорит сервер (capReason)

    /// Главная находка ревью: потолок Diamond переживал перезапуск как общий —
    /// и после рестарта не платила ни одна игра и время.
    func testSourceCapSurvivesRelaunchWithoutBlockingOtherGames() async {
        wallet.earnCap = 2
        wallet.capReason = .source
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        engine.awardGameplay(5, source: BonusGame.diamond.source)
        await waitUntil(self.engine.earnNotice != nil)
        XCTAssertFalse(engine.serverDailyCapReached)

        // «Перезапуск» в тот же день: новый движок, то же хранилище.
        let relaunched = BonusEngine(clock: clock, wallet: wallet)
        XCTAssertFalse(relaunched.serverDailyCapReached, "потолок Diamond после перезапуска — не общий")
        XCTAssertTrue(relaunched.isServerCapped(BonusGame.diamond.source), "но сам Diamond сегодня не платит")
        XCTAssertEqual(relaunched.remainingToday(.diamond), 0)
        XCTAssertNil(relaunched.remainingToday(.snake))
        relaunched.attach(userID: "u1")
        wallet.earnCap = .max
        wallet.capReason = nil
        XCTAssertEqual(relaunched.awardGameplay(3, source: "game:snake"), 3, "другие игры платят")
        XCTAssertEqual(relaunched.awardGameplay(2, source: BonusGame.diamond.source), 0)
        await waitUntil(self.wallet.serverBalance == 5)
        relaunched.resetForNewUser()
    }

    func testGlobalCapSurvivesRelaunch() async {
        wallet.earnCap = 1
        wallet.capReason = .daily
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        engine.awardGameplay(4, source: "game:snake")
        await waitUntil(self.engine.serverDailyCapReached)
        let relaunched = BonusEngine(clock: clock, wallet: wallet)
        XCTAssertTrue(relaunched.serverDailyCapReached)
        XCTAssertEqual(relaunched.remainingToday(.tetris), 0)
        relaunched.resetForNewUser()
    }

    func testPerCallTrimIsNotADailyCap() async {
        wallet.earnCap = 2
        wallet.capReason = .perCall
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        engine.awardGameplay(5, source: "game:snake")
        await waitUntil(self.wallet.serverBalance == 2)
        try? await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertFalse(engine.serverDailyCapReached)
        XCTAssertNil(engine.earnNotice, "«дневной лимит» тут был бы неправдой")
        wallet.earnCap = .max
        XCTAssertEqual(engine.awardGameplay(3, source: "game:snake"), 3)
    }

    func testOldServerWithoutCapReasonFallsBackToSourceGuess() async {
        wallet.earnCap = 2
        wallet.legacyServer = true
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        engine.awardGameplay(5, source: BonusGame.diamond.source)
        await waitUntil(self.engine.earnNotice != nil)
        XCTAssertFalse(engine.serverDailyCapReached, "старый сервер: Diamond — свой потолок")
        engine.awardGameplay(5, source: "game:snake")
        await waitUntil(self.engine.serverDailyCapReached)
    }

    func testExhaustedSourceLeftStopsPromisingEvenWithoutTrim() async {
        wallet.sourceLeft = 0
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        XCTAssertEqual(engine.awardGameplay(3, source: BonusGame.diamond.source), 3)
        await waitUntil(self.engine.isServerCapped(BonusGame.diamond.source))
        XCTAssertEqual(engine.remainingToday(.diamond), 0)
        XCTAssertNil(engine.earnNotice, "ничего не урезано — плашки нет")
    }

    func testServerSourceLeftTightensRemainingToday() async {
        wallet.sourceLeft = 7
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        engine.awardGameplay(3, source: BonusGame.diamond.source)
        await waitUntil(self.engine.remainingToday(.diamond) == 7)
        XCTAssertEqual(engine.remainingToday(.diamond), 7, "сервер знает точнее местного счётчика (27)")
    }

    // MARK: Плашка — про свой источник

    func testNoticeIsNotSummedAcrossSources() async {
        wallet.earnCap = 1
        wallet.capReason = .source
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        engine.awardGameplay(4, source: BonusGame.diamond.source)
        await waitUntil(self.engine.earnNotice?.source == BonusGame.diamond.source)
        wallet.capReason = .source
        engine.awardGameplay(3, source: "game:tetris")
        await waitUntil(self.engine.earnNotice?.source == "game:tetris")
        XCTAssertEqual(engine.earnNotice?.requested, 3, "не 4 + 3: другая игра — другая плашка")
        XCTAssertEqual(engine.earnNotice?.granted, 1)
    }

    func testPayingAwardClearsOtherSourceNotice() async {
        wallet.earnCap = 1
        wallet.capReason = .source
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        engine.awardGameplay(4, source: BonusGame.diamond.source)
        await waitUntil(self.engine.earnNotice != nil)
        wallet.earnCap = .max
        XCTAssertEqual(engine.awardGameplay(2, source: "game:snake"), 2)
        XCTAssertNil(engine.earnNotice)
    }

    // MARK: Итог захода — по ответу сервера

    func testSessionEarnedReflectsWhatServerGranted() async {
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        engine.awardGameplay(4, source: "game:snake")       // до захода — не в итоге
        await waitUntil(self.wallet.serverBalance == 4)
        engine.beginGameSession()
        wallet.earnCap = 3
        wallet.capReason = .daily
        engine.awardGameplay(10, source: "game:snake")
        XCTAssertEqual(engine.sessionEarned, 10, "до ответа — заработанное")
        await waitUntil(self.engine.earnNotice != nil)
        XCTAssertEqual(engine.sessionEarned, 3, "после — зачисленное: не «+10 🎉» после «3 из 10»")
    }

    func testSessionEarnedLocalMode() {
        let local = BonusEngine(clock: clock)
        local.resetForNewUser()
        local.beginGameSession()
        local.awardGameplay(2, source: "game:snake")
        local.awardGameplay(3, source: "game:tetris")
        XCTAssertEqual(local.sessionEarned, 5)
        local.beginGameSession()
        XCTAssertEqual(local.sessionEarned, 0)
        local.resetForNewUser()
    }

    // MARK: Застрявшая очередь

    func testAppCheckRejectionKeepsBonusesAndAsksForUpdate() async {
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        wallet.earnError = "app_check_failed"
        engine.awardGameplay(5, source: "game:snake")
        await waitUntil(self.engine.syncProblem != nil)
        XCTAssertEqual(engine.syncProblem, .appUpdateNeeded)
        XCTAssertEqual(engine.syncingAmount, 5, "бонусы ждут в очереди, не выброшены")
        wallet.earnError = nil
        engine.retryPending()
        await waitUntil(self.wallet.serverBalance == 5)
        await waitUntil(self.engine.syncProblem == nil)
        XCTAssertNil(engine.syncProblem)
    }

    func testAnonymousRejectionDoesNotDropBonuses() async {
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        wallet.earnError = "anonymous_not_allowed"
        engine.awardGameplay(4, source: "game:snake")
        await waitUntil(self.engine.syncProblem != nil)
        XCTAssertEqual(engine.syncProblem, .signInRequired)
        XCTAssertEqual(engine.balance, 4)
        XCTAssertEqual(engine.syncingAmount, 4)
    }

    func testStuckHeadRotatesSoOthersGetThrough() async {
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        wallet.failSource = BonusGame.diamond.source
        engine.awardGameplay(1, source: BonusGame.diamond.source)
        await waitUntil(self.wallet.earnCalls.count == 1)
        engine.awardGameplay(2, source: "game:snake")
        for n in 2...BonusEngine.rotateAfterFailures {
            try? await Task.sleep(nanoseconds: 30_000_000)
            engine.retryPending()
            await waitUntil(self.wallet.earnCalls.count >= n)
        }
        engine.retryPending()
        await waitUntil(self.wallet.serverBalance == 2)
        XCTAssertEqual(wallet.serverBalance, 2, "змейка прошла мимо застрявшего Diamond")
        XCTAssertEqual(engine.syncingAmount, 1, "Diamond не выброшен — ждёт")
    }

    func testBackoffGrowsAndIsBounded() {
        XCTAssertEqual(BonusEngine.backoffSeconds(failures: 1), 2)
        XCTAssertEqual(BonusEngine.backoffSeconds(failures: 3), 8)
        XCTAssertEqual(BonusEngine.backoffSeconds(failures: 20), 300)
    }

    // MARK: Выход и повторный вход

    func testUnsentEarnsSurviveSignOutAndGoToTheSameUser() async {
        engine.attach(userID: "uA")
        await waitUntil(self.wallet.hasWallet)
        wallet.offline = true
        engine.awardGameplay(3, source: "game:snake")
        await waitUntil(self.wallet.earnCalls.count == 1)
        engine.resetForNewUser()
        XCTAssertEqual(engine.balance, 0)

        wallet.offline = false
        engine.attach(userID: "uB")
        await waitUntil(self.wallet.syncCalls.count == 2)
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(wallet.earnCalls.filter { !$0.offline }.count, 0, "очередь A не уходит под B")
        engine.resetForNewUser()

        engine.attach(userID: "uA")
        await waitUntil(self.wallet.serverBalance == 3)
        let sent = wallet.earnCalls.filter { !$0.offline }
        XCTAssertEqual(sent.map(\.amount), [3], "A вошёл снова — его «+3» дошло")
        XCTAssertEqual(sent.first?.key, wallet.earnCalls[0].key, "тем же ключом")
    }

    func testReloginDoesNotResetDailyCaps() async {
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        engine.awardGameplay(25, source: BonusGame.diamond.source)
        XCTAssertEqual(engine.remainingToday(.diamond), 5)
        engine.resetForNewUser()
        engine.attach(userID: "u1")
        XCTAssertEqual(engine.remainingToday(.diamond), 5, "перезаход не выдаёт ещё 30")
    }

    func testColdStartSyncsOnce() async {
        wallet.syncGated = true
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.syncCalls.count == 1)
        engine.retryPending()
        engine.retryPending()
        try? await Task.sleep(nanoseconds: 60_000_000)
        wallet.syncGated = false
        await waitUntil(self.wallet.hasWallet)
        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertEqual(wallet.syncCalls.count, 1, "attach + retryPending — один bonusWalletSync")
    }

    func testRefreshGrantsIsThrottledAndNeedsUser() async {
        engine.refreshGrantsIfStale()
        try? await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertTrue(wallet.syncCalls.isEmpty, "без пользователя — ничего")
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.syncCalls.count == 1)
        engine.refreshGrantsIfStale()
        await waitUntil(self.wallet.syncCalls.count == 2)
        engine.refreshGrantsIfStale()
        try? await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertEqual(wallet.syncCalls.count, 2, "второй раз в ту же минуту — нет")
        clock.advance(by: 61)
        engine.refreshGrantsIfStale()
        await waitUntil(self.wallet.syncCalls.count == 3)
    }

    func testDailyCapClearsAfterMidnightWithoutAnAward() async {
        wallet.earnCap = 0
        wallet.capReason = .daily
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        engine.awardGameplay(3, source: "game:snake")
        await waitUntil(self.engine.serverDailyCapReached)
        clock.advance(by: 86_400)
        engine.refreshDay()
        XCTAssertFalse(engine.serverDailyCapReached, "полночь сняла плашку без нового начисления")
    }

    // MARK: Время

    func testReachedGoalTodayUsesInjectedClockAndBishkekDay() {
        let d = UserDefaults.standard
        // 2023-11-14 17:30 UTC = 23:30 в Бишкеке.
        clock.now = Date(timeIntervalSince1970: 1_699_983_000)
        d.set(clock.now.timeIntervalSince1970, forKey: "san.bonus.lastAwardAt")
        let fresh = BonusEngine(clock: clock)     // читает сохранённое время награды
        XCTAssertTrue(fresh.reachedGoalToday)
        clock.advance(by: 60 * 60)        // 00:30 по Бишкеку — новые сутки
        XCTAssertFalse(fresh.reachedGoalToday)
        d.removeObject(forKey: "san.bonus.lastAwardAt")
    }

    func testTimeEarningSwitchDoesNotTouchGames() {
        let local = BonusEngine(clock: clock)
        local.resetForNewUser()
        local.setTimeEarningPaused(true)
        XCTAssertTrue(local.timeEarningPaused)
        XCTAssertFalse(local.isCounting)
        XCTAssertEqual(local.awardGameplay(2, source: "game:snake"), 2)
        local.resetForNewUser()
    }

    // MARK: Ключи, переживающие перезапуск

    func testPurchaseKeySurvivesAppRestart() async {
        let offer = CouponOffer(id: "co1", venueID: "v1", venueName: "Кафе", title: "Капучино",
                                cost: 120, statusRaw: ModerationStatus.approved.rawValue)
        let first = CouponStore(backend: StubCouponService(), wallet: wallet)
        first.resetForNewUser()
        await first.sync(userID: "uK")
        wallet.offline = true
        _ = await first.buy(offer, bonus: engine)

        // «Перезапуск»: новый стор, тот же пользователь.
        let second = CouponStore(backend: StubCouponService(), wallet: wallet)
        await second.sync(userID: "uK")
        wallet.offline = false
        wallet.buyOutcome = BonusPurchaseOutcome(ok: true, coupon: Coupon(
            id: "c1", title: "Капучино", code: "AYANT-K1", createdAt: .now, venueID: "v1"), balance: 0)
        _ = await second.buy(offer, bonus: engine)
        XCTAssertEqual(wallet.buyCalls.count, 2)
        XCTAssertEqual(wallet.buyCalls[0].key, wallet.buyCalls[1].key)
        second.resetForNewUser()
    }

    func testReplayedPurchaseDoesNotApplyStaleBalance() async {
        let offer = CouponOffer(id: "co2", venueID: "v1", venueName: "Кафе", title: "Латте",
                                cost: 50, statusRaw: ModerationStatus.approved.rawValue)
        engine.attach(userID: "u1")
        await waitUntil(self.wallet.hasWallet)
        engine.applyServerBalance(70)
        let store = CouponStore(backend: StubCouponService(), wallet: wallet)
        store.resetForNewUser()
        wallet.buyOutcome = BonusPurchaseOutcome(ok: true, coupon: Coupon(
            id: "c2", title: "Латте", code: "AYANT-K2", createdAt: .now, venueID: "v1"),
            balance: 120, replayed: true)
        _ = await store.buy(offer, bonus: engine)
        XCTAssertEqual(engine.balance, 70, "баланс повтора — устаревший, не применяем")
        store.resetForNewUser()
    }

    func testRedeemKeySurvivesRestartAndStopClearsState() async {
        let repo = KeyRecordingPointsRepository()
        repo.result = .failure(.network)
        let a = PointsStore(repository: repo, clock: clock)
        a.send(.observe(userID: "uP"))
        a.send(.redeem(venueID: "v1", rewardID: "r1", pointsToSpend: 0))
        await waitUntil(repo.keys.count == 1)
        try? await Task.sleep(nanoseconds: 30_000_000)

        let b = PointsStore(repository: repo, clock: clock)
        b.send(.observe(userID: "uP"))
        repo.result = .success(RedeemReceipt(redeemed: 10, balance: 0, rewardTitle: "Кофе"))
        b.send(.redeem(venueID: "v1", rewardID: "r1", pointsToSpend: 0))
        await waitUntil(repo.keys.count == 2)
        XCTAssertEqual(repo.keys[0], repo.keys[1], "после перезапуска — тот же ключ")
        await waitUntil({ if case .done = b.state.redeem { return true }; return false }())

        b.send(.stop)
        XCTAssertEqual(b.state, PointsState(), "выход стирает карты, историю и итог списания")
    }

    // MARK: Первый скан — тоже «Начислено»

    func testFirstPointsInVenueRaisesEarnEvent() async {
        let repo = FakePointsRepository()
        let store = PointsStore(repository: repo, clock: clock)
        store.send(.observe(userID: "uF"))
        await waitUntil(store.state.cards.value != nil)
        repo.emit([VenuePointsCard(venueID: "v7", venueName: "Кафе", balance: 30)])
        await waitUntil(store.state.pendingEarn != nil)
        XCTAssertEqual(store.state.pendingEarn?.delta, 30, "карты не было — первое начисление")
        store.send(.stop)
    }

    func testFirstStampOnNewCardRaisesStampEvent() async {
        let backend = StubCouponService()
        let store = LoyaltyStore(backend: backend)
        store.resetForNewUser()
        store.observe(userID: "uL")
        try? await Task.sleep(nanoseconds: 50_000_000)
        backend.pushLoyalty([])                                    // базовый снимок: карт нет
        try? await Task.sleep(nanoseconds: 30_000_000)
        backend.pushLoyalty([LoyaltyCard(venueID: "v3", venueName: "Кофейня", stamps: 1)])
        await waitUntil(store.pendingStamp != nil)
        XCTAssertEqual(store.pendingStamp?.stamps, 1)
        XCTAssertEqual(store.pendingStamp?.rewardIssued, false)
        store.resetForNewUser()
    }

    // MARK: Витрина: ошибка загрузки

    func testShopLoadFailureIsVisible() async {
        let store = CouponStore(backend: FailingOffersService())
        await store.loadShopOffers()
        XCTAssertTrue(store.shopLoadFailed)
        await store.loadRewards()
        XCTAssertTrue(store.shopLoadFailed)
        let ok = CouponStore(backend: StubCouponService())
        await ok.loadShopOffers()
        XCTAssertFalse(ok.shopLoadFailed)
    }
}

// MARK: - Фейки

/// Витрина без сети: каталог и купоны заведений не грузятся.
final class FailingOffersService: CouponService {
    func saveCoupon(_ coupon: Coupon, userID: String) async throws {}
    func fetchGlobalRewards() async throws -> [Reward] { throw URLError(.notConnectedToInternet) }
    func fetchCouponOffers(venueID: String) async throws -> [CouponOffer] { throw URLError(.notConnectedToInternet) }
    func fetchApprovedCouponOffers() async throws -> [CouponOffer] { throw URLError(.notConnectedToInternet) }
    func fetchCoupons(userID: String) async throws -> [Coupon] { [] }
    func coupons(userID: String) -> AsyncStream<[Coupon]> { AsyncStream { $0.finish() } }
    func fetchLoyaltyCards(userID: String) async throws -> [LoyaltyCard] { [] }
    func loyaltyCards(userID: String) -> AsyncStream<[LoyaltyCard]> { AsyncStream { $0.finish() } }
    func fetchVenuePoints(userID: String) async throws -> [VenuePointsCard] { [] }
    func scanCoupon(code: String, venueID: String, idToken: String,
                    billAmount: Int?, bandIndex: Int?, idempotencyKey: String,
                    cardID: String?) async throws -> ScanOutcome { throw URLError(.unsupportedURL) }
    func redeemVenuePoints(venueID: String, userID: String, rewardId: String,
                           pointsToSpend: Int, idToken: String,
                           idempotencyKey: String, nonce: String?) async throws -> RedeemOutcome {
        throw URLError(.unsupportedURL)
    }
}

/// Кошелёк, у которого можно «задержать» ответ `earn`, — чтобы выйти из
/// аккаунта, пока запрос в сети.
///
/// `@MainActor`: движок зовёт `earn`/`sync` асинхронно, и без изоляции они
/// шли бы на общем пуле, параллельно с чтением `earnCalls` из теста, —
/// гонка, из-за которой прогон всего набора изредка падал.
@MainActor
final class GatedBonusWallet: BonusWalletService {
    var serverBalance = 0
    var hasWallet = false
    var offline = false
    var gated = false
    var earnCap = Int.max
    var earnError: String?
    /// Причина урезания, которую «сервер» вернёт (`nil` при урезании — `.daily`).
    var capReason: BonusEarnCapReason?
    /// Остаток источника в ответе (`nil` — нет потолка).
    var sourceLeft: Int?
    /// Сервер старой версии: без `capReason`/`dailyLeft`/`sourceLeft`.
    var legacyServer = false
    /// Начисления этого источника получают 500-подобный отказ.
    var failSource: String?
    var syncGated = false
    var buyOutcome: BonusPurchaseOutcome?
    private(set) var syncCalls: [Int] = []
    private(set) var earnCalls: [(amount: Int, source: String, key: String, offline: Bool)] = []
    private(set) var buyCalls: [(purchase: BonusPurchase, key: String)] = []
    private var seen: Set<String> = []

    func reset(serverBalance: Int) {
        self.serverBalance = serverBalance
        hasWallet = false
        syncCalls = []
        earnCalls = []
        seen = []
    }

    nonisolated func balance(userID: String) -> AsyncStream<Int> { AsyncStream { $0.finish() } }

    func sync(localBalance: Int) async throws -> Int {
        if offline { throw URLError(.notConnectedToInternet) }
        syncCalls.append(localBalance)
        while syncGated { try await Task.sleep(nanoseconds: 10_000_000) }
        if !hasWallet { hasWallet = true; serverBalance = localBalance }
        return serverBalance
    }

    func earn(amount: Int, source: String, idempotencyKey: String) async throws -> BonusEarnOutcome {
        earnCalls.append((amount, source, idempotencyKey, offline))
        if offline { throw URLError(.notConnectedToInternet) }
        while gated { try await Task.sleep(nanoseconds: 10_000_000) }
        guard hasWallet else { return BonusEarnOutcome(ok: false, errorCode: "no_wallet") }
        if let earnError { return BonusEarnOutcome(ok: false, errorCode: earnError) }
        if source == failSource { return BonusEarnOutcome(ok: false, errorCode: "earn_failed") }
        let granted = max(0, min(amount, earnCap))
        if seen.insert(idempotencyKey).inserted { serverBalance += granted }
        if legacyServer { return BonusEarnOutcome(ok: true, granted: granted, balance: serverBalance) }
        let reason: BonusEarnCapReason? = granted < amount ? (capReason ?? .daily) : nil
        return BonusEarnOutcome(ok: true, granted: granted, balance: serverBalance,
                                capReason: reason,
                                dailyLeft: reason == .daily ? 0 : 1000,
                                sourceLeft: reason == .source ? 0 : sourceLeft)
    }

    func buy(_ purchase: BonusPurchase, idempotencyKey: String) async throws -> BonusPurchaseOutcome {
        buyCalls.append((purchase, idempotencyKey))
        if offline { throw URLError(.notConnectedToInternet) }
        return buyOutcome ?? BonusPurchaseOutcome(ok: false, errorCode: "buy_failed")
    }

    func claimGift(code: String) async throws -> BonusPurchaseOutcome {
        BonusPurchaseOutcome(ok: false, errorCode: "not_found")
    }
}

/// Репозиторий баллов, запоминающий ключи списаний.
final class KeyRecordingPointsRepository: PointsRepository {
    var result: Result<RedeemReceipt, AppError> = .failure(.network)
    private(set) var keys: [String] = []

    nonisolated func cards(userID: String) -> AsyncStream<Result<[VenuePointsCard], AppError>> {
        AsyncStream { $0.yield(.success([])) }
    }

    func redeem(venueID: String, userID: String, rewardID: String,
                pointsToSpend: Int, idempotencyKey: String) async -> Result<RedeemReceipt, AppError> {
        keys.append(idempotencyKey)
        return result
    }

    func ledger(userID: String, venueID: String, limit: Int) async -> Result<[PointsLedgerEntry], AppError> {
        .success([])
    }
}
