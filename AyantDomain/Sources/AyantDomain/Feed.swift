import Foundation

// Фича «Лента»: состояние, намерения и ЧИСТАЯ сборка выдачи.
// Имена полей совпадают с `Feed.kt` в `android/domain`.

// MARK: - Вход для сборки

/// Агрегат отзывов заведения. Живые отзывы перевешивают seed-значения из документа.
public struct VenueRating: Equatable, Sendable {
    public let rating: Double
    public let count: Int
    public init(rating: Double, count: Int) { self.rating = rating; self.count = count }
}

/// Снимок каталога, из которого строится лента. Ровно то, что нужно ранжированию,
/// и ничего больше — поэтому сборку можно прогнать в тесте без сторов и сети.
public struct FeedCatalog: Equatable {
    public var venues: [Venue]
    public var deals: [Deal]
    /// `venueID` → агрегат отзывов. Нет ключа — берём рейтинг из самого заведения.
    public var ratings: [String: VenueRating]

    public init(venues: [Venue] = [], deals: [Deal] = [], ratings: [String: VenueRating] = [:]) {
        self.venues = venues; self.deals = deals; self.ratings = ratings
    }

    public static let empty = FeedCatalog()
}

// MARK: - Сборка ленты

/// Вся математика выдачи одним чистым модулем.
///
/// Раньше это жило в `AppStore` и звало `Date()`/`Calendar.current` прямо внутри
/// скоринга — из-за чего лента не проверялась без стора и «сегодня» было
/// невоспроизводимо. Здесь время приходит параметром `now`, а данные — снимком
/// `FeedCatalog`, поэтому весь порядок выдачи детерминирован.
public enum FeedBuilder {

    /// Заведения города, видимые пользователю: одобренные модерацией и не на паузе.
    public static func visibleVenues(_ catalog: FeedCatalog,
                                     citySlug: String,
                                     category: VenueCategory? = nil) -> [Venue] {
        catalog.venues.filter {
            $0.citySlug == citySlug && $0.isApproved && !$0.isPaused
                && (category == nil || $0.category == category)
        }
    }

    /// Каталог, видимый пользователю ВНЕ ленты: поиск, карта, избранное, «рядом»
    /// на экране QR, переходы по ссылкам.
    ///
    /// Лента фильтровала модерацию сама (`visibleVenues`), а всё остальное читало
    /// сырой каталог — поэтому отклонённое модератором заведение исчезало с
    /// главной, но продолжало находиться поиском. Правило одно на оба места и
    /// живёт здесь, а не в сторе: платформы обязаны прятать одно и то же.
    public static func userVisible(venues: [Venue]) -> [Venue] {
        venues.filter { $0.isApproved && !$0.isPaused }
    }

    /// Акции скрытых заведений скрываются вместе с ними. Акция без заведения в
    /// каталоге остаётся: это пробел в данных, а не решение модератора.
    public static func userVisible(deals: [Deal], venues: [Venue]) -> [Deal] {
        let hidden = Set(venues.filter { !($0.isApproved && !$0.isPaused) }.map(\.id))
        return deals.filter { !hidden.contains($0.venueID) }
    }

    // MARK: Контекст скоринга (считается один раз на сборку)

    /// Всё, что скорингу нужно «по заведению», посчитанное ОДИН раз.
    ///
    /// Раньше `venueScore` на каждый вызов фильтровал все акции каталога, а
    /// `dealScore` искал заведение линейным поиском и пересчитывал его скор —
    /// и всё это внутри компаратора `sorted`, то есть O(n log n) раз. На ленте
    /// из сотни акций это десятки тысяч проходов по каталогу на каждый кадр.
    /// Порядок выдачи от этого не меняется (закреплено `FeedPerformanceTests`).
    struct ScoreContext {
        let catalog: FeedCatalog
        let weights: RankingWeights
        let now: Date
        /// Первое заведение с таким id — как прежний `first { $0.id == … }`.
        let venuesByID: [String: Venue]
        let activeDealCount: [String: Int]
        private var venueScores: [String: Double] = [:]
        private var calendars: [String: Calendar] = [:]

        init(catalog: FeedCatalog, weights: RankingWeights, now: Date) {
            self.catalog = catalog; self.weights = weights; self.now = now
            venuesByID = Dictionary(catalog.venues.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var counts: [String: Int] = [:]
            for d in catalog.deals where d.isActive(at: now) { counts[d.venueID, default: 0] += 1 }
            activeDealCount = counts
        }

        mutating func venueScore(_ venue: Venue) -> Double {
            if let cached = venueScores[venue.id] { return cached }
            let aggregate = catalog.ratings[venue.id]
                ?? VenueRating(rating: venue.rating, count: venue.reviewCount)
            let score = Ranking.venueScore(rating: aggregate.rating, reviewCount: aggregate.count,
                                           savedByCount: venue.savedByCount, isVerified: venue.isVerified,
                                           hasTodaySpecial: venue.hasTodaySpecial,
                                           isOpenNow: venue.isOpen(at: now),
                                           activeDealCount: activeDealCount[venue.id] ?? 0, w: weights)
            venueScores[venue.id] = score
            return score
        }

        mutating func calendar(forSlug slug: String) -> Calendar {
            if let c = calendars[slug] { return c }
            let c = City.calendar(forSlug: slug)
            calendars[slug] = c
            return c
        }

        mutating func dealScore(_ deal: Deal) -> Double {
            let venue = venuesByID[deal.venueID]
            let vs = venue.map { venueScore($0) } ?? 0
            let daysSinceStart = deal.startDate.map { now.timeIntervalSince($0) / 86_400 }
            let hoursUntilExpiry = deal.validUntil.timeIntervalSince(now) / 3600
            // Час — по городу акции, а не по телефону: «время завтрака» должно
            // совпадать с местным утром, даже если гость приехал из другого пояса.
            let hour = calendar(forSlug: deal.citySlug).component(.hour, from: now)
            let timeRelevance = venue?.category.timeRelevance(hour: hour) ?? 0.5
            return Ranking.dealScore(venueScore: vs, isFresh: deal.isFresh(at: now),
                                     daysSinceStart: daysSinceStart,
                                     discountPercent: deal.effectiveDiscountPercent,
                                     hoursUntilExpiry: hoursUntilExpiry,
                                     timeRelevance: timeRelevance, w: weights)
        }
    }

    /// Сортировка по заранее посчитанному скору (по убыванию). При равных
    /// скорах сохраняется исходный порядок — выдача детерминирована.
    static func sortedByScore<T>(_ items: [T], score: (T) -> Double) -> [T] {
        var scored: [(index: Int, score: Double, item: T)] = []
        scored.reserveCapacity(items.count)
        for (i, item) in items.enumerated() { scored.append((index: i, score: score(item), item: item)) }
        scored.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            return a.index < b.index
        }
        return scored.map { $0.item }
    }

    /// Оценка привлекательности заведения (рейтинг, отзывы, сохранения, верификация,
    /// спецпредложение, «открыто сейчас», число активных акций).
    public static func venueScore(_ venue: Venue, catalog: FeedCatalog,
                                  weights: RankingWeights, now: Date) -> Double {
        var ctx = ScoreContext(catalog: catalog, weights: weights, now: now)
        return ctx.venueScore(venue)
    }

    /// Органическая оценка предложения: релевантность заведения + свежесть + новизна +
    /// глубина скидки + мягкий буст «скоро закончится». Платный буст — отдельно.
    public static func dealScore(_ deal: Deal, catalog: FeedCatalog,
                                 weights: RankingWeights, now: Date) -> Double {
        var ctx = ScoreContext(catalog: catalog, weights: weights, now: now)
        return ctx.dealScore(deal)
    }

    /// Заведения города по релевантности.
    public static func rankedVenues(_ catalog: FeedCatalog, citySlug: String,
                                    category: VenueCategory? = nil,
                                    weights: RankingWeights, now: Date) -> [Venue] {
        var ctx = ScoreContext(catalog: catalog, weights: weights, now: now)
        return sortedByScore(visibleVenues(catalog, citySlug: citySlug, category: category)) {
            ctx.venueScore($0)
        }
    }

    /// Активные акции заведений города, отсортированные по `dealScore`.
    public static func rankedDeals(_ catalog: FeedCatalog, citySlug: String,
                                   category: VenueCategory? = nil,
                                   weights: RankingWeights, now: Date) -> [Deal] {
        let ids = Set(visibleVenues(catalog, citySlug: citySlug, category: category).map(\.id))
        var ctx = ScoreContext(catalog: catalog, weights: weights, now: now)
        return sortedByScore(catalog.deals.filter { $0.isActive(at: now) && ids.contains($0.venueID) }) {
            ctx.dealScore($0)
        }
    }

    /// Заведения с активным платным бустом — рекламные карточки в ленте.
    /// Порядок вращается раз в 30 минут, чтобы верхнее место доставалось не всегда одному.
    ///
    /// Ключ — СТАБИЛЬНЫЙ хэш `id|окно` (`StableHash.orderKey`). Раньше был `id.hashValue &+ окно`:
    /// `hashValue` в Swift случаен на каждый запуск (порядок прыгал между
    /// запусками), а прибавка одной константы ко всем ключам порядок не меняет
    /// вовсе — то есть «вращения раз в 30 минут» не было.
    public static func boostedVenues(_ catalog: FeedCatalog, citySlug: String,
                                     category: VenueCategory? = nil, now: Date) -> [Venue] {
        let rotation = Int(floor(now.timeIntervalSince1970 / 1800))
        let boosted = visibleVenues(catalog, citySlug: citySlug, category: category)
            .filter { $0.isBoosted(at: now) }
        let keyed: [(key: UInt64, venue: Venue)] = boosted.map { venue in
            (key: StableHash.orderKey(venue.id + "|" + String(rotation)), venue: venue)
        }
        return keyed.sorted { a, b in
            if a.key != b.key { return a.key < b.key }
            return a.venue.id < b.venue.id
        }.map { $0.venue }
    }

    /// Готовая лента: акции + рекламные карточки, вставленные через интервал.
    public static func items(_ catalog: FeedCatalog, citySlug: String,
                             category: VenueCategory? = nil,
                             weights: RankingWeights, now: Date) -> [FeedItem] {
        Ranking.feed(deals: rankedDeals(catalog, citySlug: citySlug, category: category,
                                        weights: weights, now: now),
                     ads: boostedVenues(catalog, citySlug: citySlug, category: category, now: now))
    }
}

// MARK: - Стабильный хэш

/// Хэш, одинаковый на всех запусках и устройствах (в отличие от `hashValue`,
/// который Swift солит случайно на каждый запуск). Для порядка, который должен
/// быть воспроизводимым: ротация буста, раскладка мозаики.
public enum StableHash {
    /// FNV-1a, 64 бита, по UTF-8 байтам строки.
    public static func fnv1a(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01b3
        }
        return h
    }

    /// Ключ для ПОРЯДКА: FNV-1a + финализатор splitmix64. У голого FNV
    /// изменение последних байтов (номер окна ротации в хвосте строки)
    /// почти не трогает старшие биты — и сортировка по ним не вращалась.
    public static func orderKey(_ s: String) -> UInt64 {
        var z = fnv1a(s)
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}

// MARK: - Состояние

/// Всё состояние ленты одним значением.
///
/// Выдача — не хранимое поле, а функция от состояния (`items(now:)`): так она
/// не может разъехаться с каталогом, городом и фильтром.
public struct FeedState: Equatable {
    public var catalog: LoadState<FeedCatalog> = .idle
    public var citySlug: String = City.bishkek.id
    public var category: VenueCategory? = nil
    /// Опубликованные веса ранжирования; при их отсутствии — ручные дефолты.
    public var weights: RankingWeights = .default

    public init(catalog: LoadState<FeedCatalog> = .idle,
                citySlug: String = City.bishkek.id,
                category: VenueCategory? = nil,
                weights: RankingWeights = .default) {
        self.catalog = catalog; self.citySlug = citySlug
        self.category = category; self.weights = weights
    }

    private var loaded: FeedCatalog { catalog.value ?? .empty }

    public func items(now: Date) -> [FeedItem] {
        FeedBuilder.items(loaded, citySlug: citySlug, category: category, weights: weights, now: now)
    }

    public func deals(now: Date) -> [Deal] {
        FeedBuilder.rankedDeals(loaded, citySlug: citySlug, category: category, weights: weights, now: now)
    }

    public func venues(now: Date) -> [Venue] {
        FeedBuilder.rankedVenues(loaded, citySlug: citySlug, category: category, weights: weights, now: now)
    }

    /// Есть ли в городе вообще заведения — отличает «город пуст» от «нет акций в категории».
    public var hasVenuesInCity: Bool {
        !FeedBuilder.visibleVenues(loaded, citySlug: citySlug).isEmpty
    }
}

// MARK: - Намерения

public enum FeedIntent: Equatable {
    /// Каталог перезагружен владельцем (сейчас — `AppStore`/`AppViewModel`).
    case setCatalog(FeedCatalog)
    case setLoading
    case setFailure(AppError)
    case setWeights(RankingWeights)
    case selectCity(String)
    case selectCategory(VenueCategory?)
}
