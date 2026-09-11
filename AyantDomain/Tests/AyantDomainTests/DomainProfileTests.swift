import XCTest
@testable import AyantDomain

/// Личная библиотека: сборка списков по каталогу и проверки прав.
/// Раньше это жило в `AppStore` вперемешку с загрузкой и рейтингом.
final class DomainProfileTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func venue(_ id: String) -> Venue {
        Venue(id: id, name: id, category: .cafe, district: "", address: "",
              phone: "", emoji: "🍽", gradient: [0])
    }

    private func deal(_ id: String, venueID: String = "v1", until: TimeInterval = 86_400) -> Deal {
        Deal(id: id, venueID: venueID, type: .discount, title: id, details: "", emoji: "🔥",
             validUntil: now.addingTimeInterval(until))
    }

    private var catalog: FeedCatalog {
        FeedCatalog(venues: [venue("v1"), venue("v2"), venue("v3")],
                    deals: [deal("d1"), deal("d2"), deal("expired", until: -3600)])
    }

    func testSavedVenuesSkipIDsMissingFromCatalog() {
        let state = ProfileState(savedVenueIDs: ["v1", "v3", "ghost"])
        XCTAssertEqual(state.savedVenues(in: catalog).map(\.id), ["v1", "v3"])
    }

    func testFavoriteDealsDropExpiredAndSortByExpiry() {
        let state = ProfileState(favoriteDealIDs: ["d1", "d2", "expired"])
        let ids = state.favoriteDeals(in: catalog, now: now).map(\.id)
        XCTAssertEqual(ids, ["d1", "d2"])
    }

    func testHasVisitedRequiresARedeemedDealAtThatVenue() {
        var state = ProfileState(redeemedDealIDs: ["d1"])
        XCTAssertTrue(state.hasVisited(venueID: "v1", in: catalog))
        XCTAssertFalse(state.hasVisited(venueID: "v2", in: catalog))
        state.redeemedDealIDs = []
        XCTAssertFalse(state.hasVisited(venueID: "v1", in: catalog))
    }

    func testGuestCannotContributeAndHasNoReferralCode() {
        let guest = ProfileState(userID: "", isGuest: true)
        XCTAssertFalse(guest.canContribute)
        XCTAssertEqual(guest.referralCode, "")

        let signedIn = ProfileState(userID: "u1", isGuest: false)
        XCTAssertTrue(signedIn.canContribute)
        XCTAssertEqual(signedIn.referralCode, "u1")
    }

    func testMyReviewsAreScopedToAuthorAndNewestFirst() {
        let older = Review(id: "old", venueID: "v1", authorID: "u1", authorName: "Я",
                           rating: 4, text: "", photoEmojis: [],
                           createdAt: now.addingTimeInterval(-86_400), updatedAt: now)
        let newer = Review(id: "new", venueID: "v2", authorID: "u1", authorName: "Я",
                           rating: 5, text: "", photoEmojis: [], createdAt: now, updatedAt: now)
        let other = Review(id: "other", venueID: "v1", authorID: "u2", authorName: "Кто-то",
                           rating: 1, text: "", photoEmojis: [], createdAt: now, updatedAt: now)

        let state = ProfileState(userID: "u1", isGuest: false)
        XCTAssertEqual(state.myReviews(from: [older, newer, other]).map(\.id), ["new", "old"])
    }

    func testAnonymousUserHasNoReviews() {
        let review = Review(id: "r", venueID: "v1", authorID: "", authorName: "",
                            rating: 5, text: "", photoEmojis: [], createdAt: now, updatedAt: now)
        XCTAssertTrue(ProfileState().myReviews(from: [review]).isEmpty)
    }

    /// Ключи хранилища читают уже установленные приложения — их нельзя менять.
    func testStorageKeysMatchShippedInstalls() {
        XCTAssertEqual(ProfileStorageKey.savedVenues, "san.savedVenues")
        XCTAssertEqual(ProfileStorageKey.favoriteDeals, "san.favorites")
        XCTAssertEqual(ProfileStorageKey.redeemedDeals, "san.redeemed")
    }
}
