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
    /// Погашение купона (серверный счётчик + анти-абуз). Детерминированный id.
    func logRedemption(userID: String, dealID: String, venueID: String) async throws
    /// Запись реферала: пригласивший → приглашённый.
    func recordReferral(inviteeID: String, referrerID: String) async throws
    /// Забирает начисленные сервером бонусы (рефералка) и помечает claimed. Возвращает сумму.
    func claimBonusGrants(userID: String) async throws -> Int
    /// Создаёт подарочный купон (giftCoupons/{code}) — можно отправить другому пользователю.
    func createGiftCoupon(title: String, code: String, fromName: String) async throws
    /// Забирает подарок по коду (один раз). nil — если уже забран или не найден.
    func claimGiftCoupon(code: String) async throws -> GiftInfo?
    /// Гибкий список категорий заведений (управляется из админки).
    /// Пустой массив → приложение остаётся на встроенных категориях.
    func fetchCategories() async throws -> [RemoteCategory]
}

/// Данные забранного подарочного купона.
struct GiftInfo: Equatable {
    let title: String
    let code: String
}

/// Категория из бэкенда (коллекция `categories`).
struct RemoteCategory: Equatable {
    let slug: String
    let name: String
    let icon: String
    let emoji: String
    let order: Int
    let enabled: Bool
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
                           category: String?, venueID: String, dealID: String?, ownerID: String) async throws
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
    static let redemptions = "redemptions"   // купоны, погашенные в заведении
    static let all = [views, saves, calls, maps, dealTaps, redemptions]
}

/// Результат сканирования купона заведением (ответ Cloud Function scanCoupon).
struct ScanOutcome: Equatable {
    let ok: Bool
    let title: String
    let loyalty: Bool
    let stamps: Int
    let goal: Int
    let rewardIssued: Bool
    let rewardTitle: String
    let errorCode: String?     // nil при успехе; иначе "already_used"/"wrong_venue"/…
}

/// Бэкенд-трекинг купонов + карт лояльности (Firestore) и сканер заведения.
protocol CouponService {
    /// Пишет купон пользователя в Firestore (deal-купон создаёт клиент).
    func saveCoupon(_ coupon: Coupon, userID: String) async throws
    /// Купоны пользователя из Firestore (для синка used-статуса и наград).
    func fetchCoupons(userID: String) async throws -> [Coupon]
    /// Карты лояльности пользователя из Firestore.
    func fetchLoyaltyCards(userID: String) async throws -> [LoyaltyCard]
    /// Сканирование купона заведением: погашение + штамп (через Cloud Function).
    func scanCoupon(code: String, venueID: String, idToken: String) async throws -> ScanOutcome
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
    func logRedemption(userID: String, dealID: String, venueID: String) async throws {}
    func recordReferral(inviteeID: String, referrerID: String) async throws {}
    func claimBonusGrants(userID: String) async throws -> Int { 0 }
    func createGiftCoupon(title: String, code: String, fromName: String) async throws {}
    func claimGiftCoupon(code: String) async throws -> GiftInfo? { nil }
    /// Пусто → приложение оставит встроенные категории (VenueCategory.allCases).
    func fetchCategories() async throws -> [RemoteCategory] { [] }
}

/// Mock купон-сервиса: без бэкенда. Сканирование всегда «успех + штамп» для демо.
final class MockCouponService: CouponService {
    func saveCoupon(_ coupon: Coupon, userID: String) async throws {}
    func fetchCoupons(userID: String) async throws -> [Coupon] { [] }
    func fetchLoyaltyCards(userID: String) async throws -> [LoyaltyCard] { [] }
    func scanCoupon(code: String, venueID: String, idToken: String) async throws -> ScanOutcome {
        ScanOutcome(ok: true, title: "Демо-купон", loyalty: true, stamps: 1, goal: 6,
                    rewardIssued: false, rewardTitle: "", errorCode: nil)
    }
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
                           category: String?, venueID: String, dealID: String?, ownerID: String) async throws {
        print("[push] queued (mock): \(headline)")
    }
}
