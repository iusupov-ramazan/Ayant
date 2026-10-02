import XCTest
@testable import AyantDomain

/// Контакты заведения в том виде, в каком их вводят хозяева.
final class ContactLinksTests: XCTestCase {

    func testWhatsAppLocalNumberGetsCountryCode() {
        XCTAssertEqual(ContactLinks.whatsapp("0555 123 456")?.absoluteString, "https://wa.me/996555123456")
        XCTAssertEqual(ContactLinks.whatsapp("555123456")?.absoluteString, "https://wa.me/996555123456")
    }

    func testWhatsAppInternationalFormsAreKept() {
        XCTAssertEqual(ContactLinks.whatsapp("+996 (555) 12-34-56")?.absoluteString, "https://wa.me/996555123456")
        XCTAssertEqual(ContactLinks.whatsapp("996555123456")?.absoluteString, "https://wa.me/996555123456")
        XCTAssertEqual(ContactLinks.whatsapp("00996555123456")?.absoluteString, "https://wa.me/996555123456")
        XCTAssertEqual(ContactLinks.whatsapp("+7 701 123 45 67")?.absoluteString, "https://wa.me/77011234567")
        XCTAssertEqual(ContactLinks.whatsapp("wa.me/996555123456")?.absoluteString, "https://wa.me/996555123456")
    }

    func testWhatsAppGarbageIsNil() {
        XCTAssertNil(ContactLinks.whatsapp(""))
        XCTAssertNil(ContactLinks.whatsapp("нет"))
        XCTAssertNil(ContactLinks.whatsapp("123"))
    }

    func testInstagramVariants() {
        let expected = "https://instagram.com/navat.kg"
        XCTAssertEqual(ContactLinks.instagram("navat.kg")?.absoluteString, expected)
        XCTAssertEqual(ContactLinks.instagram("@navat.kg")?.absoluteString, expected)
        XCTAssertEqual(ContactLinks.instagram("instagram.com/navat.kg")?.absoluteString, expected)
        XCTAssertEqual(ContactLinks.instagram("https://instagram.com/navat.kg")?.absoluteString, expected)
        XCTAssertEqual(ContactLinks.instagram("www.instagram.com/navat.kg")?.absoluteString,
                       "https://www.instagram.com/navat.kg")
        XCTAssertNil(ContactLinks.instagram("  "))
    }

    func testTelegramVariants() {
        XCTAssertEqual(ContactLinks.telegram("@navat_bot")?.absoluteString, "https://t.me/navat_bot")
        XCTAssertEqual(ContactLinks.telegram("t.me/navat_bot")?.absoluteString, "https://t.me/navat_bot")
        XCTAssertEqual(ContactLinks.telegram("http://t.me/navat_bot")?.absoluteString, "https://t.me/navat_bot")
        XCTAssertEqual(ContactLinks.telegram("navat_bot")?.absoluteString, "https://t.me/navat_bot")
    }
}
