import Foundation

/// Правдоподобные цифры для витрины аналитики.
///
/// ВРЕМЕННО. Пока у заведений нет своего трафика, реальные счётчики стоят на
/// нуле, и «Аналитика» выглядит сломанной, а не пустой. Здесь генерируются
/// правдоподобные ряды, чтобы экран можно было показывать и обсуждать.
/// Выключается одним флагом — `AppConfig.useDemoAnalytics`.
///
/// Числа ДЕТЕРМИНИРОВАННЫЕ: они зависят от id заведения, метрики и номера дня,
/// а не от `random()`. Настоящий рандом менялся бы при каждом обновлении
/// экрана — цифры бы прыгали на глазах, и это читалось бы как баг, а не как
/// живые данные. При этом одно и то же заведение всегда даёт один и тот же
/// ряд, суммы сходятся с графиком, а «вчера» не меняется задним числом.
///
/// Зеркалит `HostMetrics.kt`.
public enum HostMetrics {

    /// Средний дневной уровень метрики для заведения.
    static func dailyBase(_ id: String, _ metric: String) -> Double {
        let seed = hash(id + metric)
        // Воронка: просмотров много, звонков единицы.
        let base: Double = [
            AnalyticsMetric.views: 42,
            AnalyticsMetric.dealTaps: 11,
            AnalyticsMetric.saves: 6,
            AnalyticsMetric.maps: 4,
            AnalyticsMetric.calls: 3,
            AnalyticsMetric.redemptions: 2,
        ][metric] ?? 5
        // ±45 % на заведение, чтобы соседние карточки не были близнецами.
        let spread = 0.55 + Double(seed % 90) / 100.0
        return base * spread
    }

    /// Значение метрики за конкретный день. `dayIndex` — сколько дней назад (0 = сегодня).
    public static func daily(_ id: String, _ metric: String, dayIndex: Int, weekday: Int) -> Int {
        let base = dailyBase(id, metric)
        // Выходные заметно живее буднего вторника.
        let weekly = [1.22, 0.82, 0.86, 0.9, 0.96, 1.15, 1.3][max(0, min(6, weekday))]
        // Разброс по дню — тоже из хеша, а не из генератора случайных чисел.
        let jitter = 0.75 + Double(hash("\(id)\(metric)\(dayIndex)") % 50) / 100.0
        return Int((base * weekly * jitter).rounded())
    }

    /// Сумма метрики за `days` дней, считается по тем же дневным значениям,
    /// что рисует график, — иначе итог и столбики разошлись бы.
    public static func total(_ id: String, _ metric: String, days: Int, weekdayOfDayAgo: (Int) -> Int) -> Int {
        (0..<max(1, days)).reduce(0) { sum, i in
            sum + daily(id, metric, dayIndex: i, weekday: weekdayOfDayAgo(i))
        }
    }

    /// Прежняя сигнатура — её зовёт оффлайн-режим. Считает то же самое,
    /// раскладывая дни от «сегодня» назад.
    public static func value(_ id: String, _ metric: String, _ days: Int,
                             calendar: Calendar = .current, now: Date = Date()) -> Int {
        total(id, metric, days: days) { i in
            let day = calendar.date(byAdding: .day, value: -i, to: now) ?? now
            return calendar.component(.weekday, from: day) - 1
        }
    }

    /// Устойчивый хеш строки. `hashValue` не подходит: он рандомизирован между
    /// запусками, и ряд менялся бы при каждом старте приложения.
    static func hash(_ s: String) -> Int {
        var h = 5381
        for b in s.utf8 { h = (h &* 33 &+ Int(b)) & 0x7fff_ffff }
        return h
    }
}
