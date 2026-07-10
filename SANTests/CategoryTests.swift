import XCTest
@testable import SAN

// Юнит-тесты чистой логики (без Firebase/UI).
//
// Требуется один раз добавить в проект таргет «Unit Testing Bundle» и включить
// в него эту папку (File ▸ New ▸ Target ▸ Unit Testing Bundle, имя SANTests,
// Target to be Tested = SAN). После этого тесты запускаются ⌘U и в CI.
final class CategoryTests: XCTestCase {

    override func tearDown() {
        // Тесты меняют глобальные реестры — сбрасываем, чтобы не влиять друг на друга.
        VenueCategory.iconRegistry = [:]
        VenueCategory.slugRegistry = [:]
        super.tearDown()
    }

    // MARK: VenueCategory (открытый тип вместо enum)

    func testInitRejectsEmptyAndKeepsValue() {
        XCTAssertNil(VenueCategory(rawValue: ""))
        XCTAssertEqual(VenueCategory(rawValue: "Кафе"), .cafe)
        XCTAssertEqual(VenueCategory(rawValue: "Бургеры")?.rawValue, "Бургеры")
    }

    func testBuiltinsAndAllCases() {
        XCTAssertEqual(VenueCategory.allCases.count, 6)
        XCTAssertEqual(VenueCategory.cafe.rawValue, "Кафе")
        XCTAssertEqual(VenueCategory.cafe.icon, "fork.knife")
    }

    func testIconFallbackForUnknown() {
        XCTAssertEqual(VenueCategory(rawValue: "Нечто")?.icon, "tag.fill")
    }

    func testApplyRemotePopulatesRegistries() {
        VenueCategory.applyRemote([
            RemoteCategory(slug: "burgers", name: "Бургеры", icon: "flame.fill",
                           emoji: "🍔", order: 1, enabled: true)
        ])
        XCTAssertEqual(VenueCategory(rawValue: "Бургеры")?.icon, "flame.fill")
        XCTAssertEqual(VenueCategory.slugRegistry["burgers"], "Бургеры")
    }

    // MARK: CategoryStore идёт через протокол данных (инъекция репозитория)

    @MainActor
    func testCategoryStoreLoadsEnabledSortedFromRepository() async {
        let stub = StubRepo()
        stub.cats = [
            RemoteCategory(slug: "hidden", name: "Скрытая", icon: "eye.slash",
                           emoji: "", order: 0, enabled: false),
            RemoteCategory(slug: "burgers", name: "Бургеры", icon: "flame.fill",
                           emoji: "🍔", order: 2, enabled: true),
            RemoteCategory(slug: "sushi", name: "Суши", icon: "fish.fill",
                           emoji: "🍣", order: 1, enabled: true),
        ]
        let store = CategoryStore(repository: stub)
        await store.load()
        // Только включённые, отсортированные по order.
        XCTAssertEqual(store.categories.map(\.rawValue), ["Суши", "Бургеры"])
        XCTAssertEqual(VenueCategory(rawValue: "Бургеры")?.icon, "flame.fill")
    }

    @MainActor
    func testCategoryStoreKeepsBuiltinsWhenEmpty() async {
        let store = CategoryStore(repository: StubRepo())   // отдаёт []
        await store.load()
        XCTAssertEqual(store.categories, VenueCategory.allCases)
    }

    // MARK: HostProfile — обратная совместимость декодирования

    func testHostProfileDecodesOldJSONWithoutNewFields() throws {
        let json = Data("""
        {"businessName":"Кафе X","categoryRaw":"cafe","phone":"+996700","email":"a@b.kg","verification":"none"}
        """.utf8)
        let p = try JSONDecoder().decode(HostProfile.self, from: json)
        XCTAssertEqual(p.businessName, "Кафе X")
        XCTAssertEqual(p.inn, "")          // новых полей нет → пустые значения по умолчанию
        XCTAssertEqual(p.legalForm, "")
        XCTAssertEqual(p.about, "")
    }
}

/// Заглушка репозитория: всё пусто, кроме подставляемых категорий.
private final class StubRepo: DataRepository {
    var cats: [RemoteCategory] = []
    func fetchVenues() async throws -> [Venue] { [] }
    func fetchDeals() async throws -> [Deal] { [] }
    func fetchReviews() async throws -> [Review] { [] }
    func saveReview(_ review: Review) async throws {}
    func deleteReview(id: String) async throws {}
    func updateReviewReply(reviewID: String, reply: HostReply?) async throws {}
    func logRedemption(userID: String, dealID: String, venueID: String) async throws {}
    func recordReferral(inviteeID: String, referrerID: String) async throws {}
    func claimBonusGrants(userID: String) async throws -> Int { 0 }
    func createGiftCoupon(title: String, code: String, fromName: String) async throws {}
    func claimGiftCoupon(code: String) async throws -> GiftInfo? { nil }
    func fetchCategories() async throws -> [RemoteCategory] { cats }
}
