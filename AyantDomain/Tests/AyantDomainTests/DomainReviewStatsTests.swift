import XCTest
@testable import AyantDomain

/// Юнит-тесты чистой математики/слияния отзывов (`Domain/ReviewStats.swift`).
/// Вызываются напрямую — без `AppStore`, async и `@MainActor`.
final class DomainReviewStatsTests: XCTestCase {

    // MARK: aggregate

    func testAggregateFallsBackToSeedWhenNoReviews() {
        let agg = ReviewStats.aggregate(reviews: [], fallbackRating: 4.2, fallbackCount: 37)
        XCTAssertEqual(agg.rating, 4.2, accuracy: 1e-9)
        XCTAssertEqual(agg.count, 37)
    }

    func testAggregateComputesLiveAverageAndIgnoresFallback() {
        let rs = [review("r1", rating: 5), review("r2", rating: 3), review("r3", rating: 4)]
        let agg = ReviewStats.aggregate(reviews: rs, fallbackRating: 1.0, fallbackCount: 999)
        XCTAssertEqual(agg.rating, 4.0, accuracy: 1e-9)   // (5+3+4)/3
        XCTAssertEqual(agg.count, 3)                       // не seed
    }

    // MARK: ratingBreakdown

    func testRatingBreakdownCountsPerStarWithAllKeysPresent() {
        let rs = [review("a", rating: 5), review("b", rating: 5), review("c", rating: 2)]
        let bd = ReviewStats.ratingBreakdown(reviews: rs)
        XCTAssertEqual(bd, [1: 0, 2: 1, 3: 0, 4: 0, 5: 2])
    }

    func testRatingBreakdownEmptyIsAllZeros() {
        XCTAssertEqual(ReviewStats.ratingBreakdown(reviews: []), [1: 0, 2: 0, 3: 0, 4: 0, 5: 0])
    }

    // MARK: merge

    func testMergeDedupesByIdWithBaseWinning() {
        let base = [review("shared", rating: 5, text: "base"), review("b2", rating: 4)]
        let user = [review("shared", rating: 1, text: "user"), review("u1", rating: 3)]
        let merged = ReviewStats.merge(base: base, userReviews: user, hostReplies: [:])

        XCTAssertEqual(merged.map(\.id), ["shared", "b2", "u1"])       // дубль пользователя отброшен
        XCTAssertEqual(merged.first { $0.id == "shared" }?.text, "base") // база выигрывает
    }

    func testMergeOverlaysHostReplies() {
        let base = [review("r1", rating: 5), review("r2", rating: 4)]
        let reply = HostReply(text: "Спасибо!", createdAt: .now, updatedAt: .now)
        let merged = ReviewStats.merge(base: base, userReviews: [], hostReplies: ["r2": reply])

        XCTAssertNil(merged.first { $0.id == "r1" }?.hostReply)
        XCTAssertEqual(merged.first { $0.id == "r2" }?.hostReply?.text, "Спасибо!")
    }

    // MARK: aggregateAll (пакетный проход — заменил O(заведения × отзывы))

    func testAggregateAllMatchesPerVenueAggregate() {
        let venues = [venue("v1", seedRating: 4.2, seedCount: 37),
                      venue("v2", seedRating: 3.0, seedCount: 5),
                      venue("v3", seedRating: 1.5, seedCount: 99)]   // без отзывов → фолбэк
        let reviews = [review("a", rating: 5, venueID: "v1"),
                       review("b", rating: 3, venueID: "v1"),
                       review("c", rating: 4, venueID: "v1"),
                       review("d", rating: 2, venueID: "v2")]

        let batch = ReviewStats.aggregateAll(venues: venues, reviews: reviews)

        // Эталон — тот самый поштучный путь, который пакетный вариант вытеснил.
        for v in venues {
            let mine = reviews.filter { $0.venueID == v.id }
            let expected = ReviewStats.aggregate(reviews: mine,
                                                 fallbackRating: v.rating,
                                                 fallbackCount: v.reviewCount)
            XCTAssertEqual(batch[v.id]?.rating ?? .nan, expected.rating, accuracy: 1e-9,
                           "рейтинг разошёлся для \(v.id)")
            XCTAssertEqual(batch[v.id]?.count, expected.count, "число отзывов разошлось для \(v.id)")
        }
    }

    func testAggregateAllFallsBackToSeedForVenuesWithoutReviews() {
        let batch = ReviewStats.aggregateAll(venues: [venue("v3", seedRating: 1.5, seedCount: 99)],
                                             reviews: [])
        XCTAssertEqual(batch["v3"]?.rating ?? .nan, 1.5, accuracy: 1e-9)
        XCTAssertEqual(batch["v3"]?.count, 99)
    }

    func testAggregateAllIgnoresReviewsOfUnknownVenues() {
        // Отзыв на заведение вне каталога не должен ни падать, ни протекать в чужой агрегат.
        let batch = ReviewStats.aggregateAll(venues: [venue("v1", seedRating: 4.0, seedCount: 2)],
                                             reviews: [review("x", rating: 1, venueID: "ghost")])
        XCTAssertEqual(batch.keys.sorted(), ["v1"])
        XCTAssertEqual(batch["v1"]?.rating ?? .nan, 4.0, accuracy: 1e-9)  // фолбэк, чужой отзыв не учтён
    }

    func testAggregateAllCoversEveryVenueExactlyOnce() {
        let venues = (1...50).map { venue("v\($0)", seedRating: 3.0, seedCount: 1) }
        let batch = ReviewStats.aggregateAll(venues: venues, reviews: [])
        XCTAssertEqual(batch.count, 50)
    }

    // MARK: - Фабрика

    private func review(_ id: String, rating: Int, text: String = "", venueID: String = "v") -> Review {
        Review(id: id, venueID: venueID, authorID: "a", authorName: "A",
               rating: rating, text: text, photoEmojis: [],
               createdAt: .now, updatedAt: .now, hostReply: nil)
    }

    private func venue(_ id: String, seedRating: Double, seedCount: Int) -> Venue {
        Venue(
            id: id, name: "Venue \(id)", category: .cafe, district: "Центр",
            address: "ул. Тестовая 1", phone: "+996700000000", emoji: "🍽",
            gradient: [0xFF5A1F, 0xFF9500], imageURL: nil,
            rating: seedRating, reviewCount: seedCount, isVerified: false,
            savedByCount: 0, citySlug: City.bishkek.id,
            latitude: City.bishkek.latitude, longitude: City.bishkek.longitude,
            todaySpecialText: nil,
            weekHours: (0..<7).map { _ in DayHours(closed: true, open: 0, close: 0) },
            statusRaw: ModerationStatus.approved.rawValue, isPaused: false,
            boostedUntil: nil)
    }
}
