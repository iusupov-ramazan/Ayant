import XCTest
@testable import AyantDomain

/// Тесты сборки ленты. Смысл именно в том, что `now` — параметр: раньше эта
/// логика жила в `AppStore`, звала `Date()` внутри и проверялась только глазами.
final class DomainFeedBuilderTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func venue(_ id: String, city: String = City.bishkek.id,
                       paused: Bool = false, status: String = "approved",
                       boosted: Date? = nil, rating: Double = 4.5,
                       reviews: Int = 100) -> Venue {
        Venue(id: id, name: id, category: .cafe, district: "Центр", address: "ул. 1",
              phone: "", emoji: "🍽", gradient: [0xFF5A1F, 0xFF9500],
              rating: rating, reviewCount: reviews, citySlug: city,
              statusRaw: status, isPaused: paused, boostedUntil: boosted)
    }

    private func deal(_ id: String, venueID: String, until: TimeInterval = 86_400) -> Deal {
        Deal(id: id, venueID: venueID, type: .discount, title: id, details: "", emoji: "🔥",
             validUntil: now.addingTimeInterval(until))
    }

    // MARK: Часовой пояс заведения

    /// Часы работы записаны по времени ГОРОДА. Телефон в другом поясе не должен
    /// сдвигать «открыто/закрыто»: раньше всё считалось по `Calendar.current`,
    /// и гость из Москвы видел бишкекское кафе закрытым за три часа до закрытия.
    func testOpenNowUsesCityTimeZoneNotDeviceTimeZone() {
        var venue = Venue(id: "v", name: "Кафе", category: .cafe, district: "", address: "",
                          phone: "", emoji: "☕️", gradient: [0], citySlug: City.bishkek.id)
        venue.openHour = 9
        venue.closeHour = 18

        // 2024-01-10, 12:00 по Бишкеку (06:00 UTC) — заведение открыто.
        var bishkek = Calendar(identifier: .gregorian)
        bishkek.timeZone = TimeZone(identifier: "Asia/Bishkek")!
        let noonInBishkek = bishkek.date(from: DateComponents(year: 2024, month: 1, day: 10,
                                                             hour: 12, minute: 0))!
        XCTAssertTrue(venue.isOpen(at: noonInBishkek))

        // 20:00 по Бишкеку — уже закрыто, в каком бы поясе ни был телефон.
        let eveningInBishkek = bishkek.date(from: DateComponents(year: 2024, month: 1, day: 10,
                                                                hour: 20, minute: 0))!
        XCTAssertFalse(venue.isOpen(at: eveningInBishkek))
    }

    /// День недели тоже берётся по городу: возле полуночи разница поясов
    /// перекидывала расписание на соседний день.
    func testTodayIndexUsesCityTimeZone() {
        // 2024-01-08 — понедельник. 00:30 по Бишкеку это ещё воскресенье в UTC.
        var bishkek = Calendar(identifier: .gregorian)
        bishkek.timeZone = TimeZone(identifier: "Asia/Bishkek")!
        let justAfterMidnight = bishkek.date(from: DateComponents(year: 2024, month: 1, day: 8,
                                                                 hour: 0, minute: 30))!
        XCTAssertEqual(Venue.todayIndex(at: justAfterMidnight, citySlug: City.bishkek.id), 0)
    }

    // MARK: Видимость вне ленты (поиск, карта, избранное)

    /// Отклонённое модератором заведение пропадало с главной, но продолжало
    /// находиться поиском — тот читал сырой каталог.
    func testUserVisibleHidesRejectedPendingAndPaused() {
        let venues = [venue("ok"), venue("rejected", status: "rejected"),
                      venue("pending", status: "pending"), venue("paused", paused: true)]
        XCTAssertEqual(FeedBuilder.userVisible(venues: venues).map(\.id), ["ok"])
    }

    func testUserVisibleHidesDealsOfHiddenVenuesButKeepsOrphans() {
        let venues = [venue("ok"), venue("rejected", status: "rejected")]
        let deals = [deal("d-ok", venueID: "ok"),
                     deal("d-rejected", venueID: "rejected"),
                     deal("d-orphan", venueID: "missing")]
        XCTAssertEqual(FeedBuilder.userVisible(deals: deals, venues: venues).map(\.id),
                       ["d-ok", "d-orphan"])
    }

    // MARK: Видимость

    func testHidesPausedAndUnapprovedAndOtherCities() {
        let catalog = FeedCatalog(venues: [
            venue("ok"),
            venue("paused", paused: true),
            venue("pending", status: "pending"),
            venue("almaty", city: "almaty"),
        ])
        let visible = FeedBuilder.visibleVenues(catalog, citySlug: City.bishkek.id).map(\.id)
        XCTAssertEqual(visible, ["ok"])
    }

    func testCategoryFilterNarrowsVenues() {
        var other = venue("bakery")
        other = Venue(id: other.id, name: other.name, category: .bakery, district: "",
                      address: "", phone: "", emoji: "🥐", gradient: [0])
        let catalog = FeedCatalog(venues: [venue("cafe"), other])
        XCTAssertEqual(FeedBuilder.visibleVenues(catalog, citySlug: City.bishkek.id,
                                                 category: .bakery).map(\.id), ["bakery"])
    }

    // MARK: Выдача

    func testOnlyActiveDealsOfVisibleVenuesReachTheFeed() {
        let catalog = FeedCatalog(
            venues: [venue("a"), venue("paused", paused: true)],
            deals: [deal("live", venueID: "a"),
                    deal("expired", venueID: "a", until: -3600),   // уже кончилась
                    deal("hidden", venueID: "paused")])
        let ids = FeedBuilder.rankedDeals(catalog, citySlug: City.bishkek.id,
                                          weights: .default, now: now).map(\.id)
        XCTAssertEqual(ids, ["live"])
    }

    func testReviewAggregateOverridesSeedRatingInScore() {
        let v = venue("a", rating: 3.0, reviews: 10)
        let seedOnly = FeedCatalog(venues: [v])
        let withReviews = FeedCatalog(venues: [v], ratings: ["a": VenueRating(rating: 5.0, count: 400)])
        XCTAssertGreaterThan(
            FeedBuilder.venueScore(v, catalog: withReviews, weights: .default, now: now),
            FeedBuilder.venueScore(v, catalog: seedOnly, weights: .default, now: now))
    }

    func testBoostedVenuesBecomeAdCardsAndRotateOverTime() {
        let boostedUntil = now.addingTimeInterval(86_400)
        let catalog = FeedCatalog(
            venues: [venue("a"), venue("ad1", boosted: boostedUntil), venue("ad2", boosted: boostedUntil)],
            deals: [deal("d", venueID: "a")])

        let ads = FeedBuilder.boostedVenues(catalog, citySlug: City.bishkek.id, now: now).map(\.id)
        XCTAssertEqual(Set(ads), ["ad1", "ad2"])

        // Ротация переставляет порядок в пределах получаса — просто проверяем,
        // что состав не меняется, а порядок вычисляется от времени.
        let later = FeedBuilder.boostedVenues(catalog, citySlug: City.bishkek.id,
                                              now: now.addingTimeInterval(3600)).map(\.id)
        XCTAssertEqual(Set(later), Set(ads))
    }

    func testFeedIsDeterministicForAFixedNow() {
        let catalog = FeedCatalog(
            venues: [venue("a"), venue("b")],
            deals: [deal("d1", venueID: "a"), deal("d2", venueID: "b")])
        let first = FeedBuilder.items(catalog, citySlug: City.bishkek.id, weights: .default, now: now)
        let second = FeedBuilder.items(catalog, citySlug: City.bishkek.id, weights: .default, now: now)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    // MARK: Состояние

    func testStateDerivesFeedAndDistinguishesEmptyCityFromEmptyCategory() {
        let catalog = FeedCatalog(venues: [venue("a")], deals: [deal("d", venueID: "a")])
        var state = FeedState(catalog: .loaded(catalog))
        XCTAssertTrue(state.hasVenuesInCity)
        XCTAssertEqual(state.items(now: now).count, 1)

        state.category = .bakery          // в городе есть заведения, но не в этой категории
        XCTAssertTrue(state.hasVenuesInCity)
        XCTAssertTrue(state.items(now: now).isEmpty)

        state.citySlug = "almaty"          // а тут города нет вовсе
        XCTAssertFalse(state.hasVenuesInCity)
    }

    func testIdleStateYieldsEmptyFeedRatherThanCrashing() {
        let state = FeedState()
        XCTAssertTrue(state.items(now: now).isEmpty)
        XCTAssertFalse(state.hasVenuesInCity)
    }
}
