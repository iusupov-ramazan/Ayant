import Foundation
import AyantDomain

/// Витринный каталог для скриншотов App Store.
///
/// Включается аргументами запуска: `-screenshots ru|en` (язык контента) и
/// `-screenshots-earn` (через 2,5 с «прилетает» начисление — для экрана
/// «Начислено»). В этом режиме приложение живёт на выдуманных заведениях без
/// Firebase: реальные бренды на витрину не попадают, а данные не зависят от
/// того, что сейчас лежит в каталоге. В обычной сборке режим никогда не
/// активен — аргументов нет.
///
/// Фото — Unsplash (лицензия Unsplash: свободное коммерческое использование без
/// атрибуции); заменить на свои — в одном месте, здесь.
///
/// Запуск: `xcrun simctl launch <device> kg.san.app -screenshots ru`.
enum ScreenshotFixtures {
    struct Mode {
        let lang: String          // "ru" | "en"
        let earn: Bool
        var isRu: Bool { lang == "ru" }
    }

    static let mode: Mode? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screenshots") else { return nil }
        let lang = args.indices.contains(i + 1) ? args[i + 1] : "ru"
        return Mode(lang: lang == "en" ? "en" : "ru", earn: args.contains("-screenshots-earn"))
    }()

    /// Папка с заранее скачанными фото (`-screenshots-photos <dir>`, файлы
    /// `<id>.jpg`): симулятор иногда рвёт HTTP/3-соединения с CDN, и кадры
    /// выходили без картинок. Без аргумента — те же фото с Unsplash по сети.
    private static let photoDir: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screenshots-photos"), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }()

    static func photo(_ id: String) -> String {
        if let dir = photoDir { return "file://\(dir)/\(id).jpg" }
        return "https://images.unsplash.com/photo-\(id)?w=1200&q=80"
    }
}

extension ScreenshotFixtures.Mode {
    private func t(_ ru: String, _ en: String) -> String { isRu ? ru : en }

    var user: SANUser {
        SANUser(id: "demo-guest", name: t("Айгерим", "Aigerim"), email: "aigerim@example.com", provider: .email)
    }

    private var center: String { t("Центр", "Center") }
    private var east: String { t("Восток-5", "East-5") }
    private var south: String { t("Джал", "Jal") }

    var venues: [Venue] {
        [
            Venue(id: "dastan", name: "Dastan", category: .teahouse, district: center,
                  address: t("пр. Чуй, 125", "125 Chuy Ave"), phone: "+996 312 000 001", emoji: "🫖",
                  gradient: [0xE65C00, 0xF9D423], imageURL: ScreenshotFixtures.photo("1512058564366-18510be2db19"), rating: 4.7, reviewCount: 213, isVerified: true, savedByCount: 214,
                  latitude: 42.8760, longitude: 74.6010,
                  todaySpecialText: t("Плов по-фергански весь день — 290 сом", "Fergana plov all day — 290 som"),
                  openHour: 8, closeHour: 23, photoEmojis: ["🫖", "🍚", "🥗"],
                  pointsEnabled: true, pointsMode: "cashback", cashbackPercent: 5,
                  pointsRewards: [
                    PointsReward(id: "r1", type: "item", title: t("Чайник чая в подарок", "Free pot of tea"), cost: 200),
                    PointsReward(id: "r2", type: "item", title: t("Плов в подарок", "Free plov"), cost: 350),
                    PointsReward(id: "r3", type: "money", title: t("Скидка баллами", "Discount with points"), cost: 100, ratio: 1),
                  ]),
            Venue(id: "fifth", name: "Fifth Morning", category: .coffee, district: center,
                  address: t("ул. Манаса, 57", "57 Manas St"), phone: "+996 312 000 002", emoji: "☕️",
                  gradient: [0x5D4157, 0xA8CABA], imageURL: ScreenshotFixtures.photo("1509042239860-f550ce710b93"), rating: 4.8, reviewCount: 402, isVerified: true, savedByCount: 389,
                  latitude: 42.8745, longitude: 74.5890,
                  todaySpecialText: t("Раф на кокосовом −20% до 12:00", "Coconut raf −20% until noon"),
                  openHour: 7, closeHour: 23, photoEmojis: ["☕️", "🍰", "🥐"],
                  pointsEnabled: true, pointsMode: "flat", pointsFlat: 25,
                  pointsRewards: [PointsReward(id: "r4", type: "item", title: t("Капучино", "Cappuccino"), cost: 150)]),
            Venue(id: "lepyoshka", name: "Lepyoshka", category: .bakery, district: center,
                  address: t("ул. Токтогула, 93", "93 Toktogul St"), phone: "+996 312 000 003", emoji: "🥐",
                  gradient: [0xF7971E, 0xFFD200], imageURL: ScreenshotFixtures.photo("1483695028939-5bb13f8648b0"), rating: 4.5, reviewCount: 168, isVerified: true, savedByCount: 156,
                  latitude: 42.8790, longitude: 74.6100, openHour: 8, closeHour: 21, photoEmojis: ["🥐", "🍞", "🥯"],
                  loyaltyEnabled: true, loyaltyGoal: 6, loyaltyReward: t("Круассан в подарок", "Free croissant")),
            Venue(id: "baobar", name: "Bao Bar", category: .cafe, district: east,
                  address: t("ул. Медерова, 217", "217 Mederov St"), phone: "+996 312 000 004", emoji: "🥟",
                  gradient: [0x11998E, 0x38EF7D], imageURL: ScreenshotFixtures.photo("1511690656952-34342bb7c2f2"), rating: 4.4, reviewCount: 96, isVerified: true, savedByCount: 88,
                  latitude: 42.8825, longitude: 74.6300, openHour: 10, closeHour: 22, photoEmojis: ["🥟", "🍜"]),
            Venue(id: "lastochka", name: "Lastochka", category: .restaurant, district: center,
                  address: t("ул. Исанова, 40", "40 Isanov St"), phone: "+996 312 000 005", emoji: "🍽️",
                  gradient: [0x2B5876, 0x4E4376], imageURL: ScreenshotFixtures.photo("1517248135467-4c7edcad34c4"), rating: 4.6, reviewCount: 240, isVerified: true, savedByCount: 201,
                  latitude: 42.8700, longitude: 74.5950, openHour: 11, closeHour: 23, photoEmojis: ["🍽️", "🥩", "🍷"]),
            Venue(id: "greenbowl", name: "Green Bowl", category: .cafe, district: south,
                  address: t("ул. Ахунбаева, 12", "12 Akhunbaev St"), phone: "+996 312 000 006", emoji: "🥗",
                  gradient: [0x56AB2F, 0xA8E063], imageURL: ScreenshotFixtures.photo("1546069901-ba9599a7e63c"), rating: 4.3, reviewCount: 74, isVerified: false, savedByCount: 60,
                  latitude: 42.8400, longitude: 74.5800, openHour: 9, closeHour: 21, photoEmojis: ["🥗", "🥑"]),
            Venue(id: "tandyr", name: "Tandyr 41", category: .restaurant, district: east,
                  address: t("ул. Жибек Жолу, 41", "41 Jibek Jolu Ave"), phone: "+996 312 000 007", emoji: "🍖",
                  gradient: [0x8E2DE2, 0x4A00E0], imageURL: ScreenshotFixtures.photo("1529042410759-befb1204b468"), rating: 4.5, reviewCount: 130, isVerified: true, savedByCount: 110,
                  latitude: 42.8850, longitude: 74.6150, openHour: 10, closeHour: 23, photoEmojis: ["🍖", "🥙"]),
            Venue(id: "kita", name: "Kita Sushi", category: .restaurant, district: center,
                  address: t("бул. Эркиндик, 22", "22 Erkindik Blvd"), phone: "+996 312 000 008", emoji: "🍣",
                  gradient: [0xC33764, 0x1D2671], imageURL: ScreenshotFixtures.photo("1553621042-f6e147245754"), rating: 4.6, reviewCount: 188, isVerified: true, savedByCount: 175,
                  latitude: 42.8720, longitude: 74.6070, openHour: 11, closeHour: 23, photoEmojis: ["🍣", "🍱"]),
        ]
    }

    var deals: [Deal] {
        let now = Date()
        func days(_ n: Int) -> Date { now.addingTimeInterval(TimeInterval(n) * 86_400) }
        return [
            Deal(id: "d1", venueID: "dastan", type: .discount,
                 title: t("−30% на манты по будням", "−30% on manty on weekdays"),
                 details: t("С 11:00 до 15:00 на все виды мантов. Идеально на обед.",
                            "11:00–15:00, all kinds of manty. Perfect for lunch."),
                 emoji: "🥟", oldPrice: 280, newPrice: 195, discountPercent: 30, validUntil: days(12),
                 startDate: days(-1), imageEmojis: ["🥟"], imageURL: ScreenshotFixtures.photo("1504674900247-0877df9cc836"),
                 terms: [t("Только по будням", "Weekdays only"), t("Не суммируется с баллами", "Not combined with points")]),
            Deal(id: "d2", venueID: "fifth", type: .promo,
                 title: t("Второй капучино в подарок", "Second cappuccino free"),
                 details: t("Каждое утро до 11:00 — второй капучино бесплатно.", "Every morning until 11:00 the second cappuccino is on us."),
                 emoji: "☕️", validUntil: days(6), startDate: days(-2), imageEmojis: ["☕️"], imageURL: ScreenshotFixtures.photo("1541167760496-1628856ab772")),
            Deal(id: "d3", venueID: "lepyoshka", type: .discount,
                 title: t("−20% на выпечку после 19:00", "−20% on pastry after 7 pm"),
                 details: t("Вся выпечка дня со скидкой в последние два часа.", "Every pastry of the day at a discount in the last two hours."),
                 emoji: "🥐", oldPrice: 120, newPrice: 96, discountPercent: 20, validUntil: days(20),
                 startDate: days(-3), imageEmojis: ["🥐"], imageURL: ScreenshotFixtures.photo("1509440159596-0249088772ff")),
            Deal(id: "d4", venueID: "baobar", type: .novelty,
                 title: t("Новые бао с уткой", "New duck bao"),
                 details: t("Утка хойсин, огурец и зелёный лук в паровой булочке.", "Hoisin duck, cucumber and spring onion in a steamed bun."),
                 emoji: "🥟", newPrice: 350, validUntil: days(30), startDate: days(-4), imageEmojis: ["🥟"], imageURL: ScreenshotFixtures.photo("1476224203421-9ac39bcb3327")),
            Deal(id: "d5", venueID: "lastochka", type: .promo,
                 title: t("Десерт в подарок к ужину", "Free dessert with dinner"),
                 details: t("При заказе от 1500 сом после 18:00.", "With any order over 1500 som after 6 pm."),
                 emoji: "🍰", validUntil: days(9), startDate: days(-5), imageEmojis: ["🍰"], imageURL: ScreenshotFixtures.photo("1490474418585-ba9bad8fd0ea")),
            Deal(id: "d6", venueID: "greenbowl", type: .discount,
                 title: t("−15% на боулы на вынос", "−15% on takeaway bowls"),
                 details: t("Все боулы с собой дешевле каждый день.", "Every bowl to go, cheaper every day."),
                 emoji: "🥗", oldPrice: 420, newPrice: 357, discountPercent: 15, validUntil: days(15),
                 startDate: days(-6), imageEmojis: ["🥗"], imageURL: ScreenshotFixtures.photo("1546069901-ba9599a7e63c")),
            Deal(id: "d7", venueID: "kita", type: .discount,
                 title: t("Сет «Токио» −25%", "“Tokyo” set −25%"),
                 details: t("32 кусочка: лосось, угорь, тунец. Только в зале.", "32 pieces: salmon, eel, tuna. Dine-in only."),
                 emoji: "🍣", oldPrice: 1600, newPrice: 1200, discountPercent: 25, validUntil: days(8),
                 startDate: days(-1), imageEmojis: ["🍣"], imageURL: ScreenshotFixtures.photo("1553621042-f6e147245754")),
        ]
    }

    var reviews: [Review] {
        let now = Date()
        func r(_ id: String, _ venue: String, _ author: String, _ rating: Int, _ text: String, daysAgo: Int) -> Review {
            Review(id: id, venueID: venue, authorID: "u_\(id)", authorName: author, rating: rating, text: text,
                   photoEmojis: [], createdAt: now.addingTimeInterval(-Double(daysAgo) * 86_400),
                   updatedAt: now.addingTimeInterval(-Double(daysAgo) * 86_400), verifiedVisit: true)
        }
        return [
            r("rv1", "dastan", t("Данияр", "Daniyar"), 5, t("Лучший плов в центре, порции огромные.", "Best plov downtown, huge portions."), daysAgo: 2),
            r("rv2", "dastan", t("Мээрим", "Meerim"), 4, t("Вкусно, но в обед очередь.", "Tasty, but there's a queue at lunch."), daysAgo: 6),
            r("rv3", "fifth", t("Айбек", "Aibek"), 5, t("Раф на кокосовом — моя утренняя привычка.", "The coconut raf is my morning habit."), daysAgo: 1),
            r("rv4", "lepyoshka", t("Нургуль", "Nurgul"), 5, t("Круассаны как в Париже, честно.", "Croissants like in Paris, honestly."), daysAgo: 3),
            r("rv5", "kita", t("Эрлан", "Erlan"), 4, t("Сет «Токио» стоит своих денег.", "The Tokyo set is worth every som."), daysAgo: 4),
        ]
    }

    var pointsCards: [VenuePointsCard] {
        [
            VenuePointsCard(venueID: "dastan", venueName: "Dastan", balance: 320, lifetimeEarned: 540, lifetimeRedeemed: 220),
            VenuePointsCard(venueID: "fifth", venueName: "Fifth Morning", balance: 125, lifetimeEarned: 125),
        ]
    }

    var loyaltyCards: [LoyaltyCard] {
        [LoyaltyCard(venueID: "lepyoshka", venueName: "Lepyoshka", stamps: 4, completedRounds: 1, goal: 6,
                     reward: t("Круассан в подарок", "Free croissant"))]
    }

    var coupons: [Coupon] {
        [Coupon(id: "cp_demo1", title: t("−20% на выпечку после 19:00", "−20% on pastry after 7 pm"),
                code: "AYANT-K7F2QD", createdAt: Date().addingTimeInterval(-3_600), used: false,
                venueID: "lepyoshka", venueName: "Lepyoshka", kind: "deal", dealID: "d3")]
    }
}
