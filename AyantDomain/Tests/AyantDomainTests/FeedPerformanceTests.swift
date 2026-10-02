import XCTest
@testable import AyantDomain

/// Ранжирование ленты считает скоры один раз на сборку (`FeedBuilder.ScoreContext`)
/// вместо пересчёта внутри компаратора. Эти тесты держат две вещи: порядок
/// выдачи тот же, что у прежней наивной реализации, и сборка большой ленты
/// укладывается в кадр.
final class FeedPerformanceTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let categories: [VenueCategory] = [.cafe, .coffee, .fastfood, .restaurant, .teahouse, .bakery]

    /// Детерминированный «случайный» каталог: разные рейтинги, отзывы,
    /// сохранения, акции разной свежести и скидки — скоры почти все разные.
    private func catalog(venues nv: Int, dealsPerVenue: Int) -> FeedCatalog {
        var venues: [Venue] = []
        var deals: [Deal] = []
        for i in 0..<nv {
            let seed = Double((i * 7919) % 997)
            var v = Venue(id: "v\(i)", name: "V\(i)", category: categories[i % categories.count],
                          district: "", address: "", phone: "", emoji: "🍽", gradient: [0],
                          rating: 3 + (seed.truncatingRemainder(dividingBy: 20)) / 10,
                          reviewCount: (i * 37) % 500, isVerified: i % 3 == 0,
                          savedByCount: (i * 13) % 200,
                          todaySpecialText: i % 4 == 0 ? "Суп дня" : nil,
                          openHour: 8 + i % 4, closeHour: 18 + i % 6)
            v.boostedUntil = i % 9 == 0 ? now.addingTimeInterval(3600) : nil
            venues.append(v)
            for j in 0..<dealsPerVenue {
                let k = i * dealsPerVenue + j
                deals.append(Deal(id: "d\(k)", venueID: "v\(i)", type: .discount, title: "D\(k)",
                                  details: "", emoji: "🔥",
                                  discountPercent: (k * 11) % 60,
                                  validUntil: now.addingTimeInterval(Double((k * 3571) % 400_000) - 20_000),
                                  startDate: now.addingTimeInterval(-Double((k * 1931) % 2_000_000))))
            }
        }
        // Пара отзывных агрегатов поверх документа.
        let ratings = ["v1": VenueRating(rating: 4.9, count: 12), "v2": VenueRating(rating: 2.1, count: 40)]
        return FeedCatalog(venues: venues, deals: deals, ratings: ratings)
    }

    // MARK: Прежняя реализация — эталон порядка

    private func naiveVenueScore(_ venue: Venue, _ c: FeedCatalog) -> Double {
        let agg = c.ratings[venue.id] ?? VenueRating(rating: venue.rating, count: venue.reviewCount)
        let active = c.deals.filter { $0.venueID == venue.id && $0.isActive(at: now) }.count
        return Ranking.venueScore(rating: agg.rating, reviewCount: agg.count,
                                  savedByCount: venue.savedByCount, isVerified: venue.isVerified,
                                  hasTodaySpecial: venue.hasTodaySpecial, isOpenNow: venue.isOpen(at: now),
                                  activeDealCount: active, w: .default)
    }

    private func naiveDealScore(_ deal: Deal, _ c: FeedCatalog) -> Double {
        let venue = c.venues.first { $0.id == deal.venueID }
        let vs = venue.map { naiveVenueScore($0, c) } ?? 0
        let hour = City.calendar(forSlug: deal.citySlug).component(.hour, from: now)
        return Ranking.dealScore(venueScore: vs, isFresh: deal.isFresh(at: now),
                                 daysSinceStart: deal.startDate.map { now.timeIntervalSince($0) / 86_400 },
                                 discountPercent: deal.effectiveDiscountPercent,
                                 hoursUntilExpiry: deal.validUntil.timeIntervalSince(now) / 3600,
                                 timeRelevance: venue?.category.timeRelevance(hour: hour) ?? 0.5, w: .default)
    }

    // MARK: Эквивалентность

    func testCachedScoresMatchNaiveScores() {
        let c = catalog(venues: 40, dealsPerVenue: 3)
        for v in c.venues {
            XCTAssertEqual(FeedBuilder.venueScore(v, catalog: c, weights: .default, now: now),
                           naiveVenueScore(v, c), accuracy: 1e-12)
        }
        for d in c.deals {
            XCTAssertEqual(FeedBuilder.dealScore(d, catalog: c, weights: .default, now: now),
                           naiveDealScore(d, c), accuracy: 1e-12)
        }
    }

    func testRankedOrderMatchesNaiveOrder() {
        let c = catalog(venues: 60, dealsPerVenue: 3)
        let city = City.bishkek.id

        let deals = FeedBuilder.rankedDeals(c, citySlug: city, weights: .default, now: now)
        let expectedDeals = c.deals.filter { $0.isActive(at: now) }
        XCTAssertEqual(Set(deals.map(\.id)), Set(expectedDeals.map(\.id)))
        let dealScores = deals.map { naiveDealScore($0, c) }
        XCTAssertEqual(dealScores, dealScores.sorted(by: >), "акции идут по убыванию прежнего скора")

        let venues = FeedBuilder.rankedVenues(c, citySlug: city, weights: .default, now: now)
        XCTAssertEqual(venues.count, c.venues.count)
        let venueScores = venues.map { naiveVenueScore($0, c) }
        XCTAssertEqual(venueScores, venueScores.sorted(by: >), "заведения идут по убыванию прежнего скора")
    }

    func testEqualScoresKeepCatalogOrder() {
        let same = (0..<5).map {
            Venue(id: "s\($0)", name: "S", category: .cafe, district: "", address: "", phone: "",
                  emoji: "☕️", gradient: [0], rating: 4.5, reviewCount: 10)
        }
        let c = FeedCatalog(venues: same)
        XCTAssertEqual(FeedBuilder.rankedVenues(c, citySlug: City.bishkek.id, weights: .default, now: now)
                        .map(\.id), ["s0", "s1", "s2", "s3", "s4"])
    }

    // MARK: Ротация буста

    func testStableHashIsFixedAcrossRuns() {
        // FNV-1a 64 от пустой строки и от "a" — общеизвестные значения.
        XCTAssertEqual(StableHash.fnv1a(""), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(StableHash.fnv1a("a"), 0xaf63_dc4c_8601_ec8c)
    }

    func testBoostRotationIsReproducibleAndActuallyRotates() {
        let until = now.addingTimeInterval(30 * 86_400)
        let venues = (0..<6).map {
            Venue(id: "ad\($0)", name: "A", category: .cafe, district: "", address: "", phone: "",
                  emoji: "📣", gradient: [0], boostedUntil: until)
        }
        let c = FeedCatalog(venues: venues)
        let city = City.bishkek.id
        let first = FeedBuilder.boostedVenues(c, citySlug: city, now: now).map(\.id)
        XCTAssertEqual(first, FeedBuilder.boostedVenues(c, citySlug: city, now: now).map(\.id))
        // В пределах одного получасового окна порядок не меняется.
        let windowStart = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 1800) * 1800)
        XCTAssertEqual(FeedBuilder.boostedVenues(c, citySlug: city, now: windowStart).map(\.id),
                       FeedBuilder.boostedVenues(c, citySlug: city,
                                                 now: windowStart.addingTimeInterval(1799)).map(\.id))
        // За сутки (48 окон) верхнее место достаётся не одному заведению.
        var leaders = Set<String>()
        for k in 0..<48 {
            let t = now.addingTimeInterval(Double(k) * 1800)
            if let top = FeedBuilder.boostedVenues(c, citySlug: city, now: t).first { leaders.insert(top.id) }
        }
        XCTAssertGreaterThan(leaders.count, 2, "ротация должна менять лидера, а не только состав")
    }

    // MARK: Производительность

    func testLargeFeedBuildsWithinAFrameBudget() {
        let c = catalog(venues: 300, dealsPerVenue: 4)   // 1200 акций
        let start = Date()
        let items = FeedBuilder.items(c, citySlug: City.bishkek.id, weights: .default, now: now)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertFalse(items.isEmpty)
        // Наивная реализация на таком каталоге — секунды; кэш — миллисекунды.
        // Порог щедрый, чтобы не мигать на медленном CI в отладочной сборке.
        XCTAssertLessThan(elapsed, 1.0, "сборка ленты: \(elapsed) с")
    }
}
