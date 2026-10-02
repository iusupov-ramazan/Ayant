import Foundation

/// Ряд «Аналитики» кабинета: ключи дней, суммы и столбики графика.
///
/// Документы `analytics/{venueID}/days/{yyyy-MM-dd}` пишет сервер
/// (`countAnalyticsEvent`, `countRedemption`, `scanCoupon`) с ключом дня по
/// **UTC** (`toISOString().slice(0, 10)` в `functions/src/index.ts`). Клиент
/// раньше резал период по ЛОКАЛЬНОМУ дню телефона: в Бишкеке (UTC+6) с полуночи
/// до 06:00 «сегодня» на клиенте — это ещё «вчера» на сервере, и граница
/// периода съезжала на день. Здесь ключи считаются тем же правилом, что у сервера.
///
/// Пустые дни тоже входят в ряд: раньше график из 30 дней с данными за три дня
/// рисовал три столбика, растянутые на всю ширину, — провалы просто исчезали.
public enum HostAnalyticsSeries {

    /// Календарь серверного ключа дня.
    public static var serverCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return cal
    }

    /// Ключ дня `yyyy-MM-dd` — как `dayKey()` в функциях.
    public static func dayKey(_ date: Date) -> String {
        let c = serverCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Ключи последних `days` дней, от старого к новому; последний — сегодня (UTC).
    public static func dayKeys(days: Int, now: Date) -> [String] {
        let count = max(days, 1)
        let cal = serverCalendar
        return (0..<count).reversed().map { back in
            dayKey(cal.date(byAdding: .day, value: -back, to: now) ?? now)
        }
    }

    /// Первый ключ периода — граница запроса `documentID >= cutoff`.
    public static func cutoffKey(days: Int, now: Date) -> String {
        dayKeys(days: days, now: now).first ?? dayKey(now)
    }

    /// Суммы метрик за период из ряда по дням (дни вне периода не считаются).
    public static func totals(daily: [String: [String: Int]], keys: [String]) -> [String: Int] {
        var out: [String: Int] = [:]
        for key in keys {
            for (metric, n) in daily[key] ?? [:] { out[metric, default: 0] += n }
        }
        return out
    }

    /// Значения одной метрики по каждому дню периода, нули — для пустых дней.
    public static func values(daily: [String: [String: Int]], keys: [String], metric: String) -> [Int] {
        keys.map { daily[$0]?[metric] ?? 0 }
    }

    /// Столбики графика: 7 дней — 7 столбиков, длиннее — 12 равных корзин.
    /// Все нули — пустой массив: рисовать ровную линию из нулей незачем.
    public static func buckets(_ values: [Int], period: Int) -> [Int] {
        guard values.contains(where: { $0 > 0 }) else { return [] }
        let count = period <= 7 ? min(7, values.count) : 12
        guard values.count > count else { return values }
        let size = Double(values.count) / Double(count)
        return (0..<count).map { i in
            let lo = Int((Double(i) * size).rounded(.down))
            let hi = min(values.count, Int((Double(i + 1) * size).rounded(.down)))
            return values[lo..<max(hi, lo + 1)].reduce(0, +)
        }
    }
}
