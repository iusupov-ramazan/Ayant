import XCTest
@testable import AyantDomain

/// Юнит-тесты чистой математики ранжирования (`Domain/Ranking.swift`).
///
/// В отличие от `RankingTests` (которые гоняют логику через весь `AppStore`),
/// здесь функции вызываются напрямую — без стора, async и `@MainActor`. Это
/// 1:1 порт Android `RankingTest.kt`: те же кейсы и те же ожидаемые числа, чтобы
/// две платформы не разъезжались по алгоритму выдачи.
final class DomainRankingTests: XCTestCase {

    /// Слагаемое популярности с затуханием — считаем тут для проверки вкладов.
    private func sat(_ n: Double, _ ref: Double) -> Double { min(1.0, log(n + 1) / log(ref + 1)) }

    // MARK: bayesianRating — сглаживание к среднему по каталогу

    func testBayesianRatingPullsSparseRatingsTowardPrior() {
        // (v·R + m·C)/(v+m), C=4.0, m=20.
        XCTAssertEqual(Ranking.bayesianRating(rating: 5.0, reviewCount: 2),
                       (2 * 5.0 + 20 * 4.0) / 22.0, accuracy: 1e-9)
        XCTAssertEqual(Ranking.bayesianRating(rating: 4.6, reviewCount: 400),
                       (400 * 4.6 + 20 * 4.0) / 420.0, accuracy: 1e-9)
    }

    func testWellReviewedFourSixBeatsThinFiveStar() {
        let fiveButThin = Ranking.venueScore(rating: 5.0, reviewCount: 2, savedByCount: 0,
                                             isVerified: false, hasTodaySpecial: false,
                                             isOpenNow: false, activeDealCount: 0)
        let strongFourSix = Ranking.venueScore(rating: 4.6, reviewCount: 400, savedByCount: 0,
                                               isVerified: false, hasTodaySpecial: false,
                                               isOpenNow: false, activeDealCount: 0)
        XCTAssertGreaterThan(strongFourSix, fiveButThin)
    }

    // MARK: venueScore

    func testVenueScoreRewardsRatingMonotonically() {
        let low = Ranking.venueScore(rating: 3.0, reviewCount: 10, savedByCount: 5,
                                     isVerified: false, hasTodaySpecial: false,
                                     isOpenNow: false, activeDealCount: 0)
        let high = Ranking.venueScore(rating: 4.5, reviewCount: 10, savedByCount: 5,
                                      isVerified: false, hasTodaySpecial: false,
                                      isOpenNow: false, activeDealCount: 0)
        XCTAssertGreaterThan(high, low)
        // Отличается только байесово-качественное слагаемое: вес 4.0 на (bayes/5).
        let expected = 4.0 * (Ranking.bayesianRating(rating: 4.5, reviewCount: 10)
                              - Ranking.bayesianRating(rating: 3.0, reviewCount: 10)) / 5.0
        XCTAssertEqual(high - low, expected, accuracy: 1e-9)
    }

    func testVenueScoreVerifiedBonusIsOnePointFive() {
        let plain = Ranking.venueScore(rating: 4.0, reviewCount: 20, savedByCount: 10,
                                       isVerified: false, hasTodaySpecial: false,
                                       isOpenNow: false, activeDealCount: 2)
        let verified = Ranking.venueScore(rating: 4.0, reviewCount: 20, savedByCount: 10,
                                          isVerified: true, hasTodaySpecial: false,
                                          isOpenNow: false, activeDealCount: 2)
        XCTAssertEqual(verified - plain, 1.5, accuracy: 1e-9)
    }

    func testVenueScoreActiveDealsSaturate() {
        let five = Ranking.venueScore(rating: 4.0, reviewCount: 20, savedByCount: 10,
                                      isVerified: false, hasTodaySpecial: false,
                                      isOpenNow: false, activeDealCount: 5)
        let fifty = Ranking.venueScore(rating: 4.0, reviewCount: 20, savedByCount: 10,
                                       isVerified: false, hasTodaySpecial: false,
                                       isOpenNow: false, activeDealCount: 50)
        XCTAssertEqual(five, fifty, accuracy: 1e-9)       // вклад акций насыщается
        let four = Ranking.venueScore(rating: 4.0, reviewCount: 20, savedByCount: 10,
                                      isVerified: false, hasTodaySpecial: false,
                                      isOpenNow: false, activeDealCount: 4)
        XCTAssertEqual(five - four, 1.5 * (sat(5, 5) - sat(4, 5)), accuracy: 1e-9) // вес 1.5
    }

    // MARK: dealScore

    func testDealScoreAddsFreshnessAndRecency() {
        let base = 10.0
        let stale = Ranking.dealScore(venueScore: base, isFresh: false, daysSinceStart: 20.0,
                                      discountPercent: nil, hoursUntilExpiry: nil, timeRelevance: 0.0)
        XCTAssertEqual(stale, base, accuracy: 1e-9)                 // (14-20)/14 → 0
        let fresh = Ranking.dealScore(venueScore: base, isFresh: true, daysSinceStart: 0.0,
                                      discountPercent: nil, hoursUntilExpiry: nil, timeRelevance: 0.0)
        XCTAssertEqual(fresh, base + 3.0 + 2.0, accuracy: 1e-9)     // свежесть(+3) + полная новизна(+2)
        let recentOnly = Ranking.dealScore(venueScore: base, isFresh: false, daysSinceStart: 7.0,
                                           discountPercent: nil, hoursUntilExpiry: nil, timeRelevance: 0.0)
        XCTAssertEqual(recentOnly, base + 2.0 * (14.0 - 7.0) / 14.0, accuracy: 1e-9)
    }

    func testDealScoreRewardsDiscountDepth() {
        let base = 10.0
        XCTAssertEqual(Ranking.dealScore(venueScore: base, isFresh: false, daysSinceStart: nil,
                                         discountPercent: 25, hoursUntilExpiry: nil, timeRelevance: 0.0),
                       base + 1.5, accuracy: 1e-9)                  // 25/50 → 1.5
        XCTAssertEqual(Ranking.dealScore(venueScore: base, isFresh: false, daysSinceStart: nil,
                                         discountPercent: 50, hoursUntilExpiry: nil, timeRelevance: 0.0),
                       base + 3.0, accuracy: 1e-9)                  // 50/50 → 3
        XCTAssertEqual(Ranking.dealScore(venueScore: base, isFresh: false, daysSinceStart: nil,
                                         discountPercent: 90, hoursUntilExpiry: nil, timeRelevance: 0.0),
                       base + 3.0, accuracy: 1e-9)                  // капнуто на 3
        XCTAssertEqual(Ranking.dealScore(venueScore: base, isFresh: false, daysSinceStart: nil,
                                         discountPercent: 0, hoursUntilExpiry: nil, timeRelevance: 0.0),
                       base, accuracy: 1e-9)                        // без скидки
    }

    func testDealScoreNudgesEndingSoon() {
        let base = 10.0
        XCTAssertEqual(Ranking.dealScore(venueScore: base, isFresh: false, daysSinceStart: nil,
                                         discountPercent: nil, hoursUntilExpiry: 0.0, timeRelevance: 0.0),
                       base + 1.5, accuracy: 1e-9)                  // истекает сейчас
        XCTAssertEqual(Ranking.dealScore(venueScore: base, isFresh: false, daysSinceStart: nil,
                                         discountPercent: nil, hoursUntilExpiry: 24.0, timeRelevance: 0.0),
                       base + 0.75, accuracy: 1e-9)                 // полдня
        XCTAssertEqual(Ranking.dealScore(venueScore: base, isFresh: false, daysSinceStart: nil,
                                         discountPercent: nil, hoursUntilExpiry: 48.0, timeRelevance: 0.0),
                       base, accuracy: 1e-9)                        // край окна
        XCTAssertEqual(Ranking.dealScore(venueScore: base, isFresh: false, daysSinceStart: nil,
                                         discountPercent: nil, hoursUntilExpiry: 100.0, timeRelevance: 0.0),
                       base, accuracy: 1e-9)                        // вне окна
    }

    func testDealScoreAddsTimeOfDayRelevance() {
        let base = 10.0
        // вес 2.0 на слагаемом 0…1; остальное нейтрально.
        let off = Ranking.dealScore(venueScore: base, isFresh: false, daysSinceStart: nil,
                                    discountPercent: nil, hoursUntilExpiry: nil, timeRelevance: 0.0)
        let peak = Ranking.dealScore(venueScore: base, isFresh: false, daysSinceStart: nil,
                                     discountPercent: nil, hoursUntilExpiry: nil, timeRelevance: 1.0)
        XCTAssertEqual(off, base, accuracy: 1e-9)
        XCTAssertEqual(peak, base + 2.0, accuracy: 1e-9)
    }

    // MARK: timeRelevance — соответствие категории часу

    func testTimeRelevanceFavoursCoffeeMorningRestaurantDinner() {
        XCTAssertGreaterThan(VenueCategory.coffee.timeRelevance(hour: 9),
                             VenueCategory.restaurant.timeRelevance(hour: 9))
        XCTAssertGreaterThan(VenueCategory.restaurant.timeRelevance(hour: 20),
                             VenueCategory.coffee.timeRelevance(hour: 20))
        // Неизвестная/серверная категория — нейтральные 0.5 в любой час.
        XCTAssertEqual(VenueCategory(rawValue: "Барбершоп")!.timeRelevance(hour: 9), 0.5, accuracy: 1e-9)
    }

    // MARK: feedScore + haversine

    func testFeedScoreWeightsNearerVenuesHigher() {
        let near = Ranking.feedScore(distanceKm: 1.0, rating: 4.0, reviewCount: 10,
                                     hasFreshDeal: false, hasTodaySpecial: false, dealCount: 0,
                                     timeRelevance: 0.0)
        let far = Ranking.feedScore(distanceKm: 4.0, rating: 4.0, reviewCount: 10,
                                    hasFreshDeal: false, hasTodaySpecial: false, dealCount: 0,
                                    timeRelevance: 0.0)
        XCTAssertGreaterThan(near, far)
        XCTAssertEqual(near - far, 3.6, accuracy: 1e-9)   // 6*(4/5) - 6*(1/5)
    }

    func testFeedScoreIgnoresDistanceBeyondFiveKm() {
        let atFive = Ranking.feedScore(distanceKm: 5.0, rating: 4.0, reviewCount: 10,
                                       hasFreshDeal: false, hasTodaySpecial: false, dealCount: 0,
                                       timeRelevance: 0.0)
        let atTen = Ranking.feedScore(distanceKm: 10.0, rating: 4.0, reviewCount: 10,
                                      hasFreshDeal: false, hasTodaySpecial: false, dealCount: 0,
                                      timeRelevance: 0.0)
        XCTAssertEqual(atFive, atTen, accuracy: 1e-9)
    }

    func testFeedScoreNilDistanceDropsDistanceTerm() {
        let withDist = Ranking.feedScore(distanceKm: 0.0, rating: 4.0, reviewCount: 10,
                                         hasFreshDeal: false, hasTodaySpecial: false, dealCount: 0,
                                         timeRelevance: 0.0)
        let noDist = Ranking.feedScore(distanceKm: nil, rating: 4.0, reviewCount: 10,
                                       hasFreshDeal: false, hasTodaySpecial: false, dealCount: 0,
                                       timeRelevance: 0.0)
        XCTAssertEqual(withDist - noDist, 6.0, accuracy: 1e-9) // 6 * (5-0)/5
    }

    func testHaversineIsZeroForIdenticalPoints() {
        XCTAssertEqual(Ranking.haversineKm(42.8746, 74.5698, 42.8746, 74.5698), 0.0, accuracy: 1e-9)
    }

    func testHaversineOneDegreeOfLatitudeIsAbout111Km() {
        let km = Ranking.haversineKm(0.0, 0.0, 1.0, 0.0)
        XCTAssertEqual(km, 111.19, accuracy: 0.5)
    }

    // MARK: feed — каденс вставки рекламы

    func testFeedInsertsSponsoredCardBeforeFourthDeal() {
        let deals = (0..<6).map { deal("d\($0)") }
        let feed = Ranking.feed(deals: deals, ads: [venue("ad0")])

        XCTAssertEqual(feed.count, 7)                    // 6 акций + 1 реклама
        guard case .adVenue(let v) = feed[3] else { return XCTFail("ожидали рекламу на позиции 3") }
        XCTAssertEqual(v.id, "ad0")
        guard case .deal(let d2) = feed[2] else { return XCTFail("ожидали акцию на позиции 2") }
        XCTAssertEqual(d2.id, "d2")                      // порядок акций сохранён вокруг рекламы
        guard case .deal(let d3) = feed[4] else { return XCTFail("ожидали акцию на позиции 4") }
        XCTAssertEqual(d3.id, "d3")
        XCTAssertEqual(feed.filter { if case .adVenue = $0 { return true }; return false }.count, 1)
    }

    func testFeedAppendsLeftoverAdsWhenDealsTooFew() {
        let feed = Ranking.feed(deals: [deal("d0"), deal("d1")],
                                ads: [venue("ad0"), venue("ad1")])
        // Ни один индекс не достигает 3 — обе рекламы уходят в хвост по порядку.
        XCTAssertEqual(feed.map(\.id), ["d_d0", "d_d1", "av_ad0", "av_ad1"])
    }

    func testFeedWithNoDealsReturnsAdsOnly() {
        let feed = Ranking.feed(deals: [], ads: [venue("ad0"), venue("ad1")])
        XCTAssertEqual(feed.count, 2)
        XCTAssertTrue(feed.allSatisfy { if case .adVenue = $0 { return true }; return false })
    }

    // MARK: RankingWeights — публикуемые веса (config → веса)

    func testRankingWeightsFromOverlaysKnownKeysAndDefaultsRest() {
        let w = RankingWeights.from(["W_RATING": 10.0, "W_VALUE": 9.0, "UNKNOWN": 1.0])
        XCTAssertEqual(w.rating, 10.0, accuracy: 1e-9)                        // переопределено
        XCTAssertEqual(w.value, 9.0, accuracy: 1e-9)                          // переопределено
        XCTAssertEqual(w.reviews, RankingWeights.default.reviews, accuracy: 1e-9) // не тронуто → дефолт
    }

    func testRankingWeightsFromNilOrEmptyReturnsDefaults() {
        XCTAssertEqual(RankingWeights.from(nil).rating, RankingWeights.default.rating, accuracy: 1e-9)
        XCTAssertEqual(RankingWeights.from([:]).time, RankingWeights.default.time, accuracy: 1e-9)
    }

    func testPublishedWeightsChangeScore() {
        let base = Ranking.venueScore(rating: 5, reviewCount: 200, savedByCount: 0,
                                      isVerified: false, hasTodaySpecial: false, isOpenNow: false,
                                      activeDealCount: 0)
        let heavier = Ranking.venueScore(rating: 5, reviewCount: 200, savedByCount: 0,
                                         isVerified: false, hasTodaySpecial: false, isOpenNow: false,
                                         activeDealCount: 0, w: RankingWeights.from(["W_RATING": 8.0]))
        XCTAssertGreaterThan(heavier, base)   // вес рейтинга 4 → 8
    }

    // MARK: - Минимальные фабрики моделей (важны только id)

    private func venue(_ id: String) -> Venue {
        Venue(
            id: id, name: "Venue \(id)", category: .cafe, district: "Центр",
            address: "ул. Тестовая 1", phone: "+996700000000", emoji: "🍽",
            gradient: [0xFF5A1F, 0xFF9500], imageURL: nil,
            rating: 0, reviewCount: 0, isVerified: false,
            savedByCount: 0, citySlug: City.bishkek.id,
            latitude: City.bishkek.latitude, longitude: City.bishkek.longitude,
            todaySpecialText: nil,
            weekHours: (0..<7).map { _ in DayHours(closed: true, open: 0, close: 0) },
            statusRaw: ModerationStatus.approved.rawValue, isPaused: false,
            boostedUntil: nil)
    }

    private func deal(_ id: String, venueID: String = "v") -> Deal {
        Deal(
            id: id, venueID: venueID, type: .discount, title: "Deal \(id)",
            details: "", emoji: "🔥", oldPrice: nil, newPrice: 100, discountPercent: 20,
            validUntil: Calendar.current.date(byAdding: .day, value: 30, to: .now)!,
            status: .active, startDate: nil)
    }
}
