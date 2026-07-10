package kg.ayant.app.data

import kg.ayant.app.data.model.City
import kg.ayant.app.data.model.Deal
import kg.ayant.app.data.model.DealType
import kg.ayant.app.data.model.HostReply
import kg.ayant.app.data.model.Review
import kg.ayant.app.data.model.Venue
import kg.ayant.app.data.model.VenueCategory
import java.util.Calendar
import java.util.Date

/** Mock data for MVP — Bishkek venues, deals, reviews. Mirrors MockData.swift. */
object MockData {

    private fun days(n: Int): Date =
        Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, n) }.time

    private fun hoursAgo(n: Int): Date =
        Calendar.getInstance().apply { add(Calendar.HOUR_OF_DAY, -n) }.time

    private fun daysAgo(n: Int): Date =
        Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -n) }.time

    /** Opaque ARGB (0xFFRRGGBB) as a Long — the UI maps it to a Compose Color. */
    private fun hex(rgb: Int): Long = 0xFF000000L or (rgb.toLong() and 0xFFFFFFL)

    val cities = listOf(
        City("bishkek", "Бишкек", "Кыргызстан", 42.8746, 74.5698),
        City("osh", "Ош", "Кыргызстан", 40.5283, 72.7985),
        City("tashkent", "Ташкент", "Узбекистан", 41.2995, 69.2401),
        City("samarkand", "Самарканд", "Узбекистан", 39.6270, 66.9750),
        City("almaty", "Алматы", "Казахстан", 43.2389, 76.8897),
        City("astana", "Астана", "Казахстан", 51.1605, 71.4704),
    )

    fun city(slug: String): City = cities.firstOrNull { it.id == slug } ?: cities[0]

    val venues: List<Venue> = listOf(
        Venue(
            id = "navat", name = "Navat", category = VenueCategory.TEAHOUSE, district = "Центр",
            address = "пр. Чуй, 125", phone = "+996 312 909 000", emoji = "🫖",
            gradient = listOf(hex(0xE65C00), hex(0xF9D423)),
            rating = 4.6, reviewCount = 213, isVerified = true, savedByCount = 214,
            latitude = 42.8760, longitude = 74.6010,
            todaySpecialText = "Плов по-фергански весь день — 290 сом",
            openHour = 10, closeHour = 23, photoEmojis = listOf("🫖", "🍚", "🥗", "🍢"),
        ),
        Venue(
            id = "faiza", name = "Faiza", category = VenueCategory.CAFE, district = "Восток-5",
            address = "ул. Медерова, 217", phone = "+996 555 919 555", emoji = "🥟",
            gradient = listOf(hex(0x11998E), hex(0x38EF7D)),
            rating = 4.4, reviewCount = 168, isVerified = true, savedByCount = 156,
            latitude = 42.8825, longitude = 74.6300, openHour = 9, closeHour = 22,
            photoEmojis = listOf("🥟", "🍜", "🥗"),
        ),
        Venue(
            id = "sierra", name = "Sierra Coffee", category = VenueCategory.COFFEE, district = "Центр",
            address = "ул. Манаса, 57", phone = "+996 312 311 000", emoji = "☕️",
            gradient = listOf(hex(0x5D4157), hex(0xA8CABA)),
            rating = 4.7, reviewCount = 402, isVerified = true, savedByCount = 389,
            latitude = 42.8745, longitude = 74.5890,
            todaySpecialText = "Раф на кокосовом −20% до 12:00",
            openHour = 8, closeHour = 23, photoEmojis = listOf("☕️", "🍰", "🥐", "🧋"),
            loyaltyEnabled = true, loyaltyGoal = 6, loyaltyReward = "Бесплатный кофе",
        ),
        Venue(
            id = "bublik", name = "Bublik", category = VenueCategory.BAKERY, district = "Центр",
            address = "ул. Токтогула, 93", phone = "+996 700 905 905", emoji = "🥐",
            gradient = listOf(hex(0xF7971E), hex(0xFFD200)),
            rating = 4.3, reviewCount = 97, isVerified = false, savedByCount = 88,
            latitude = 42.8710, longitude = 74.6020, openHour = 8, closeHour = 21,
            photoEmojis = listOf("🥐", "🍞", "🥨"),
            loyaltyEnabled = true, loyaltyGoal = 5, loyaltyReward = "Кофе + круассан",
        ),
        Venue(
            id = "furusato", name = "Furusato", category = VenueCategory.RESTAURANT, district = "Центр",
            address = "пр. Эркиндик, 35", phone = "+996 555 750 750", emoji = "🍣",
            gradient = listOf(hex(0xC31432), hex(0x240B36)),
            rating = 4.5, reviewCount = 254, isVerified = true, savedByCount = 271,
            latitude = 42.8690, longitude = 74.6105, openHour = 11, closeHour = 23,
            pdfMenuURL = "https://example.com/furusato-menu.pdf",
            photoEmojis = listOf("🍣", "🍱", "🍤", "🥢"),
        ),
        Venue(
            id = "chickenstar", name = "Chicken Star", category = VenueCategory.FASTFOOD, district = "Центр",
            address = "пр. Эркиндик, 36", phone = "+996 708 700 007", emoji = "🍗",
            gradient = listOf(hex(0xF12711), hex(0xF5AF19)),
            rating = 4.2, reviewCount = 143, isVerified = false, savedByCount = 120,
            latitude = 42.8688, longitude = 74.6110,
            todaySpecialText = "Комбо «Стар» сегодня 350 сом",
            openHour = 10, closeHour = 24, photoEmojis = listOf("🍗", "🍟", "🥤"),
        ),
        Venue(
            id = "cyclone", name = "Cyclone", category = VenueCategory.RESTAURANT, district = "Центр",
            address = "пр. Чуй, 136", phone = "+996 312 621 190", emoji = "🍝",
            gradient = listOf(hex(0x355C7D), hex(0xC06C84)),
            rating = 4.1, reviewCount = 76, isVerified = false, savedByCount = 64,
            latitude = 42.8762, longitude = 74.5990, openHour = 12, closeHour = 23,
            photoEmojis = listOf("🍝", "🍷", "🥩"),
        ),
        Venue(
            id = "adriano", name = "Adriano Coffee", category = VenueCategory.COFFEE, district = "Моссовет",
            address = "ул. Киевская, 77", phone = "+996 702 909 290", emoji = "🍵",
            gradient = listOf(hex(0x3E5151), hex(0xDECBA4)),
            rating = 4.8, reviewCount = 311, isVerified = true, savedByCount = 342,
            latitude = 42.8770, longitude = 74.5805, openHour = 8, closeHour = 22,
            photoEmojis = listOf("🍵", "☕️", "🍰"),
        ),
        Venue(
            id = "arzu", name = "Арзу", category = VenueCategory.CAFE, district = "Юг-2",
            address = "ул. Горького, 1Б", phone = "+996 312 540 540", emoji = "🍲",
            gradient = listOf(hex(0x870000), hex(0x190A05)),
            rating = 4.0, reviewCount = 52, isVerified = false, savedByCount = 41,
            latitude = 42.8530, longitude = 74.6000, openHour = 9, closeHour = 22,
            photoEmojis = listOf("🍲", "🥘"),
        ),
        Venue(
            id = "shaurma1", name = "Шаурма №1", category = VenueCategory.FASTFOOD, district = "Аламедин-1",
            address = "ул. Лущихина, 10", phone = "+996 550 100 100", emoji = "🌯",
            gradient = listOf(hex(0x636FA4), hex(0xE8CBC0)),
            rating = 4.5, reviewCount = 188, isVerified = false, savedByCount = 173,
            latitude = 42.8900, longitude = 74.6200,
            todaySpecialText = "Вторая шаурма −50% после 18:00",
            openHour = 10, closeHour = 24, photoEmojis = listOf("🌯", "🧀", "🥙"),
        ),
    )

    val deals: List<Deal> = listOf(
        Deal("d1", "navat", DealType.DISCOUNT, "−30% на манты по будням",
            "С 11:00 до 15:00 на все виды мантов. Идеально на обед.", "🥟",
            280, 195, 30, days(12), startDate = hoursAgo(20), imageEmojis = listOf("🥟")),
        Deal("d2", "navat", DealType.PROMO, "Чайник чая в подарок",
            "При заказе от 1500 сом — чайник ташкентского чая бесплатно.", "🫖",
            null, null, null, days(6), startDate = daysAgo(5), imageEmojis = listOf("🫖")),
        Deal("d3", "faiza", DealType.DISCOUNT, "−20% на лагман",
            "Фирменный лагман по будням после 16:00.", "🍜",
            320, 255, 20, days(9), startDate = daysAgo(3), imageEmojis = listOf("🍜")),
        Deal("d4", "sierra", DealType.PROMO, "1+1 на капучино",
            "Каждое утро до 10:00 — второй капучино бесплатно.", "☕️",
            null, null, null, days(20), startDate = hoursAgo(30), imageEmojis = listOf("☕️")),
        Deal("d5", "sierra", DealType.NOVELTY, "Bumble с апельсином",
            "Новый летний кофе: эспрессо + свежевыжатый апельсин.", "🍊",
            null, 290, null, days(25), startDate = daysAgo(8), imageEmojis = listOf("🍊")),
        Deal("d6", "bublik", DealType.DISCOUNT, "−50% на выпечку вечером",
            "Ежедневно после 20:00 — вся витрина за полцены.", "🥐",
            null, null, 50, days(30), startDate = daysAgo(12), imageEmojis = listOf("🥐")),
        Deal("d7", "furusato", DealType.NOVELTY, "Сет «Бишкек» — 24 ролла",
            "Новый большой сет: филадельфия, калифорния, запечённые.", "🍣",
            null, 1890, null, days(18), startDate = hoursAgo(10), imageEmojis = listOf("🍣")),
        Deal("d8", "furusato", DealType.DISCOUNT, "−15% на всё меню по вторникам",
            "Весь день, на зал и самовывоз.", "🍱",
            null, null, 15, days(14), startDate = daysAgo(6), imageEmojis = listOf("🍱")),
        Deal("d9", "chickenstar", DealType.PROMO, "Комбо «Стар» за 390 сом",
            "Крылышки + картофель + напиток. Обычная цена 520 сом.", "🍗",
            520, 390, null, days(8), startDate = daysAgo(2), imageEmojis = listOf("🍗")),
        Deal("d10", "cyclone", DealType.DISCOUNT, "−25% на пасту в обед",
            "Будни с 12:00 до 15:00, вся паста ручной работы.", "🍝",
            480, 360, 25, days(10), startDate = daysAgo(4), imageEmojis = listOf("🍝")),
        Deal("d11", "adriano", DealType.NOVELTY, "Матча-латте",
            "Японская матча церемониального сорта, на любом молоке.", "🍵",
            null, 270, null, days(22), startDate = daysAgo(9), imageEmojis = listOf("🍵")),
        Deal("d12", "adriano", DealType.PROMO, "Десерт в подарок к кофе",
            "С 14:00 до 16:00 — чизкейк или брауни к любому кофе.", "🍰",
            null, null, null, days(5), startDate = daysAgo(1), imageEmojis = listOf("🍰")),
        Deal("d13", "arzu", DealType.DISCOUNT, "−20% на бешбармак",
            "Для компаний от 4 человек, по предзаказу.", "🍲",
            null, null, 20, days(11), startDate = daysAgo(7), imageEmojis = listOf("🍲")),
        Deal("d14", "shaurma1", DealType.PROMO, "Вторая шаурма −50%",
            "На классическую и сырную, ежедневно.", "🌯",
            null, null, null, days(7), startDate = hoursAgo(40), imageEmojis = listOf("🌯")),
        Deal("d15", "shaurma1", DealType.NOVELTY, "Шаурма с сыром",
            "Двойной сыр, фирменный соус. Уже в меню.", "🧀",
            null, 250, null, days(16), startDate = daysAgo(5), imageEmojis = listOf("🧀")),
    )

    val reviews: List<Review> = listOf(
        Review("r1", "navat", "u_aida", "Айда", 5,
            "Лучшая чайхана в центре. Манты огонь, чай наливают бесконечно.",
            listOf("🥟", "🫖"), daysAgo(3), daysAgo(3),
            HostReply("Спасибо, Айда! Ждём снова 🫖", daysAgo(2), daysAgo(2))),
        Review("r2", "navat", "u_marat", "Марат", 4,
            "Вкусно, но в обед бывает шумно. Сервис быстрый.",
            emptyList(), daysAgo(10), daysAgo(10)),
        Review("r3", "sierra", "u_lena", "Лена", 5,
            "Мой любимый кофе в городе. Раф на кокосовом — топ.",
            listOf("☕️"), daysAgo(1), daysAgo(1)),
        Review("r4", "sierra", "u_ts", "Тимур", 4,
            "Отличное место для работы с ноутом, розеток хватает.",
            emptyList(), daysAgo(14), daysAgo(14)),
        Review("r5", "furusato", "u_dasha", "Даша", 5,
            "Свежие роллы, большие порции. Сет «Бишкек» берём компанией.",
            listOf("🍣", "🍱"), daysAgo(5), daysAgo(5),
            HostReply("Рады, что понравилось! 🍣", daysAgo(4), daysAgo(4))),
        Review("r6", "adriano", "u_nur", "Нуржан", 5,
            "Матча просто космос. Десерты тоже на уровне.",
            listOf("🍵"), daysAgo(2), daysAgo(2)),
        Review("r7", "shaurma1", "u_beka", "Бека", 4,
            "Сытно и недорого. Вторая по акции — приятно.",
            emptyList(), daysAgo(6), daysAgo(6)),
        Review("r8", "faiza", "u_gulnara", "Гульнара", 4,
            "Лагман как у бабушки. Уютно и по-домашнему.",
            listOf("🍜"), daysAgo(8), daysAgo(8)),
        Review("r9", "chickenstar", "u_sam", "Сам", 3,
            "Курица вкусная, но ждали комбо долго.",
            emptyList(), daysAgo(11), daysAgo(11)),
        Review("r10", "bublik", "u_olya", "Оля", 5,
            "Круассаны утром свежайшие. Вечерняя скидка — бонус.",
            listOf("🥐"), daysAgo(4), daysAgo(4)),
    )
}
