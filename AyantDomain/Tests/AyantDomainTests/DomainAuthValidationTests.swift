import XCTest
@testable import AyantDomain

/// Проверки формы входа. Правило общее для iOS и Android — тест здесь
/// фиксирует его словами, а не «как получилось на экране».
final class DomainAuthValidationTests: XCTestCase {

    // MARK: Почта

    func testAcceptsOrdinaryAddresses() {
        for email in ["user@mail.ru", "a.b-c@sub.domain.kg", "ЮЗЕР@почта.рф", " User@Mail.RU "] {
            XCTAssertTrue(AuthValidation.isValidEmail(email), email)
        }
    }

    func testRejectsAddressWithoutAtOrDot() {
        for email in ["", "abc", "a@", "@mail.ru", "a@b", "a b@mail.ru", "a@@mail.ru",
                      "a@mail.", "a@.ru", "a@mail.r"] {
            XCTAssertFalse(AuthValidation.isValidEmail(email), email)
        }
    }

    /// Почта нормализуется, иначе « User@Mail.ru » и «user@mail.ru» станут
    /// двумя разными аккаунтами.
    func testNormalizedEmailTrimsAndLowercases() {
        XCTAssertEqual(AuthValidation.normalizedEmail("  User@Mail.RU "), "user@mail.ru")
    }

    // MARK: Имя

    func testAcceptsHumanNames() {
        for name in ["Аяна", "Иван Петров", "Жийде-Айым", "O'Brian", "Ai"] {
            XCTAssertTrue(AuthValidation.isValidName(name), name)
        }
    }

    func testRejectsDigitsSymbolsAndEmoji() {
        for name in ["", "A", "Иван228", "user_name", "🙂🙂", "<script>", "Иван!", String(repeating: "а", count: 41)] {
            XCTAssertFalse(AuthValidation.isValidName(name), name)
        }
    }

    // MARK: Пароль

    func testPasswordNeedsSixCharacters() {
        XCTAssertFalse(AuthValidation.isValidPassword("12345"))
        XCTAssertTrue(AuthValidation.isValidPassword("123456"))
    }

    // MARK: Готовность формы

    func testEmptyFormCannotBeSubmitted() {
        XCTAssertFalse(AuthValidation.canSignIn(email: "", password: ""))
        XCTAssertFalse(AuthValidation.canSignIn(email: "user@mail.ru", password: ""))
        XCTAssertFalse(AuthValidation.canSignIn(email: "", password: "123456"))
        XCTAssertTrue(AuthValidation.canSignIn(email: "user@mail.ru", password: "123456"))
    }

    func testRegistrationAlsoNeedsValidName() {
        XCTAssertFalse(AuthValidation.canRegister(name: "", email: "user@mail.ru", password: "123456"))
        XCTAssertFalse(AuthValidation.canRegister(name: "Иван1", email: "user@mail.ru", password: "123456"))
        XCTAssertTrue(AuthValidation.canRegister(name: "Иван", email: "user@mail.ru", password: "123456"))
    }

    /// Подсказка молчит на пустом поле: иначе форма краснеет при открытии.
    func testHintsStaySilentUntilSomethingIsTyped() {
        XCTAssertNil(AuthValidation.emailHint(""))
        XCTAssertNil(AuthValidation.nameHint("  "))
        XCTAssertNil(AuthValidation.passwordHint(""))
        XCTAssertNotNil(AuthValidation.emailHint("abc"))
        XCTAssertNotNil(AuthValidation.nameHint("Иван228"))
        XCTAssertNotNil(AuthValidation.passwordHint("123"))
    }
}
