import Foundation

/// Источник данных о заведениях и предложениях.
/// MockDataRepository отдаёт локальные данные. FirebaseDataRepository
/// будет читать те же модели из Firestore — UI не меняется.
protocol DataRepository {
    func fetchVenues() async throws -> [Venue]
    func fetchDeals() async throws -> [Deal]
    func fetchReviews() async throws -> [Review]
    /// Публикация отзыва пользователя в Firestore (коллекция reviews).
    func saveReview(_ review: Review) async throws
    func deleteReview(id: String) async throws
    /// Ответ владельца — обновляет поле hostReply в документе отзыва.
    func updateReviewReply(reviewID: String, reply: HostReply?) async throws
}

/// Запись/чтение контента хоста в Firestore (заведения и предложения с владельцем).
protocol HostRepository {
    func saveVenue(_ dto: HostVenueDTO, ownerID: String) async throws
    func deleteVenue(id: String) async throws
    func saveDeal(_ dto: HostDealDTO, ownerID: String) async throws
    func deleteDeal(id: String) async throws
    func fetchOwnedVenues(ownerID: String) async throws -> [HostVenueDTO]
    func fetchOwnedDeals(ownerID: String) async throws -> [HostDealDTO]
    /// Профиль хоста в коллекции hosts/{uid} (включая статус верификации).
    func saveProfile(_ profile: HostProfile, ownerID: String) async throws
    func fetchProfile(ownerID: String) async throws -> HostProfile?
    /// Кладёт push-кампанию в очередь (Firestore). Реальную рассылку делает
    /// Cloud Function по триггеру создания документа.
    func queuePushCampaign(headline: String, body: String, city: String,
                           category: String?, venueID: String, ownerID: String) async throws
}

/// Аналитика заведений: события пишутся в коллекцию `analytics/{venueID}/days/{date}`.
protocol AnalyticsService {
    /// Лог события (просмотр/сохранение/звонок/маршрут/клик по акции). Fire-and-forget.
    func log(venueID: String, metric: String)
    /// Сумма метрик за последние `days` дней.
    func fetchStats(venueID: String, days: Int) async throws -> [String: Int]
}

enum AnalyticsMetric {
    static let views = "views"
    static let saves = "saves"
    static let calls = "calls"
    static let maps = "maps"
    static let dealTaps = "dealTaps"
    static let all = [views, saves, calls, maps, dealTaps]
}

/// Push-уведомления (новые акции рядом / у избранных мест).
protocol PushService {
    func requestAuthorization() async -> Bool
    /// Подписка на темы: "deals_bishkek", "favorites_<venueID>" и т.п.
    func subscribe(topic: String)
    func unsubscribe(topic: String)
    /// Регистрирует FCM-токен устройства для адресной рассылки (с частотным лимитом).
    func registerToken(_ token: String, city: String, uid: String?)
}

// MARK: - Mock-реализации (работают сейчас)

final class MockDataRepository: DataRepository {
    func fetchVenues() async throws -> [Venue] { MockData.venues }
    func fetchDeals() async throws -> [Deal] { MockData.deals }
    func fetchReviews() async throws -> [Review] { MockData.reviews }
    func saveReview(_ review: Review) async throws {}
    func deleteReview(id: String) async throws {}
    func updateReviewReply(reviewID: String, reply: HostReply?) async throws {}
}

final class MockPushService: PushService {
    func requestAuthorization() async -> Bool { true }
    func subscribe(topic: String) { print("[push] subscribe \(topic)") }
    func unsubscribe(topic: String) { print("[push] unsubscribe \(topic)") }
    func registerToken(_ token: String, city: String, uid: String?) { print("[push] token \(token.prefix(8))…") }
}

/// Mock аналитики: события игнорируются, статистика — детерминированная заглушка.
final class MockAnalyticsService: AnalyticsService {
    func log(venueID: String, metric: String) { }
    func fetchStats(venueID: String, days: Int) async throws -> [String: Int] {
        var out: [String: Int] = [:]
        for m in AnalyticsMetric.all { out[m] = HostMetrics.value(venueID, m, days) }
        return out
    }
}

/// Mock хост-репозитория: без бэкенда. HostStore хранит локальный кэш сам.
final class MockHostRepository: HostRepository {
    func saveVenue(_ dto: HostVenueDTO, ownerID: String) async throws {}
    func deleteVenue(id: String) async throws {}
    func saveDeal(_ dto: HostDealDTO, ownerID: String) async throws {}
    func deleteDeal(id: String) async throws {}
    func fetchOwnedVenues(ownerID: String) async throws -> [HostVenueDTO] { [] }
    func fetchOwnedDeals(ownerID: String) async throws -> [HostDealDTO] { [] }
    func saveProfile(_ profile: HostProfile, ownerID: String) async throws {}
    func fetchProfile(ownerID: String) async throws -> HostProfile? { nil }
    func queuePushCampaign(headline: String, body: String, city: String,
                           category: String?, venueID: String, ownerID: String) async throws {
        print("[push] queued (mock): \(headline)")
    }
}
