import Foundation

// Фича «Заведение» (карточка заведения): состояние и намерения.
// Имена полей совпадают с `VenueDetail.kt` в `android/domain`.

/// Всё, что показывает карточка заведения, — одним значением.
///
/// Производные величины (рейтинг, разбивка по звёздам, «мой отзыв») здесь —
/// функции состояния, а не хранимые поля: иначе они разъезжаются с отзывами.
/// Считает их чистый `ReviewStats`, тот же, что и раньше в сторе.
public struct VenueDetailState: Equatable {
    /// `nil` — экран ещё не открыт (или заведение исчезло из каталога).
    public var venue: Venue?
    public var deals: [Deal] = []
    public var reviews: [Review] = []
    public var isSaved: Bool = false
    public var favoriteDealIDs: Set<String> = []
    /// Пусто — гость: сохранять и писать отзывы нельзя.
    public var currentUserID: String = ""
    public var isGuest: Bool = true
    public var submission: ReviewSubmission = .idle

    public init(venue: Venue? = nil, deals: [Deal] = [], reviews: [Review] = [],
                isSaved: Bool = false, favoriteDealIDs: Set<String> = [],
                currentUserID: String = "", isGuest: Bool = true,
                submission: ReviewSubmission = .idle) {
        self.venue = venue; self.deals = deals; self.reviews = reviews
        self.isSaved = isSaved; self.favoriteDealIDs = favoriteDealIDs
        self.currentUserID = currentUserID; self.isGuest = isGuest
        self.submission = submission
    }

    /// Рейтинг и число отзывов. Пока отзывов нет — seed-значения из документа.
    public var aggregate: VenueRating {
        let a = ReviewStats.aggregate(reviews: reviews,
                                      fallbackRating: venue?.rating ?? 0,
                                      fallbackCount: venue?.reviewCount ?? 0)
        return VenueRating(rating: a.rating, count: a.count)
    }

    /// Разбивка 5★…1★ → количество (ключи 1…5 всегда есть).
    public var ratingBreakdown: [Int: Int] { ReviewStats.ratingBreakdown(reviews: reviews) }

    /// Отзыв текущего пользователя на заведение целиком или на конкретный объект
    /// (блюдо/услугу). Гость своих отзывов не имеет.
    public func myReview(itemID: String? = nil) -> Review? {
        guard !currentUserID.isEmpty else { return nil }
        return reviews.first { $0.authorID == currentUserID && $0.itemID == itemID }
    }

    public func isFavorite(_ dealID: String) -> Bool { favoriteDealIDs.contains(dealID) }

    /// Может ли пользователь сохранять заведение и писать отзывы.
    public var canContribute: Bool { !isGuest && !currentUserID.isEmpty }
}

/// Фаза публикации отзыва. Отдельно от списка: карточка остаётся видимой,
/// пока отзыв отправляется.
public enum ReviewSubmission: Equatable {
    case idle
    case sending
    case failed(AppError)

    public var isSending: Bool {
        if case .sending = self { return true }
        return false
    }
}

/// Единственный вход в стор карточки заведения.
public enum VenueDetailIntent: Equatable {
    /// Экран открыт для этого заведения (логирует просмотр).
    case open(venueID: String)
    case close
    case toggleSave
    case toggleFavorite(dealID: String)
    /// Публикация/правка отзыва. `itemID` — объект отзыва (блюдо/услуга) или nil.
    case submitReview(rating: Int, text: String, photos: [String],
                      itemID: String?, itemName: String?)
    case deleteReview(reviewID: String)
    case dismissSubmission
    /// Пользователь позвонил / построил маршрут — событие для аналитики заведения.
    case logContact(ContactAction)
}

/// Действия, которые заведение считает как обращения.
public enum ContactAction: String, Equatable, Sendable {
    case call = "calls"
    case maps = "maps"
}
