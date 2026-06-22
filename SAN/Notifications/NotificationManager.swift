import UserNotifications

/// Локальные напоминания: если за день пользователь не набрал 30 активных
/// минут (и не получил бонус), шлём напоминание каждые 4 часа.
/// Как только цель достигнута — напоминания на сегодня снимаются.
enum NotificationManager {

    private static let reminderID = "san.bonus.reminder"
    private static let intervalSeconds: TimeInterval = 4 * 60 * 60   // 4 часа

    /// Запрос разрешения (один раз при старте).
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Включает или снимает напоминания в зависимости от прогресса.
    static func refresh(reachedGoalToday: Bool) {
        if reachedGoalToday {
            cancel()
        } else {
            schedule()
        }
    }

    private static func schedule() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderID])

        let content = UNMutableNotificationContent()
        content.title = "Бонусы ждут 🎁"
        content.body = "Залипни в Ayta на 30 активных минут и забери +50 бонусов"
        content.sound = .default

        // Повторяющийся триггер каждые 4 часа
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: intervalSeconds, repeats: true)
        let request = UNNotificationRequest(
            identifier: reminderID, content: content, trigger: trigger)
        center.add(request)
    }

    private static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminderID])
    }
}
