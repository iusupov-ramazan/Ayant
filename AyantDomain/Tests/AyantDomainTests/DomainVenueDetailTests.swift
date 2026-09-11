import XCTest
@testable import AyantDomain

/// Производные величины карточки заведения. Раньше они жили в `AppStore` и
/// проверялись только глазами; здесь это чистые функции состояния.
final class DomainVenueDetailTests: XCTestCase {

    private func venue(rating: Double = 4.0, reviews: Int = 10) -> Venue {
        Venue(id: "v1", name: "Navat", category: .cafe, district: "", address: "",
              phone: "", emoji: "🍽", gradient: [0], rating: rating, reviewCount: reviews)
    }

    private func review(_ id: String, rating: Int, author: String = "me",
                        itemID: String? = nil) -> Review {
        Review(id: id, venueID: "v1", authorID: author, authorName: "Я",
               rating: rating, text: "", photoEmojis: [],
               createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0),
               itemID: itemID)
    }

    func testAggregateFallsBackToSeedWhenNoReviews() {
        let state = VenueDetailState(venue: venue(rating: 4.6, reviews: 213))
        XCTAssertEqual(state.aggregate.rating, 4.6, accuracy: 1e-9)
        XCTAssertEqual(state.aggregate.count, 213)
    }

    func testLiveReviewsOverrideSeedRating() {
        let state = VenueDetailState(venue: venue(rating: 4.6, reviews: 213),
                                     reviews: [review("a", rating: 2), review("b", rating: 4)])
        XCTAssertEqual(state.aggregate.rating, 3.0, accuracy: 1e-9)
        XCTAssertEqual(state.aggregate.count, 2)
    }

    func testRatingBreakdownAlwaysHasAllFiveKeys() {
        let state = VenueDetailState(venue: venue(), reviews: [review("a", rating: 5)])
        XCTAssertEqual(state.ratingBreakdown, [1: 0, 2: 0, 3: 0, 4: 0, 5: 1])
    }

    func testMyReviewIsScopedToAuthorAndItem() {
        let state = VenueDetailState(
            venue: venue(),
            reviews: [review("mine", rating: 5),
                      review("mine-dish", rating: 4, itemID: "dish1"),
                      review("theirs", rating: 1, author: "someone")],
            currentUserID: "me", isGuest: false)
        XCTAssertEqual(state.myReview()?.id, "mine")
        XCTAssertEqual(state.myReview(itemID: "dish1")?.id, "mine-dish")
        XCTAssertNil(state.myReview(itemID: "dish2"))
    }

    func testGuestHasNoOwnReviewAndCannotContribute() {
        let state = VenueDetailState(venue: venue(), reviews: [review("mine", rating: 5)],
                                     currentUserID: "", isGuest: true)
        XCTAssertNil(state.myReview())
        XCTAssertFalse(state.canContribute)
    }

    func testEmptyStateIsSafeToRender() {
        let state = VenueDetailState()
        XCTAssertNil(state.venue)
        XCTAssertEqual(state.aggregate.count, 0)
        XCTAssertEqual(state.ratingBreakdown, [1: 0, 2: 0, 3: 0, 4: 0, 5: 0])
        XCTAssertFalse(state.canContribute)
    }
}

/// Одна механика лояльности на заведение (см. `LoyaltyKind`).
final class LoyaltyKindTests: XCTestCase {

    func testPointsWinWhenBothEnabled() {
        XCTAssertEqual(LoyaltyKind.active(pointsEnabled: true, loyaltyEnabled: true), .points,
                       "две механики сразу невозможны — баллы приоритетнее")
    }

    func testStampsOnlyWhenPointsOff() {
        XCTAssertEqual(LoyaltyKind.active(pointsEnabled: false, loyaltyEnabled: true), .stamps)
    }

    func testNoneWhenBothOff() {
        XCTAssertEqual(LoyaltyKind.active(pointsEnabled: false, loyaltyEnabled: false), .none)
    }

    func testVenueWithBothFlagsRunsPointsOnly() {
        var venue = MockData.venues[0]
        venue.pointsEnabled = true
        venue.loyaltyEnabled = true
        XCTAssertTrue(venue.pointsActive)
        XCTAssertFalse(venue.stampsActive, "штампы не должны работать, пока включены баллы")
    }
}
