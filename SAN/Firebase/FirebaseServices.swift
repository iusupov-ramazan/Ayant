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

// MARK: - Auth

final class FirebaseAuthService: AuthService {

    func currentUser() -> SANUser? {
        guard let u = Auth.auth().currentUser else { return nil }
        return SANUser(id: u.uid, name: u.displayName ?? "Друг",
                       email: u.email, provider: .email)
    }

    func idToken() async -> String? {
        guard let u = Auth.auth().currentUser else { return nil }
        return try? await u.getIDToken()
    }

    func signInWithEmail(_ email: String, password: String) async throws -> SANUser {
        let r = try await Auth.auth().signIn(withEmail: email, password: password)
        return map(r.user, provider: .email)
    }

    func registerWithEmail(name: String, email: String, password: String) async throws -> SANUser {
        let r = try await Auth.auth().createUser(withEmail: email, password: password)
        let change = r.user.createProfileChangeRequest()
        change.displayName = name
        try await change.commitChanges()
        return SANUser(id: r.user.uid, name: name, email: email, provider: .email)
    }

    func signInWithGoogle() async throws -> SANUser {
        #if canImport(GoogleSignIn)
        guard let clientID = FirebaseApp.app()?.options.clientID,
              let root = await UIApplication.shared.firstKeyWindow?.rootViewController
        else { throw AuthError.notConfigured("Google") }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.invalidCredentials
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString)
        let authResult = try await Auth.auth().signIn(with: credential)
        return map(authResult.user, provider: .google)
        #else
        // Пакет GoogleSignIn ещё не добавлен — см. FIREBASE_SETUP.md, шаг 2.
        throw AuthError.notConfigured("Google (нужен пакет GoogleSignIn-iOS)")
        #endif
    }

    func signInWithApple(_ c: AppleCredential) async throws -> SANUser {
        // Обмениваем Apple id-token + nonce на Firebase-credential.
        guard let token = c.idTokenString, let nonce = c.rawNonce else {
            throw AuthError.invalidCredentials
        }
        let credential = OAuthProvider.appleCredential(
            withIDToken: token, rawNonce: nonce, fullName: nil)
        let result = try await Auth.auth().signIn(with: credential)
        // Имя Apple отдаёт только при первом входе — сохраняем в профиль Firebase.
        if let name = c.name, result.user.displayName == nil {
            let change = result.user.createProfileChangeRequest()
            change.displayName = name
            try? await change.commitChanges()
        }
        return map(result.user, provider: .apple)
    }

    func continueAsGuest() async throws -> SANUser {
        let r = try await Auth.auth().signInAnonymously()
        return SANUser(id: r.user.uid, name: "Гость", email: nil, provider: .guest)
    }

    func signOut() {
        try? Auth.auth().signOut()
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
    }

    private func map(_ u: User, provider: AuthProvider) -> SANUser {
        SANUser(id: u.uid, name: u.displayName ?? "Друг", email: u.email, provider: provider)
    }
}

// MARK: - Firestore

final class FirebaseDataRepository: DataRepository {
    private let db = Firestore.firestore()

    func fetchVenues() async throws -> [Venue] {
        let snap = try await db.collection("venues").getDocuments()
        print("🔥 venues snap: \(snap.documents.count) docs")
        return snap.documents.compactMap { doc -> Venue? in
            let v = Venue(firestore: doc.data(), id: doc.documentID)
            if v == nil { print("⚠️ venue mapping failed [\(doc.documentID)]: \(doc.data())") }
            return v
        }
    }

    func fetchDeals() async throws -> [Deal] {
        let snap = try await db.collection("deals")
            .whereField("validUntil", isGreaterThan: Timestamp(date: .now))
            .getDocuments()
        print("🔥 deals snap: \(snap.documents.count) docs")
        return snap.documents.compactMap { doc -> Deal? in
            let d = Deal(firestore: doc.data(), id: doc.documentID)
            if d == nil { print("⚠️ deal mapping failed [\(doc.documentID)]: \(doc.data())") }
            return d
        }
    }

    func fetchReviews() async throws -> [Review] {
        let snap = try await db.collection("reviews").getDocuments()
        print("🔥 reviews snap: \(snap.documents.count) docs")
        return snap.documents.compactMap { Review(firestore: $0.data(), id: $0.documentID) }
    }

    func saveReview(_ review: Review) async throws {
        try await db.collection("reviews").document(review.id)
            .setData(review.firestoreData, merge: true)
    }

    func deleteReview(id: String) async throws {
        try await db.collection("reviews").document(id).delete()
    }

    // Погашение купона: детерминированный id ⇒ повторно не дублируется.
    func logRedemption(userID: String, dealID: String, venueID: String) async throws {
        try await db.collection("redemptions").document("\(userID)_\(dealID)").setData([
            "userID": userID, "dealID": dealID, "venueID": venueID,
            "createdAt": Timestamp(date: .now), "status": "new"
        ], merge: true)
    }

    // Реферал: один документ на приглашённого.
    func recordReferral(inviteeID: String, referrerID: String) async throws {
        try await db.collection("referrals").document(inviteeID).setData([
            "inviteeID": inviteeID, "referrerID": referrerID,
            "createdAt": Timestamp(date: .now)
        ], merge: true)
    }

    // Подарочный купон: создаём документ по коду.
    func createGiftCoupon(title: String, code: String, fromName: String) async throws {
        try await db.collection("giftCoupons").document(code).setData([
            "title": title, "code": code, "fromName": fromName,
            "claimed": false, "createdAt": Timestamp(date: .now)
        ])
    }

    // Забираем подарок один раз: если не занят — помечаем claimed и возвращаем.
    func claimGiftCoupon(code: String) async throws -> GiftInfo? {
        let ref = db.collection("giftCoupons").document(code)
        let snap = try await ref.getDocument()
        guard let d = snap.data(), (d["claimed"] as? Bool) != true,
              let title = d["title"] as? String else { return nil }
        try await ref.setData(["claimed": true, "claimedAt": Timestamp(date: .now)], merge: true)
        return GiftInfo(title: title, code: code)
    }

    // Забирает неполученные серверные бонусы и помечает claimed.
    func claimBonusGrants(userID: String) async throws -> Int {
        // Один фильтр по userID (без составного индекса); claimed фильтруем в коде.
        let snap = try await db.collection("bonusGrants")
            .whereField("userID", isEqualTo: userID)
            .getDocuments()
        let unclaimed = snap.documents.filter { ($0.data()["claimed"] as? Bool) != true }
        guard !unclaimed.isEmpty else { return 0 }
        var total = 0
        let batch = db.batch()
        for doc in unclaimed {
            total += (doc.data()["amount"] as? NSNumber)?.intValue ?? 0
            batch.setData(["claimed": true], forDocument: doc.reference, merge: true)
        }
        try await batch.commit()
        return total
    }

    func updateReviewReply(reviewID: String, reply: HostReply?) async throws {
        let doc = db.collection("reviews").document(reviewID)
        if let reply {
            try await doc.setData([
                "hostReply": [
                    "text": reply.text,
                    "createdAt": Timestamp(date: reply.createdAt),
                    "updatedAt": Timestamp(date: reply.updatedAt)
                ]
            ], merge: true)
        } else {
            try await doc.updateData(["hostReply": FieldValue.delete()])
        }
    }
}

// MARK: - Analytics (Firestore)

final class FirebaseAnalyticsService: AnalyticsService {
    private let db = Firestore.firestore()

    func log(venueID: String, metric: String) {
        guard !venueID.isEmpty else { return }
        let day = Self.dayKey()
        db.collection("analytics").document(venueID)
            .collection("days").document(day)
            .setData([metric: FieldValue.increment(Int64(1)), "date": day], merge: true)
    }

    func fetchStats(venueID: String, days: Int) async throws -> [String: Int] {
        let cutoff = Self.dayKey(daysAgo: max(0, days - 1))
        let snap = try await db.collection("analytics").document(venueID)
            .collection("days")
            .whereField(FieldPath.documentID(), isGreaterThanOrEqualTo: cutoff)
            .getDocuments()
        var totals: [String: Int] = [:]
        for doc in snap.documents {
            for (k, v) in doc.data() where k != "date" {
                if let n = (v as? NSNumber)?.intValue { totals[k, default: 0] += n }
            }
        }
        return totals
    }

    static func dayKey(daysAgo: Int = 0) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

// MARK: - Push (FCM)

final class FirebasePushService: NSObject, PushService {
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
        return granted
    }
    func subscribe(topic: String) { Messaging.messaging().subscribe(toTopic: topic) }
    func unsubscribe(topic: String) { Messaging.messaging().unsubscribe(fromTopic: topic) }

    func registerToken(_ token: String, city: String, uid: String?) {
        var data: [String: Any] = ["city": city, "updatedAt": Timestamp(date: .now)]
        if let uid { data["uid"] = uid }
        Firestore.firestore().collection("userTokens").document(token).setData(data, merge: true)
    }
}

// MARK: - Маппинг Firestore → модели
// Схема документов описана в FIREBASE_SETUP.md.

private let categoryMap: [String: VenueCategory] = [
    "cafe": .cafe, "coffee": .coffee, "fastfood": .fastfood,
    "restaurant": .restaurant, "teahouse": .teahouse, "bakery": .bakery
]

private let typeMap: [String: DealType] = [
    "discount": .discount, "promo": .promo, "novelty": .novelty, "announcement": .announcement
]

private let statusMap: [String: DealStatus] = [
    "active": .active, "paused": .paused, "expired": .expired, "draft": .draft
]

// Обратные карты: модель → строковый ключ для записи в Firestore.
private let categoryKeyMap: [VenueCategory: String] = [
    .cafe: "cafe", .coffee: "coffee", .fastfood: "fastfood",
    .restaurant: "restaurant", .teahouse: "teahouse", .bakery: "bakery"
]
private let typeKeyMap: [DealType: String] = [
    .discount: "discount", .promo: "promo", .novelty: "novelty", .announcement: "announcement"
]
func firestoreCategoryKey(_ c: VenueCategory) -> String { categoryKeyMap[c] ?? c.rawValue }
func firestoreTypeKey(_ t: DealType) -> String { typeKeyMap[t] ?? t.rawValue }

extension Venue {
    init?(firestore d: [String: Any], id: String) {
        guard let name = d["name"] as? String,
              let categoryKey = d["category"] as? String,
              let category = categoryMap[categoryKey] ?? VenueCategory(rawValue: categoryKey)
        else { return nil }

        self.init(
            id: id,
            name: name,
            category: category,
            district: d["district"] as? String ?? "",
            address: d["address"] as? String ?? "",
            phone: d["phone"] as? String ?? "",
            emoji: d["emoji"] as? String ?? "🍽",
            gradient: [
                Color(hexString: d["gradientFrom"] as? String) ?? .sanAccent,
                Color(hexString: d["gradientTo"] as? String) ?? .orange
            ],
            imageURL: d["imageURL"] as? String,
            rating: (d["rating"] as? NSNumber)?.doubleValue ?? 0,
            reviewCount: (d["reviewCount"] as? NSNumber)?.intValue ?? 0,
            isVerified: d["isVerified"] as? Bool ?? false,
            savedByCount: (d["savedByCount"] as? NSNumber)?.intValue ?? 0,
            citySlug: d["city"] as? String ?? City.bishkek.id,
            latitude: (d["latitude"] as? NSNumber)?.doubleValue ?? City.bishkek.latitude,
            longitude: (d["longitude"] as? NSNumber)?.doubleValue ?? City.bishkek.longitude,
            todaySpecialText: d["todaySpecial"] as? String,
            openHour: (d["openHour"] as? NSNumber)?.intValue ?? 9,
            closeHour: (d["closeHour"] as? NSNumber)?.intValue ?? 22,
            weekHours: DayHours.parseArray(d["weekHours"]),
            pdfMenuURL: d["pdfMenuURL"] as? String,
            photoEmojis: d["photoEmojis"] as? [String] ?? [],
            ownerID: d["ownerID"] as? String ?? "",
            items: VenueItem.parse(d["items"]),
            statusRaw: d["status"] as? String ?? ModerationStatus.approved.rawValue,
            isPaused: d["isPaused"] as? Bool ?? false,
            whatsapp: d["whatsapp"] as? String ?? "",
            instagram: d["instagram"] as? String ?? "",
            telegram: d["telegram"] as? String ?? "",
            branches: Branch.parseArray(d["branches"]),
            boostedUntil: (d["boostedUntil"] as? Timestamp)?.dateValue(),
            loyaltyEnabled: d["loyaltyEnabled"] as? Bool ?? false,
            loyaltyGoal: (d["loyaltyGoal"] as? NSNumber)?.intValue ?? 6,
            loyaltyReward: d["loyaltyReward"] as? String ?? "Награда за лояльность",
            couponsEnabled: d["couponsEnabled"] as? Bool ?? true
        )
    }
}

extension Branch {
    var firestoreMap: [String: Any] {
        ["id": id, "address": address, "latitude": latitude, "longitude": longitude, "phone": phone]
    }
    static func parseArray(_ raw: Any?) -> [Branch] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { m in
            guard let id = m["id"] as? String, let address = m["address"] as? String else { return nil }
            return Branch(id: id, address: address,
                          latitude: (m["latitude"] as? NSNumber)?.doubleValue ?? 0,
                          longitude: (m["longitude"] as? NSNumber)?.doubleValue ?? 0,
                          phone: m["phone"] as? String ?? "")
        }
    }
}

extension DayHours {
    var firestoreMap: [String: Any] { ["closed": closed, "open": open, "close": close] }
    static func parseArray(_ raw: Any?) -> [DayHours] {
        guard let arr = raw as? [[String: Any]], arr.count == 7 else { return [] }
        return arr.map { m in
            DayHours(closed: m["closed"] as? Bool ?? false,
                     open: (m["open"] as? NSNumber)?.intValue ?? 540,
                     close: (m["close"] as? NSNumber)?.intValue ?? 1320)
        }
    }
}

extension VenueItem {
    /// Парсит массив карт Firestore в [VenueItem].
    static func parse(_ raw: Any?) -> [VenueItem] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { m in
            guard let id = m["id"] as? String, let name = m["name"] as? String else { return nil }
            return VenueItem(id: id, name: name,
                             emoji: m["emoji"] as? String ?? "🍽",
                             kind: m["kind"] as? String ?? "food",
                             imageURL: m["imageURL"] as? String ?? "")
        }
    }
    var firestoreMap: [String: Any] {
        ["id": id, "name": name, "emoji": emoji, "kind": kind, "imageURL": imageURL]
    }
}

extension Deal {
    init?(firestore d: [String: Any], id: String) {
        guard let venueID = d["venueID"] as? String,
              let typeKey = d["type"] as? String,
              let type = typeMap[typeKey] ?? DealType(rawValue: typeKey),
              let title = d["title"] as? String
        else { return nil }

        self.init(
            id: id,
            venueID: venueID,
            type: type,
            title: title,
            details: d["details"] as? String ?? "",
            emoji: d["emoji"] as? String ?? "🔥",
            oldPrice: (d["oldPrice"] as? NSNumber)?.intValue,
            newPrice: (d["newPrice"] as? NSNumber)?.intValue,
            discountPercent: (d["discountPercent"] as? NSNumber)?.intValue,
            validUntil: (d["validUntil"] as? Timestamp)?.dateValue() ?? .now,
            status: statusMap[d["status"] as? String ?? "active"] ?? .active,
            startDate: (d["startDate"] as? Timestamp)?.dateValue(),
            imageEmojis: d["imageEmojis"] as? [String] ?? [],
            imageURL: d["imageURL"] as? String,
            imageURLs: d["imageURLs"] as? [String] ?? []
        )
    }
}

extension Review {
    /// Документ для коллекции reviews.
    var firestoreData: [String: Any] {
        var d: [String: Any] = [
            "venueID": venueID,
            "authorID": authorID,
            "authorName": authorName,
            "rating": rating,
            "text": text,
            "photoEmojis": photoEmojis,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt)
        ]
        if let itemID { d["itemID"] = itemID }
        if let itemName { d["itemName"] = itemName }
        if !photos.isEmpty { d["photos"] = photos }
        if verifiedVisit { d["verifiedVisit"] = true }
        if let hostReply {
            d["hostReply"] = [
                "text": hostReply.text,
                "createdAt": Timestamp(date: hostReply.createdAt),
                "updatedAt": Timestamp(date: hostReply.updatedAt)
            ]
        }
        return d
    }

    init?(firestore d: [String: Any], id: String) {
        guard let venueID = d["venueID"] as? String,
              let rating = (d["rating"] as? NSNumber)?.intValue
        else { return nil }

        let created = (d["createdAt"] as? Timestamp)?.dateValue() ?? .now
        var reply: HostReply? = nil
        if let r = d["hostReply"] as? [String: Any], let text = r["text"] as? String {
            let rc = (r["createdAt"] as? Timestamp)?.dateValue() ?? created
            reply = HostReply(text: text, createdAt: rc, updatedAt: rc)
        }
        self.init(
            id: id,
            venueID: venueID,
            authorID: d["authorID"] as? String ?? "anon",
            authorName: d["authorName"] as? String ?? "Гость",
            rating: rating,
            text: d["text"] as? String ?? "",
            photoEmojis: d["photoEmojis"] as? [String] ?? [],
            createdAt: created,
            updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue() ?? created,
            hostReply: reply,
            itemID: d["itemID"] as? String,
            itemName: d["itemName"] as? String,
            photos: d["photos"] as? [String] ?? [],
            verifiedVisit: d["verifiedVisit"] as? Bool ?? false
        )
    }
}

private extension Color {
    /// Парсит "#RRGGBB" или "RRGGBB" в Color.
    init?(hexString: String?) {
        guard var s = hexString else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
}

// MARK: - Host DTO ⇄ Firestore

extension HostProfile {
    var firestoreData: [String: Any] {
        [
            "businessName": businessName,
            "categoryRaw": categoryRaw,
            "phone": phone,
            "email": email,
            "verification": verification.rawValue
        ]
    }
    init?(firestore d: [String: Any]) {
        guard let name = d["businessName"] as? String else { return nil }
        self.init(
            businessName: name,
            categoryRaw: d["categoryRaw"] as? String ?? VenueCategory.cafe.rawValue,
            phone: d["phone"] as? String ?? "",
            email: d["email"] as? String ?? "",
            verification: VerificationStatus(rawValue: d["verification"] as? String ?? "none") ?? .none)
    }
}

extension HostVenueDTO {
    /// Документ для коллекции venues (хост-заведение).
    func firestoreData(ownerID: String) -> [String: Any] {
        var d: [String: Any] = [
            "name": name,
            "category": firestoreCategoryKey(category),
            "district": district,
            "address": address,
            "phone": phone,
            "emoji": emoji,
            "gradientFrom": "#FF4D29",
            "gradientTo": "#FF8A1E",
            "city": City.bishkek.id,
            "latitude": latitude,
            "longitude": longitude,
            "openHour": openHour,
            "closeHour": closeHour,
            "isVerified": isVerified,
            "isPaused": isPaused,
            "ownerID": ownerID,
            "photoEmojis": [emoji],
            "status": status,
            "items": items.map(\.firestoreMap),
            "imageURL": imageURL,
            "weekHours": weekHours.map(\.firestoreMap),
            "pdfMenuURL": pdfMenuURL,
            "whatsapp": whatsapp,
            "instagram": instagram,
            "telegram": telegram,
            "branches": branches.map(\.firestoreMap),
            "boostedUntil": boostedUntil.map { Timestamp(date: $0) } as Any,
            "loyaltyEnabled": loyaltyEnabled,
            "loyaltyGoal": loyaltyGoal,
            "loyaltyReward": loyaltyReward,
            "couponsEnabled": couponsEnabled,
            "todaySpecial": todaySpecial ?? ""
        ]
        if (todaySpecial ?? "").isEmpty { d["todaySpecial"] = "" }
        return d
    }

    init?(firestore d: [String: Any], id: String) {
        guard let name = d["name"] as? String else { return nil }
        let key = d["category"] as? String ?? "cafe"
        // Порядок: встроенные слаги → пользовательские (slug→имя из бэкенда) → как есть.
        let cat = categoryMap[key]
            ?? VenueCategory.slugRegistry[key].flatMap(VenueCategory.init(rawValue:))
            ?? VenueCategory(rawValue: key)
            ?? .cafe
        let special = d["todaySpecial"] as? String
        self.init(
            id: id, name: name, categoryRaw: cat.rawValue,
            district: d["district"] as? String ?? "",
            address: d["address"] as? String ?? "",
            phone: d["phone"] as? String ?? "",
            emoji: d["emoji"] as? String ?? "🍽",
            latitude: (d["latitude"] as? NSNumber)?.doubleValue ?? City.bishkek.latitude,
            longitude: (d["longitude"] as? NSNumber)?.doubleValue ?? City.bishkek.longitude,
            openHour: (d["openHour"] as? NSNumber)?.intValue ?? 9,
            closeHour: (d["closeHour"] as? NSNumber)?.intValue ?? 22,
            todaySpecial: (special?.isEmpty == false) ? special : nil,
            isPaused: d["isPaused"] as? Bool ?? false,
            isVerified: d["isVerified"] as? Bool ?? false,
            status: d["status"] as? String ?? ModerationStatus.approved.rawValue,
            items: VenueItem.parse(d["items"]),
            imageURL: d["imageURL"] as? String ?? "",
            weekHours: { let w = DayHours.parseArray(d["weekHours"]); return w.isEmpty ? Venue.defaultWeek() : w }(),
            pdfMenuURL: d["pdfMenuURL"] as? String ?? "",
            whatsapp: d["whatsapp"] as? String ?? "",
            instagram: d["instagram"] as? String ?? "",
            telegram: d["telegram"] as? String ?? "",
            branches: Branch.parseArray(d["branches"]),
            boostedUntil: (d["boostedUntil"] as? Timestamp)?.dateValue(),
            loyaltyEnabled: d["loyaltyEnabled"] as? Bool ?? false,
            loyaltyGoal: (d["loyaltyGoal"] as? NSNumber)?.intValue ?? 6,
            loyaltyReward: d["loyaltyReward"] as? String ?? "Награда за лояльность",
            couponsEnabled: d["couponsEnabled"] as? Bool ?? true)
    }
}

extension HostDealDTO {
    func firestoreData(ownerID: String) -> [String: Any] {
        let until = endDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now)!
        var d: [String: Any] = [
            "venueID": venueID,
            "type": firestoreTypeKey(type),
            "title": title,
            "details": details,
            "emoji": emoji,
            "status": status.rawValue,
            "ownerID": ownerID,
            "imageEmojis": [emoji],
            "startDate": Timestamp(date: startDate),
            "validUntil": Timestamp(date: until)
        ]
        if let newPrice { d["newPrice"] = newPrice }
        if let discountPercent { d["discountPercent"] = discountPercent }
        if let endDate { d["endDate"] = Timestamp(date: endDate) }
        d["imageURL"] = imageURL
        d["imageURLs"] = imageURLs
        return d
    }

    init?(firestore d: [String: Any], id: String) {
        guard let venueID = d["venueID"] as? String,
              let title = d["title"] as? String else { return nil }
        let typeKey = d["type"] as? String ?? "discount"
        let type = typeMap[typeKey] ?? DealType(rawValue: typeKey) ?? .discount
        let status = statusMap[d["status"] as? String ?? "active"] ?? .active
        self.init(
            id: id, venueID: venueID, typeRaw: type.rawValue, title: title,
            details: d["details"] as? String ?? "",
            emoji: d["emoji"] as? String ?? "🔥",
            newPrice: (d["newPrice"] as? NSNumber)?.intValue,
            discountPercent: (d["discountPercent"] as? NSNumber)?.intValue,
            startDate: (d["startDate"] as? Timestamp)?.dateValue() ?? .now,
            endDate: (d["endDate"] as? Timestamp)?.dateValue(),
            statusRaw: status.rawValue,
            imageURL: d["imageURL"] as? String ?? "",
            imageURLs: d["imageURLs"] as? [String] ?? [])
    }
}

// MARK: - Host Repository (Firestore)

final class FirebaseHostRepository: HostRepository {
    private let db = Firestore.firestore()

    func saveVenue(_ dto: HostVenueDTO, ownerID: String) async throws {
        try await db.collection("venues").document(dto.id)
            .setData(dto.firestoreData(ownerID: ownerID), merge: true)
    }

    func deleteVenue(id: String) async throws {
        try await db.collection("venues").document(id).delete()
        // Удаляем связанные предложения этого заведения.
        let snap = try await db.collection("deals").whereField("venueID", isEqualTo: id).getDocuments()
        for doc in snap.documents { try? await doc.reference.delete() }
    }

    func saveDeal(_ dto: HostDealDTO, ownerID: String) async throws {
        try await db.collection("deals").document(dto.id)
            .setData(dto.firestoreData(ownerID: ownerID), merge: true)
    }

    func deleteDeal(id: String) async throws {
        try await db.collection("deals").document(id).delete()
    }

    func fetchOwnedVenues(ownerID: String) async throws -> [HostVenueDTO] {
        let snap = try await db.collection("venues")
            .whereField("ownerID", isEqualTo: ownerID).getDocuments()
        return snap.documents.compactMap { HostVenueDTO(firestore: $0.data(), id: $0.documentID) }
    }

    func fetchOwnedDeals(ownerID: String) async throws -> [HostDealDTO] {
        let snap = try await db.collection("deals")
            .whereField("ownerID", isEqualTo: ownerID).getDocuments()
        return snap.documents.compactMap { HostDealDTO(firestore: $0.data(), id: $0.documentID) }
    }

    func saveProfile(_ profile: HostProfile, ownerID: String) async throws {
        try await db.collection("hosts").document(ownerID).setData(profile.firestoreData, merge: true)
    }

    func fetchProfile(ownerID: String) async throws -> HostProfile? {
        let snap = try await db.collection("hosts").document(ownerID).getDocument()
        guard let d = snap.data() else { return nil }
        return HostProfile(firestore: d)
    }

    func queuePushCampaign(headline: String, body: String, city: String,
                           category: String?, venueID: String, dealID: String?, ownerID: String) async throws {
        var data: [String: Any] = [
            "headline": headline,
            "body": body,
            "city": city,
            "venueID": venueID,
            "ownerID": ownerID,
            "status": "pending",   // ждёт одобрения админом в панели
            "delivered": false,
            "createdAt": Timestamp(date: .now)
        ]
        if let category { data["category"] = category }
        if let dealID, !dealID.isEmpty { data["dealID"] = dealID }
        // Админ одобряет в панели (status → approved) → Cloud Function рассылает.
        _ = try await db.collection("pushCampaigns").addDocument(data: data)
    }
}

// MARK: - Купоны (бэкенд-трекинг + сканер)

final class FirebaseCouponService: CouponService {
    private let db = Firestore.firestore()
    private let scanURL = "https://us-central1-san-25d32.cloudfunctions.net/scanCoupon"

    func saveCoupon(_ c: Coupon, userID: String) async throws {
        let data: [String: Any] = [
            "code": c.code, "userID": userID,
            "venueID": c.venueID, "venueName": c.venueName,
            "title": c.title, "kind": c.kind, "dealID": c.dealID,
            "used": c.used, "createdAt": Timestamp(date: c.createdAt)
        ]
        try await db.collection("coupons").document(c.id).setData(data, merge: true)
    }

    func fetchCoupons(userID: String) async throws -> [Coupon] {
        let snap = try await db.collection("coupons")
            .whereField("userID", isEqualTo: userID).getDocuments()
        return snap.documents.map { doc in
            let d = doc.data()
            return Coupon(
                id: doc.documentID,
                title: d["title"] as? String ?? "Купон",
                code: d["code"] as? String ?? "",
                createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? .now,
                used: d["used"] as? Bool ?? false,
                venueID: d["venueID"] as? String ?? "",
                venueName: d["venueName"] as? String ?? "",
                kind: d["kind"] as? String ?? "bonus",
                dealID: d["dealID"] as? String ?? ""
            )
        }
    }

    func fetchLoyaltyCards(userID: String) async throws -> [LoyaltyCard] {
        let snap = try await db.collection("loyaltyCards")
            .whereField("userID", isEqualTo: userID).getDocuments()
        return snap.documents.map { doc in
            let d = doc.data()
            return LoyaltyCard(
                venueID: d["venueID"] as? String ?? "",
                venueName: d["venueName"] as? String ?? "",
                stamps: (d["stamps"] as? NSNumber)?.intValue ?? 0,
                completedRounds: (d["completedRounds"] as? NSNumber)?.intValue ?? 0,
                goal: (d["goal"] as? NSNumber)?.intValue ?? 6,
                reward: d["reward"] as? String ?? "Награда за лояльность"
            )
        }
    }

    func scanCoupon(code: String, venueID: String, idToken: String) async throws -> ScanOutcome {
        guard let url = URL(string: scanURL) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["code": code, "venueID": venueID])
        let (data, _) = try await URLSession.shared.data(for: req)
        let j = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let ok = j["ok"] as? Bool ?? false
        return ScanOutcome(
            ok: ok,
            title: j["title"] as? String ?? "",
            loyalty: j["loyalty"] as? Bool ?? false,
            stamps: (j["stamps"] as? NSNumber)?.intValue ?? 0,
            goal: (j["goal"] as? NSNumber)?.intValue ?? 6,
            rewardIssued: j["rewardIssued"] as? Bool ?? false,
            rewardTitle: j["rewardTitle"] as? String ?? "",
            errorCode: ok ? nil : (j["error"] as? String ?? "scan_failed")
        )
    }
}

private extension UIApplication {
    var firstKeyWindow: UIWindow? {
        connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow }
    }
}

// MARK: - Категории (гибкий список из бэкенда)
//
// Коллекция Firestore `categories` (управляется из админки): slug, name, icon,
// emoji, order, enabled. Приложение читает её и использует в фильтрах и формах.
// Если бэкенд недоступен / пуст — остаёмся на встроенных VenueCategory.allCases.

@MainActor
final class CategoryStore: ObservableObject {
    static let shared = CategoryStore()

    /// Категории для UI (встроенные — как фолбэк до загрузки).
    @Published private(set) var categories: [VenueCategory] = VenueCategory.allCases

    private init() {}

    func load() async {
        guard AppConfig.useFirebase else { return }
        do {
            let snap = try await Firestore.firestore().collection("categories").getDocuments()
            struct Row { let name: String; let slug: String; let icon: String; let order: Int; let enabled: Bool }
            let rows: [Row] = snap.documents.compactMap { doc in
                let d = doc.data()
                let name = (d["name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
                guard !name.isEmpty else { return nil }
                let slug = (d["slug"] as? String) ?? doc.documentID
                let icon = (d["icon"] as? String) ?? "tag.fill"
                let order = (d["order"] as? NSNumber)?.intValue ?? 0
                let enabled = (d["enabled"] as? Bool) ?? true
                return Row(name: name, slug: slug, icon: icon, order: order, enabled: enabled)
            }
            guard !rows.isEmpty else { return }   // пусто → остаёмся на встроенных
            let visible = rows.filter { $0.enabled }.sorted { $0.order < $1.order }
            var icons: [String: String] = [:]
            var slugs: [String: String] = [:]
            for r in rows { icons[r.name] = r.icon; slugs[r.slug] = r.name }
            VenueCategory.iconRegistry = icons
            VenueCategory.slugRegistry = slugs
            categories = visible.compactMap { VenueCategory(rawValue: $0.name) }
        } catch {
            // Нет доступа/ошибка — тихо остаёмся на встроенных категориях.
        }
    }
}
