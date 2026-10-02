import XCTest
import AyantFeatures

/// Напоминание о бонусах: одно в день, в 18:00, и не тогда, когда цель уже
/// набрана. Раньше — повторяющийся триггер каждые 4 часа, ночью тоже.
final class NotificationManagerTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Bishkek")!
        return c
    }()

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    func testBeforeEveningAndGoalNotReachedRemindsToday() {
        XCTAssertEqual(NotificationManager.nextFireDate(reachedGoalToday: false, now: date(1, 10), calendar: calendar),
                       date(1, NotificationManager.reminderHour))
    }

    func testAfterEveningRemindsTomorrow() {
        XCTAssertEqual(NotificationManager.nextFireDate(reachedGoalToday: false, now: date(1, 21), calendar: calendar),
                       date(2, NotificationManager.reminderHour))
    }

    func testGoalReachedSkipsToday() {
        XCTAssertEqual(NotificationManager.nextFireDate(reachedGoalToday: true, now: date(1, 10), calendar: calendar),
                       date(2, NotificationManager.reminderHour))
    }
}
