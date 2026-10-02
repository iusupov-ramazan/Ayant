import Foundation
import UserNotifications

/// Локальное напоминание про бонусы за активное время.
///
/// Одно напоминание в день, днём, и только если цель дня ещё не набрана.
/// Раньше это был повторяющийся триггер каждые 4 часа — до шести пушей в
/// сутки, ночью тоже, — с текстом «+50 бонусов», хотя цикл приносит 1
/// (аудит 2026-10-01). Текст теперь собирает приложение из действующего курса
/// (`BonusEngine.rewardPerGoal`, `goalSeconds`), поэтому он не может
/// разойтись с тем, что реально начисляется.
public enum NotificationManager {

    private static let reminderID = "san.bonus.reminder"
    /// Час напоминания — по Бишкеку.
    public static let reminderHour = 18

    /// Календарь напоминания — Бишкек, как у `BonusEngine.reachedGoalToday` и
    /// сервера. По календарю телефона гость в другом поясе получал «18:00» не
    /// в тот день, по которому считается цель: напоминание о вчерашней цели
    /// или ни одного в день, когда она не набрана.
    public static let bishkekCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Bishkek") ?? TimeZone(secondsFromGMT: 6 * 3600)!
        return c
    }()

    /// Запрос разрешения (один раз при старте).
    public static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Ставит или снимает напоминание в зависимости от прогресса.
    /// Заголовок и текст передаёт приложение — уже на языке интерфейса:
    /// у пакета нет доступа к каталогу переводов приложения.
    /// `now` — обязательный: приходит от вызывающего (часы `BonusEngine`),
    /// в пакете фич системные часы не читаются.
    public static func refresh(reachedGoalToday: Bool, title: String, body: String,
                               now: Date, calendar: Calendar = bishkekCalendar) {
        guard let fireAt = nextFireDate(reachedGoalToday: reachedGoalToday, now: now, calendar: calendar) else {
            cancelReminder()
            return
        }
        schedule(title: title, body: body, in: fireAt.timeIntervalSince(now))
    }

    /// Когда напомнить: сегодня в `reminderHour`, если час ещё не прошёл и
    /// цель не набрана; иначе — завтра в тот же час (завтра цель новая).
    public static func nextFireDate(reachedGoalToday: Bool, now: Date, calendar: Calendar) -> Date? {
        guard let todayAt = calendar.date(bySettingHour: reminderHour, minute: 0, second: 0, of: now) else {
            return nil
        }
        if !reachedGoalToday, todayAt > now { return todayAt }
        return calendar.date(byAdding: .day, value: 1, to: todayAt)
    }

    private static func schedule(title: String, body: String, in interval: TimeInterval) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderID])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Разовый триггер через интервал до момента — не повторяющийся. Не
        // календарный: компоненты даты телефон прочёл бы в СВОЁМ поясе, и
        // «18:00 по Бишкеку» превратилось бы в 18:00 по часам телефона.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        center.add(UNNotificationRequest(identifier: reminderID, content: content, trigger: trigger))
    }

    /// Снимает напоминание — цель на сегодня набрана, кошелёк скрыт или
    /// пользователь вышел.
    public static func cancelReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminderID])
    }

    /// Прежнее имя `cancelReminder()` для сборок, где глобальный кошелёк скрыт.
    public static func disable() { cancelReminder() }
}
