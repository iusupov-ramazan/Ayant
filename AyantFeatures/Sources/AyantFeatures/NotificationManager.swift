import UserNotifications

/// Локальные напоминания: если за день пользователь не набрал 30 активных
/// минут (и не получил бонус), шлём напоминание каждые 4 часа.
/// Как только цель достигнута — напоминания на сегодня снимаются.
public enum NotificationManager {

    private static let reminderID = "san.bonus.reminder"
    private static let intervalSeconds: TimeInterval = 4 * 60 * 60   // 4 часа

    /// Запрос разрешения (один раз при старте).
    public static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Включает или снимает напоминания в зависимости от прогресса.
    /// Заголовок и текст передаёт приложение — уже на языке интерфейса:
    /// у пакета нет доступа к каталогу переводов приложения.
    public static func refresh(reachedGoalToday: Bool,
                               title: String = "Бонусы ждут 🎁",
                               body: String = "Залипни в Ayant на 30 активных минут и забери +50 бонусов") {
        if reachedGoalToday {
            cancel()
        } else {
            schedule(title: title, body: body)
        }
    }

    private static func schedule(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderID])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Повторяющийся триггер каждые 4 часа
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: intervalSeconds, repeats: true)
        let request = UNNotificationRequest(
            identifier: reminderID, content: content, trigger: trigger)
        center.add(request)
    }

    /// Снимает напоминание насовсем — для сборок, где глобальный кошелёк
    /// бонусов скрыт: пуш про «+50 бонусов» вёл бы в никуда.
    public static func disable() { cancel() }

    private static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminderID])
    }
}
