import Foundation
import FirebaseFirestore
import AyantDomain

/// Живой источник карт баллов на Firestore.
///
/// Раньше экран баллов опрашивал бэкенд раз в 4 секунды, пока был открыт: баланс
/// менялся на сервере (сотрудник сканировал QR), а клиент узнавал об этом в
/// среднем через две секунды и делал ~15 лишних запросов в минуту на каждого
/// открывшего экран. Здесь вместо опроса — `addSnapshotListener`: сервер сам
/// присылает изменение, трафика меньше, задержка близка к нулю.
///
/// Листенер снимается в `onTermination`, то есть живёт ровно столько, сколько
/// живёт задача-потребитель (у стора — пока открыт экран).
public final class FirebasePointsRepository: PointsRepository {
    private let db = Firestore.firestore()
    private let backend: CouponService
    private let auth: AuthService

    /// Зависимости даёт композиционный корень (`AppConfig`) — слой данных
    /// про сборку приложения не знает.
    public init(backend: CouponService, auth: AuthService) {
        self.backend = backend
        self.auth = auth
    }

    public func cards(userID: String) -> AsyncStream<Result<[VenuePointsCard], AppError>> {
        AsyncStream { continuation in
            guard !userID.isEmpty else {
                continuation.yield(.success([]))
                continuation.finish()
                return
            }
            let registration = db.collection(FS.Collection.venuePoints)
                .whereField(FS.VenuePointsDoc.userID, isEqualTo: userID)
                .addSnapshotListener { snapshot, error in
                    if let error {
                        continuation.yield(.failure(AppError(firestore: error)))
                        return
                    }
                    let cards = snapshot?.documents.map { VenuePointsCard(firestore: $0.data()) } ?? []
                    continuation.yield(.success(cards))
                }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    public func redeem(venueID: String, userID: String, rewardID: String,
                pointsToSpend: Int, idempotencyKey: String) async -> Result<RedeemReceipt, AppError> {
        guard !userID.isEmpty else { return .failure(.unauthenticated) }
        guard let token = await auth.idToken(), !token.isEmpty else { return .failure(.unauthenticated) }
        do {
            let out = try await backend.redeemVenuePoints(
                venueID: venueID, userID: userID, rewardId: rewardID,
                pointsToSpend: pointsToSpend, idToken: token, idempotencyKey: idempotencyKey)
            guard out.ok else { return .failure(.server(code: out.errorCode ?? "redeem_failed")) }
            return .success(RedeemReceipt(redeemed: out.redeemed, balance: out.balance,
                                          rewardTitle: out.rewardTitle, somOff: out.somOff,
                                          replayed: out.replayed))
        } catch {
            return .failure(.network)
        }
    }
}

/// Оффлайн-источник: отдаёт то, что положили в конструктор, и «списывает» локально.
/// Нужен, чтобы приложение работало и тестировалось без Firebase (`AppConfig.useFirebase`).
public final class MockPointsRepository: PointsRepository {
    private var stored: [VenuePointsCard]

    public init(cards: [VenuePointsCard] = []) { stored = cards }

    public func cards(userID: String) -> AsyncStream<Result<[VenuePointsCard], AppError>> {
        let snapshot = userID.isEmpty ? [] : stored
        return AsyncStream { continuation in
            continuation.yield(.success(snapshot))
            continuation.finish()
        }
    }

    public func redeem(venueID: String, userID: String, rewardID: String,
                pointsToSpend: Int, idempotencyKey: String) async -> Result<RedeemReceipt, AppError> {
        guard !userID.isEmpty else { return .failure(.unauthenticated) }
        let spend = max(pointsToSpend, 1)
        guard let index = stored.firstIndex(where: { $0.venueID == venueID }),
              stored[index].balance >= spend else { return .failure(.server(code: "insufficient")) }
        stored[index].balance -= spend
        stored[index].lifetimeRedeemed += spend
        return .success(RedeemReceipt(redeemed: spend, balance: stored[index].balance,
                                      rewardTitle: "Демо-награда"))
    }
}

// MARK: - Приведение ошибок Firestore к доменным

extension AppError {
    /// Граница слоя Data: выше неё `NSError` от Firebase уже не встречается.
    public init(firestore error: Error) {
        let code = FirestoreErrorCode.Code(rawValue: (error as NSError).code)
        switch code {
        case .permissionDenied:            self = .permissionDenied
        case .unauthenticated:             self = .unauthenticated
        case .unavailable, .deadlineExceeded: self = .network
        case .notFound:                    self = .notFound
        default:                           self = .unknown
        }
    }
}
