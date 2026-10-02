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

/// Авторизация: отвечает мгновенно и запоминает вызовы.
///
/// `calls` — порядок вызовов денежно-чувствительных методов: тест удаления
/// аккаунта проверяет, что отзыв гранта Apple идёт только ПОСЛЕ успешного
/// удаления записи на сервере.
final class FakeAuth: AuthService {
    var stored: SANUser?
    var discardedGuest = false
    var deleted = false
    /// Что вернуть/бросить из `deleteAccount` и `revokeAppleToken`.
    var deleteError: Error?
    var revokeError: Error?
    private(set) var passwordResets: [String] = []
    private(set) var revokedAppleCodes: [String] = []
    private(set) var calls: [String] = []
    /// Продолжение потока — тест может «прислать» восстановленную сессию.
    var continuation: AsyncStream<SANUser?>.Continuation?

    func currentUser() -> SANUser? { stored }

    func userChanges() -> AsyncStream<SANUser?> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(self.stored)
        }
    }

    func idToken() async -> String? { "token" }

    func signInWithEmail(_ email: String, password: String) async throws -> SANUser {
        let user = SANUser(id: "u1", name: "Тест", email: email, provider: .email)
        stored = user
        return user
    }

    func registerWithEmail(name: String, email: String, password: String) async throws -> SANUser {
        let user = SANUser(id: "u1", name: name, email: email, provider: .email)
        stored = user
        return user
    }

    func sendPasswordReset(email: String) async throws {
        calls.append("reset")
        passwordResets.append(email)
    }

    func signInWithGoogle() async throws -> SANUser {
        throw AuthError.notConfigured("Google")
    }

    func signInWithApple(_ credential: AppleCredential) async throws -> SANUser {
        throw AuthError.cancelled
    }

    func continueAsGuest() async throws -> SANUser {
        let user = SANUser(id: "guest", name: "Гость", email: nil, provider: .guest)
        stored = user
        return user
    }

    func signOut() { stored = nil }

    func deleteAccount() async throws {
        calls.append("delete")
        if let deleteError { throw deleteError }
        deleted = true
        stored = nil
    }

    func revokeAppleToken(authorizationCode: String) async throws {
        calls.append("revoke")
        if let revokeError { throw revokeError }
        revokedAppleCodes.append(authorizationCode)
    }

    func discardGuestAccount() async { discardedGuest = true; stored = nil }
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

/// Кабинет хоста: помнит, что ему сохранили, и отдаёт то, что «лежит на сервере».
/// `saveError` имитирует отказ Firestore (правила, сеть) на записи.
@MainActor
final class FakeHostRepository: HostRepository {
    var remoteVenues: [HostVenueDTO] = []
    var remoteDeals: [HostDealDTO] = []
    var remoteProfile: HostProfile?
    var savedVenues: [HostVenueDTO] = []
    var savedDeals: [HostDealDTO] = []
    var deletedVenueIDs: [String] = []
    var deletedDealIDs: [String] = []
    var remoteCouponOffers: [CouponOffer] = []
    var savedCouponOffers: [CouponOffer] = []
    var deletedCouponOfferIDs: [String] = []
    var saveError: Error?

    func saveVenue(_ dto: HostVenueDTO, ownerID: String) async throws {
        if let saveError { throw saveError }
        savedVenues.append(dto)
    }
    func deleteVenue(id: String) async throws { deletedVenueIDs.append(id) }
    func saveDeal(_ dto: HostDealDTO, ownerID: String) async throws {
        if let saveError { throw saveError }
        savedDeals.append(dto)
    }
    func deleteDeal(id: String) async throws { deletedDealIDs.append(id) }
    func fetchOwnedVenues(ownerID: String) async throws -> [HostVenueDTO] { remoteVenues }
    func fetchOwnedDeals(ownerID: String) async throws -> [HostDealDTO] { remoteDeals }
    func saveCouponOffer(_ offer: CouponOffer, ownerID: String) async throws {
        if let saveError { throw saveError }
        savedCouponOffers.append(offer)
    }
    func deleteCouponOffer(id: String) async throws { deletedCouponOfferIDs.append(id) }
    func fetchOwnedCouponOffers(ownerID: String) async throws -> [CouponOffer] { remoteCouponOffers }
    func saveProfile(_ profile: HostProfile, ownerID: String) async throws { remoteProfile = profile }
    func fetchProfile(ownerID: String) async throws -> HostProfile? { remoteProfile }
    func queuePushCampaign(headline: String, body: String, city: String,
                           category: String?, venueID: String, dealID: String?, ownerID: String) async throws {}
}

/// Баллы САН: карты и журнал из памяти, списание — локально.
@MainActor
final class FakePointsRepository: PointsRepository {
    var cards: [VenuePointsCard] = []
    var ledger: [String: [PointsLedgerEntry]] = [:]
    var ledgerError: AppError?
    var redeemError: AppError?
    var ledgerRequests = 0

    /// Живой поток: тест «присылает» новые снимки через `emit`, как это делал бы
    /// snapshot-листенер Firestore после скана сотрудником.
    private var continuation: AsyncStream<Result<[VenuePointsCard], AppError>>.Continuation?

    nonisolated func cards(userID: String) -> AsyncStream<Result<[VenuePointsCard], AppError>> {
        AsyncStream { continuation in
            Task { @MainActor in
                self.continuation = continuation
                continuation.yield(.success(userID.isEmpty ? [] : self.cards))
            }
        }
    }

    func emit(_ cards: [VenuePointsCard]) {
        self.cards = cards
        continuation?.yield(.success(cards))
    }

    func redeem(venueID: String, userID: String, rewardID: String,
                pointsToSpend: Int, idempotencyKey: String) async -> Result<RedeemReceipt, AppError> {
        if let redeemError { return .failure(redeemError) }
        return .success(RedeemReceipt(redeemed: max(pointsToSpend, 1), balance: 0, rewardTitle: "Тест"))
    }

    func ledger(userID: String, venueID: String, limit: Int) async -> Result<[PointsLedgerEntry], AppError> {
        ledgerRequests += 1
        if let ledgerError { return .failure(ledgerError) }
        return .success(Array((ledger[venueID] ?? []).prefix(limit)))
    }
}

/// Instagram заведения: программируемый дубль.
///
/// Посты задаются тестом, ошибки — через `failure`. Счётчики вызовов нужны,
/// чтобы проверять то, чего не видно в состоянии: например, что при
/// отключённом аккаунте в сеть вообще не ходили.
final class FakeInstagramService: InstagramService {
    var posts: [InstagramPost] = []
    var connectionValue: InstagramConnection?
    var failure: AppError?
    private(set) var mediaCalls = 0
    private(set) var importedPosts: [String] = []
    private(set) var disconnected: [String] = []

    func authURL(venueID: String) async throws -> URL {
        if let failure { throw failure }
        return URL(string: "https://instagram.test/authorize?venue=\(venueID)")!
    }

    func media(venueID: String, limit: Int) async throws -> [InstagramPost] {
        mediaCalls += 1
        if let failure { throw failure }
        return posts
    }

    func importPost(venueID: String, postID: String) async throws -> InstagramImport {
        importedPosts.append(postID)
        if let failure { throw failure }
        guard let post = posts.first(where: { $0.id == postID }) else { throw AppError.notFound }
        return InstagramImport(postID: post.id,
                               imageURLs: ["https://cdn.ayant.test/\(post.id).jpg"],
                               caption: post.caption, permalink: post.permalink)
    }

    func disconnect(venueID: String) async throws { disconnected.append(venueID) }

    func connection(ownerID: String, venueID: String) -> AsyncStream<InstagramConnection?> {
        let value = connectionValue
        return AsyncStream { continuation in
            continuation.yield(value)
            continuation.finish()
        }
    }
}
