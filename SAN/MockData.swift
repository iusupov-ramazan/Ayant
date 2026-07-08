import SwiftUI

/// Мок-данные для MVP: заведения Бишкека, их предложения и отзывы.
/// В проде заменяется на API/Firestore.
enum MockData {

    private static func days(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: .now) ?? .now
    }
    private static func hoursAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .hour, value: -n, to: .now) ?? .now
    }
    private static func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: .now) ?? .now
    }

    // MARK: - Поддерживаемые города

    static let cities: [City] = [
        City(id: "bishkek",   name: "Бишкек",   country: "Кыргызстан", latitude: 42.8746, longitude: 74.5698),
        City(id: "osh",       name: "Ош",       country: "Кыргызстан", latitude: 40.5283, longitude: 72.7985),
        City(id: "tashkent",  name: "Ташкент",  country: "Узбекистан", latitude: 41.2995, longitude: 69.2401),
        City(id: "samarkand", name: "Самарканд", country: "Узбекистан", latitude: 39.6270, longitude: 66.9750),
        City(id: "almaty",    name: "Алматы",   country: "Казахстан",  latitude: 43.2389, longitude: 76.8897),
        City(id: "astana",    name: "Астана",   country: "Казахстан",  latitude: 51.1605, longitude: 71.4704),
    ]

    static func city(slug: String) -> City {
        cities.first { $0.id == slug } ?? cities[0]
    }

    // MARK: - Заведения

    static let venues: [Venue] = [
        Venue(id: "navat", name: "Navat", category: .teahouse, district: "Центр",
              address: "пр. Чуй, 125", phone: "+996 312 909 000", emoji: "🫖",
              gradient: [Color(hex: 0xE65C00), Color(hex: 0xF9D423)], imageURL: nil,
              rating: 4.6, reviewCount: 213, isVerified: true, savedByCount: 214,
              latitude: 42.8760, longitude: 74.6010, todaySpecialText: "Плов по-фергански весь день — 290 сом",
              openHour: 10, closeHour: 23, photoEmojis: ["🫖", "🍚", "🥗", "🍢"]),
        Venue(id: "faiza", name: "Faiza", category: .cafe, district: "Восток-5",
              address: "ул. Медерова, 217", phone: "+996 555 919 555", emoji: "🥟",
              gradient: [Color(hex: 0x11998E), Color(hex: 0x38EF7D)], imageURL: nil,
              rating: 4.4, reviewCount: 168, isVerified: true, savedByCount: 156,
              latitude: 42.8825, longitude: 74.6300, openHour: 9, closeHour: 22,
              photoEmojis: ["🥟", "🍜", "🥗"]),
        Venue(id: "sierra", name: "Sierra Coffee", category: .coffee, district: "Центр",
              address: "ул. Манаса, 57", phone: "+996 312 311 000", emoji: "☕️",
              gradient: [Color(hex: 0x5D4157), Color(hex: 0xA8CABA)], imageURL: nil,
              rating: 4.7, reviewCount: 402, isVerified: true, savedByCount: 389,
              latitude: 42.8745, longitude: 74.5890, todaySpecialText: "Раф на кокосовом −20% до 12:00",
              openHour: 8, closeHour: 23, photoEmojis: ["☕️", "🍰", "🥐", "🧋"],
              loyaltyEnabled: true, loyaltyGoal: 6, loyaltyReward: "Бесплатный кофе"),
        Venue(id: "bublik", name: "Bublik", category: .bakery, district: "Центр",
              address: "ул. Токтогула, 93", phone: "+996 700 905 905", emoji: "🥐",
              gradient: [Color(hex: 0xF7971E), Color(hex: 0xFFD200)], imageURL: nil,
              rating: 4.3, reviewCount: 97, isVerified: false, savedByCount: 88,
              latitude: 42.8710, longitude: 74.6020, openHour: 8, closeHour: 21,
              photoEmojis: ["🥐", "🍞", "🥨"],
              loyaltyEnabled: true, loyaltyGoal: 5, loyaltyReward: "Кофе + круассан"),
        Venue(id: "furusato", name: "Furusato", category: .restaurant, district: "Центр",
              address: "пр. Эркиндик, 35", phone: "+996 555 750 750", emoji: "🍣",
              gradient: [Color(hex: 0xC31432), Color(hex: 0x240B36)], imageURL: nil,
              rating: 4.5, reviewCount: 254, isVerified: true, savedByCount: 271,
              latitude: 42.8690, longitude: 74.6105, openHour: 11, closeHour: 23,
              pdfMenuURL: "https://example.com/furusato-menu.pdf",
              photoEmojis: ["🍣", "🍱", "🍤", "🥢"]),
        Venue(id: "chickenstar", name: "Chicken Star", category: .fastfood, district: "Центр",
              address: "пр. Эркиндик, 36", phone: "+996 708 700 007", emoji: "🍗",
              gradient: [Color(hex: 0xF12711), Color(hex: 0xF5AF19)], imageURL: nil,
              rating: 4.2, reviewCount: 143, isVerified: false, savedByCount: 120,
              latitude: 42.8688, longitude: 74.6110, todaySpecialText: "Комбо «Стар» сегодня 350 сом",
              openHour: 10, closeHour: 24, photoEmojis: ["🍗", "🍟", "🥤"]),
        Venue(id: "cyclone", name: "Cyclone", category: .restaurant, district: "Центр",
              address: "пр. Чуй, 136", phone: "+996 312 621 190", emoji: "🍝",
              gradient: [Color(hex: 0x355C7D), Color(hex: 0xC06C84)], imageURL: nil,
              rating: 4.1, reviewCount: 76, isVerified: false, savedByCount: 64,
              latitude: 42.8762, longitude: 74.5990, openHour: 12, closeHour: 23,
              photoEmojis: ["🍝", "🍷", "🥩"]),
        Venue(id: "adriano", name: "Adriano Coffee", category: .coffee, district: "Моссовет",
              address: "ул. Киевская, 77", phone: "+996 702 909 290", emoji: "🍵",
              gradient: [Color(hex: 0x3E5151), Color(hex: 0xDECBA4)], imageURL: nil,
              rating: 4.8, reviewCount: 311, isVerified: true, savedByCount: 342,
              latitude: 42.8770, longitude: 74.5805, openHour: 8, closeHour: 22,
              photoEmojis: ["🍵", "☕️", "🍰"]),
        Venue(id: "arzu", name: "Арзу", category: .cafe, district: "Юг-2",
              address: "ул. Горького, 1Б", phone: "+996 312 540 540", emoji: "🍲",
              gradient: [Color(hex: 0x870000), Color(hex: 0x190A05)], imageURL: nil,
              rating: 4.0, reviewCount: 52, isVerified: false, savedByCount: 41,
              latitude: 42.8530, longitude: 74.6000, openHour: 9, closeHour: 22,
              photoEmojis: ["🍲", "🥘"]),
        Venue(id: "shaurma1", name: "Шаурма №1", category: .fastfood, district: "Аламедин-1",
              address: "ул. Лущихина, 10", phone: "+996 550 100 100", emoji: "🌯",
              gradient: [Color(hex: 0x636FA4), Color(hex: 0xE8CBC0)], imageURL: nil,
              rating: 4.5, reviewCount: 188, isVerified: false, savedByCount: 173,
              latitude: 42.8900, longitude: 74.6200, todaySpecialText: "Вторая шаурма −50% после 18:00",
              openHour: 10, closeHour: 24, photoEmojis: ["🌯", "🧀", "🥙"]),
    ]

    // MARK: - Предложения

    static let deals: [Deal] = [
        Deal(id: "d1", venueID: "navat", type: .discount,
             title: "−30% на манты по будням",
             details: "С 11:00 до 15:00 на все виды мантов. Идеально на обед.",
             emoji: "🥟", oldPrice: 280, newPrice: 195, discountPercent: 30, validUntil: days(12),
             status: .active, startDate: hoursAgo(20), imageEmojis: ["🥟"]),
        Deal(id: "d2", venueID: "navat", type: .promo,
             title: "Чайник чая в подарок",
             details: "При заказе от 1500 сом — чайник ташкентского чая бесплатно.",
             emoji: "🫖", oldPrice: nil, newPrice: nil, discountPercent: nil, validUntil: days(6),
             status: .active, startDate: daysAgo(5), imageEmojis: ["🫖"]),
        Deal(id: "d3", venueID: "faiza", type: .discount,
             title: "−20% на лагман",
             details: "Фирменный лагман по будням после 16:00.",
             emoji: "🍜", oldPrice: 320, newPrice: 255, discountPercent: 20, validUntil: days(9),
             status: .active, startDate: daysAgo(3), imageEmojis: ["🍜"]),
        Deal(id: "d4", venueID: "sierra", type: .promo,
             title: "1+1 на капучино",
             details: "Каждое утро до 10:00 — второй капучино бесплатно.",
             emoji: "☕️", oldPrice: nil, newPrice: nil, discountPercent: nil, validUntil: days(20),
             status: .active, startDate: hoursAgo(30), imageEmojis: ["☕️"]),
        Deal(id: "d5", venueID: "sierra", type: .novelty,
             title: "Bumble с апельсином",
             details: "Новый летний кофе: эспрессо + свежевыжатый апельсин.",
             emoji: "🍊", oldPrice: nil, newPrice: 290, discountPercent: nil, validUntil: days(25),
             status: .active, startDate: daysAgo(8), imageEmojis: ["🍊"]),
        Deal(id: "d6", venueID: "bublik", type: .discount,
             title: "−50% на выпечку вечером",
             details: "Ежедневно после 20:00 — вся витрина за полцены.",
             emoji: "🥐", oldPrice: nil, newPrice: nil, discountPercent: 50, validUntil: days(30),
             status: .active, startDate: daysAgo(12), imageEmojis: ["🥐"]),
        Deal(id: "d7", venueID: "furusato", type: .novelty,
             title: "Сет «Бишкек» — 24 ролла",
             details: "Новый большой сет: филадельфия, калифорния, запечённые.",
             emoji: "🍣", oldPrice: nil, newPrice: 1890, discountPercent: nil, validUntil: days(18),
             status: .active, startDate: hoursAgo(10), imageEmojis: ["🍣"]),
        Deal(id: "d8", venueID: "furusato", type: .discount,
             title: "−15% на всё меню по вторникам",
             details: "Весь день, на зал и самовывоз.",
             emoji: "🍱", oldPrice: nil, newPrice: nil, discountPercent: 15, validUntil: days(14),
             status: .active, startDate: daysAgo(6), imageEmojis: ["🍱"]),
        Deal(id: "d9", venueID: "chickenstar", type: .promo,
             title: "Комбо «Стар» за 390 сом",
             details: "Крылышки + картофель + напиток. Обычная цена 520 сом.",
             emoji: "🍗", oldPrice: 520, newPrice: 390, discountPercent: nil, validUntil: days(8),
             status: .active, startDate: daysAgo(2), imageEmojis: ["🍗"]),
        Deal(id: "d10", venueID: "cyclone", type: .discount,
             title: "−25% на пасту в обед",
             details: "Будни с 12:00 до 15:00, вся паста ручной работы.",
             emoji: "🍝", oldPrice: 480, newPrice: 360, discountPercent: 25, validUntil: days(10),
             status: .active, startDate: daysAgo(4), imageEmojis: ["🍝"]),
        Deal(id: "d11", venueID: "adriano", type: .novelty,
             title: "Матча-латте",
             details: "Японская матча церемониального сорта, на любом молоке.",
             emoji: "🍵", oldPrice: nil, newPrice: 270, discountPercent: nil, validUntil: days(22),
             status: .active, startDate: daysAgo(9), imageEmojis: ["🍵"]),
        Deal(id: "d12", venueID: "adriano", type: .promo,
             title: "Десерт в подарок к кофе",
             details: "С 14:00 до 16:00 — чизкейк или брауни к любому кофе.",
             emoji: "🍰", oldPrice: nil, newPrice: nil, discountPercent: nil, validUntil: days(5),
             status: .active, startDate: daysAgo(1), imageEmojis: ["🍰"]),
        Deal(id: "d13", venueID: "arzu", type: .discount,
             title: "−20% на бешбармак",
             details: "Для компаний от 4 человек, по предзаказу.",
             emoji: "🍲", oldPrice: nil, newPrice: nil, discountPercent: 20, validUntil: days(11),
             status: .active, startDate: daysAgo(7), imageEmojis: ["🍲"]),
        Deal(id: "d14", venueID: "shaurma1", type: .promo,
             title: "Вторая шаурма −50%",
             details: "На классическую и сырную, ежедневно.",
             emoji: "🌯", oldPrice: nil, newPrice: nil, discountPercent: nil, validUntil: days(7),
             status: .active, startDate: hoursAgo(40), imageEmojis: ["🌯"]),
        Deal(id: "d15", venueID: "shaurma1", type: .novelty,
             title: "Шаурма с сыром",
             details: "Двойной сыр, фирменный соус. Уже в меню.",
             emoji: "🧀", oldPrice: nil, newPrice: 250, discountPercent: nil, validUntil: days(16),
             status: .active, startDate: daysAgo(5), imageEmojis: ["🧀"]),
    ]

    // MARK: - Отзывы (демо-набор от разных пользователей)

    static let reviews: [Review] = [
        Review(id: "r1", venueID: "navat", authorID: "u_aida", authorName: "Айда",
               rating: 5, text: "Лучшая чайхана в центре. Манты огонь, чай наливают бесконечно.",
               photoEmojis: ["🥟", "🫖"], createdAt: daysAgo(3), updatedAt: daysAgo(3),
               hostReply: HostReply(text: "Спасибо, Айда! Ждём снова 🫖", createdAt: daysAgo(2), updatedAt: daysAgo(2))),
        Review(id: "r2", venueID: "navat", authorID: "u_marat", authorName: "Марат",
               rating: 4, text: "Вкусно, но в обед бывает шумно. Сервис быстрый.",
               photoEmojis: [], createdAt: daysAgo(10), updatedAt: daysAgo(10), hostReply: nil),
        Review(id: "r3", venueID: "sierra", authorID: "u_lena", authorName: "Лена",
               rating: 5, text: "Мой любимый кофе в городе. Раф на кокосовом — топ.",
               photoEmojis: ["☕️"], createdAt: daysAgo(1), updatedAt: daysAgo(1), hostReply: nil),
        Review(id: "r4", venueID: "sierra", authorID: "u_ts", authorName: "Тимур",
               rating: 4, text: "Отличное место для работы с ноутом, розеток хватает.",
               photoEmojis: [], createdAt: daysAgo(14), updatedAt: daysAgo(14), hostReply: nil),
        Review(id: "r5", venueID: "furusato", authorID: "u_dasha", authorName: "Даша",
               rating: 5, text: "Свежие роллы, большие порции. Сет «Бишкек» берём компанией.",
               photoEmojis: ["🍣", "🍱"], createdAt: daysAgo(5), updatedAt: daysAgo(5),
               hostReply: HostReply(text: "Рады, что понравилось! 🍣", createdAt: daysAgo(4), updatedAt: daysAgo(4))),
        Review(id: "r6", venueID: "adriano", authorID: "u_nur", authorName: "Нуржан",
               rating: 5, text: "Матча просто космос. Десерты тоже на уровне.",
               photoEmojis: ["🍵"], createdAt: daysAgo(2), updatedAt: daysAgo(2), hostReply: nil),
        Review(id: "r7", venueID: "shaurma1", authorID: "u_beka", authorName: "Бека",
               rating: 4, text: "Сытно и недорого. Вторая по акции — приятно.",
               photoEmojis: [], createdAt: daysAgo(6), updatedAt: daysAgo(6), hostReply: nil),
        Review(id: "r8", venueID: "faiza", authorID: "u_gulnara", authorName: "Гульнара",
               rating: 4, text: "Лагман как у бабушки. Уютно и по-домашнему.",
               photoEmojis: ["🍜"], createdAt: daysAgo(8), updatedAt: daysAgo(8), hostReply: nil),
        Review(id: "r9", venueID: "chickenstar", authorID: "u_sam", authorName: "Сам",
               rating: 3, text: "Курица вкусная, но ждали комбо долго.",
               photoEmojis: [], createdAt: daysAgo(11), updatedAt: daysAgo(11), hostReply: nil),
        Review(id: "r10", venueID: "bublik", authorID: "u_olya", authorName: "Оля",
               rating: 5, text: "Круассаны утром свежайшие. Вечерняя скидка — бонус.",
               photoEmojis: ["🥐"], createdAt: daysAgo(4), updatedAt: daysAgo(4), hostReply: nil),
    ]

    // MARK: - Выборки

    static func venue(for deal: Deal) -> Venue {
        venues.first { $0.id == deal.venueID } ?? venues[0]
    }

    static func deals(for venue: Venue) -> [Deal] {
        deals.filter { $0.venueID == venue.id && $0.isActive }
    }

    static var activeDeals: [Deal] {
        deals.filter(\.isActive).sorted { $0.validUntil < $1.validUntil }
    }

    static func deal(by id: String) -> Deal? {
        deals.first { $0.id == id }
    }
}
