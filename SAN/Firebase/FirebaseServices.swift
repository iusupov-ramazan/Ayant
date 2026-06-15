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
    "discount": .discount, "promo": .promo, "novelty": .novelty
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
    .discount: "discount", .promo: "promo", .novelty: "novelty"
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
            pdfMenuURL: d["pdfMenuURL"] as? String,
            photoEmojis: d["photoEmojis"] as? [String] ?? [],
            ownerID: d["ownerID"] as? String ?? "",
            items: VenueItem.parse(d["items"]),
            statusRaw: d["status"] as? String ?? ModerationStatus.approved.rawValue,
            isPaused: d["isPaused"] as? Bool ?? false
        )
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
                             kind: m["kind"] as? String ?? "food")
        }
    }
    var firestoreMap: [String: Any] {
        ["id": id, "name": name, "emoji": emoji, "kind": kind]
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
            imageEmojis: d["imageEmojis"] as? [String] ?? []
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
            itemName: d["itemName"] as? String
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
            "todaySpecial": todaySpecial ?? ""
        ]
        if (todaySpecial ?? "").isEmpty { d["todaySpecial"] = "" }
        return d
    }

    init?(firestore d: [String: Any], id: String) {
        guard let name = d["name"] as? String else { return nil }
        let key = d["category"] as? String ?? "cafe"
        let cat = categoryMap[key] ?? VenueCategory(rawValue: key) ?? .cafe
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
            items: VenueItem.parse(d["items"]))
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
            statusRaw: status.rawValue)
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
                           category: String?, venueID: String, ownerID: String) async throws {
        var data: [String: Any] = [
            "headline": headline,
            "body": body,
            "city": city,
            "venueID": venueID,
            "ownerID": ownerID,
            "status": "queued",
            "createdAt": Timestamp(date: .now)
        ]
        if let category { data["category"] = category }
        // Создание документа триггерит Cloud Function, которая шлёт FCM на топик.
        _ = try await db.collection("pushCampaigns").addDocument(data: data)
    }
}

private extension UIApplication {
    var firstKeyWindow: UIWindow? {
        connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }.first { $0.isKeyWindow }
    }
}
