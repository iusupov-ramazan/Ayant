import XCTest
@testable import AyantDomain

/// Фильтр отзывов перед публикацией (Guidelines 1.2). Главное здесь — не
/// только поймать мат, но и НЕ поймать обычные слова: ложное срабатывание
/// хуже пропуска, человек просто не сможет опубликовать нормальный отзыв.
final class ContentFilterTests: XCTestCase {

    func testCleanReviewsPass() {
        let clean = [
            "Очень вкусно, плов отличный, обслуживание быстрое!",
            "Хлеб свежий, небо над террасой красивое, официант мудрый человек.",
            "Колебался между двумя блюдами, взял лагман — не пожалел.",
            "Учебный день закончился, зашли с друзьями. Цена 1 200 сом, порция 350 г.",
            "Застрахуйте себя от плохого настроения — приходите сюда :)",
            "Оскорблять персонал не стоит, они стараются. 5 рублей сдачи вернули.",
            "Тамак абдан даамдуу экен, рахмат!",
            "Great place, the dickens of a good dinner. Shiitake soup was nice.",
            "Скидка 20% до 23:00, столик на 4 человек.",
        ]
        for text in clean {
            XCTAssertNil(ContentFilter.check(text), text)
        }
    }

    func testRussianProfanityIsBlocked() {
        for text in ["Какая же это хуйня", "Официант — мудак", "пиздец как долго",
                     "бля, остыло", "Сука, опять опоздали", "заебали ждать", "Ёбаный сервис"] {
            XCTAssertEqual(ContentFilter.check(text), .profanity, text)
        }
    }

    func testMaskedProfanityIsBlocked() {
        // Латинские двойники и точки между буквами.
        XCTAssertEqual(ContentFilter.check("полная xуйня"), .profanity)
        XCTAssertEqual(ContentFilter.check("cyka"), .profanity)
        XCTAssertEqual(ContentFilter.check("х.у.й"), .profanity)
    }

    func testKyrgyzAndEnglishProfanityIsBlocked() {
        XCTAssertEqual(ContentFilter.check("сиктир бул жерден"), .profanity)
        XCTAssertEqual(ContentFilter.check("What the fuck is this"), .profanity)
        XCTAssertEqual(ContentFilter.check("total bullshit"), .profanity)
        XCTAssertEqual(ContentFilter.check("the waiter is a bitch"), .profanity)
    }

    func testLinksAreBlocked() {
        for text in ["Лучше идите на https://example.com", "смотрите www.promo.kg",
                     "пишите t.me/spammer", "заказ на cheapfood.ru дешевле"] {
            XCTAssertEqual(ContentFilter.check(text), .link, text)
        }
    }

    func testPhonesAreBlocked() {
        for text in ["Звоните +996 555 123 456", "WhatsApp 0555-12-34-56",
                     "номер (0700) 123456"] {
            XCTAssertEqual(ContentFilter.check(text), .phone, text)
        }
    }

    func testMessagesAreCatalogKeys() {
        XCTAssertEqual(ContentFilter.Violation.profanity.message, "Отзыв содержит недопустимые слова")
        XCTAssertEqual(ContentFilter.Violation.phone.message, ContentFilter.Violation.link.message)
    }
}
