import Foundation

/// Элемент ленты: либо акция, либо рекламная карточка заведения (буст).
public enum FeedItem: Identifiable {
    case deal(Deal)
    case adVenue(Venue)
    public var id: String {
        switch self {
        case .deal(let d): return "d_\(d.id)"
        case .adVenue(let v): return "av_\(v.id)"
        }
    }
}

/// Настраиваемые коэффициенты ранжирования. Вынесены из `Ranking`, чтобы их можно
/// было **публиковать как данные** (Firestore `config/rankingWeights`) и заменять
/// весами, обученными на логе `rankingEvents`, — без релиза приложения (см.
/// ml/README.md). `.default` — ручные значения; `from(_:)` накладывает
/// опубликованную карту по полям (отсутствующий ключ оставляет дефолт, так что
/// частичный/пустой документ всегда безопасен).
///
/// Ключи карты совпадают с выводом тренера (W_RATING, FW_DISTANCE, …). Зеркалит
/// `RankingWeights` в `data/Ranking.kt` 1:1 (поля, дефолты, имена ключей).
/// Нормировочные опоры (reviewsRef, valueRefPct, …) сюда НЕ входят — это общие
/// гиперпараметры, одинаковые у обоих клиентов и тренера.
public struct RankingWeights: Equatable, Sendable {
    // Качество заведения.
    public let rating, reviews, saves, verified, todaySpecial, openNow, activeDeals: Double
    // Предложение.
    public let fresh, recency, value, urgency, time: Double
    // Лента (по заведениям).
    public let fwDistance, fwQuality, fwPopularity, fwFreshDeal, fwTodaySpecial, fwDeals, fwTime: Double

    public init(rating: Double, reviews: Double, saves: Double, verified: Double,
                todaySpecial: Double, openNow: Double, activeDeals: Double,
                fresh: Double, recency: Double, value: Double, urgency: Double, time: Double,
                fwDistance: Double, fwQuality: Double, fwPopularity: Double, fwFreshDeal: Double,
                fwTodaySpecial: Double, fwDeals: Double, fwTime: Double) {
        self.rating = rating; self.reviews = reviews; self.saves = saves
        self.verified = verified; self.todaySpecial = todaySpecial
        self.openNow = openNow; self.activeDeals = activeDeals
        self.fresh = fresh; self.recency = recency; self.value = value
        self.urgency = urgency; self.time = time
        self.fwDistance = fwDistance; self.fwQuality = fwQuality
        self.fwPopularity = fwPopularity; self.fwFreshDeal = fwFreshDeal
        self.fwTodaySpecial = fwTodaySpecial; self.fwDeals = fwDeals; self.fwTime = fwTime
    }

    public static let `default` = RankingWeights(
        rating: 4.0, reviews: 2.0, saves: 1.0, verified: 1.5, todaySpecial: 1.0,
        openNow: 1.0, activeDeals: 1.5,
        fresh: 3.0, recency: 2.0, value: 3.0, urgency: 1.5, time: 2.0,
        fwDistance: 6.0, fwQuality: 4.0, fwPopularity: 1.5, fwFreshDeal: 3.0,
        fwTodaySpecial: 3.0, fwDeals: 1.5, fwTime: 2.0)

    /// Накладывает опубликованную карту весов на `.default`; неизвестные/отсутствующие
    /// ключи оставляют дефолт.
    public static func from(_ m: [String: Double]?) -> RankingWeights {
        guard let m, !m.isEmpty else { return .default }
        let d = RankingWeights.default
        func g(_ k: String, _ dv: Double) -> Double { m[k] ?? dv }
        return RankingWeights(
            rating: g("W_RATING", d.rating), reviews: g("W_REVIEWS", d.reviews),
            saves: g("W_SAVES", d.saves), verified: g("W_VERIFIED", d.verified),
            todaySpecial: g("W_TODAY_SPECIAL", d.todaySpecial), openNow: g("W_OPEN_NOW", d.openNow),
            activeDeals: g("W_ACTIVE_DEALS", d.activeDeals),
            fresh: g("W_FRESH", d.fresh), recency: g("W_RECENCY", d.recency),
            value: g("W_VALUE", d.value), urgency: g("W_URGENCY", d.urgency), time: g("W_TIME", d.time),
            fwDistance: g("FW_DISTANCE", d.fwDistance), fwQuality: g("FW_QUALITY", d.fwQuality),
            fwPopularity: g("FW_POPULARITY", d.fwPopularity), fwFreshDeal: g("FW_FRESH_DEAL", d.fwFreshDeal),
            fwTodaySpecial: g("FW_TODAY_SPECIAL", d.fwTodaySpecial), fwDeals: g("FW_DEALS", d.fwDeals),
            fwTime: g("FW_TIME", d.fwTime))
    }
}

/// Чистая, Firebase- и UI-независимая математика ранжирования выдачи, вынесенная
/// из `AppStore`, чтобы её можно было юнит-тестировать напрямую (и чтобы стор не
/// был god-object). Полностью зеркалит Android `data/Ranking.kt`: сигнатуры, веса
/// и порядок слагаемых совпадают — при изменении правь ОБЕ стороны.
///
/// Принципы (см. подробный комментарий в `data/Ranking.kt`):
///  - Скор — **линейная модель** над нормализованными слагаемыми. Коэффициенты — из
///    `RankingWeights` (дефолт = ручные значения, переопределяемы из конфига), чтобы
///    веса, **обученные на логе rankingEvents**, публиковались без правки логики.
///  - Каждое слагаемое **нормализовано** (в основном к 0…1) перед взвешиванием.
///  - Рейтинг **сглажен по Байесу** к среднему по каталогу: 5.0 с двумя отзывами
///    не обгоняет 4.6 с четырьмя сотнями.
///
/// Каждая функция — чистая функция своих входов: без состояния, без типов
/// фреймворка. `AppStore` остаётся тонким адаптером: собирает агрегаты
/// (рейтинг/число отзывов/активные акции) и вызывает эти функции.
public enum Ranking {

    // MARK: Нормировочные опоры (общие гиперпараметры — держать в синхроне с тренером)
    private static let priorMean = 4.0          // средний рейтинг по каталогу (C)
    private static let priorWeight = 20.0       // «виртуальных» отзывов у приора (m)
    private static let reviewsRef = 150.0       // отзывов, при которых популярность ≈ 1
    private static let savesRef = 150.0         // сохранений, при которых популярность ≈ 1
    private static let dealsRef = 5.0           // акций, при которых слагаемое ≈ 1
    private static let recencyDays = 14.0       // за столько дней бонус новизны гаснет до 0
    private static let valueRefPct = 50.0       // ≥50% скидки — полный балл ценности
    private static let urgencyHours = 48.0      // срочность растёт в последние 48ч
    private static let distanceMaxKm = 5.0      // дальше — вклад близости 0

    /// Рейтинг, сглаженный к среднему по каталогу (классический Байес / IMDB):
    /// `(v·R + m·C) / (v + m)`. Редкие оценки притягиваются к `priorMean`; свои
    /// крайние значения рейтинг набирает лишь когда его подкрепляет достаточно
    /// отзывов (масштаба `priorWeight`).
    public static func bayesianRating(rating: Double, reviewCount: Int) -> Double {
        let v = Double(reviewCount)
        return (v * rating + priorWeight * priorMean) / (v + priorWeight)
    }

    /// Популярность с затуханием, 0…1: `ln(n+1) / ln(ref+1)`, не выше 1.
    private static func saturating(_ n: Double, _ ref: Double) -> Double {
        min(1.0, log(n + 1) / log(ref + 1))
    }

    /// Органическая оценка привлекательности заведения. Чем выше — тем выше в списках.
    /// Зеркалит `Ranking.venueScore` на Android.
    public static func venueScore(rating: Double, reviewCount: Int, savedByCount: Int,
                           isVerified: Bool, hasTodaySpecial: Bool, isOpenNow: Bool,
                           activeDealCount: Int, w: RankingWeights = .default) -> Double {
        var s = 0.0
        s += w.rating * (bayesianRating(rating: rating, reviewCount: reviewCount) / 5.0)
        s += w.reviews * saturating(Double(reviewCount), reviewsRef)
        s += w.saves * saturating(Double(savedByCount), savesRef)
        if isVerified { s += w.verified }
        if hasTodaySpecial { s += w.todaySpecial }
        if isOpenNow { s += w.openNow }
        s += w.activeDeals * saturating(Double(activeDealCount), dealsRef)
        return s
    }

    /// Органическая оценка предложения: скор заведения + свежесть + новизна +
    /// глубина скидки + мягкий буст «скоро закончится». Зеркалит `Ranking.dealScore`.
    ///  - `discountPercent`: эффективный % скидки (nil/≤0 → без бонуса ценности).
    ///  - `hoursUntilExpiry`: часов до `validUntil`; срочность действует только в
    ///    последние `urgencyHours` и растёт к концу. Протухшие акции отсечены выше
    ///    (`isActive`), так что в ленте это ≥ 0.
    ///  - `timeRelevance`: 0…1 соответствие категории заведения текущему часу
    ///    (`VenueCategory.timeRelevance`), считает вызывающий — функция остаётся чистой.
    public static func dealScore(venueScore: Double, isFresh: Bool, daysSinceStart: Double?,
                          discountPercent: Int?, hoursUntilExpiry: Double?,
                          timeRelevance: Double, w: RankingWeights = .default) -> Double {
        var s = venueScore
        if isFresh { s += w.fresh }
        if let days = daysSinceStart {
            s += w.recency * max(0, (recencyDays - days) / recencyDays)
        }
        if let pct = discountPercent, pct > 0 {
            s += w.value * min(1.0, Double(pct) / valueRefPct)
        }
        if let hrs = hoursUntilExpiry, hrs >= 0, hrs <= urgencyHours {
            s += w.urgency * ((urgencyHours - hrs) / urgencyHours)
        }
        s += w.time * timeRelevance
        return s
    }

    /// Оценка ленты с весом расстояния (haversine). Зеркалит `Ranking.feedScore`.
    ///  - `timeRelevance`: 0…1 соответствие категории заведения текущему часу
    ///    (`VenueCategory.timeRelevance`), считает вызывающий — функция остаётся чистой.
    public static func feedScore(distanceKm: Double?, rating: Double, reviewCount: Int,
                          hasFreshDeal: Bool, hasTodaySpecial: Bool, dealCount: Int,
                          timeRelevance: Double, w: RankingWeights = .default) -> Double {
        var score = 0.0
        // Distance (High): чем ближе — тем выше; ≤0км — максимум, >5км — 0.
        if let km = distanceKm { score += w.fwDistance * max(0, (distanceMaxKm - km) / distanceMaxKm) }
        // Quality (Medium): байесов рейтинг + отдельная популярность по отзывам.
        score += w.fwQuality * (bayesianRating(rating: rating, reviewCount: reviewCount) / 5.0)
        score += w.fwPopularity * saturating(Double(reviewCount), reviewsRef)
        if hasFreshDeal { score += w.fwFreshDeal }          // свежая акция (<48ч)
        if hasTodaySpecial { score += w.fwTodaySpecial }    // «сегодня»
        score += w.fwDeals * saturating(Double(dealCount), dealsRef)  // число акций (Low)
        score += w.fwTime * timeRelevance
        return score
    }

    /// Расстояние по большому кругу (км) между двумя точками lat/lng.
    /// Единственная реализация haversine — `LocationManager.haversine` делегирует сюда.
    public static func haversineKm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6371.0 // радиус Земли, км
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Вставка рекламных карточек заведений в ранжированную ленту акций:
    /// карточка перед каждой 4-й акцией (индексы 3, 8, 13…), остаток — в хвост.
    /// Зеркалит `Ranking.feed` на Android.
    public static func feed(deals: [Deal], ads: [Venue]) -> [FeedItem] {
        var items: [FeedItem] = []
        var ai = 0
        for (i, d) in deals.enumerated() {
            if i % 5 == 3, ai < ads.count { items.append(.adVenue(ads[ai])); ai += 1 }
            items.append(.deal(d))
        }
        while ai < ads.count { items.append(.adVenue(ads[ai])); ai += 1 }
        return items
    }
}

// MARK: - Осмысленность расстояния

/// Каталог всегда в пределах ОДНОГО города (`citySlug`, сейчас всегда
/// «bishkek»), поэтому расстояние имеет смысл, только пока пользователь рядом с
/// этим городом. Если геопозиция за тысячи километров (другая страна, симулятор
/// с дефолтной точкой, VPN), «11358.7 км» в каждой строке — шум, а не данные.
///
/// Порог общий для обеих платформ: расстояние либо показывается, либо его нет
/// вовсе, третьего состояния в макете не предусмотрено.
public enum GeoDisplay {
    /// Дальше этого — считаем, что пользователь не в городе каталога.
    /// Сам Бишкек укладывается в ~30 км, так что 100 км — с большим запасом.
    public static let maxMeaningfulKm: Double = 100

    /// Стоит ли вообще показывать это расстояние.
    public static func isMeaningful(_ km: Double) -> Bool {
        km.isFinite && km >= 0 && km <= maxMeaningfulKm
    }
}
