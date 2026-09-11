import XCTest
import SwiftUI
import CoreLocation
@testable import SAN
import AyantDomain
import AyantFeatures

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
        await makeStoreWithLog(venues: venues, deals: deals).store
    }

    /// Вариант с доступом к журналу ранжирования (для проверки событий).
    private func makeStoreWithLog(venues: [Venue], deals: [Deal] = []) async
        -> (store: AppStore, log: FakeRankingEventService) {
        let repo = RankingStubRepo(venues: venues, deals: deals)
        let log = FakeRankingEventService()
        let store = AppStore(repository: repo,
                             analytics: FakeAnalyticsService(),
                             push: FakePushService(),
                             rankingLog: log,
                             prefs: InMemoryPreferences())
        await store.load()
        return (store, log)
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
            gradient: [Palette.accent, Palette.orange], imageURL: nil,
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
        // Два одинаковых заведения, отличие только в верификации → разница ровно +1.5.
        let plain = venue("plain", rating: 4, reviews: 10)
        let verified = venue("verified", rating: 4, reviews: 10, verified: true)
        let store = await makeStore(venues: [plain, verified])

        XCTAssertEqual(store.venueScore(verified) - store.venueScore(plain), 1.5, accuracy: 0.0001)
    }

    // MARK: Байесов рейтинг — редкие оценки не побеждают числом

    func testBayesianRatingShrinksSparseRatings() {
        // (v·R + m·C)/(v+m), C=4.0, m=20.
        XCTAssertEqual(Ranking.bayesianRating(rating: 5, reviewCount: 2),
                       (2 * 5.0 + 20 * 4.0) / 22.0, accuracy: 1e-9)
        // 4.6 с 400 отзывами обходит 5.0 с двумя.
        XCTAssertGreaterThan(Ranking.bayesianRating(rating: 4.6, reviewCount: 400),
                             Ranking.bayesianRating(rating: 5, reviewCount: 2))
    }

    func testWellReviewedVenueOutranksThinFiveStar() async {
        let thin = venue("thin", rating: 5, reviews: 2)
        let strong = venue("strong", rating: 4.6, reviews: 400)
        let store = await makeStore(venues: [thin, strong])
        XCTAssertEqual(store.rankedVenues().map(\.id), ["strong", "thin"])
    }

    // MARK: dealScore — глубина скидки и «скоро закончится» (чистая функция)

    func testDealScoreRewardsDiscountDepth() {
        let base = 10.0
        XCTAssertEqual(Ranking.dealScore(venueScore: base, isFresh: false, daysSinceStart: nil,
                                         discountPercent: 25, hoursUntilExpiry: nil, timeRelevance: 0.0),
                       base + 1.5, accuracy: 1e-9)                 // 25/50 → 1.5
        XCTAssertEqual(Ranking.dealScore(venueScore: base, isFresh: false, daysSinceStart: nil,
                                         discountPercent: 90, hoursUntilExpiry: nil, timeRelevance: 0.0),
                       base + 3.0, accuracy: 1e-9)                 // капнуто на 3
    }

    func testDealScoreNudgesEndingSoon() {
        let base = 10.0
        XCTAssertEqual(Ranking.dealScore(venueScore: base, isFresh: false, daysSinceStart: nil,
                                         discountPercent: nil, hoursUntilExpiry: 0, timeRelevance: 0.0),
                       base + 1.5, accuracy: 1e-9)                 // истекает сейчас
        XCTAssertEqual(Ranking.dealScore(venueScore: base, isFresh: false, daysSinceStart: nil,
                                         discountPercent: nil, hoursUntilExpiry: 100, timeRelevance: 0.0),
                       base, accuracy: 1e-9)                       // вне окна 48ч
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

    // MARK: Журнал ранжирования (learning-to-rank)

    func testImpressionLogsSlateWithRankTimeFeatures() async {
        let v = venue("v", rating: 4, reviews: 10)
        let deals = (0..<3).map { deal("d\($0)", venueID: "v") }
        let (store, log) = await makeStoreWithLog(venues: [v], deals: deals)

        store.logFeedImpression(category: nil, userCoord: nil)

        XCTAssertEqual(log.logged.count, 1)
        let e = log.logged[0]
        XCTAssertEqual(e.type, .impression)
        XCTAssertEqual(e.sessionID, store.sessionID)
        XCTAssertEqual(e.items.count, 3)
        // Позиции проставлены по порядку; фичи на момент показа сняты.
        XCTAssertEqual(e.items.map(\.position), [0, 1, 2])
        XCTAssertEqual(e.items[0].discountPercent, 20)          // из deal(): discountPercent 20
        XCTAssertGreaterThan(e.items[0].score, 0)
    }

    func testImpressionDedupesIdenticalRenders() async {
        let v = venue("v", rating: 4, reviews: 10)
        let (store, log) = await makeStoreWithLog(venues: [v], deals: [deal("d0", venueID: "v")])

        store.logFeedImpression(category: nil, userCoord: nil)
        store.logFeedImpression(category: nil, userCoord: nil)   // тот же слейт → без дубля

        XCTAssertEqual(log.logged.count, 1)
    }

    func testTapAndRedeemAreLogged() async {
        let v = venue("v", rating: 4, reviews: 10)
        let d = deal("d0", venueID: "v")
        let (store, log) = await makeStoreWithLog(venues: [v], deals: [d])

        store.logRankingTap(d)
        store.redeem(d)

        XCTAssertEqual(log.logged.map(\.type), [.tap, .redeem])
        XCTAssertEqual(log.logged[0].dealID, "d0")
        XCTAssertEqual(log.logged[1].dealID, "d0")
        XCTAssertEqual(log.logged[1].venueID, "v")
    }
}

// MARK: - Стаб-репозиторий (венью/акции подставляются; остальное пусто)

private final class RankingStubRepo: DataRepository {
    let venues: [Venue]
    let deals: [Deal]
    init(venues: [Venue], deals: [Deal]) { self.venues = venues; self.deals = deals }

    func fetchVenues() async throws -> [Venue] { venues }
    func fetchDeals() async throws -> [Deal] { deals }
    // Пусто → агрегат берёт денормализованные venue.rating/reviewCount.
    func fetchReviews(venueID: String, limit: Int) async throws -> [Review] { [] }
    func fetchReviews(venueIDs: [String], limit: Int) async throws -> [Review] { [] }
    func fetchReviews(authorID: String, limit: Int) async throws -> [Review] { [] }
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
