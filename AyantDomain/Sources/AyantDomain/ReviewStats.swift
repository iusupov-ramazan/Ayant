import Foundation

/// Чистая математика и слияние отзывов, вынесенные из `AppStore`.
///
/// Firebase- и UI-независимо: на вход — уже загруженные модели, на выход — числа
/// или собранный список. I/O (Firestore, UserDefaults) остаётся в сторе; сюда
/// приходят готовые массивы. Так агрегаты рейтинга и слияние отзывов можно
/// юнит-тестировать без стора, async и `@MainActor`.
public enum ReviewStats {

    /// Агрегированный рейтинг и число отзывов. Пока отзывов нет — фолбэк на seed
    /// (значения из документа заведения: `venue.rating` / `venue.reviewCount`).
    public static func aggregate(reviews: [Review],
                          fallbackRating: Double,
                          fallbackCount: Int) -> (rating: Double, count: Int) {
        guard !reviews.isEmpty else { return (fallbackRating, fallbackCount) }
        let sum = reviews.reduce(0) { $0 + $1.rating }
        return (Double(sum) / Double(reviews.count), reviews.count)
    }

    /// Агрегаты рейтинга сразу для всего каталога — за один проход по отзывам.
    ///
    /// Наивный вариант («для каждого заведения отфильтровать все отзывы») —
    /// O(заведения × отзывы): на 3000 заведений и 150 000 отзывов это 450 млн
    /// сравнений в главном потоке при каждой пересборке каталога. Здесь отзывы
    /// раскладываются по `venueID` один раз, дальше каждое заведение читает
    /// только свою корзину: O(отзывы + заведения).
    ///
    /// Результат идентичен поштучному `aggregate(reviews:fallbackRating:fallbackCount:)`,
    /// включая фолбэк на seed-значения документа для заведений без отзывов.
    ///
    /// Зеркалит `ReviewStats.aggregateAll` на Android 1:1.
    public static func aggregateAll(venues: [Venue], reviews: [Review]) -> [String: VenueRating] {
        var byVenue: [String: [Review]] = [:]
        byVenue.reserveCapacity(venues.count)
        for r in reviews { byVenue[r.venueID, default: []].append(r) }

        var result: [String: VenueRating] = [:]
        result.reserveCapacity(venues.count)
        for v in venues {
            let a = aggregate(reviews: byVenue[v.id] ?? [],
                              fallbackRating: v.rating, fallbackCount: v.reviewCount)
            result[v.id] = VenueRating(rating: a.rating, count: a.count)
        }
        return result
    }

    /// Разбивка 5★…1★ → количество. Ключи 1…5 всегда присутствуют (в т.ч. нули).
    public static func ratingBreakdown(reviews: [Review]) -> [Int: Int] {
        var counts = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
        for r in reviews { counts[r.rating, default: 0] += 1 }
        return counts
    }

    /// Объединяет отзывы из репозитория с локальными отзывами пользователя
    /// (дедуп по id — база «выигрывает») и накладывает ответы владельца.
    public static func merge(base: [Review],
                      userReviews: [Review],
                      hostReplies: [String: HostReply]) -> [Review] {
        let baseIDs = Set(base.map(\.id))
        var combined = base + userReviews.filter { !baseIDs.contains($0.id) }
        for i in combined.indices {
            if let reply = hostReplies[combined[i].id] { combined[i].hostReply = reply }
        }
        return combined
    }
}
