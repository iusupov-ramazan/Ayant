import XCTest
@testable import AyantDomain

/// Русский счёт. Тест держит две ловушки, на которых ошибаются всегда:
/// подростковые числа и круглые десятки.
final class PluralTests: XCTestCase {

    private func minutes(_ n: Int) -> String {
        "\(n) " + Plural.ru(n, "минута", "минуты", "минут")
    }

    func testSingularFewMany() {
        XCTAssertEqual(minutes(1), "1 минута")
        XCTAssertEqual(minutes(2), "2 минуты")
        XCTAssertEqual(minutes(4), "4 минуты")
        XCTAssertEqual(minutes(5), "5 минут")
        XCTAssertEqual(minutes(0), "0 минут")
    }

    func testTeensAreAlwaysMany() {
        for n in 11...14 { XCTAssertEqual(minutes(n), "\(n) минут") }
        XCTAssertEqual(minutes(111), "111 минут", "сто одиннадцать — тоже подростковое")
    }

    func testTensAndHundreds() {
        XCTAssertEqual(minutes(21), "21 минута")
        XCTAssertEqual(minutes(22), "22 минуты")
        XCTAssertEqual(minutes(25), "25 минут")
        XCTAssertEqual(minutes(100), "100 минут")
        XCTAssertEqual(minutes(101), "101 минута")
    }

    func testNegativeCountsLikeItsAbsoluteValue() {
        XCTAssertEqual(Plural.ru(-1, "минута", "минуты", "минут"), "минута")
    }
}
