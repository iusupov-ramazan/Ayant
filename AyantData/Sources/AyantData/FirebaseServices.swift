//
//  FirebaseServices.swift
//
//  Реализации протоколов AuthService / DataRepository / PushService на Firebase.
//  Включается флагом AppConfig.useFirebase = true.
//
//  Google-вход требует пакета GoogleSignIn-iOS. Пока он не добавлен,
//  код всё равно компилируется (#if canImport), а Google отдаёт notConfigured.
//

import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import UIKit
import SwiftUI
import GoogleSignIn
import AyantDomain

// MARK: - Auth

public final class FirebaseAuthService: AuthService {
    /// Пустой инициализатор нужен явно: синтезированный — internal.
    public init() {}


    public func currentUser() -> SANUser? {
        guard let u = Auth.auth().currentUser else { return nil }
        return map(u, provider: Self.provider(of: u))
    }

    /// Провайдер восстановленной сессии — из самой записи Firebase.
    ///
    /// Раньше здесь стояло `provider: .email` для всех: после перезапуска гость
    /// переставал быть гостем (`isGuest == false`), все гостевые ограничения
    /// молча отключались, а имя «Гость» превращалось в «Друг». Анонимность
    /// проверяем первой — у анонимной записи `providerData` пуст.
    private static func provider(of user: User) -> AuthProvider {
        if user.isAnonymous { return .guest }
        let ids = user.providerData.map(\.providerID)
        if ids.contains("apple.com") { return .apple }
        if ids.contains("google.com") { return .google }
        return .email
    }

    /// Слушатель состояния Firebase Auth, завёрнутый в поток.
    /// Слушатель снимается вместе с потребителем (`onTermination`) — тот же
    /// приём, что у снапшот-листенеров баллов и карт лояльности.
    public func userChanges() -> AsyncStream<SANUser?> {
        AsyncStream { continuation in
            let handle = Auth.auth().addStateDidChangeListener { [self] _, user in
                continuation.yield(user.map { map($0, provider: Self.provider(of: $0)) })
            }
            continuation.onTermination = { _ in
                Auth.auth().removeStateDidChangeListener(handle)
            }
        }
    }

    public func idToken() async -> String? {
        guard let u = Auth.auth().currentUser else { return nil }
        return try? await u.getIDToken()
    }

    /// Вход по почте. Привязать её к гостевой записи нельзя — аккаунт уже
    /// существует и у него свой uid, поэтому гостевая запись просто сменяется.
    /// Данных в ней нет (гостю запрещены сохранения, отзывы, баллы), а сама
    /// анонимная запись убирается штатной чисткой Firebase Auth.
    public func signInWithEmail(_ email: String, password: String) async throws -> SANUser {
        let clean = AuthValidation.normalizedEmail(email)
        return try await Self.translating {
            let r = try await Auth.auth().signIn(withEmail: clean, password: password)
            return map(r.user, provider: .email)
        }
    }

    /// Регистрация. Если сейчас открыт ГОСТЕВОЙ сеанс — не создаём вторую
    /// запись, а привязываем почту к текущей анонимной (`link`): uid
    /// сохраняется, поэтому накопленное гостем не теряется, а в Firebase Auth
    /// не остаётся брошенной анонимной записи.
    public func registerWithEmail(name: String, email: String, password: String) async throws -> SANUser {
        let clean = AuthValidation.normalizedEmail(email)
        let cleanName = AuthValidation.normalizedName(name)
        return try await Self.translating {
            let user: User
            if let guest = Auth.auth().currentUser, guest.isAnonymous {
                let credential = EmailAuthProvider.credential(withEmail: clean, password: password)
                user = try await guest.link(with: credential).user
            } else {
                user = try await Auth.auth().createUser(withEmail: clean, password: password).user
            }
            let change = user.createProfileChangeRequest()
            change.displayName = cleanName
            try await change.commitChanges()
            return SANUser(id: user.uid, name: cleanName, email: clean, provider: .email)
        }
    }

    /// Сброс пароля. Ошибку «нет такого аккаунта» Firebase (с защитой от
    /// перебора) не отдаёт — для пользователя это всегда «письмо отправлено».
    public func sendPasswordReset(email: String) async throws {
        let clean = AuthValidation.normalizedEmail(email)
        try await Self.translating {
            try await Auth.auth().sendPasswordReset(withEmail: clean)
        }
    }

    /// `@MainActor`: шторка Google — UIKit-презентация поверх корневого
    /// контроллера, окно ищем на главном потоке.
    ///
    /// ВЕСЬ вызов GIDSignIn стоит внутри `translating`: раньше туда попадал
    /// только обмен credential на Firebase-пользователя, и отмена шторки
    /// (`com.google.GIDSignIn`, код -5) улетала наружу английским системным
    /// текстом вместо `AuthError.cancelled`, который стор молча проглатывает.
    @MainActor
    public func signInWithGoogle() async throws -> SANUser {
        #if canImport(GoogleSignIn)
        guard let clientID = FirebaseApp.app()?.options.clientID,
              let root = UIApplication.shared.firstKeyWindow?.rootViewController
        else { throw AuthError.notConfigured("Google") }

        return try await Self.translating {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthError.invalidCredentials
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString)
            return map(try await signInLinkingGuest(with: credential), provider: .google)
        }
        #else
        // Пакет GoogleSignIn ещё не добавлен — см. FIREBASE_SETUP.md, шаг 2.
        throw AuthError.notConfigured("Google (нужен пакет GoogleSignIn-iOS)")
        #endif
    }

    public func signInWithApple(_ c: AppleCredential) async throws -> SANUser {
        // Обмениваем Apple id-token + nonce на Firebase-credential.
        guard let token = c.idTokenString, let nonce = c.rawNonce else {
            throw AuthError.invalidCredentials
        }
        let credential = OAuthProvider.appleCredential(
            withIDToken: token, rawNonce: nonce, fullName: nil)
        return try await Self.translating {
            let user = try await signInLinkingGuest(with: credential)
            // Имя Apple отдаёт только при первом входе — сохраняем в профиль Firebase.
            if let name = c.name, user.displayName == nil {
                let change = user.createProfileChangeRequest()
                change.displayName = AuthValidation.normalizedName(name)
                try? await change.commitChanges()
            }
            return map(user, provider: .apple)
        }
    }

    public func continueAsGuest() async throws -> SANUser {
        try await Self.translating {
            let r = try await Auth.auth().signInAnonymously()
            return SANUser(id: r.user.uid, name: "Гость", email: nil, provider: .guest)
        }
    }

    public func signOut() {
        try? Auth.auth().signOut()
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
    }

    /// Полное удаление аккаунта. Каскад по Firestore делает Cloud Function
    /// (клиенту правила запрещают чистить `venuePoints`/`coupons`), затем она же
    /// удаляет запись в Firebase Auth — поэтому локально остаётся только выйти.
    public func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { return }
        // Анонимную запись сервером чистить нечего — удаляем на месте.
        if user.isAnonymous {
            try await Self.translating { try await user.delete() }
            signOut()
            return
        }
        guard let token = try? await user.getIDToken() else { throw AuthError.requiresRecentLogin }
        var req = URLRequest(url: URL(string: AyantBackend.functionURL("deleteAccount"))!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let (_, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200: signOut()
        case 401: throw AuthError.requiresRecentLogin
        case 409: throw AuthError.unknown("Аккаунт управляет заведениями. Напишите в поддержку, чтобы передать их, — после этого удалим аккаунт.")
        // 404 = функция ещё не развёрнута (`firebase deploy --only functions`),
        // 503 = недоступна. Для пользователя это одно и то же: сервер молчит.
        case 404, 503, 0: throw AuthError.unknown("Сервис удаления недоступен. Попробуйте позже или напишите в поддержку (код \(code)).")
        default: throw AuthError.unknown("Не удалось удалить аккаунт (код \(code)). Попробуйте позже.")
        }
    }

    /// Отзыв гранта Apple (App Review 5.1.1(v)). Код — из повторной шторки
    /// Sign in with Apple, показанной перед удалением; Firebase сам обменивает
    /// его у Apple на refresh-токен и отзывает.
    public func revokeAppleToken(authorizationCode: String) async throws {
        try await Self.translating {
            try await Auth.auth().revokeToken(withAuthorizationCode: authorizationCode)
        }
    }

    public func discardGuestAccount() async {
        guard let user = Auth.auth().currentUser, user.isAnonymous else { return }
        try? await user.delete()
    }

    /// Вход по внешнему провайдеру поверх гостевого сеанса.
    ///
    /// Сначала пробуем привязать (`link`) — тогда гость сохраняет uid и всё,
    /// что успел накопить. Если такой аккаунт уже существует, привязка невозможна
    /// (`credentialAlreadyInUse`) — входим обычным способом, гостевая запись
    /// остаётся анонимной и без данных: писать что-либо гостю уже запрещено.
    private func signInLinkingGuest(with credential: AuthCredential) async throws -> User {
        if let guest = Auth.auth().currentUser, guest.isAnonymous {
            do { return try await guest.link(with: credential).user }
            catch let error as NSError where
                error.code == AuthErrorCode.credentialAlreadyInUse.rawValue ||
                error.code == AuthErrorCode.emailAlreadyInUse.rawValue {
                // Падаем в обычный вход ниже.
            }
        }
        return try await Auth.auth().signIn(with: credential).user
    }

    private func map(_ u: User, provider: AuthProvider) -> SANUser {
        // Гостю подставляем «Гость», а не «Друг»: имя видно в профиле и на
        // гостевых заглушках, и «Друг» читается как настоящий аккаунт.
        let fallback = provider == .guest ? "Гость" : "Друг"
        return SANUser(id: u.uid, name: u.displayName ?? fallback, email: u.email, provider: provider)
    }

    // MARK: Перевод ошибок Firebase

    /// Оборачивает вызов Firebase и переводит его ошибку в `AuthError`.
    /// Всё, что уже `AuthError`, пропускаем как есть.
    private static func translating<T>(_ work: () async throws -> T) async throws -> T {
        do { return try await work() }
        catch let error as AuthError { throw error }
        catch { throw mapError(error) }
    }

    /// `AuthErrorCode` → русское сообщение. Без этого пользователь видел
    /// «The password is invalid or the user does not have a password.».
    static func mapError(_ error: Error) -> AuthError {
        let ns = error as NSError
        // Отмена в шторке Google приходит из GIDSignIn, а не из Firebase, и без
        // этой ветки показывалась как ошибка на английском.
        if ns.domain == "com.google.GIDSignIn" && ns.code == -5 { return .cancelled }
        guard ns.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: ns.code) else {
            if ns.domain == NSURLErrorDomain {
                return ns.code == NSURLErrorCancelled ? .cancelled : .network
            }
            return .unknown(ns.localizedDescription)
        }
        switch code {
        case .invalidEmail: return .invalidEmail
        case .emailAlreadyInUse, .accountExistsWithDifferentCredential, .credentialAlreadyInUse:
            return .emailAlreadyInUse
        case .weakPassword: return .weakPassword
        case .userNotFound: return .userNotFound
        case .userDisabled: return .userDisabled
        case .wrongPassword, .invalidCredential: return .invalidCredentials
        case .tooManyRequests: return .tooManyRequests
        case .networkError: return .network
        case .requiresRecentLogin: return .requiresRecentLogin
        case .webContextCancelled: return .cancelled
        // Связка ключей недоступна (обычно неподписанная сборка в симуляторе;
        // на устройстве — сразу после восстановления из бэкапа). Английский
        // текст SDK пользователю ни о чём не говорит.
        case .keychainError:
            return .unknown("Не удалось сохранить сессию на устройстве. Перезапустите приложение и попробуйте снова.")
        // Остальные коды SDK — по-русски и с кодом для поддержки, а не
        // `localizedDescription` на английском.
        default:
            return .unknown("Не удалось выполнить операцию. Попробуйте ещё раз (код \(ns.code)).")
        }
    }
}

// MARK: - Firestore

public final class FirebaseDataRepository: DataRepository {
    /// Пустой инициализатор нужен явно: синтезированный — internal.
    public init() {}

    private let db = Firestore.firestore()

    public func fetchVenues() async throws -> [Venue] {
        let snap = try await db.collection(FS.Collection.venues).getDocuments()
        print("🔥 venues snap: \(snap.documents.count) docs")
        return snap.documents.compactMap { doc -> Venue? in
            let v = Venue(firestore: doc.data(), id: doc.documentID)
            if v == nil { print("⚠️ venue mapping failed [\(doc.documentID)]: \(doc.data())") }
            return v
        }
    }

    public func fetchDeals() async throws -> [Deal] {
        let snap = try await db.collection(FS.Collection.deals)
            .whereField(FS.DealDoc.validUntil, isGreaterThan: Timestamp(date: .now))
            .getDocuments()
        print("🔥 deals snap: \(snap.documents.count) docs")
        return snap.documents.compactMap { doc -> Deal? in
            let d = Deal(firestore: doc.data(), id: doc.documentID)
            if d == nil { print("⚠️ deal mapping failed [\(doc.documentID)]: \(doc.data())") }
            return d
        }
    }

    /// Отзывы одного заведения. Индекс: reviews (venueID ASC, createdAt DESC)
    /// — он объявлен в firestore.indexes.json, без него запрос падает в проде.
    public func fetchReviews(venueID: String, limit: Int) async throws -> [Review] {
        let snap = try await db.collection(FS.Collection.reviews)
            .whereField(FS.ReviewDoc.venueID, isEqualTo: venueID)
            .order(by: FS.ReviewDoc.createdAt, descending: true)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap { Review(firestore: $0.data(), id: $0.documentID) }
    }

    /// Инбокс владельца. `whereIn` у Firestore ограничен 30 значениями, поэтому
    /// список заведений режем на куски и запрашиваем их параллельно.
    public func fetchReviews(venueIDs: [String], limit: Int) async throws -> [Review] {
        guard !venueIDs.isEmpty else { return [] }
        let chunks = stride(from: 0, to: venueIDs.count, by: Self.whereInLimit).map {
            Array(venueIDs[$0 ..< min($0 + Self.whereInLimit, venueIDs.count)])
        }
        let collected = try await withThrowingTaskGroup(of: [Review].self) { group in
            for chunk in chunks {
                group.addTask { [db] in
                    let snap = try await db.collection(FS.Collection.reviews)
                        .whereField(FS.ReviewDoc.venueID, in: chunk)
                        .order(by: FS.ReviewDoc.createdAt, descending: true)
                        .limit(to: limit)
                        .getDocuments()
                    return snap.documents.compactMap { Review(firestore: $0.data(), id: $0.documentID) }
                }
            }
            var all: [Review] = []
            for try await part in group { all += part }
            return all
        }
        // Каждый кусок вернул свои `limit` — общий срез делаем после слияния.
        return Array(collected.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }

    /// Отзывы пользователя. Одиночное равенство — хватает автоиндекса по полю.
    public func fetchReviews(authorID: String, limit: Int) async throws -> [Review] {
        let snap = try await db.collection(FS.Collection.reviews)
            .whereField(FS.ReviewDoc.authorID, isEqualTo: authorID)
            .limit(to: limit)
            .getDocuments()
        return snap.documents.compactMap { Review(firestore: $0.data(), id: $0.documentID) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Потолок значений в `whereField(_:in:)` у Firestore.
    private static let whereInLimit = 30

    public func saveReview(_ review: Review) async throws {
        try await db.collection(FS.Collection.reviews).document(review.id)
            .setData(review.firestoreData, merge: true)
    }

    public func deleteReview(id: String) async throws {
        try await db.collection(FS.Collection.reviews).document(id).delete()
    }

    // Погашение купона: детерминированный id ⇒ повторно не дублируется.
    public func logRedemption(userID: String, dealID: String, venueID: String) async throws {
        try await db.collection(FS.Collection.redemptions).document("\(userID)_\(dealID)").setData([
            FS.RedemptionDoc.userID: userID,
            FS.RedemptionDoc.dealID: dealID,
            FS.RedemptionDoc.venueID: venueID,
            FS.RedemptionDoc.createdAt: Timestamp(date: .now),
            FS.RedemptionDoc.status: FS.RedemptionDoc.statusNew,
        ], merge: true)
    }

    // Реферал: один документ на приглашённого.
    public func recordReferral(inviteeID: String, referrerID: String) async throws {
        try await db.collection(FS.Collection.referrals).document(inviteeID).setData([
            FS.ReferralDoc.inviteeID: inviteeID,
            FS.ReferralDoc.referrerID: referrerID,
            FS.ReferralDoc.createdAt: Timestamp(date: .now),
        ], merge: true)
    }

    // Подарочный купон: создаём документ по коду.
    public func createGiftCoupon(title: String, code: String, fromName: String) async throws {
        try await db.collection(FS.Collection.giftCoupons).document(code).setData([
            FS.GiftCouponDoc.title: title,
            FS.GiftCouponDoc.code: code,
            FS.GiftCouponDoc.fromName: fromName,
            FS.GiftCouponDoc.claimed: false,
            FS.GiftCouponDoc.createdAt: Timestamp(date: .now),
        ])
    }

    // Забираем подарок один раз: если не занят — помечаем claimed и возвращаем.
    public func claimGiftCoupon(code: String) async throws -> GiftInfo? {
        let ref = db.collection(FS.Collection.giftCoupons).document(code)
        let snap = try await ref.getDocument()
        guard let d = snap.data(), d.bool(FS.GiftCouponDoc.claimed) != true,
              let title = d.string(FS.GiftCouponDoc.title) else { return nil }
        try await ref.setData([
            FS.GiftCouponDoc.claimed: true,
            FS.GiftCouponDoc.claimedAt: Timestamp(date: .now),
        ], merge: true)
        return GiftInfo(title: title, code: code)
    }

    // Забирает неполученные серверные бонусы и помечает claimed.
    public func claimBonusGrants(userID: String) async throws -> Int {
        // Один фильтр по userID (без составного индекса); claimed фильтруем в коде.
        let snap = try await db.collection(FS.Collection.bonusGrants)
            .whereField(FS.BonusGrantDoc.userID, isEqualTo: userID)
            .getDocuments()
        let unclaimed = snap.documents.filter { $0.data().bool(FS.BonusGrantDoc.claimed) != true }
        guard !unclaimed.isEmpty else { return 0 }
        var total = 0
        let batch = db.batch()
        for doc in unclaimed {
            total += doc.data().int(FS.BonusGrantDoc.amount) ?? 0
            batch.setData([FS.BonusGrantDoc.claimed: true], forDocument: doc.reference, merge: true)
        }
        try await batch.commit()
        return total
    }

    public func updateReviewReply(reviewID: String, reply: HostReply?) async throws {
        let doc = db.collection(FS.Collection.reviews).document(reviewID)
        if let reply {
            try await doc.setData([FS.ReviewDoc.hostReply: reply.firestoreMap], merge: true)
        } else {
            try await doc.updateData([FS.ReviewDoc.hostReply: FieldValue.delete()])
        }
    }

    public func fetchCategories() async throws -> [RemoteCategory] {
        let snap = try await db.collection(FS.Collection.categories).getDocuments()
        return snap.documents.compactMap { RemoteCategory(firestore: $0.data(), id: $0.documentID) }
    }

    /// Опубликованные веса ранжирования из config/rankingWeights (карта W_*→число).
    /// Отсутствие документа/поля → nil → клиент остаётся на `RankingWeights.default`.
    public func fetchRankingWeights() async throws -> [String: Double]? {
        let snap = try await db.collection(FS.Collection.config)
            .document(FS.Document.rankingWeights).getDocument()
        guard snap.exists, let data = snap.data() else { return nil }
        var out: [String: Double] = [:]
        for (k, v) in data {
            if let n = (v as? NSNumber)?.doubleValue { out[k] = n }
        }
        return out.isEmpty ? nil : out
    }
}

// MARK: - Analytics (Firestore)

public final class FirebaseAnalyticsService: AnalyticsService {
    /// Пустой инициализатор нужен явно: синтезированный — internal.
    public init() {}

    private let db = Firestore.firestore()

    public func log(venueID: String, metric: String) {
        guard !venueID.isEmpty else { return }
        // Событие телеметрии: счётчик инкрементирует Cloud Function countAnalyticsEvent
        // (клиенту запрещено писать в analytics/* напрямую — см. firestore.rules).
        db.collection(FS.Collection.analyticsEvents).addDocument(data: [
            FS.AnalyticsEventDoc.venueID: venueID,
            FS.AnalyticsEventDoc.metric: metric,
            FS.AnalyticsEventDoc.createdAt: Timestamp(date: .now),
        ])
    }

    public func fetchStats(venueID: String, days: Int) async throws -> [String: Int] {
        let cutoff = Self.dayKey(daysAgo: max(0, days - 1))
        let snap = try await db.collection(FS.Collection.analytics).document(venueID)
            .collection(FS.Collection.days)
            .whereField(FieldPath.documentID(), isGreaterThanOrEqualTo: cutoff)
            .getDocuments()
        var totals: [String: Int] = [:]
        for doc in snap.documents {
            for (k, v) in doc.data() where k != FS.AnalyticsDayDoc.date {
                if let n = (v as? NSNumber)?.intValue { totals[k, default: 0] += n }
            }
        }
        return totals
    }

    public func fetchDailyStats(venueID: String, days: Int) async throws -> [String: [String: Int]] {
        let cutoff = Self.dayKey(daysAgo: max(0, days - 1))
        let snap = try await db.collection(FS.Collection.analytics).document(venueID)
            .collection(FS.Collection.days)
            .whereField(FieldPath.documentID(), isGreaterThanOrEqualTo: cutoff)
            .getDocuments()
        var byDay: [String: [String: Int]] = [:]
        for doc in snap.documents {
            var metrics: [String: Int] = [:]
            for (k, v) in doc.data() where k != FS.AnalyticsDayDoc.date {
                if let n = (v as? NSNumber)?.intValue { metrics[k] = n }
            }
            byDay[doc.documentID] = metrics
        }
        return byDay
    }

    static func dayKey(daysAgo: Int = 0) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

/// Пишет события ранжирования в append-only коллекцию `rankingEvents`
/// (правила: только create, см. firestore.rules). Fire-and-forget: ошибки не
/// пробрасываем, чтобы телеметрия не влияла на UX. Экспорт для обучения весов —
/// офлайн (BigQuery / выгрузка), клиент отсюда не читает.
public final class FirebaseRankingEventService: RankingEventService {
    /// Пустой инициализатор нужен явно: синтезированный — internal.
    public init() {}

    private let db = Firestore.firestore()
    public func log(_ event: RankingEvent) {
        db.collection(FS.Collection.rankingEvents).addDocument(data: event.asFirestore)
    }
}

// MARK: - Push (FCM)

public final class FirebasePushService: NSObject, PushService {
    /// Явный public init: у наследника NSObject он обязан быть override.
    public override init() { super.init() }

    public func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
        return granted
    }
    public func subscribe(topic: String) { Messaging.messaging().subscribe(toTopic: topic) }
    public func unsubscribe(topic: String) { Messaging.messaging().unsubscribe(fromTopic: topic) }

    public func registerToken(_ token: String, city: String, uid: String?) {
        var data: [String: Any] = [
            FS.UserTokenDoc.city: city,
            FS.UserTokenDoc.updatedAt: Timestamp(date: .now),
        ]
        if let uid { data[FS.UserTokenDoc.uid] = uid }
        Firestore.firestore().collection(FS.Collection.userTokens)
            .document(token).setData(data, merge: true)
    }

    /// Выход: снимаем темы, удаляем документ `userTokens/<token>` и сам токен.
    ///
    /// Порядок важен — документ удаляем ПОКА пользователь ещё авторизован
    /// (правило `userTokens` требует `request.auth != null`), и только потом
    /// сбрасываем токен в FCM. Иначе адресные кампании старого uid продолжают
    /// приходить на это устройство.
    public func unregisterDevice(topics: [String]) async {
        for topic in topics { try? await Messaging.messaging().unsubscribe(fromTopic: topic) }
        if let token = try? await Messaging.messaging().token() {
            try? await Firestore.firestore().collection(FS.Collection.userTokens)
                .document(token).delete()
        }
        try? await Messaging.messaging().deleteToken()
    }
}

// MARK: - Host Repository (Firestore)

public final class FirebaseHostRepository: HostRepository {
    /// Пустой инициализатор нужен явно: синтезированный — internal.
    public init() {}

    private let db = Firestore.firestore()

    public func saveVenue(_ dto: HostVenueDTO, ownerID: String) async throws {
        try await db.collection(FS.Collection.venues).document(dto.id)
            .setData(dto.firestoreData(ownerID: ownerID), merge: true)
    }

    public func deleteVenue(id: String) async throws {
        try await db.collection(FS.Collection.venues).document(id).delete()
        // Удаляем связанные предложения этого заведения.
        let snap = try await db.collection(FS.Collection.deals)
            .whereField(FS.DealDoc.venueID, isEqualTo: id).getDocuments()
        for doc in snap.documents { try? await doc.reference.delete() }
    }

    public func saveDeal(_ dto: HostDealDTO, ownerID: String) async throws {
        try await db.collection(FS.Collection.deals).document(dto.id)
            .setData(dto.firestoreData(ownerID: ownerID), merge: true)
    }

    public func deleteDeal(id: String) async throws {
        try await db.collection(FS.Collection.deals).document(id).delete()
    }

    public func fetchOwnedVenues(ownerID: String) async throws -> [HostVenueDTO] {
        let snap = try await db.collection(FS.Collection.venues)
            .whereField(FS.VenueDoc.ownerID, isEqualTo: ownerID).getDocuments()
        return snap.documents.compactMap { HostVenueDTO(firestore: $0.data(), id: $0.documentID) }
    }

    public func fetchOwnedDeals(ownerID: String) async throws -> [HostDealDTO] {
        let snap = try await db.collection(FS.Collection.deals)
            .whereField(FS.DealDoc.ownerID, isEqualTo: ownerID).getDocuments()
        return snap.documents.compactMap { HostDealDTO(firestore: $0.data(), id: $0.documentID) }
    }

    public func saveProfile(_ profile: HostProfile, ownerID: String) async throws {
        try await db.collection(FS.Collection.hosts).document(ownerID)
            .setData(profile.firestoreData, merge: true)
    }

    public func fetchProfile(ownerID: String) async throws -> HostProfile? {
        let snap = try await db.collection(FS.Collection.hosts).document(ownerID).getDocument()
        guard let d = snap.data() else { return nil }
        return HostProfile(firestore: d)
    }

    public func queuePushCampaign(headline: String, body: String, city: String,
                           category: String?, venueID: String, dealID: String?, ownerID: String) async throws {
        var data: [String: Any] = [
            FS.PushCampaignDoc.headline: headline,
            FS.PushCampaignDoc.body: body,
            FS.PushCampaignDoc.city: city,
            FS.PushCampaignDoc.venueID: venueID,
            FS.PushCampaignDoc.ownerID: ownerID,
            FS.PushCampaignDoc.status: FS.PushCampaignDoc.statusPending,
            FS.PushCampaignDoc.delivered: false,
            FS.PushCampaignDoc.createdAt: Timestamp(date: .now),
        ]
        if let category { data[FS.PushCampaignDoc.category] = category }
        if let dealID, !dealID.isEmpty { data[FS.PushCampaignDoc.dealID] = dealID }
        // Админ одобряет в панели (status → approved) → Cloud Function рассылает.
        _ = try await db.collection(FS.Collection.pushCampaigns).addDocument(data: data)
    }
}

// MARK: - Купоны (бэкенд-трекинг + сканер)

public final class FirebaseCouponService: CouponService {
    /// Пустой инициализатор нужен явно: синтезированный — internal.
    public init() {}

    private let db = Firestore.firestore()
    private let scanURL = AyantBackend.functionURL("scanCoupon")
    private let redeemURL = AyantBackend.functionURL("redeemVenuePoints")

    public func saveCoupon(_ c: Coupon, userID: String) async throws {
        try await db.collection(FS.Collection.coupons).document(c.id)
            .setData(c.firestoreData(userID: userID), merge: true)
    }

    public func fetchCoupons(userID: String) async throws -> [Coupon] {
        let snap = try await db.collection(FS.Collection.coupons)
            .whereField(FS.CouponDoc.userID, isEqualTo: userID).getDocuments()
        return snap.documents.map { Coupon(firestore: $0.data(), id: $0.documentID) }
    }

    public func fetchLoyaltyCards(userID: String) async throws -> [LoyaltyCard] {
        let snap = try await db.collection(FS.Collection.loyaltyCards)
            .whereField(FS.LoyaltyCardDoc.userID, isEqualTo: userID).getDocuments()
        return snap.documents.map { LoyaltyCard(firestore: $0.data()) }
    }

    /// Живой поток: штамп начисляет Cloud Function, а Firestore сам присылает
    /// изменение. Заменяет опрос раз в 4 с, который был на экранах лояльности.
    public func loyaltyCards(userID: String) -> AsyncStream<[LoyaltyCard]> {
        AsyncStream { continuation in
            guard !userID.isEmpty else { continuation.finish(); return }
            let registration = db.collection(FS.Collection.loyaltyCards)
                .whereField(FS.LoyaltyCardDoc.userID, isEqualTo: userID)
                .addSnapshotListener { snapshot, error in
                    guard error == nil else { return }   // сеть моргнула — оставляем последнее состояние
                    continuation.yield(snapshot?.documents.map { LoyaltyCard(firestore: $0.data()) } ?? [])
                }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    public func fetchVenuePoints(userID: String) async throws -> [VenuePointsCard] {
        let snap = try await db.collection(FS.Collection.venuePoints)
            .whereField(FS.VenuePointsDoc.userID, isEqualTo: userID).getDocuments()
        return snap.documents.map { VenuePointsCard(firestore: $0.data()) }
    }

    public func scanCoupon(code: String, venueID: String, idToken: String,
                    billAmount: Int?, bandIndex: Int?, idempotencyKey: String) async throws -> ScanOutcome {
        guard let url = URL(string: scanURL) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = [FS.ScanResponse.code: code, FS.ScanResponse.venueID: venueID]
        if let billAmount { body[FS.ScanResponse.billAmount] = billAmount }
        if let bandIndex { body[FS.ScanResponse.bandIndex] = bandIndex }
        if !idempotencyKey.isEmpty { body[FS.ScanResponse.idempotencyKey] = idempotencyKey }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        let j = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let ok = j.bool(FS.ScanResponse.ok) ?? false
        return ScanOutcome(
            ok: ok,
            title: j.string(FS.ScanResponse.title) ?? "",
            loyalty: j.bool(FS.ScanResponse.loyalty) ?? false,
            stamps: j.int(FS.ScanResponse.stamps) ?? 0,
            goal: j.int(FS.ScanResponse.goal) ?? 6,
            rewardIssued: j.bool(FS.ScanResponse.rewardIssued) ?? false,
            rewardTitle: j.string(FS.ScanResponse.rewardTitle) ?? "",
            errorCode: ok ? nil : (j.string(FS.ScanResponse.error) ?? "scan_failed"),
            points: j.bool(FS.ScanResponse.points) ?? false,
            awarded: j.int(FS.ScanResponse.awarded) ?? 0,
            balance: j.int(FS.ScanResponse.balance) ?? 0,
            replayed: j.bool(FS.ScanResponse.replayed) ?? false
        )
    }

    public func redeemVenuePoints(venueID: String, userID: String, rewardId: String,
                           pointsToSpend: Int, idToken: String,
                           idempotencyKey: String) async throws -> RedeemOutcome {
        guard let url = URL(string: redeemURL) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = [
            FS.RedeemResponse.venueID: venueID,
            FS.RedeemResponse.rewardId: rewardId,
        ]
        if !userID.isEmpty { body[FS.RedeemResponse.userID] = userID }
        if pointsToSpend > 0 { body[FS.RedeemResponse.pointsToSpend] = pointsToSpend }
        if !idempotencyKey.isEmpty { body[FS.RedeemResponse.idempotencyKey] = idempotencyKey }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        let j = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let ok = j.bool(FS.RedeemResponse.ok) ?? false
        return RedeemOutcome(
            ok: ok,
            redeemed: j.int(FS.RedeemResponse.redeemed) ?? 0,
            balance: j.int(FS.RedeemResponse.balance) ?? 0,
            rewardTitle: j.string(FS.RedeemResponse.rewardTitle) ?? "",
            somOff: j.int(FS.RedeemResponse.somOff),
            errorCode: ok ? nil : (j.string(FS.RedeemResponse.error) ?? "redeem_failed"),
            replayed: j.bool(FS.RedeemResponse.replayed) ?? false
        )
    }
}

private extension UIApplication {
    var firstKeyWindow: UIWindow? {
        connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow }
    }
}
