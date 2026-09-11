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

    /// Оценка привлекательности заведения (рейтинг, отзывы, сохранения, верификация,
    /// спецпредложение, «открыто сейчас», число активных акций).
    public static func venueScore(_ venue: Venue, catalog: FeedCatalog,
                                  weights: RankingWeights, now: Date) -> Double {
        let aggregate = catalog.ratings[venue.id]
            ?? VenueRating(rating: venue.rating, count: venue.reviewCount)
        let activeDeals = catalog.deals.filter { $0.venueID == venue.id && $0.isActive(at: now) }.count
        return Ranking.venueScore(rating: aggregate.rating, reviewCount: aggregate.count,
                                  savedByCount: venue.savedByCount, isVerified: venue.isVerified,
                                  hasTodaySpecial: venue.hasTodaySpecial, isOpenNow: venue.isOpen(at: now),
                                  activeDealCount: activeDeals, w: weights)
    }

    /// Органическая оценка предложения: релевантность заведения + свежесть + новизна +
    /// глубина скидки + мягкий буст «скоро закончится». Платный буст — отдельно.
    public static func dealScore(_ deal: Deal, catalog: FeedCatalog,
                                 weights: RankingWeights, now: Date) -> Double {
        let venue = catalog.venues.first { $0.id == deal.venueID }
        let vs = venue.map { venueScore($0, catalog: catalog, weights: weights, now: now) } ?? 0
        let daysSinceStart = deal.startDate.map { now.timeIntervalSince($0) / 86_400 }
        let hoursUntilExpiry = deal.validUntil.timeIntervalSince(now) / 3600
        // Час — по городу акции, а не по телефону: «время завтрака» должно
        // совпадать с местным утром, даже если гость приехал из другого пояса.
        let hour = City.calendar(forSlug: deal.citySlug).component(.hour, from: now)
        let timeRelevance = venue?.category.timeRelevance(hour: hour) ?? 0.5
        return Ranking.dealScore(venueScore: vs, isFresh: deal.isFresh(at: now),
                                 daysSinceStart: daysSinceStart,
                                 discountPercent: deal.effectiveDiscountPercent,
                                 hoursUntilExpiry: hoursUntilExpiry,
                                 timeRelevance: timeRelevance, w: weights)
    }

    /// Заведения города по релевантности.
    public static func rankedVenues(_ catalog: FeedCatalog, citySlug: String,
                                    category: VenueCategory? = nil,
                                    weights: RankingWeights, now: Date) -> [Venue] {
        visibleVenues(catalog, citySlug: citySlug, category: category)
            .sorted { venueScore($0, catalog: catalog, weights: weights, now: now)
                    > venueScore($1, catalog: catalog, weights: weights, now: now) }
    }

    /// Активные акции заведений города, отсортированные по `dealScore`.
    public static func rankedDeals(_ catalog: FeedCatalog, citySlug: String,
                                   category: VenueCategory? = nil,
                                   weights: RankingWeights, now: Date) -> [Deal] {
        let ids = Set(visibleVenues(catalog, citySlug: citySlug, category: category).map(\.id))
        return catalog.deals
            .filter { $0.isActive(at: now) && ids.contains($0.venueID) }
            .sorted { dealScore($0, catalog: catalog, weights: weights, now: now)
                    > dealScore($1, catalog: catalog, weights: weights, now: now) }
    }

    /// Заведения с активным платным бустом — рекламные карточки в ленте.
    /// Порядок вращается раз в 30 минут, чтобы верхнее место доставалось не всегда одному.
    public static func boostedVenues(_ catalog: FeedCatalog, citySlug: String,
                                     category: VenueCategory? = nil, now: Date) -> [Venue] {
        let rotation = Int(now.timeIntervalSince1970 / 1800)
        return visibleVenues(catalog, citySlug: citySlug, category: category)
            .filter { $0.isBoosted(at: now) }
            .sorted { ($0.id.hashValue &+ rotation) < ($1.id.hashValue &+ rotation) }
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
