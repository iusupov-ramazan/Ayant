import XCTest
@testable import AyantDomain

/// Ключи дней «Аналитики» совпадают с серверными (UTC), пустые дни — нули.
final class HostAnalyticsSeriesTests: XCTestCase {

    /// 2026-10-02 02:00 по Бишкеку = 2026-10-01 20:00 UTC.
    private let bishkekNight: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 2; c.hour = 2
        return City.calendar(forSlug: City.bishkek.id).date(from: c)!
    }()

    func testDayKeyUsesServerUTCNotLocalDay() {
        XCTAssertEqual(HostAnalyticsSeries.dayKey(bishkekNight), "2026-10-01")
    }

    func testDayKeysCoverWholePeriodOldestFirst() {
        let keys = HostAnalyticsSeries.dayKeys(days: 3, now: bishkekNight)
        XCTAssertEqual(keys, ["2026-09-29", "2026-09-30", "2026-10-01"])
        XCTAssertEqual(HostAnalyticsSeries.cutoffKey(days: 3, now: bishkekNight), "2026-09-29")
    }

    func testZeroDaysAreKeptAndOutOfPeriodDaysIgnored() {
        let keys = HostAnalyticsSeries.dayKeys(days: 3, now: bishkekNight)
        let daily = ["2026-09-28": ["views": 100],          // вне периода
                     "2026-10-01": ["views": 4, "saves": 1]]
        XCTAssertEqual(HostAnalyticsSeries.values(daily: daily, keys: keys, metric: "views"), [0, 0, 4])
        XCTAssertEqual(HostAnalyticsSeries.totals(daily: daily, keys: keys), ["views": 4, "saves": 1])
    }

    func testBuckets() {
        XCTAssertEqual(HostAnalyticsSeries.buckets([0, 0, 0], period: 7), [])
        XCTAssertEqual(HostAnalyticsSeries.buckets([1, 0, 2, 0, 0, 0, 3], period: 7), [1, 0, 2, 0, 0, 0, 3])
        let thirty = Array(repeating: 1, count: 30)
        let b = HostAnalyticsSeries.buckets(thirty, period: 30)
        XCTAssertEqual(b.count, 12)
        XCTAssertEqual(b.reduce(0, +), 30)
    }
}
