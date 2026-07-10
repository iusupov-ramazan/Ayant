import XCTest
import SwiftUI
import CoreLocation
@testable import SAN

/// Юнит-тесты алгоритма ранжирования выдачи (AppStore).
///
/// AppStore инъектируем: подставляем стаб-репозиторий (венью/акции), стаб
/// аналитики/пуша и in-memory хранилище настроек — тесты не трогают сеть и
/// UserDefaults. Паттерн инъекции повторяет CategoryTests (StubRepo).
@MainActor
final class RankingTests: XCTestCase {

    // MARK: Фабрика стора и тестовых моделей

    /// Собирает AppStore на стаб-репозитории и загружает данные (load()).
    private func makeStore(venues: [Venue], deals: [Deal] = []) async -> AppStore {
        let repo = RankingStubRepo(venues: venues, deals: deals)
        let store = AppStore(repository: repo,
                             analytics: MockAnalyticsService(),
                             push: MockPushService(),
                             prefs: InMemoryPreferences())
        await store.load()
        return store
    }

    /// Venue в Бишкеке, одобренное, не на паузе. weekHours = закрыто всю неделю,
    /// чтобы `isOpenNow` был детерминированно false (не зависел от времени прогона).
    private func venue(_ id: String, rating: Double = 0, reviews: Int = 0,
                       verified: Bool = false, savedBy: Int = 0,
                       todaySpecial: String? = nil, boosted: Bool = false,
                       lat: Double = City.bishkek.latitude,
                       lng: Double = City.bishkek.longitude) -> Venue {
        Venue(
            id: id, name: "Venue \(id)", category: .cafe, district: "Центр",
            address: "ул. Тестовая 1", phone: "+996700000000", emoji: "🍽",
            gradient: [.sanAccent, .orange], imageURL: nil,
            rating: rating, reviewCount: reviews, isVerified: verified,
            savedByCount: savedBy, citySlug: City.bishkek.id, latitude: lat, longitude: lng,
            todaySpecialText: todaySpecial,
            weekHours: (0..<7).map { _ in DayHours(closed: true, open: 0, close: 0) },
            statusRaw: ModerationStatus.approved.rawValue, isPaused: false,
            boostedUntil: boosted ? Calendar.current.date(byAdding: .day, value: 7, to: .now) : nil)
    }

    private func deal(_ id: String, venueID: String, start: Date? = nil,
                      daysValid: Int = 30) -> Deal {
        Deal(
            id: id, venueID: venueID, type: .discount, title: "Deal \(id)",
            details: "", emoji: "🔥", oldPrice: nil, newPrice: 100, discountPercent: 20,
            validUntil: Calendar.current.date(byAdding: .day, value: daysValid, to: .now)!,
            status: .active, startDate: start)
    }

    // MARK: venueScore — упорядочивание по качеству и сигналам

    func testVenueScoreRanksHigherQualityAbove() async {
        let strong = venue("strong", rating: 5, reviews: 200, verified: true, savedBy: 80)
        let weak = venue("weak", rating: 3, reviews: 2, verified: false, savedBy: 0)
        let store = await makeStore(venues: [weak, strong])

        XCTAssertGreaterThan(store.venueScore(strong), store.venueScore(weak))
        // rankedVenues сортирует по venueScore по убыванию.
        XCTAssertEqual(store.rankedVenues().map(\.id), ["strong", "weak"])
    }

    func testVenueScoreVerificationAddsFixedBonus() async {
        // Два одинаковых заведения, отличие только в верификации → разница ровно +3.
        let plain = venue("plain", rating: 4, reviews: 10)
        let verified = venue("verified", rating: 4, reviews: 10, verified: true)
        let store = await makeStore(venues: [plain, verified])

        XCTAssertEqual(store.venueScore(verified) - store.venueScore(plain), 3.0, accuracy: 0.0001)
    }

    // MARK: dealScore — свежесть даёт буст

    func testDealScoreBoostsFreshDeal() async {
        let v = venue("v", rating: 4, reviews: 10)
        let fresh = deal("fresh", venueID: "v", start: .now)                    // <48ч
        let stale = deal("stale", venueID: "v",
                         start: Calendar.current.date(byAdding: .day, value: -30, to: .now))
        let store = await makeStore(venues: [v], deals: [fresh, stale])

        // Одно заведение → venueScore-слагаемое равно; решает свежесть.
        XCTAssertGreaterThan(store.dealScore(fresh), store.dealScore(stale))
        // Свежая акция раньше в органической ленте акций.
        XCTAssertEqual(store.feedDeals(category: nil).map(\.id), ["fresh", "stale"])
    }

    // MARK: feedScore — вес расстояния (haversine)

    func testFeedScoreWeightsNearbyVenueHigher() async {
        // Идентичные заведения, отличаются только координатами.
        let near = venue("near", rating: 4, reviews: 10,
                         lat: City.bishkek.latitude, lng: City.bishkek.longitude)
        let far = venue("far", rating: 4, reviews: 10,
                        lat: City.bishkek.latitude + 0.5, lng: City.bishkek.longitude + 0.5)
        let store = await makeStore(venues: [near, far])

        let me = CLLocationCoordinate2D(latitude: City.bishkek.latitude, longitude: City.bishkek.longitude)
        // Рядом со мной — выше в ленте, за счёт distance-слагаемого.
        XCTAssertEqual(store.rankedFeed(category: nil, userCoord: me).map(\.id), ["near", "far"])
        // Без координат заведения равнозначны (порядок не гарантирован, но набор — тот же).
        XCTAssertEqual(Set(store.rankedFeed(category: nil, userCoord: nil).map(\.id)), ["near", "far"])
    }

    // MARK: feedItems — каденс вставки рекламных карточек

    func testFeedItemsInsertsAdVenuesOnCadence() async {
        // 9 активных акций + 2 забустленных заведения.
        let dealVenue = venue("dv", rating: 4, reviews: 10)
        let ad1 = venue("ad1", rating: 4, reviews: 10, boosted: true)
        let ad2 = venue("ad2", rating: 4, reviews: 10, boosted: true)
        let deals = (0..<9).map { deal("d\($0)", venueID: "dv") }
        let store = await makeStore(venues: [dealVenue, ad1, ad2], deals: deals)

        let items = store.feedItems(category: nil)

        // Все акции + обе рекламные карточки присутствуют.
        let dealCount = items.filter { if case .deal = $0 { return true }; return false }.count
        let adIndexes = items.enumerated().compactMap { idx, item -> Int? in
            if case .adVenue = item { return idx }; return nil
        }
        XCTAssertEqual(dealCount, 9)
        XCTAssertEqual(items.count, 11)                 // 9 акций + 2 рекламы
        // Реклама вставляется перед 4-й акцией (i%5==3) и перед 9-й.
        XCTAssertEqual(adIndexes, [3, 9])
    }
}

// MARK: - Стаб-репозиторий (венью/акции подставляются; остальное пусто)

private final class RankingStubRepo: DataRepository {
    let venues: [Venue]
    let deals: [Deal]
    init(venues: [Venue], deals: [Deal]) { self.venues = venues; self.deals = deals }

    func fetchVenues() async throws -> [Venue] { venues }
    func fetchDeals() async throws -> [Deal] { deals }
    func fetchReviews() async throws -> [Review] { [] }   // пусто → aggregate берёт venue.rating/reviewCount
    func saveReview(_ review: Review) async throws {}
    func deleteReview(id: String) async throws {}
    func updateReviewReply(reviewID: String, reply: HostReply?) async throws {}
    func logRedemption(userID: String, dealID: String, venueID: String) async throws {}
    func recordReferral(inviteeID: String, referrerID: String) async throws {}
    func claimBonusGrants(userID: String) async throws -> Int { 0 }
    func createGiftCoupon(title: String, code: String, fromName: String) async throws {}
    func claimGiftCoupon(code: String) async throws -> GiftInfo? { nil }
    func fetchCategories() async throws -> [RemoteCategory] { [] }
}

/// In-memory настройки — изолируют тесты от UserDefaults.
private final class InMemoryPreferences: LocalPreferencesStore {
    private var sets: [String: Set<String>] = [:]
    private var strings: [String: String] = [:]
    func stringSet(forKey key: String) -> Set<String> { sets[key] ?? [] }
    func setStringSet(_ value: Set<String>, forKey key: String) { sets[key] = value }
    func string(forKey key: String) -> String? { strings[key] }
    func setString(_ value: String, forKey key: String) { strings[key] = value }
}
