import XCTest
import UIKit
@testable import SAN
import AyantDomain
@testable import AyantFeatures

/// Падения, память и холодный старт (предрелизный аудит): размер фото из
/// Cloudinary, кружки штампов, шаг времени змейки, состояния ленты и кэш отзывов.
@MainActor
final class LaunchStabilityTests: XCTestCase {

    // MARK: CloudinaryURL

    func testCloudinaryURLInsertsSizeTransformation() {
        let raw = "https://res.cloudinary.com/dsb14gwxw/image/upload/v1712345/ayant/abc.jpg"
        XCTAssertEqual(CloudinaryURL.sized(raw, width: 800)?.absoluteString,
                       "https://res.cloudinary.com/dsb14gwxw/image/upload/f_auto,q_auto,w_800,c_limit/v1712345/ayant/abc.jpg")
    }

    func testCloudinaryURLLeavesOtherHostsAndExistingTransformsAlone() {
        let other = "https://images.unsplash.com/photo-1?w=600"
        XCTAssertEqual(CloudinaryURL.sized(other, width: 800)?.absoluteString, other)
        let transformed = "https://res.cloudinary.com/x/image/upload/c_fill,w_100/v1/a.jpg"
        XCTAssertEqual(CloudinaryURL.sized(transformed, width: 800)?.absoluteString, transformed)
        XCTAssertNil(CloudinaryURL.sized("", width: 800))
        XCTAssertNil(CloudinaryURL.sized(nil, width: 800))
        // Без версии сразу имя файла — тоже трансформируется.
        XCTAssertEqual(CloudinaryURL.sized("https://res.cloudinary.com/x/image/upload/a.jpg", width: 10)?.absoluteString,
                       "https://res.cloudinary.com/x/image/upload/f_auto,q_auto,w_10,c_limit/a.jpg")
    }

    func testCloudinaryPixelWidthIsTripledAndCapped() {
        XCTAssertEqual(CloudinaryURL.pixels(40), 120)
        XCTAssertEqual(CloudinaryURL.pixels(400), 1200)
        XCTAssertEqual(CloudinaryURL.pixels(5000), CloudinaryURL.maxWidth)
        XCTAssertEqual(CloudinaryURL.pixels(.nan), 1)
        XCTAssertEqual(CloudinaryURL.pixels(-3), 1)
    }

    // MARK: Уменьшение фото перед загрузкой

    func testDownsamplerProducesPixelSizedJPEG() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let big = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000), format: format)
            .image { ctx in UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000)) }
        let source = try XCTUnwrap(big.pngData())
        let jpeg = try XCTUnwrap(ImageDownsampler.jpeg(from: source, maxPixel: 1200))
        let decoded = try XCTUnwrap(UIImage(data: jpeg))
        XCTAssertEqual(max(decoded.size.width * decoded.scale, decoded.size.height * decoded.scale), 1200)
        XCTAssertNil(ImageDownsampler.jpeg(from: Data()))
        XCTAssertNil(ImageDownsampler.jpeg(from: Data("not an image".utf8)))
    }

    func testDownscaledIgnoresScreenScale() {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let img = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1200), format: format)
            .image { _ in }
        let small = img.downscaled(maxDimension: 1200)
        XCTAssertEqual(small.size.width * small.scale, 1200, accuracy: 0.5,
                       "1200 пикселей, а не 1200 точек × масштаб экрана")
    }

    // MARK: Штампы

    func testStampLayoutClampsAndWraps() {
        XCTAssertEqual(StampLayout.shown(-5), 0)
        XCTAssertEqual(StampLayout.shown(6), 6)
        XCTAssertEqual(StampLayout.shown(500), StampLayout.maxShown)
        XCTAssertEqual(StampLayout.rows(-1, perRow: 12), [])
        XCTAssertEqual(StampLayout.rows(5, perRow: 12), [[0, 1, 2, 3, 4]])
        let rows = StampLayout.rows(25, perRow: 12)
        XCTAssertEqual(rows.map(\.count), [12, 12, 1])
        XCTAssertEqual(rows.flatMap { $0 }, Array(0..<25))
        XCTAssertEqual(StampLayout.rows(1000, perRow: 12).flatMap { $0 }.count, StampLayout.maxShown)
    }

    // MARK: Змейка

    func testSnakeFrameDeltaIsClamped() {
        XCTAssertEqual(SnakeScene.frameDelta(current: 10, last: 0), 0, "первый кадр партии")
        XCTAssertEqual(SnakeScene.frameDelta(current: 10.016, last: 10), 0.016, accuracy: 1e-9)
        XCTAssertEqual(SnakeScene.frameDelta(current: 500, last: 10), SnakeScene.maxFrameDelta,
                       "после фона — не десятки шагов разом")
        XCTAssertEqual(SnakeScene.frameDelta(current: 5, last: 10), 0, "время назад — шаг 0")
    }

    // MARK: Лента: состояния загрузки

    func testFeedIsLoadingBeforeFirstLoadAndHostOverlayDoesNotPublishEmptyCatalog() async {
        let store = FeedStore(repository: LaunchStubRepo())
        XCTAssertTrue(store.isLoading, ".idle — это ещё загрузка, а не «пусто»")
        store.setHostContent(venues: [], deals: [])
        XCTAssertNil(store.state.catalog.value, "оверлей хоста до загрузки не публикует пустой каталог")
        XCTAssertTrue(store.isLoading)
        await store.load()
        XCTAssertFalse(store.isLoading)
        XCTAssertNotNil(store.state.catalog.value)
    }

    func testFeedFailureStaysVisible() async {
        let repo = LaunchStubRepo()
        repo.fail = true
        let store = FeedStore(repository: repo)
        await store.load()
        XCTAssertTrue(store.loadFailed, "ошибка не затирается пустым каталогом")
        XCTAssertFalse(store.isLoading)
        store.setHostContent(venues: [], deals: [])
        XCTAssertTrue(store.loadFailed)
        repo.fail = false
        await store.load()
        XCTAssertFalse(store.loadFailed)
    }

    // MARK: Лента: кэш отзывов

    private static let userReviewsKey = "san.userReviews"
    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: Self.userReviewsKey)
    }
    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: Self.userReviewsKey)
    }

    private func review(_ id: String, venue: String = "v1", author: String = "u1", text: String = "ok") -> Review {
        Review(id: id, venueID: venue, authorID: author, authorName: "A", rating: 5, text: text,
               photoEmojis: [], createdAt: Date(timeIntervalSince1970: 0),
               updatedAt: Date(timeIntervalSince1970: 0))
    }

    func testDeletedReviewDoesNotComeBackOnNextFetch() async {
        let repo = LaunchStubRepo()
        repo.reviews = [review("r1"), review("r2")]
        let store = FeedStore(repository: repo)
        store.currentUserID = "u1"
        await store.load()
        await store.loadReviews(forVenue: "v1")
        XCTAssertEqual(Set(store.reviews.map(\.id)), ["r1", "r2"])

        store.removeReview(id: "r1")
        // Другой экран подтягивает отзывы автора — сервер ещё отдаёт только r2.
        repo.reviews = [review("r2")]
        await store.loadMyReviews(authorID: "u1")
        XCTAssertEqual(store.reviews.map(\.id), ["r2"], "удалённый отзыв не воскресает из базы")
    }

    func testEditedReviewIsNotRevertedByBase() async {
        let repo = LaunchStubRepo()
        repo.reviews = [review("r1", text: "старый")]
        let store = FeedStore(repository: repo)
        store.currentUserID = "u1"
        await store.load()
        await store.loadReviews(forVenue: "v1")
        store.upsertUserReview(review("r1", text: "новый"))
        // Подгрузка ДРУГОГО заведения пересобирает кэш — правка должна остаться.
        repo.reviews = [review("o1", venue: "v2", author: "z")]
        await store.loadReviews(forVenue: "v2")
        XCTAssertEqual(store.reviews.first { $0.id == "r1" }?.text, "новый")
    }

    func testCompleteFetchDropsReviewsServerNoLongerReturns() async {
        let repo = LaunchStubRepo()
        repo.reviews = [review("r1", author: "x"), review("r2", author: "y"), review("o1", venue: "v2", author: "z")]
        let store = FeedStore(repository: repo)
        await store.load()
        await store.loadReviews(forVenue: "v1")
        await store.loadReviews(forVenue: "v2")
        // r1 удалила модерация: полный ответ по v1 его больше не содержит.
        repo.reviews = [review("r2", author: "y"), review("o1", venue: "v2", author: "z")]
        await store.loadReviews(forVenue: "v1")
        XCTAssertEqual(Set(store.reviews.map(\.id)), ["r2", "o1"], "чужие заведения не трогаем")
    }
}

/// Репозиторий для тестов ленты: каталог пустой, отзывы фильтруются по запросу.
private final class LaunchStubRepo: DataRepository {
    var fail = false
    var reviews: [Review] = []
    struct Offline: Error {}

    func fetchVenues() async throws -> [Venue] {
        if fail { throw Offline() }
        return []
    }
    func fetchDeals() async throws -> [Deal] {
        if fail { throw Offline() }
        return []
    }
    func fetchReviews(venueID: String, limit: Int) async throws -> [Review] {
        Array(reviews.filter { $0.venueID == venueID }.prefix(limit))
    }
    func fetchReviews(venueIDs: [String], limit: Int) async throws -> [Review] {
        Array(reviews.filter { venueIDs.contains($0.venueID) }.prefix(limit))
    }
    func fetchReviews(authorID: String, limit: Int) async throws -> [Review] {
        Array(reviews.filter { $0.authorID == authorID }.prefix(limit))
    }
    func saveReview(_ review: Review) async throws {}
    func deleteReview(id: String) async throws {}
    func updateReviewReply(reviewID: String, reply: HostReply?) async throws {}
    func reportReview(_ report: ReviewReport) async throws {}
    func logRedemption(userID: String, dealID: String, venueID: String) async throws {}
    func recordReferral(inviteeID: String, referrerID: String) async throws {}
    func claimBonusGrants(userID: String) async throws -> Int { 0 }
    func createGiftCoupon(title: String, code: String, fromName: String) async throws {}
    func claimGiftCoupon(code: String) async throws -> GiftInfo? { nil }
    func fetchCategories() async throws -> [RemoteCategory] { [] }
}
