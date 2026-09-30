import XCTest
@testable import AyantDomain

/// Правила разбора PDF-меню. Фрагменты повторяют вёрстку настоящих меню
/// Бишкека, на которых правила подбирались: «таблица» (ZERNO: название,
/// граммовка и цена в строку), «карточки» (NAVAT: НАЗВАНИЕ, описание,
/// `35 cm 820 som`), барная карта (FRUNZE: `0.33/0.7L 90/180KGS`).
/// Новая вёрстка, которую парсер читает неверно, — новый тест здесь.
final class MenuTextParserTests: XCTestCase {

    /// Фрагмент в пунктах страницы 595×842, начало сверху слева.
    private func f(_ text: String, x: Double, y: Double, w: Double? = nil, h: Double = 10,
                   page: Int = 0) -> MenuTextFragment {
        MenuTextFragment(page: page, text: text, x: x, y: y, width: w ?? Double(text.count) * 5,
                         height: h, pageWidth: 595)
    }

    private func names(_ items: [MenuDraftItem]) -> [String] { items.map(\.name) }

    // MARK: Цена

    func testPriceFormats() {
        let cases: [(String, String, Int, String)] = [
            ("Лагман 350", "Лагман", 350, ""),
            ("Лагман ........ 350 сом", "Лагман", 350, ""),
            ("Плов 380 с", "Плов", 380, ""),
            ("Шашлык 1 200", "Шашлык", 1200, ""),
            ("Шашлык 1.200", "Шашлык", 1200, ""),
            ("Манты 450,00", "Манты", 450, ""),
            ("Salad with beef 240gr 650", "Salad with beef", 650, "240 gr"),
            ("Specialty cheeses 330/470gr 720/1220", "Specialty cheeses", 720, "330/470 gr 720/1220"),
            ("35 cm 820 som", "", 820, "35 cm"),
            ("0.33/0.7L 90/180KGS", "", 90, "0.33/0.7 L 90/180"),
            ("150 g/3 pcs 290 som", "", 290, "150 g 3 pcs"),
            ("• 380", "", 380, ""),
        ]
        for (text, body, value, note) in cases {
            let m = MenuPrice.parse(text)
            XCTAssertEqual(m?.body, body, text)
            XCTAssertEqual(m?.value, value, text)
            XCTAssertEqual(m?.note, note, text)
        }
    }

    func testThingsThatAreNotPrices() {
        for text in ["Лагман 350 г", "Вода 0,5 л", "Service 15%", "Доставка 24/7", "Меню 2024",
                     "Манты 5", "Бешбармак", "Сет на 4 персоны"] {
            XCTAssertNil(MenuPrice.parse(text), text)
        }
    }

    // MARK: Таблица

    func testTableLayoutWithWeightColumnWrappedNamesAndNotes() {
        let items = MenuTextParser.parse([
            f("SOUP", x: 36, y: 50, h: 16),
            f("Chicken soup with homemade", x: 36, y: 80, h: 9),
            f("240gr", x: 216, y: 81, h: 8),
            f("280", x: 250, y: 79, h: 11),
            f("noodles and quail egg", x: 36, y: 90, h: 9),          // перенос названия
            f("Okroshka", x: 36, y: 108, h: 9),
            f("*NEW", x: 90, y: 104, h: 5),                          // пометка-надстрочник
            f("365gr", x: 216, y: 109, h: 8),
            f("390", x: 250, y: 107, h: 11),
            f("Assorted bread", x: 36, y: 126, h: 9),
            f("100", x: 250, y: 125, h: 11),
            f("rye bread, cornbread, onion bread", x: 36, y: 136, h: 8),   // состав
            f("Rye bread/Onion bread", x: 36, y: 150, h: 9),
            f("60/70", x: 230, y: 149, h: 11),
        ])
        XCTAssertEqual(names(items), ["Chicken soup with homemade noodles and quail egg", "Okroshka",
                                      "Assorted bread", "Rye bread/Onion bread"])
        XCTAssertEqual(items.map(\.section), ["Soup", "Soup", "Soup", "Soup"])
        XCTAssertEqual(items.map(\.price), [280, 390, 100, 60])
        XCTAssertEqual(items[0].details, "240 gr")
        XCTAssertEqual(items[2].details, "rye bread, cornbread, onion bread")
        XCTAssertEqual(items[3].details, "60/70")
    }

    func testTwoColumnsAreReadOneAfterAnother() {
        let items = MenuTextParser.parse([
            f("BREAD", x: 36, y: 50, h: 16), f("SALADS", x: 325, y: 50, h: 16),
            f("Brioche", x: 36, y: 80), f("100", x: 250, y: 80),
            f("Greek salad", x: 325, y: 80), f("450", x: 540, y: 80),
            f("Cornbread", x: 36, y: 100), f("70", x: 250, y: 100),
            f("Caesar", x: 325, y: 100), f("520", x: 540, y: 100),
        ])
        XCTAssertEqual(names(items), ["Brioche", "Cornbread", "Greek salad", "Caesar"])
        XCTAssertEqual(items.map(\.section), ["Bread", "Bread", "Salads", "Salads"])
    }

    func testRussianDotLeadersAndNumberedItems() {
        let items = MenuTextParser.parse([
            f("ГОРЯЧИЕ БЛЮДА", x: 40, y: 40, h: 16),
            f("1. Лагман по-уйгурски ............ 350 с", x: 40, y: 70, w: 400),
            f("2. Плов чайханский ................ 380 с", x: 40, y: 90, w: 400),
            f("рис девзира, баранина, морковь", x: 40, y: 101, w: 200, h: 8),
        ])
        XCTAssertEqual(names(items), ["Лагман по-уйгурски", "Плов чайханский"])
        XCTAssertEqual(items.map(\.price), [350, 380])
        XCTAssertEqual(items[0].section, "Горячие блюда")
        XCTAssertEqual(items[1].details, "рис девзира, баранина, морковь")
    }

    func testFooterAfterGapIsNotADescription() {
        let items = MenuTextParser.parse([
            f("Chef's honey cake", x: 36, y: 100), f("360", x: 250, y: 100),
            f("Please warn us about your allergies and", x: 36, y: 300, w: 200),
            f("other food preferences", x: 36, y: 312, w: 120),
            f("+996 709 31 78 79", x: 36, y: 330),
        ])
        XCTAssertEqual(names(items), ["Chef's honey cake"])
        XCTAssertEqual(items[0].details, "")
    }

    func testRepeatedTagLinesAreDropped() {
        var frags: [MenuTextFragment] = []
        for (i, name) in ["Okroshka", "Gazpacho", "Tortellini"].enumerated() {
            let y = 60 + Double(i) * 30
            frags += [f(name, x: 36, y: y), f("390", x: 250, y: y),
                      f("The seasons of Kyrgyzstan SUMMER", x: 36, y: y + 11, w: 100, h: 7)]
        }
        let items = MenuTextParser.parse(frags)
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.allSatisfy { $0.details.isEmpty })
    }

    // MARK: Карточки

    func testCardLayoutWithSectionAboveName() {
        let items = MenuTextParser.parse([
            f("PIZZA", x: 441, y: 80, h: 26),
            f("CHICKEN PIZZA", x: 397, y: 150, h: 19),
            f("A light pizza with tender baked", x: 397, y: 170, h: 14),
            f("chicken breast, mushrooms", x: 397, y: 181, h: 14),
            f("35 cm 820 som", x: 397, y: 205, h: 19),
            f("Recommend", x: 139, y: 300, h: 26),
            f("PIZZA CAESAR", x: 380, y: 400, h: 19),
            f("Everyone's favourite salad in pizza form", x: 380, y: 420, h: 14),
            f("35 cm 840 som", x: 380, y: 445, h: 19),
        ])
        XCTAssertEqual(names(items), ["Chicken pizza", "Pizza caesar"])
        XCTAssertEqual(items.map(\.section), ["Pizza", "Pizza"])
        XCTAssertEqual(items.map(\.price), [820, 840])
        XCTAssertEqual(items[0].details, "A light pizza with tender baked chicken breast, mushrooms 35 cm")
    }

    func testCardVariantsAndSecondSize() {
        let items = MenuTextParser.parse([
            f("CHEBUREKS", x: 268, y: 157, h: 18),
            f("with chives", x: 269, y: 176, h: 13),
            f("150 g/3 pcs 290 som", x: 271, y: 190, h: 19),
            f("with chicken and cheese", x: 269, y: 214, h: 13),
            f("150 g/3 pcs 320 som", x: 271, y: 228, h: 19),
            f("BOORSOKS", x: 268, y: 300, h: 18),
            f("200 g 130 som", x: 268, y: 318, h: 19),
            f("1 kg 560 som", x: 268, y: 336, h: 19),
        ])
        XCTAssertEqual(names(items), ["Chebureks with chives", "Chebureks with chicken and cheese", "Boorsoks"])
        XCTAssertEqual(items.map(\.price), [290, 320, 130])
        XCTAssertEqual(items[2].details, "200 g 1 kg 560")
    }

    func testBarCardWithVolumeAndTwoPrices() {
        let items = MenuTextParser.parse([
            f("LEGEND", x: 314, y: 120, h: 16),
            f("Spring water of glacial origin, extracted from", x: 314, y: 145, w: 280, h: 11),
            f("the foothills of Ala-Archa.", x: 314, y: 158, w: 150, h: 11),
            f("0.33/0.7L 90/180KGS", x: 314, y: 180, h: 11),
            f("VOSS", x: 314, y: 240, h: 16),
            f("Mineral water from Norway.", x: 314, y: 262, w: 160, h: 11),
            f("0.375L 600KGS", x: 314, y: 280, h: 11),
        ])
        XCTAssertEqual(names(items), ["Legend", "Voss"])
        XCTAssertEqual(items.map(\.price), [90, 600])
        XCTAssertTrue(items[0].details.hasSuffix("0.33/0.7 L 90/180"), items[0].details)
    }

    func testFreeBadgesAreStrippedButGlutenFreeDishStays() {
        let items = MenuTextParser.parse([
            f("Gluten-free", x: 36, y: 60), f("100", x: 250, y: 60),
            f("Salmon with smoked cauliflowerLUTEn-FREE", x: 36, y: 80, w: 200), f("1250", x: 250, y: 80),
            f("Pike perch with potatoes and Ten fRee", x: 36, y: 100, w: 200), f("950", x: 250, y: 100),
            f("Grilled vegetables with Pesto sauce GARFRE", x: 36, y: 120, w: 200), f("300", x: 250, y: 120),
        ])
        XCTAssertEqual(names(items), ["Gluten-free", "Salmon with smoked cauliflower",
                                      "Pike perch with potatoes and", "Grilled vegetables with Pesto sauce"])
    }

    func testServiceChargeAndBadgesAreNotDishes() {
        let items = MenuTextParser.parse([
            f("NEW Chef Nicoise", x: 40, y: 60), f("750", x: 300, y: 60),
            f("Service 15%", x: 40, y: 80),
            f("New", x: 40, y: 100, h: 20),
            f("Shiso salad", x: 40, y: 130), f("600", x: 300, y: 130),
        ])
        XCTAssertEqual(names(items), ["Chef Nicoise", "Shiso salad"])
    }

    func testTextOutsidePageDoesNotCrash() {
        // Вылет за поля (фон, повёрнутые подписи) — не падение, а просто текст.
        let items = MenuTextParser.parse([
            f("Лагман", x: -20, y: 60), f("350", x: 700, y: 60),
            f("Плов", x: 40, y: 80), f("380", x: 300, y: 80),
        ])
        XCTAssertTrue(items.contains { $0.name == "Плов" && $0.price == 380 })
    }
}

/// Меню из таблиц: CSV и строки Excel (Excel сводится к тем же строкам ячеек
/// в `MenuXLSXReader`).
final class MenuTableTests: XCTestCase {

    func testHeaderInRussianWithCategoryColumnAndTitleRowAbove() {
        let items = MenuTable.items(from: [MenuTable.Sheet(name: "Кухня", rows: [
            ["Прайс кафе «Пармезан» на сентябрь"],
            ["Категория", "Наименование блюда", "Выход, г", "Цена, сом", "Описание"],
            ["Супы", "Лагман", "350/50", "350", "Домашняя лапша"],
            ["", "Шорпо", "400", "320", ""],
            ["Горячее", "Манты (5 шт)", "", "400 сом", ""],
        ])])
        XCTAssertEqual(items.map(\.name), ["Лагман", "Шорпо", "Манты (5 шт)"])
        XCTAssertEqual(items.map(\.section), ["Супы", "Супы", "Горячее"])
        XCTAssertEqual(items.map(\.price), [350, 320, 400])
        XCTAssertEqual(items[0].details, "Домашняя лапша 350/50")
    }

    func testEnglishHeaderWithSectionRows() {
        let items = MenuTable.items(from: [MenuTable.Sheet(name: "", rows: [
            ["Name", "Price", "Size"],
            ["COFFEE"],
            ["Espresso", "170", "30 ml"],
            ["Капучино", "1 200", "300 мл"],
        ])])
        XCTAssertEqual(items.map(\.name), ["Espresso", "Капучино"])
        XCTAssertEqual(items.map(\.section), ["Coffee", "Coffee"])
        XCTAssertEqual(items.map(\.price), [170, 1200])
    }

    func testNoHeaderColumnsAreInferredFromContent() {
        let items = MenuTable.items(from: [MenuTable.Sheet(name: "", rows: [
            ["САЛАТЫ"],
            ["Цезарь с курицей", "салат, курица, пармезан, соус", "450"],
            ["Греческий", "огурцы, томаты, фета", "390"],
            ["ДЕСЕРТЫ"],
            ["Чизкейк", "", "350"],
        ])])
        XCTAssertEqual(items.map(\.name), ["Цезарь с курицей", "Греческий", "Чизкейк"])
        XCTAssertEqual(items.map(\.section), ["Салаты", "Салаты", "Десерты"])
        XCTAssertEqual(items[0].details, "салат, курица, пармезан, соус")
    }

    func testSheetNamesBecomeSectionsWhenThereAreSeveral() {
        let items = MenuTable.items(from: [
            MenuTable.Sheet(name: "Кухня", rows: [["Лагман", "350"]]),
            MenuTable.Sheet(name: "Бар", rows: [["Чай", "150"]]),
        ])
        XCTAssertEqual(items.map(\.section), ["Кухня", "Бар"])
    }

    // MARK: CSV

    func testCSVWithSemicolonsQuotesAndCP1251() {
        let csv = "Название;Цена;Состав\r\nСупы;;\r\nЛагман;350;\"Лапша; говядина\"\r\n\"Плов \"\"Ош\"\"\";380;\"Рис,\r\nбаранина\"\r\n"
        let rows = MenuTable.csvRows(csv.data(using: .windowsCP1251)!)
        XCTAssertEqual(rows[2], ["Лагман", "350", "Лапша; говядина"])
        XCTAssertEqual(rows[3], ["Плов \"Ош\"", "380", "Рис,\r\nбаранина"])
        let items = MenuTable.items(from: [MenuTable.Sheet(name: "", rows: rows)])
        XCTAssertEqual(items.map(\.name), ["Лагман", "Плов \"Ош\""])
        XCTAssertEqual(items.map(\.section), ["Супы", "Супы"])
    }

    func testCSVWithBOMCommasAndNoHeader() {
        let rows = MenuTable.csvRows(Data("\u{FEFF}Лагман,350\nШорпо,320\n".utf8))
        XCTAssertEqual(rows, [["Лагман", "350"], ["Шорпо", "320"]])
        let items = MenuTable.items(from: [MenuTable.Sheet(name: "", rows: rows)])
        XCTAssertEqual(items.map(\.price), [350, 320])
    }

    func testFileKindByExtension() {
        XCTAssertEqual(MenuFileKind(fileName: "Меню.PDF"), .pdf)
        XCTAssertEqual(MenuFileKind(fileName: "price.xlsx"), .xlsx)
        XCTAssertEqual(MenuFileKind(fileName: "menu.csv"), .csv)
        XCTAssertNil(MenuFileKind(fileName: "menu.xls"), "старый двоичный Excel не читаем")
    }
}
