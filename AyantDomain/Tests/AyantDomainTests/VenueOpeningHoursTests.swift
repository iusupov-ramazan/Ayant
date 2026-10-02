import XCTest
@testable import AyantDomain

/// «Открыто сейчас» со сменами через полночь. Время — по Бишкеку (UTC+6).
final class VenueOpeningHoursTests: XCTestCase {

    /// 2026-10-02 — пятница. `day` 2 = пятница, 3 = суббота.
    private func bishkek(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = day; c.hour = hour; c.minute = minute
        return City.calendar(forSlug: City.bishkek.id).date(from: c)!
    }

    /// Пн…Вс. Пятница 18:00–02:00, суббота — как указано.
    private func venue(friday: DayHours, saturday: DayHours) -> Venue {
        var week = Venue.defaultWeek()
        week[4] = friday
        week[5] = saturday
        return Venue(id: "v", name: "Бар", category: .cafe, district: "", address: "",
                     phone: "", emoji: "🍸", gradient: [0], weekHours: week)
    }

    func testFridayNightShiftIsOpenAfterMidnightOnSaturday() {
        let v = venue(friday: DayHours(open: 18 * 60, close: 2 * 60),
                      saturday: DayHours(open: 12 * 60, close: 22 * 60))
        XCTAssertTrue(v.isOpen(at: bishkek(day: 3, 1, 0)))
        XCTAssertEqual(v.openShiftClose(at: bishkek(day: 3, 1, 0)), 2 * 60)
        XCTAssertFalse(v.isOpen(at: bishkek(day: 3, 2, 0)))   // смена кончилась
        XCTAssertFalse(v.isOpen(at: bishkek(day: 3, 11, 0)))
        XCTAssertTrue(v.isOpen(at: bishkek(day: 3, 12, 0)))
    }

    func testTailWorksEvenWhenSaturdayIsDayOff() {
        let v = venue(friday: DayHours(open: 18 * 60, close: 2 * 60),
                      saturday: DayHours(closed: true))
        XCTAssertTrue(v.isOpen(at: bishkek(day: 3, 1, 30)))
        XCTAssertFalse(v.isOpen(at: bishkek(day: 3, 19, 0)))
    }

    func testOwnNightShiftDoesNotOpenTheMorningBeforeIt() {
        // Суббота 20:00–03:00, пятница — выходной: в субботу в 01:00 закрыто.
        let v = venue(friday: DayHours(closed: true),
                      saturday: DayHours(open: 20 * 60, close: 3 * 60))
        XCTAssertFalse(v.isOpen(at: bishkek(day: 3, 1, 0)))
        XCTAssertTrue(v.isOpen(at: bishkek(day: 3, 21, 0)))
        XCTAssertTrue(v.isOpen(at: bishkek(day: 4, 2, 59)))   // хвост в воскресенье
    }

    func testRegularDayAndRoundTheClock() {
        let v = venue(friday: DayHours(open: 9 * 60, close: 22 * 60),
                      saturday: DayHours(open: 0, close: 0))
        XCTAssertTrue(v.isOpen(at: bishkek(day: 2, 9, 0)))
        XCTAssertFalse(v.isOpen(at: bishkek(day: 2, 22, 0)))
        XCTAssertTrue(v.isOpen(at: bishkek(day: 3, 4, 0)))    // круглосуточно
    }

    func testLegacyHoursUntilMidnight() {
        let v = Venue(id: "v", name: "Кафе", category: .cafe, district: "", address: "",
                      phone: "", emoji: "☕️", gradient: [0], openHour: 10, closeHour: 24)
        XCTAssertTrue(v.isOpen(at: bishkek(day: 2, 23, 59)))
        XCTAssertFalse(v.isOpen(at: bishkek(day: 3, 0, 30)))
    }
}
