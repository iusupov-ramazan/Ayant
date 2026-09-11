import Foundation
import FirebaseFirestore
import AyantDomain

// Маппинг Firestore ⇄ доменные модели.
//
// Весь разбор и сборка документов живёт здесь; `FirebaseServices.swift` только
// делает запросы и вызывает эти мапперы. Имена полей берутся из `FS` — своих
// строковых литералов в этом файле нет, поэтому переименование поля правится
// в одном месте (см. FirestoreSchema.swift). Схема документов — FIREBASE_SETUP.md.

// MARK: - Общие поля заведения

/// Разбор полей заведения, которые кодируются ОДИНАКОВО у `Venue` и `HostVenueDTO`.
///
/// Поля с расходящейся семантикой сюда НЕ входят и разбираются в каждом init
/// отдельно (см. комментарии там):
///  • `category` — у Venue проще (`FSKeys.category ?? rawValue`), у DTO добавлен
///    поиск по `slugRegistry` и фолбэк `.cafe`;
///  • `weekHours` — DTO подставляет `Venue.defaultWeek()` при пустом массиве;
///  • `imageURL` / `pdfMenuURL` / `todaySpecial` — у Venue опциональны, у DTO — `""`;
///  • только у Venue: `gradient`, `rating`, `reviewCount`, `savedByCount`,
///    `city`, `photoEmojis`, `ownerID` — публичные поля, которых нет у
///    редактируемого хостом DTO.
public struct VenueFirestoreCommonFields {
    let district: String
    let address: String
    let phone: String
    let emoji: String
    let latitude: Double
    let longitude: Double
    let openHour: Int
    let closeHour: Int
    let isPaused: Bool
    let isVerified: Bool
    let status: String
    let items: [VenueItem]
    let whatsapp: String
    let instagram: String
    let telegram: String
    let branches: [Branch]
    let boostedUntil: Date?
    let loyaltyEnabled: Bool
    let loyaltyGoal: Int
    let loyaltyReward: String
    let couponsEnabled: Bool
    let pointsEnabled: Bool
    let pointsMode: String
    let pointsFlat: Int
    let pointsBands: [PointsBand]
    let cashbackPercent: Double
    let pointsRewards: [PointsReward]
    let pointsExpiryMonths: Int
    let redeemMode: String
    let earnCooldownMinutes: Int

    public init(_ d: [String: Any]) {
        district = d.string(FS.VenueDoc.district) ?? ""
        address = d.string(FS.VenueDoc.address) ?? ""
        phone = d.string(FS.VenueDoc.phone) ?? ""
        emoji = d.string(FS.VenueDoc.emoji) ?? "🍽"
        latitude = d.double(FS.VenueDoc.latitude) ?? City.bishkek.latitude
        longitude = d.double(FS.VenueDoc.longitude) ?? City.bishkek.longitude
        openHour = d.int(FS.VenueDoc.openHour) ?? 9
        closeHour = d.int(FS.VenueDoc.closeHour) ?? 22
        isPaused = d.bool(FS.VenueDoc.isPaused) ?? false
        isVerified = d.bool(FS.VenueDoc.isVerified) ?? false
        status = d.string(FS.VenueDoc.status) ?? ModerationStatus.approved.rawValue
        items = VenueItem.parse(d[FS.VenueDoc.items])
        whatsapp = d.string(FS.VenueDoc.whatsapp) ?? ""
        instagram = d.string(FS.VenueDoc.instagram) ?? ""
        telegram = d.string(FS.VenueDoc.telegram) ?? ""
        branches = Branch.parseArray(d[FS.VenueDoc.branches])
        boostedUntil = d.date(FS.VenueDoc.boostedUntil)
        loyaltyEnabled = d.bool(FS.VenueDoc.loyaltyEnabled) ?? false
        loyaltyGoal = d.int(FS.VenueDoc.loyaltyGoal) ?? 6
        loyaltyReward = d.string(FS.VenueDoc.loyaltyReward) ?? "Награда за лояльность"
        couponsEnabled = d.bool(FS.VenueDoc.couponsEnabled) ?? true
        pointsEnabled = d.bool(FS.VenueDoc.pointsEnabled) ?? false
        pointsMode = d.string(FS.VenueDoc.pointsMode) ?? "flat"
        pointsFlat = d.int(FS.VenueDoc.pointsFlat) ?? 0
        pointsBands = PointsBand.parseArray(d[FS.VenueDoc.pointsBands])
        cashbackPercent = d.double(FS.VenueDoc.cashbackPercent) ?? 0
        pointsRewards = PointsReward.parse(d[FS.VenueDoc.pointsRewards])
        pointsExpiryMonths = d.int(FS.VenueDoc.pointsExpiryMonths) ?? 6
        redeemMode = d.string(FS.VenueDoc.redeemMode) ?? "staffScan"
        earnCooldownMinutes = d.int(FS.VenueDoc.earnCooldownMinutes) ?? 60
    }
}

// MARK: - Venue

extension Venue {
    public init?(firestore d: [String: Any], id: String) {
        guard let name = d.string(FS.VenueDoc.name),
              let categoryKey = d.string(FS.VenueDoc.category),
              let category = FSKeys.category[categoryKey] ?? VenueCategory(rawValue: categoryKey)
        else { return nil }

        let f = VenueFirestoreCommonFields(d)
        self.init(
            id: id,
            name: name,
            category: category,
            district: f.district,
            address: f.address,
            phone: f.phone,
            emoji: f.emoji,
            gradient: [
                UInt32(hexString: d.string(FS.VenueDoc.gradientFrom)) ?? Palette.accent,
                UInt32(hexString: d.string(FS.VenueDoc.gradientTo)) ?? Palette.orange
            ],
            imageURL: d.string(FS.VenueDoc.imageURL),
            rating: d.double(FS.VenueDoc.rating) ?? 0,
            reviewCount: d.int(FS.VenueDoc.reviewCount) ?? 0,
            isVerified: f.isVerified,
            savedByCount: d.int(FS.VenueDoc.savedByCount) ?? 0,
            citySlug: d.string(FS.VenueDoc.city) ?? City.bishkek.id,
            latitude: f.latitude,
            longitude: f.longitude,
            todaySpecialText: d.string(FS.VenueDoc.todaySpecial),
            openHour: f.openHour,
            closeHour: f.closeHour,
            weekHours: DayHours.parseArray(d[FS.VenueDoc.weekHours]),
            pdfMenuURL: d.string(FS.VenueDoc.pdfMenuURL),
            photoEmojis: d[FS.VenueDoc.photoEmojis] as? [String] ?? [],
            ownerID: d.string(FS.VenueDoc.ownerID) ?? "",
            items: f.items,
            statusRaw: f.status,
            isPaused: f.isPaused,
            whatsapp: f.whatsapp,
            instagram: f.instagram,
            telegram: f.telegram,
            branches: f.branches,
            boostedUntil: f.boostedUntil,
            loyaltyEnabled: f.loyaltyEnabled,
            loyaltyGoal: f.loyaltyGoal,
            loyaltyReward: f.loyaltyReward,
            couponsEnabled: f.couponsEnabled,
            pointsEnabled: f.pointsEnabled,
            pointsMode: f.pointsMode,
            pointsFlat: f.pointsFlat,
            pointsBands: f.pointsBands,
            cashbackPercent: f.cashbackPercent,
            pointsRewards: f.pointsRewards,
            pointsExpiryMonths: f.pointsExpiryMonths,
            redeemMode: f.redeemMode,
            earnCooldownMinutes: f.earnCooldownMinutes
        )
    }
}

// MARK: - Вложенные объекты заведения

extension PointsBand {
    var firestoreMap: [String: Any] {
        [FS.PointsBandField.maxAmount: maxAmount, FS.PointsBandField.points: points]
    }
    static func parseArray(_ raw: Any?) -> [PointsBand] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { m in
            guard let points = m.int(FS.PointsBandField.points) else { return nil }
            return PointsBand(maxAmount: m.int(FS.PointsBandField.maxAmount) ?? 0, points: points)
        }
    }
}

extension PointsReward {
    var firestoreMap: [String: Any] {
        [
            FS.PointsRewardField.id: id, FS.PointsRewardField.type: type,
            FS.PointsRewardField.title: title, FS.PointsRewardField.cost: cost,
            FS.PointsRewardField.ratio: ratio, FS.PointsRewardField.active: active,
        ]
    }
    static func parse(_ raw: Any?) -> [PointsReward] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { m in
            guard let id = m.string(FS.PointsRewardField.id),
                  let title = m.string(FS.PointsRewardField.title) else { return nil }
            return PointsReward(id: id,
                                type: m.string(FS.PointsRewardField.type) ?? "item",
                                title: title,
                                cost: m.int(FS.PointsRewardField.cost) ?? 0,
                                ratio: m.double(FS.PointsRewardField.ratio) ?? 1,
                                active: m.bool(FS.PointsRewardField.active) ?? true)
        }
    }
}

extension Branch {
    var firestoreMap: [String: Any] {
        [
            FS.BranchField.id: id, FS.BranchField.address: address,
            FS.BranchField.latitude: latitude, FS.BranchField.longitude: longitude,
            FS.BranchField.phone: phone,
        ]
    }
    static func parseArray(_ raw: Any?) -> [Branch] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { m in
            guard let id = m.string(FS.BranchField.id),
                  let address = m.string(FS.BranchField.address) else { return nil }
            return Branch(id: id, address: address,
                          latitude: m.double(FS.BranchField.latitude) ?? 0,
                          longitude: m.double(FS.BranchField.longitude) ?? 0,
                          phone: m.string(FS.BranchField.phone) ?? "")
        }
    }
}

extension DayHours {
    var firestoreMap: [String: Any] {
        [FS.DayHoursField.closed: closed, FS.DayHoursField.open: open, FS.DayHoursField.close: close]
    }
    static func parseArray(_ raw: Any?) -> [DayHours] {
        guard let arr = raw as? [[String: Any]], arr.count == 7 else { return [] }
        return arr.map { m in
            DayHours(closed: m.bool(FS.DayHoursField.closed) ?? false,
                     open: m.int(FS.DayHoursField.open) ?? 540,
                     close: m.int(FS.DayHoursField.close) ?? 1320)
        }
    }
}

extension VenueItem {
    /// Парсит массив карт Firestore в [VenueItem].
    static func parse(_ raw: Any?) -> [VenueItem] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { m in
            guard let id = m.string(FS.ItemField.id),
                  let name = m.string(FS.ItemField.name) else { return nil }
            return VenueItem(id: id, name: name,
                             emoji: m.string(FS.ItemField.emoji) ?? "🍽",
                             kind: m.string(FS.ItemField.kind) ?? "food",
                             imageURL: m.string(FS.ItemField.imageURL) ?? "")
        }
    }
    var firestoreMap: [String: Any] {
        [
            FS.ItemField.id: id, FS.ItemField.name: name, FS.ItemField.emoji: emoji,
            FS.ItemField.kind: kind, FS.ItemField.imageURL: imageURL,
        ]
    }
}

// MARK: - Deal

extension Deal {
    public init?(firestore d: [String: Any], id: String) {
        guard let venueID = d.string(FS.DealDoc.venueID),
              let typeKey = d.string(FS.DealDoc.type),
              let type = FSKeys.dealType[typeKey] ?? DealType(rawValue: typeKey),
              let title = d.string(FS.DealDoc.title)
        else { return nil }

        self.init(
            id: id,
            venueID: venueID,
            type: type,
            title: title,
            details: d.string(FS.DealDoc.details) ?? "",
            emoji: d.string(FS.DealDoc.emoji) ?? "🔥",
            oldPrice: d.int(FS.DealDoc.oldPrice),
            newPrice: d.int(FS.DealDoc.newPrice),
            discountPercent: d.int(FS.DealDoc.discountPercent),
            validUntil: d.date(FS.DealDoc.validUntil) ?? .now,
            citySlug: d.string(FS.DealDoc.city) ?? City.bishkek.id,
            status: FSKeys.dealStatus[d.string(FS.DealDoc.status) ?? "active"] ?? .active,
            startDate: d.date(FS.DealDoc.startDate),
            imageEmojis: d[FS.DealDoc.imageEmojis] as? [String] ?? [],
            imageURL: d.string(FS.DealDoc.imageURL),
            imageURLs: d[FS.DealDoc.imageURLs] as? [String] ?? [],
            terms: d[FS.DealDoc.terms] as? [String] ?? []
        )
    }
}

// MARK: - Review

extension HostReply {
    /// Вложенная карта `reviews/{id}.hostReply`.
    var firestoreMap: [String: Any] {
        [
            FS.HostReplyField.text: text,
            FS.HostReplyField.createdAt: Timestamp(date: createdAt),
            FS.HostReplyField.updatedAt: Timestamp(date: updatedAt),
        ]
    }

    /// `fallbackDate` — дата отзыва: у старых ответов своей даты может не быть.
    public init?(firestore raw: Any?, fallbackDate: Date) {
        guard let r = raw as? [String: Any], let text = r.string(FS.HostReplyField.text) else { return nil }
        let created = r.date(FS.HostReplyField.createdAt) ?? fallbackDate
        self.init(text: text, createdAt: created, updatedAt: created)
    }
}

extension Review {
    /// Документ для коллекции reviews.
    var firestoreData: [String: Any] {
        var d: [String: Any] = [
            FS.ReviewDoc.venueID: venueID,
            FS.ReviewDoc.authorID: authorID,
            FS.ReviewDoc.authorName: authorName,
            FS.ReviewDoc.rating: rating,
            FS.ReviewDoc.text: text,
            FS.ReviewDoc.photoEmojis: photoEmojis,
            FS.ReviewDoc.createdAt: Timestamp(date: createdAt),
            FS.ReviewDoc.updatedAt: Timestamp(date: updatedAt),
            FS.ReviewDoc.city: citySlug,
        ]
        if let itemID { d[FS.ReviewDoc.itemID] = itemID }
        if let itemName { d[FS.ReviewDoc.itemName] = itemName }
        if !photos.isEmpty { d[FS.ReviewDoc.photos] = photos }
        if verifiedVisit { d[FS.ReviewDoc.verifiedVisit] = true }
        if let hostReply { d[FS.ReviewDoc.hostReply] = hostReply.firestoreMap }
        return d
    }

    public init?(firestore d: [String: Any], id: String) {
        guard let venueID = d.string(FS.ReviewDoc.venueID),
              let rating = d.int(FS.ReviewDoc.rating)
        else { return nil }

        let created = d.date(FS.ReviewDoc.createdAt) ?? .now
        self.init(
            id: id,
            venueID: venueID,
            authorID: d.string(FS.ReviewDoc.authorID) ?? "anon",
            authorName: d.string(FS.ReviewDoc.authorName) ?? "Гость",
            rating: rating,
            text: d.string(FS.ReviewDoc.text) ?? "",
            photoEmojis: d[FS.ReviewDoc.photoEmojis] as? [String] ?? [],
            createdAt: created,
            updatedAt: d.date(FS.ReviewDoc.updatedAt) ?? created,
            hostReply: HostReply(firestore: d[FS.ReviewDoc.hostReply], fallbackDate: created),
            itemID: d.string(FS.ReviewDoc.itemID),
            itemName: d.string(FS.ReviewDoc.itemName),
            photos: d[FS.ReviewDoc.photos] as? [String] ?? [],
            verifiedVisit: d.bool(FS.ReviewDoc.verifiedVisit) ?? false,
            citySlug: d.string(FS.ReviewDoc.city) ?? City.bishkek.id
        )
    }
}

// MARK: - RemoteCategory

extension RemoteCategory {
    /// nil — у категории нет имени, показывать нечего.
    public init?(firestore d: [String: Any], id: String) {
        let name = (d.string(FS.CategoryDoc.name))?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !name.isEmpty else { return nil }
        self.init(
            slug: d.string(FS.CategoryDoc.slug) ?? id,
            name: name,
            icon: d.string(FS.CategoryDoc.icon) ?? "tag.fill",
            emoji: d.string(FS.CategoryDoc.emoji) ?? "",
            order: d.int(FS.CategoryDoc.order) ?? 0,
            enabled: d.bool(FS.CategoryDoc.enabled) ?? true)
    }
}

// MARK: - Кошельки гостя

extension Coupon {
    func firestoreData(userID: String) -> [String: Any] {
        [
            FS.CouponDoc.code: code, FS.CouponDoc.userID: userID,
            FS.CouponDoc.venueID: venueID, FS.CouponDoc.venueName: venueName,
            FS.CouponDoc.title: title, FS.CouponDoc.kind: kind, FS.CouponDoc.dealID: dealID,
            FS.CouponDoc.used: used, FS.CouponDoc.createdAt: Timestamp(date: createdAt),
        ]
    }

    public init(firestore d: [String: Any], id: String) {
        self.init(
            id: id,
            title: d.string(FS.CouponDoc.title) ?? "Купон",
            code: d.string(FS.CouponDoc.code) ?? "",
            createdAt: d.date(FS.CouponDoc.createdAt) ?? .now,
            used: d.bool(FS.CouponDoc.used) ?? false,
            venueID: d.string(FS.CouponDoc.venueID) ?? "",
            venueName: d.string(FS.CouponDoc.venueName) ?? "",
            kind: d.string(FS.CouponDoc.kind) ?? "bonus",
            dealID: d.string(FS.CouponDoc.dealID) ?? ""
        )
    }
}

extension LoyaltyCard {
    public init(firestore d: [String: Any]) {
        self.init(
            venueID: d.string(FS.LoyaltyCardDoc.venueID) ?? "",
            venueName: d.string(FS.LoyaltyCardDoc.venueName) ?? "",
            stamps: d.int(FS.LoyaltyCardDoc.stamps) ?? 0,
            completedRounds: d.int(FS.LoyaltyCardDoc.completedRounds) ?? 0,
            goal: d.int(FS.LoyaltyCardDoc.goal) ?? 6,
            reward: d.string(FS.LoyaltyCardDoc.reward) ?? "Награда за лояльность"
        )
    }
}

extension PointsLedgerEntry {
    public init(firestore d: [String: Any], id: String) {
        self.init(
            id: id,
            kind: Kind(rawValue: d.string(FS.LedgerDoc.type) ?? "") ?? .unknown,
            points: d.int(FS.LedgerDoc.points) ?? 0,
            at: d.date(FS.LedgerDoc.at) ?? Date(timeIntervalSince1970: 0),
            billAmount: d.int(FS.LedgerDoc.billAmount),
            rewardID: d.string(FS.LedgerDoc.rewardId)
        )
    }
}

extension VenuePointsCard {
    public init(firestore d: [String: Any]) {
        self.init(
            venueID: d.string(FS.VenuePointsDoc.venueID) ?? "",
            venueName: d.string(FS.VenuePointsDoc.venueName) ?? "",
            balance: d.int(FS.VenuePointsDoc.balance) ?? 0,
            lifetimeEarned: d.int(FS.VenuePointsDoc.lifetimeEarned) ?? 0,
            lifetimeRedeemed: d.int(FS.VenuePointsDoc.lifetimeRedeemed) ?? 0
        )
    }
}

// MARK: - Host DTO ⇄ Firestore

extension HostProfile {
    var firestoreData: [String: Any] {
        [
            FS.HostDoc.businessName: businessName,
            FS.HostDoc.categoryRaw: categoryRaw,
            FS.HostDoc.phone: phone,
            FS.HostDoc.email: email,
            FS.HostDoc.verification: verification.rawValue,
            FS.HostDoc.legalForm: legalForm,
            FS.HostDoc.legalName: legalName,
            FS.HostDoc.inn: inn,
            FS.HostDoc.registrationAddress: registrationAddress,
            FS.HostDoc.website: website,
            FS.HostDoc.about: about,
        ]
    }
    public init?(firestore d: [String: Any]) {
        guard let name = d.string(FS.HostDoc.businessName) else { return nil }
        self.init(
            businessName: name,
            categoryRaw: d.string(FS.HostDoc.categoryRaw) ?? VenueCategory.cafe.rawValue,
            phone: d.string(FS.HostDoc.phone) ?? "",
            email: d.string(FS.HostDoc.email) ?? "",
            verification: VerificationStatus(rawValue: d.string(FS.HostDoc.verification) ?? "none") ?? .none,
            legalForm: d.string(FS.HostDoc.legalForm) ?? "",
            legalName: d.string(FS.HostDoc.legalName) ?? "",
            inn: d.string(FS.HostDoc.inn) ?? "",
            registrationAddress: d.string(FS.HostDoc.registrationAddress) ?? "",
            website: d.string(FS.HostDoc.website) ?? "",
            about: d.string(FS.HostDoc.about) ?? "")
    }
}

extension HostVenueDTO {
    /// Документ для коллекции venues (хост-заведение).
    ///
    /// Конфиг баллов САН (`points*`, `cashbackPercent`, `redeemMode`,
    /// `earnCooldownMinutes`) теперь ведёт сам хост с вкладки «Лояльность»
    /// (`HostIntent.savePointsConfig` → `HostForms.applyPoints`); админ-панель
    /// правит те же поля тем же именам. Раньше они здесь намеренно
    /// отсутствовали, чтобы сохранение из приложения не затирало конфиг из
    /// админки. Запись по-прежнему идёт с `merge: true`: поля, которых DTO не
    /// знает (рейтинг, счётчики сохранений, служебные), остаются нетронутыми.
    func firestoreData(ownerID: String) -> [String: Any] {
        [
            FS.VenueDoc.name: name,
            FS.VenueDoc.category: FSKeys.key(for: category),
            FS.VenueDoc.district: district,
            FS.VenueDoc.address: address,
            FS.VenueDoc.phone: phone,
            FS.VenueDoc.emoji: emoji,
            FS.VenueDoc.gradientFrom: "#FF4D29",
            FS.VenueDoc.gradientTo: "#FF8A1E",
            FS.VenueDoc.city: City.bishkek.id,
            FS.VenueDoc.latitude: latitude,
            FS.VenueDoc.longitude: longitude,
            FS.VenueDoc.openHour: openHour,
            FS.VenueDoc.closeHour: closeHour,
            FS.VenueDoc.isVerified: isVerified,
            FS.VenueDoc.isPaused: isPaused,
            FS.VenueDoc.ownerID: ownerID,
            FS.VenueDoc.photoEmojis: [emoji],
            FS.VenueDoc.status: status,
            FS.VenueDoc.items: items.map(\.firestoreMap),
            FS.VenueDoc.imageURL: imageURL,
            FS.VenueDoc.weekHours: weekHours.map(\.firestoreMap),
            FS.VenueDoc.pdfMenuURL: pdfMenuURL,
            FS.VenueDoc.whatsapp: whatsapp,
            FS.VenueDoc.instagram: instagram,
            FS.VenueDoc.telegram: telegram,
            FS.VenueDoc.branches: branches.map(\.firestoreMap),
            FS.VenueDoc.boostedUntil: boostedUntil.map { Timestamp(date: $0) } as Any,
            FS.VenueDoc.todaySpecial: todaySpecial ?? "",
            // Карта лояльности — её настраивает сам хост, в отличие от баллов САН.
            FS.VenueDoc.loyaltyEnabled: loyaltyEnabled,
            FS.VenueDoc.loyaltyGoal: loyaltyGoal,
            FS.VenueDoc.loyaltyReward: loyaltyReward,
            FS.VenueDoc.couponsEnabled: couponsEnabled,
            // Баллы САН — тот же контракт полей, что читает `scanCoupon` и админ-панель.
            FS.VenueDoc.pointsEnabled: pointsEnabled,
            FS.VenueDoc.pointsMode: pointsMode,
            FS.VenueDoc.pointsFlat: pointsFlat,
            FS.VenueDoc.pointsBands: pointsBands.map(\.firestoreMap),
            FS.VenueDoc.cashbackPercent: cashbackPercent,
            FS.VenueDoc.pointsRewards: pointsRewards.map(\.firestoreMap),
            FS.VenueDoc.pointsExpiryMonths: pointsExpiryMonths,
            FS.VenueDoc.redeemMode: redeemMode,
            FS.VenueDoc.earnCooldownMinutes: earnCooldownMinutes,
        ]
    }

    public init?(firestore d: [String: Any], id: String) {
        guard let name = d.string(FS.VenueDoc.name) else { return nil }
        let key = d.string(FS.VenueDoc.category) ?? "cafe"
        // Порядок: встроенные слаги → пользовательские (slug→имя из бэкенда) → как есть.
        let cat = FSKeys.category[key]
            ?? VenueCategory.slugRegistry[key].flatMap(VenueCategory.init(rawValue:))
            ?? VenueCategory(rawValue: key)
            ?? .cafe
        let special = d.string(FS.VenueDoc.todaySpecial)
        let f = VenueFirestoreCommonFields(d)
        self.init(
            id: id, name: name, categoryRaw: cat.rawValue,
            district: f.district,
            address: f.address,
            phone: f.phone,
            emoji: f.emoji,
            latitude: f.latitude,
            longitude: f.longitude,
            openHour: f.openHour,
            closeHour: f.closeHour,
            todaySpecial: (special?.isEmpty == false) ? special : nil,
            isPaused: f.isPaused,
            isVerified: f.isVerified,
            status: f.status,
            items: f.items,
            imageURL: d.string(FS.VenueDoc.imageURL) ?? "",
            weekHours: { let w = DayHours.parseArray(d[FS.VenueDoc.weekHours]); return w.isEmpty ? Venue.defaultWeek() : w }(),
            pdfMenuURL: d.string(FS.VenueDoc.pdfMenuURL) ?? "",
            whatsapp: f.whatsapp,
            instagram: f.instagram,
            telegram: f.telegram,
            branches: f.branches,
            boostedUntil: f.boostedUntil,
            loyaltyEnabled: f.loyaltyEnabled,
            loyaltyGoal: f.loyaltyGoal,
            loyaltyReward: f.loyaltyReward,
            couponsEnabled: f.couponsEnabled,
            // Конфиг баллов САН: читается для сканера и правится хостом — см. firestoreData.
            pointsEnabled: f.pointsEnabled,
            pointsMode: f.pointsMode,
            pointsFlat: f.pointsFlat,
            pointsBands: f.pointsBands,
            cashbackPercent: f.cashbackPercent,
            pointsRewards: f.pointsRewards,
            pointsExpiryMonths: f.pointsExpiryMonths,
            redeemMode: f.redeemMode,
            earnCooldownMinutes: f.earnCooldownMinutes)
    }
}

extension HostDealDTO {
    func firestoreData(ownerID: String) -> [String: Any] {
        let until = endDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now)!
        var d: [String: Any] = [
            FS.DealDoc.venueID: venueID,
            FS.DealDoc.type: FSKeys.key(for: type),
            FS.DealDoc.title: title,
            FS.DealDoc.details: details,
            FS.DealDoc.emoji: emoji,
            FS.DealDoc.status: status.rawValue,
            FS.DealDoc.ownerID: ownerID,
            FS.DealDoc.imageEmojis: [emoji],
            FS.DealDoc.startDate: Timestamp(date: startDate),
            FS.DealDoc.validUntil: Timestamp(date: until),
            // Партиционирование по городам: хост-заведения пока только в Бишкеке.
            FS.DealDoc.city: City.bishkek.id,
        ]
        if let newPrice { d[FS.DealDoc.newPrice] = newPrice }
        if let discountPercent { d[FS.DealDoc.discountPercent] = discountPercent }
        if let endDate { d[FS.DealDoc.endDate] = Timestamp(date: endDate) }
        d[FS.DealDoc.imageURL] = imageURL
        d[FS.DealDoc.imageURLs] = imageURLs
        d[FS.DealDoc.terms] = terms
        return d
    }

    public init?(firestore d: [String: Any], id: String) {
        guard let venueID = d.string(FS.DealDoc.venueID),
              let title = d.string(FS.DealDoc.title) else { return nil }
        let typeKey = d.string(FS.DealDoc.type) ?? "discount"
        let type = FSKeys.dealType[typeKey] ?? DealType(rawValue: typeKey) ?? .discount
        let status = FSKeys.dealStatus[d.string(FS.DealDoc.status) ?? "active"] ?? .active
        self.init(
            id: id, venueID: venueID, typeRaw: type.rawValue, title: title,
            details: d.string(FS.DealDoc.details) ?? "",
            emoji: d.string(FS.DealDoc.emoji) ?? "🔥",
            newPrice: d.int(FS.DealDoc.newPrice),
            discountPercent: d.int(FS.DealDoc.discountPercent),
            startDate: d.date(FS.DealDoc.startDate) ?? .now,
            endDate: d.date(FS.DealDoc.endDate),
            statusRaw: status.rawValue,
            imageURL: d.string(FS.DealDoc.imageURL) ?? "",
            imageURLs: d[FS.DealDoc.imageURLs] as? [String] ?? [],
            terms: d[FS.DealDoc.terms] as? [String] ?? [])
    }
}

// MARK: - Типизированное чтение полей документа

/// Firestore отдаёт `[String: Any]`, поэтому каждое чтение — это приведение типа.
/// Раньше оно писалось вручную (`(d["rating"] as? NSNumber)?.doubleValue`), из-за
/// чего числовые поля легко было прочитать не тем способом. Здесь приведение
/// сделано один раз, а вызов читается как объявление типа поля.
extension Dictionary where Key == String, Value == Any {
    public func string(_ key: String) -> String? { self[key] as? String }
    func bool(_ key: String) -> Bool? { self[key] as? Bool }
    /// Firestore хранит все числа как `NSNumber`, поэтому Int/Double берём через него.
    func int(_ key: String) -> Int? { (self[key] as? NSNumber)?.intValue }
    func double(_ key: String) -> Double? { (self[key] as? NSNumber)?.doubleValue }
    func date(_ key: String) -> Date? { (self[key] as? Timestamp)?.dateValue() }
}
