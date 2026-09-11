import Foundation
import AyantDomain

/*
 * Тестовые дубли доменных контрактов.
 *
 * Живут здесь, а не берутся из `AyantData`: тот пакет тянет за собой Firebase
 * SDK (Firestore, gRPC), и тест-таргету пришлось бы линковать его целиком ради
 * трёх пустых заглушек. Заодно это честнее — дубль принадлежит тесту, а
 * `Mock*` в слое данных существует для оффлайн-режима приложения, и менять его
 * под нужды теста незачем.
 *
 * Зеркалит подход Android, где все тесты живут в `:domain` со своими фейками.
 */

/// Журнал ранжирования: запоминает события, чтобы тест их проверил.
final class FakeRankingEventService: RankingEventService {
    private(set) var logged: [RankingEvent] = []
    func log(_ event: RankingEvent) { logged.append(event) }
}

/// Аналитика заведения: молча принимает записи.
final class FakeAnalyticsService: AnalyticsService {
    func log(venueID: String, metric: String) {}
    func fetchStats(venueID: String, days: Int) async throws -> [String: Int] { [:] }
    func fetchDailyStats(venueID: String, days: Int) async throws -> [String: [String: Int]] { [:] }
}

/// Push: подписки в тесте не нужны.
final class FakePushService: PushService {
    func requestAuthorization() async -> Bool { true }
    func subscribe(topic: String) {}
    func unsubscribe(topic: String) {}
    func registerToken(_ token: String, city: String, uid: String?) {}
    private(set) var unregisteredTopics: [String] = []
    func unregisterDevice(topics: [String]) async { unregisteredTopics = topics }
}
