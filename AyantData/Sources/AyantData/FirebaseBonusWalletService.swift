import Foundation
import FirebaseFirestore
import AyantDomain

/// Серверный кошелёк бонусов: `bonusWallets/{uid}` + функции
/// `bonusWalletSync` / `earnBonus` / `buyCoupon` (`functions/src/index.ts`, секция 9).
///
/// Баланс читается снапшот-листенером — покупка на другом устройстве или
/// награда за приглашённого видны сразу, без опроса. Всё, что меняет баланс,
/// идёт через функции: правила закрывают кошелёк на запись целиком.
public final class FirebaseBonusWalletService: BonusWalletService {
    private let db = Firestore.firestore()
    private let auth: AuthService
    private let syncURL = AyantBackend.functionURL("bonusWalletSync")
    private let earnURL = AyantBackend.functionURL("earnBonus")
    private let buyURL = AyantBackend.functionURL("buyCoupon")
    private let claimGiftURL = AyantBackend.functionURL("claimGift")

    /// `AuthService` — за ID-токеном для функций. Даёт композиционный корень.
    public init(auth: AuthService) {
        self.auth = auth
    }

    public func balance(userID: String) -> AsyncStream<Int> {
        AsyncStream { continuation in
            guard !userID.isEmpty else { continuation.finish(); return }
            let registration = db.collection(FS.Collection.bonusWallets).document(userID)
                .addSnapshotListener { snapshot, _ in
                    // Документа ещё нет (кошелёк не заведён) — молчим: баланс
                    // придёт ответом bonusWalletSync.
                    guard let data = snapshot?.data() else { return }
                    continuation.yield(data.int(FS.BonusWalletDoc.balance) ?? 0)
                }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    public func sync(localBalance: Int) async throws -> Int {
        let j = try await post(syncURL, [FS.WalletAPI.localBalance: max(0, localBalance)])
        guard j.bool(FS.WalletAPI.ok) == true else {
            throw WalletError.server(j.string(FS.WalletAPI.error) ?? "sync_failed")
        }
        return j.int(FS.WalletAPI.balance) ?? 0
    }

    public func earn(amount: Int, source: String, idempotencyKey: String) async throws -> BonusEarnOutcome {
        let j = try await post(earnURL, [
            FS.WalletAPI.amount: amount,
            FS.WalletAPI.source: source,
            FS.WalletAPI.idempotencyKey: idempotencyKey,
        ])
        let ok = j.bool(FS.WalletAPI.ok) ?? false
        return BonusEarnOutcome(ok: ok,
                                granted: j.int(FS.WalletAPI.granted) ?? 0,
                                balance: j.int(FS.WalletAPI.balance) ?? 0,
                                errorCode: ok ? nil : (j.string(FS.WalletAPI.error) ?? "earn_failed"),
                                capReason: j.string(FS.WalletAPI.capReason).flatMap(BonusEarnCapReason.init(rawValue:)),
                                dailyLeft: j.int(FS.WalletAPI.dailyLeft),
                                sourceLeft: j.int(FS.WalletAPI.sourceLeft))
    }

    public func buy(_ purchase: BonusPurchase, idempotencyKey: String) async throws -> BonusPurchaseOutcome {
        var body: [String: Any] = [FS.WalletAPI.idempotencyKey: idempotencyKey]
        switch purchase {
        case .offer(let id):
            body[FS.WalletAPI.offerID] = id
        case .reward(let id, let asGift, let fromName):
            body[FS.WalletAPI.rewardID] = id
            if asGift {
                body[FS.WalletAPI.asGift] = true
                body[FS.WalletAPI.fromName] = fromName
            }
        }
        let j = try await post(buyURL, body)
        let ok = j.bool(FS.WalletAPI.ok) ?? false
        guard ok else {
            return BonusPurchaseOutcome(ok: false, errorCode: j.string(FS.WalletAPI.error) ?? "buy_failed")
        }
        var coupon: Coupon?
        if let code = j.string(FS.WalletAPI.code), !code.isEmpty {
            coupon = Coupon(id: j.string(FS.WalletAPI.couponID) ?? code,
                            title: j.string(FS.WalletAPI.title) ?? "",
                            code: code, createdAt: .now, used: false,
                            venueID: j.string(FS.WalletAPI.venueID) ?? "",
                            venueName: j.string(FS.WalletAPI.venueName) ?? "",
                            kind: { if case .offer = purchase { return "offer" } else { return "reward" } }(),
                            expiresAt: j.int(FS.WalletAPI.expiresAt).map {
                                Date(timeIntervalSince1970: TimeInterval($0) / 1000) })
        }
        return BonusPurchaseOutcome(ok: true, coupon: coupon,
                                    giftCode: j.string(FS.WalletAPI.giftCode),
                                    balance: j.int(FS.WalletAPI.balance) ?? 0,
                                    replayed: j.bool(FS.WalletAPI.replayed) ?? false)
    }

    public func claimGift(code: String) async throws -> BonusPurchaseOutcome {
        let j = try await post(claimGiftURL, [FS.WalletAPI.code: code])
        guard j.bool(FS.WalletAPI.ok) == true, let couponCode = j.string(FS.WalletAPI.code) else {
            return BonusPurchaseOutcome(ok: false, errorCode: j.string(FS.WalletAPI.error) ?? "claim_failed")
        }
        let coupon = Coupon(id: j.string(FS.WalletAPI.couponID) ?? couponCode,
                            title: j.string(FS.WalletAPI.title) ?? "",
                            code: couponCode, createdAt: .now, used: false,
                            venueID: j.string(FS.WalletAPI.venueID) ?? "",
                            venueName: j.string(FS.WalletAPI.venueName) ?? "",
                            kind: "gift")
        return BonusPurchaseOutcome(ok: true, coupon: coupon,
                                    replayed: j.bool(FS.WalletAPI.replayed) ?? false)
    }

    // MARK: HTTP

    private enum WalletError: Error {
        case unauthenticated
        case server(String)
    }

    /// POST с ID-токеном. Ответ с кодом ошибки (409/404) — это данные, а не
    /// исключение: разбирает вызывающий. Исключение — только сеть и токен.
    private func post(_ urlString: String, _ body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        guard let token = await auth.idToken(), !token.isEmpty else { throw WalletError.unauthenticated }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        await req.attachAppCheck()
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let j = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        // Любой 5xx — с телом (`buy_failed`, `earn_failed`) или без — как обрыв
        // сети: транзакция могла пройти до сбоя, вызывающий повторит с тем же
        // ключом. Окончательный ответ — только 2xx/4xx.
        if let http = response as? HTTPURLResponse, http.statusCode >= 500 {
            throw URLError(.badServerResponse)
        }
        return j
    }
}
