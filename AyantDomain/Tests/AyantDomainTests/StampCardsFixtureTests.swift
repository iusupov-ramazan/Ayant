import XCTest
@testable import AyantDomain

/// Прогон общего фикстура `specs/fixtures/stamp-cards-fixtures.json` через
/// `StampCards`. Тот же файл гоняет `functions/test/stampCardsFixture.test.js`
/// через серверные `activeStampCards`/`stampCardDocID` — расхождение правил
/// клиента и сервера ловится здесь. Новый случай — в JSON.
final class StampCardsFixtureTests: XCTestCase {

    private static let fixtureURL: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // AyantDomainTests/
        .deletingLastPathComponent()   // Tests/
        .deletingLastPathComponent()   // AyantDomain/
        .deletingLastPathComponent()   // корень репозитория
        .appendingPathComponent("specs/fixtures/stamp-cards-fixtures.json")

    private func fixture() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.fixtureURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testDocIDs() throws {
        let cases = try XCTUnwrap(fixture()["docID"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let cardID = c["cardID"] as? String ?? ""
            XCTAssertEqual(StampCards.ledgerDocID(userID: c["userID"] as? String ?? "",
                                                  venueID: c["venueID"] as? String ?? "",
                                                  cardID: cardID),
                           c["expect"] as? String)
            XCTAssertEqual(StampCards.isFirstCard(cardID), (c["collection"] as? String) == "loyaltyCards",
                           "коллекция для «\(cardID)»")
        }
    }

    func testActiveCards() throws {
        let cases = try XCTUnwrap(fixture()["active"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let name = c["name"] as? String ?? "?"
            let venue = c["venue"] as? [String: Any] ?? [:]
            // Разбор — как в `FirestoreMapping` (Venue и `StampCard.parse`):
            // отсутствующая цель → 6, отсутствующий текст → "".
            let extras = (venue["stampCards"] as? [[String: Any]] ?? []).compactMap { m -> StampCard? in
                guard let id = m["id"] as? String else { return nil }
                return StampCard(id: id, title: m["title"] as? String ?? "",
                                 goal: m["goal"] as? Int ?? StampCards.defaultGoal,
                                 reward: m["reward"] as? String ?? "",
                                 active: m["active"] as? Bool ?? true)
            }
            let cards = StampCards.active(
                enabled: venue["loyaltyEnabled"] as? Bool ?? false,
                title: venue["loyaltyTitle"] as? String ?? "",
                goal: venue["loyaltyGoal"] as? Int ?? StampCards.defaultGoal,
                reward: venue["loyaltyReward"] as? String ?? StampCards.defaultReward,
                extras: StampCards.sanitizedExtras(extras))
            let expect = (c["expect"] as? [[Any]] ?? []).map { row in
                "\(row[0])|\(row[1])|\(row[2])|\(row[3])"
            }
            XCTAssertEqual(cards.map { "\($0.id)|\($0.title)|\($0.goal)|\($0.reward)" }, expect, name)
        }
    }
}
