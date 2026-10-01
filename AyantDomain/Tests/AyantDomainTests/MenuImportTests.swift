import XCTest
@testable import AyantDomain

final class MenuImportTests: XCTestCase {

    private func draft(_ id: String, _ section: String, _ name: String, _ price: Int?,
                       _ details: String = "", include: Bool = true) -> MenuDraftItem {
        MenuDraftItem(id: id, section: section, name: name, price: price, details: details, include: include)
    }

    // MARK: Чистка — повторяет серверную (`cleanDishes`)

    func testCleanedTrimsDropsEmptyAndDuplicates() {
        let out = MenuImport.cleaned([
            draft("1", " Супы ", "  Лагман  ", 350, "  лапша  "),
            draft("2", "Супы", "лагман", 400),                  // дубль без учёта регистра
            draft("3", "", "   ", 100),                          // без названия
            draft("4", "Горячее", "Плов", -5),                   // отрицательная → нет цены
            draft("5", "Горячее", "Манты", 99_999_999),          // склеенные цифры → нет цены
        ])
        XCTAssertEqual(out.map(\.name), ["Лагман", "Плов", "Манты"])
        XCTAssertEqual(out[0].section, "Супы")
        XCTAssertEqual(out[0].details, "лапша")
        XCTAssertEqual(out.map(\.price), [350, nil, nil])
    }

    func testSameNameInDifferentSectionsIsNotADuplicate() {
        let out = MenuImport.cleaned([draft("1", "Завтраки", "Сырники", 250),
                                      draft("2", "Десерты", "Сырники", 280)])
        XCTAssertEqual(out.count, 2)
    }

    // MARK: Слияние с заведёнными блюдами

    func testMergeUpdatesExistingKeepsIdPhotoAndAppendsNew() {
        let existing = [
            VenueItem(id: "it_1", name: "Лагман", emoji: "🍜", kind: "food",
                      imageURL: "https://img/lagman.jpg", price: 300),
            VenueItem(id: "it_2", name: "Кальян", emoji: "💨", kind: "service"),   // заведён руками
        ]
        var n = 0
        let merged = MenuImport.merge(existing: existing, drafts: [
            draft("a", "Супы", "  лагман ", 350, "Домашняя лапша"),
            draft("b", "Горячее", "Плов", 380),
            draft("c", "Напитки", "Компот", nil, include: false),               // снята галочка
        ], newID: { n += 1; return "new_\(n)" })

        XCTAssertEqual(merged.map(\.id), ["it_1", "it_2", "new_1"],
                       "блюдо, заведённое руками, не удаляется; снятое — не добавляется")
        XCTAssertEqual(merged[0].price, 350, "цена обновлена")
        XCTAssertEqual(merged[0].details, "Домашняя лапша")
        XCTAssertEqual(merged[0].section, "Супы")
        XCTAssertEqual(merged[0].imageURL, "https://img/lagman.jpg", "фото хозяина сохранено")
        XCTAssertEqual(merged[0].name, "Лагман", "название — как у хозяина")
        XCTAssertEqual(merged[2].name, "Плов")
        XCTAssertEqual(merged[2].kind, "food")
    }

    func testMergeDoesNotEraseDetailsWithEmptyDraft() {
        let existing = [VenueItem(id: "it_1", name: "Плов", emoji: "🍚", kind: "food",
                                  details: "Рис девзира", section: "Горячее")]
        let merged = MenuImport.merge(existing: existing, drafts: [draft("a", "", "Плов", 400)],
                                      newID: { "x" })
        XCTAssertEqual(merged[0].details, "Рис девзира")
        XCTAssertEqual(merged[0].section, "Горячее")
        XCTAssertEqual(merged[0].price, 400)
    }

    func testUpdatesCountCountsOnlyIncludedMatches() {
        let existing = [VenueItem(id: "1", name: "Плов", emoji: "", kind: "food")]
        XCTAssertEqual(MenuImport.updatesCount(existing: existing, drafts: [
            draft("a", "", "плов", 1), draft("b", "", "Лагман", 1), draft("c", "", "Плов ", 1, include: false),
        ]), 1)
    }

    func testGroupedKeepsMenuOrder() {
        let groups = MenuImport.grouped(["Супы:Лагман", "Горячее:Плов", "Супы:Шорпо"]) {
            String($0.split(separator: ":")[0])
        }
        XCTAssertEqual(groups.map(\.section), ["Супы", "Горячее"])
        XCTAssertEqual(groups[0].items.count, 2)
    }

    // MARK: Кэш

    func testOldCachedItemDecodesWithoutNewFields() throws {
        let old = #"{"id":"it_1","name":"Лагман","emoji":"🍜","kind":"food","imageURL":""}"#
        let item = try JSONDecoder().decode(VenueItem.self, from: Data(old.utf8))
        XCTAssertNil(item.price)
        XCTAssertEqual(item.details, "")
        XCTAssertEqual(item.section, "")
    }

    // MARK: Разделы при ручном добавлении

    private func dish(_ name: String, _ section: String) -> VenueItem {
        VenueItem(id: name, name: name, emoji: "🍽", kind: "food", section: section)
    }

    func testSectionsKeepMenuOrderWithoutEmptyAndRepeats() {
        let menu = [dish("Лагман", "Супы"), dish("Чай", ""), dish("Плов", "Горячее"), dish("Шорпо", "Супы")]
        XCTAssertEqual(MenuImport.sections(menu), ["Супы", "Горячее"])
    }

    func testCanonicalSectionSnapsToExistingSpelling() {
        let existing = ["Супы", "Горячее"]
        // Регистр и лишние пробелы не заводят второй раздел «Супы».
        XCTAssertEqual(MenuImport.canonicalSection("  супы ", existing: existing), "Супы")
        XCTAssertEqual(MenuImport.canonicalSection("ГОРЯЧЕЕ", existing: existing), "Горячее")
        // Новый раздел — как ввели, но очищенный.
        XCTAssertEqual(MenuImport.canonicalSection(" Десерты  дня ", existing: existing), "Десерты дня")
        // Пустой — блюдо без раздела.
        XCTAssertEqual(MenuImport.canonicalSection("   ", existing: existing), "")
    }
}
