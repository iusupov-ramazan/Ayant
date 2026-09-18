import XCTest
@testable import AyantDomain

/// Жалоба на отзыв (App Review Guidelines 1.2).
final class DomainReviewReportTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func review(id: String = "rv1", venueID: String = "v1") -> Review {
        Review(id: id, venueID: venueID, authorID: "author", authorName: "Аида",
               rating: 1, text: "плохо", photoEmojis: [], createdAt: now, updatedAt: now)
    }

    /// Один человек — одна жалоба на отзыв: иначе очередь модерации можно
    /// засыпать повторными нажатиями.
    func testSameReporterAndReviewGiveSameID() {
        let first = ReviewReport(review: review(), reporterID: "u1", reason: .spam, now: now)
        let second = ReviewReport(review: review(), reporterID: "u1", reason: .offensive, now: now)
        XCTAssertEqual(first.id, second.id)
    }

    func testDifferentReportersGiveDifferentIDs() {
        let a = ReviewReport(review: review(), reporterID: "u1", reason: .spam, now: now)
        let b = ReviewReport(review: review(), reporterID: "u2", reason: .spam, now: now)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testReportCarriesVenueSoModeratorSeesContext() {
        let r = ReviewReport(review: review(venueID: "navat"), reporterID: "u1", reason: .fake, now: now)
        XCTAssertEqual(r.venueID, "navat")
        XCTAssertEqual(r.reviewID, "rv1")
        XCTAssertEqual(r.reason.rawValue, "fake")
        XCTAssertEqual(r.createdAt, now)
    }

    /// Причины ходят в Firestore слагами — переименование сломало бы админку.
    func testReasonSlugsAreStable() {
        XCTAssertEqual(ReviewReportReason.allCases.map(\.rawValue),
                       ["fake", "spam", "offensive"])
    }
}
