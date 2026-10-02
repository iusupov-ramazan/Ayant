import XCTest
@testable import SAN
import AyantFeatures

/// Напоминание ставится по Бишкеку — тем же суткам, что у
/// `BonusEngine.reachedGoalToday` и сервера, — а не по поясу телефона.
final class NotificationReminderBishkekTests: XCTestCase {

    private let cal = NotificationManager.bishkekCalendar

    func testDefaultCalendarIsBishkek() {
        XCTAssertEqual(cal.timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: 1_700_000_000)), 6 * 3600)
    }

    func testFiresAt18BishkekRegardlessOfDeviceZone() {
        // 2023-11-14 05:00 UTC = 11:00 в Бишкеке → сегодня в 18:00 Бишкека = 12:00 UTC.
        let now = Date(timeIntervalSince1970: 1_699_938_000)
        let fire = NotificationManager.nextFireDate(reachedGoalToday: false, now: now, calendar: cal)
        XCTAssertEqual(fire, Date(timeIntervalSince1970: 1_699_963_200))
    }

    func testLateEveningInBishkekMovesToTomorrow() {
        // 2023-11-14 17:30 UTC = 23:30 в Бишкеке: 18:00 прошло → завтра, 2023-11-15 12:00 UTC.
        let now = Date(timeIntervalSince1970: 1_699_983_000)
        let fire = NotificationManager.nextFireDate(reachedGoalToday: false, now: now, calendar: cal)
        XCTAssertEqual(fire, Date(timeIntervalSince1970: 1_700_049_600))
    }

    func testJustAfterBishkekMidnightIsANewDay() {
        // 2023-11-14 18:30 UTC = 00:30 15-го в Бишкеке; телефон в UTC думал бы,
        // что сейчас ещё 14-е и 18:00 прошло. Бишкек: сегодня (15-го) в 18:00.
        let now = Date(timeIntervalSince1970: 1_699_986_600)
        let fire = NotificationManager.nextFireDate(reachedGoalToday: true, now: now, calendar: cal)
        // Цель «вчерашняя» не в счёт: reachedGoalToday=true → завтра (16-го) 12:00 UTC.
        XCTAssertEqual(fire, Date(timeIntervalSince1970: 1_700_136_000))
        let notReached = NotificationManager.nextFireDate(reachedGoalToday: false, now: now, calendar: cal)
        XCTAssertEqual(notReached, Date(timeIntervalSince1970: 1_700_049_600))
    }
}
