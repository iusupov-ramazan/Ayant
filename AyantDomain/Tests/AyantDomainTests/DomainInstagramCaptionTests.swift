import XCTest
@testable import AyantDomain

/// Разбор подписи поста на заголовок и описание акции.
///
/// Главное правило, которое тут и закрепляется: описание НИЧЕГО не теряет.
/// Заголовок — витрина, и его можно обрезать; текст, который хост написал,
/// обрезать нельзя.
final class DomainInstagramCaptionTests: XCTestCase {

    func testShortFirstLineBecomesTitle() {
        let p = InstagramCaption.parse("Новое меню завтраков\nКаждый день с 8:00 до 12:00.")
        XCTAssertEqual(p.title, "Новое меню завтраков")
        XCTAssertEqual(p.details, "Каждый день с 8:00 до 12:00.")
        XCTAssertTrue(p.hashtags.isEmpty)
    }

    func testTrailingHashtagsAreStripped() {
        let p = InstagramCaption.parse("Скидка на кофе\nВесь январь\n\n#бишкек #кофе @ayant.kg")
        XCTAssertEqual(p.title, "Скидка на кофе")
        XCTAssertEqual(p.details, "Весь январь")
        XCTAssertEqual(p.hashtags, ["#бишкек", "#кофе", "@ayant.kg"])
    }

    func testHashtagInsideTextSurvives() {
        let p = InstagramCaption.parse("Ждём вас в #Ayant\nДо конца недели")
        XCTAssertEqual(p.title, "Ждём вас в #Ayant")
        XCTAssertEqual(p.details, "До конца недели")
        XCTAssertTrue(p.hashtags.isEmpty)
    }

    func testLongLineCutAtSentenceEnd() {
        let p = InstagramCaption.parse(
            "Скидка 30% на всё меню! Приходите до конца недели, будем очень рады гостям.")
        XCTAssertEqual(p.title, "Скидка 30% на всё меню")
        XCTAssertEqual(p.details, "Приходите до конца недели, будем очень рады гостям.")
    }

    func testLongLineWithoutSentenceEndKeepsWholeTextInDetails() {
        let long = "Огромное спасибо всем нашим гостям за этот невероятный год вместе с нами"
        let p = InstagramCaption.parse(long)
        XCTAssertTrue(p.title.hasSuffix("…"), "обрезанный заголовок помечается многоточием")
        XCTAssertLessThanOrEqual(p.title.count, InstagramCaption.maxTitle + 1)
        XCTAssertEqual(p.details, long, "обрезка заголовка не должна терять текст")
    }

    /// Настоящая подпись ayant_kg: законченная фраза на символ длиннее лимита.
    /// Раньше заголовок резался по слову («…без лишних…»), а описание начиналось
    /// с той же самой фразы. Теперь фраза целиком становится заголовком.
    func testWholeSentenceSlightlyOverTheLimitBecomesTitle() {
        let caption = "Ayant — приводите клиентов и растите бизнес без лишних затрат!\n\nПрисоединяйтесь к платформе."
        let p = InstagramCaption.parse(caption)
        XCTAssertEqual(p.title, "Ayant — приводите клиентов и растите бизнес без лишних затрат")
        XCTAssertFalse(p.title.hasSuffix("…"), "фраза целая — обрезки быть не должно")
        XCTAssertEqual(p.details, "Присоединяйтесь к платформе.",
                       "описание не повторяет заголовок")
    }

    /// Запас — только для законченной фразы. Предложение, которое и с запасом не
    /// влезает (92 символа), по-прежнему режется по слову.
    func testSentenceEndTooFarStillFallsBackToWordCut() {
        let caption = "Ayant это приложение которое собирает лучшие локальные заведения скидки и развлечения города!"
        let p = InstagramCaption.parse(caption)
        XCTAssertTrue(p.title.hasSuffix("…"))
        XCTAssertLessThanOrEqual(p.title.count, InstagramCaption.maxTitle + 1)
        XCTAssertEqual(p.details, caption, "текст не теряется")
    }

    func testEmptyCaption() {
        let p = InstagramCaption.parse("   \n\n  ")
        XCTAssertEqual(p.title, "")
        XCTAssertEqual(p.details, "")
    }

    func testCaptionOfOnlyHashtags() {
        let p = InstagramCaption.parse("#бишкек #еда")
        XCTAssertEqual(p.title, "")
        XCTAssertEqual(p.details, "")
        XCTAssertEqual(p.hashtags, ["#бишкек", "#еда"])
    }

    func testMediaKindMapping() {
        XCTAssertEqual(InstagramMediaKind(apiValue: "CAROUSEL_ALBUM"), .carousel)
        XCTAssertEqual(InstagramMediaKind(apiValue: "VIDEO"), .video)
        XCTAssertEqual(InstagramMediaKind(apiValue: "IMAGE"), .image)
        XCTAssertEqual(InstagramMediaKind(apiValue: "что-то новое"), .image)
    }
}
