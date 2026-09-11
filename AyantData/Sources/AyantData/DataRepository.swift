import Foundation
import AyantDomain

// MARK: - Mock-реализации (работают сейчас)

public final class MockDataRepository: DataRepository {
    /// Пустой инициализатор нужен явно: синтезированный — internal.
    public init() {}

    public func fetchVenues() async throws -> [Venue] { MockData.venues }
    public func fetchDeals() async throws -> [Deal] { MockData.deals }
    // Mock работает на полном локальном наборе — фильтруем его в памяти,
    // но форму запроса повторяем 1:1, чтобы офлайн-режим вёл себя как боевой.
    public func fetchReviews(venueID: String, limit: Int) async throws -> [Review] {
        Array(MockData.reviews.filter { $0.venueID == venueID }
            .sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }
    public func fetchReviews(venueIDs: [String], limit: Int) async throws -> [Review] {
        let ids = Set(venueIDs)
        return Array(MockData.reviews.filter { ids.contains($0.venueID) }
            .sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }
    public func fetchReviews(authorID: String, limit: Int) async throws -> [Review] {
        Array(MockData.reviews.filter { $0.authorID == authorID }
            .sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
    }
    public func saveReview(_ review: Review) async throws {}
    public func deleteReview(id: String) async throws {}
    public func updateReviewReply(reviewID: String, reply: HostReply?) async throws {}
    public func logRedemption(userID: String, dealID: String, venueID: String) async throws {}
    public func recordReferral(inviteeID: String, referrerID: String) async throws {}
    public func claimBonusGrants(userID: String) async throws -> Int { 0 }
    public func createGiftCoupon(title: String, code: String, fromName: String) async throws {}
    public func claimGiftCoupon(code: String) async throws -> GiftInfo? { nil }
    /// Пусто → приложение оставит встроенные категории (VenueCategory.allCases).
    public func fetchCategories() async throws -> [RemoteCategory] { [] }
    /// nil → приложение оставит дефолтные веса ранжирования.
    public func fetchRankingWeights() async throws -> [String: Double]? { nil }
}

/// Mock купон-сервиса: без бэкенда. Сканирование всегда «успех + штамп» для демо.
public final class MockCouponService: CouponService {
    /// Пустой инициализатор нужен явно: синтезированный — internal.
    public init() {}

    public func saveCoupon(_ coupon: Coupon, userID: String) async throws {}
    public func fetchCoupons(userID: String) async throws -> [Coupon] { [] }
    public func fetchLoyaltyCards(userID: String) async throws -> [LoyaltyCard] { [] }
    public func loyaltyCards(userID: String) -> AsyncStream<[LoyaltyCard]> {
        AsyncStream { $0.finish() }
    }
    public func fetchVenuePoints(userID: String) async throws -> [VenuePointsCard] { [] }
    public func scanCoupon(code: String, venueID: String, idToken: String,
                    billAmount: Int?, bandIndex: Int?, idempotencyKey: String) async throws -> ScanOutcome {
        ScanOutcome(ok: true, title: "Демо-купон", loyalty: true, stamps: 1, goal: 6,
                    rewardIssued: false, rewardTitle: "", errorCode: nil)
    }
    public func redeemVenuePoints(venueID: String, userID: String, rewardId: String,
                           pointsToSpend: Int, idToken: String,
                           idempotencyKey: String) async throws -> RedeemOutcome {
        RedeemOutcome(ok: true, redeemed: pointsToSpend > 0 ? pointsToSpend : 100, balance: 0,
                      rewardTitle: "Демо-награда", somOff: nil, errorCode: nil)
    }
}

public final class MockPushService: PushService {
    /// Пустой инициализатор нужен явно: синтезированный — internal.
    public init() {}

    public func requestAuthorization() async -> Bool { true }
    public func subscribe(topic: String) { print("[push] subscribe \(topic)") }
    public func unsubscribe(topic: String) { print("[push] unsubscribe \(topic)") }
    public func registerToken(_ token: String, city: String, uid: String?) { print("[push] token \(token.prefix(8))…") }
    public func unregisterDevice(topics: [String]) async { print("[push] unregister device, topics: \(topics)") }
}

/// Mock аналитики: события игнорируются, статистика — детерминированная заглушка.
public final class MockAnalyticsService: AnalyticsService {
    /// Пустой инициализатор нужен явно: синтезированный — internal.
    public init() {}

    public func log(venueID: String, metric: String) { }
    public func fetchStats(venueID: String, days: Int) async throws -> [String: Int] {
        var out: [String: Int] = [:]
        for m in AnalyticsMetric.all { out[m] = HostMetrics.value(venueID, m, days) }
        return out
    }

    /// Оффлайн-режим ряда по дням не хранит — график просто не рисуется.
    public func fetchDailyStats(venueID: String, days: Int) async throws -> [String: [String: Int]] { [:] }
}

/// ВРЕМЕННО: витринная аналитика поверх настоящей.
///
/// Пока у заведений нет своего трафика, реальные счётчики стоят на нуле и
/// «Аналитика» выглядит сломанной. Этот декоратор ЧИТАЕТ сгенерированные ряды
/// (`HostMetrics`), но `log` продолжает писать в настоящий сервис — телеметрия
/// копится, и когда флаг `AppConfig.useDemoAnalytics` выключат, в отчётах
/// окажутся реальные накопленные данные, а не дыра за весь период показа.
///
/// Зеркалит `DemoAnalyticsService.kt`.
public final class DemoAnalyticsService: AnalyticsService {
    private let real: AnalyticsService
    private let calendar: Calendar
    private let now: () -> Date

    public init(wrapping real: AnalyticsService,
                calendar: Calendar = .current,
                now: @escaping () -> Date = { Date() }) {
        self.real = real
        self.calendar = calendar
        self.now = now
    }

    public func log(venueID: String, metric: String) {
        real.log(venueID: venueID, metric: metric)
    }

    public func fetchStats(venueID: String, days: Int) async throws -> [String: Int] {
        var out: [String: Int] = [:]
        for m in AnalyticsMetric.all {
            out[m] = HostMetrics.value(venueID, m, days, calendar: calendar, now: now())
        }
        return out
    }

    public func fetchDailyStats(venueID: String, days: Int) async throws -> [String: [String: Int]] {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"

        var out: [String: [String: Int]] = [:]
        let today = now()
        for i in 0..<max(1, days) {
            guard let day = calendar.date(byAdding: .day, value: -i, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day) - 1
            var row: [String: Int] = [:]
            for m in AnalyticsMetric.all {
                row[m] = HostMetrics.daily(venueID, m, dayIndex: i, weekday: weekday)
            }
            out[f.string(from: day)] = row
        }
        return out
    }
}

/// Mock журнала ранжирования: копит события в памяти (для тестов), ничего не шлёт.
public final class MockRankingEventService: RankingEventService {
    /// Пустой инициализатор нужен явно: синтезированный — internal.
    public init() {}

    public private(set) var logged: [RankingEvent] = []
    public func log(_ event: RankingEvent) { logged.append(event) }
}

/// Mock хост-репозитория: без бэкенда. HostStore хранит локальный кэш сам.
public final class MockHostRepository: HostRepository {
    /// Пустой инициализатор нужен явно: синтезированный — internal.
    public init() {}

    public func saveVenue(_ dto: HostVenueDTO, ownerID: String) async throws {}
    public func deleteVenue(id: String) async throws {}
    public func saveDeal(_ dto: HostDealDTO, ownerID: String) async throws {}
    public func deleteDeal(id: String) async throws {}
    public func fetchOwnedVenues(ownerID: String) async throws -> [HostVenueDTO] { [] }
    public func fetchOwnedDeals(ownerID: String) async throws -> [HostDealDTO] { [] }
    public func saveProfile(_ profile: HostProfile, ownerID: String) async throws {}
    public func fetchProfile(ownerID: String) async throws -> HostProfile? { nil }
    public func queuePushCampaign(headline: String, body: String, city: String,
                           category: String?, venueID: String, dealID: String?, ownerID: String) async throws {
        print("[push] queued (mock): \(headline)")
    }
}
