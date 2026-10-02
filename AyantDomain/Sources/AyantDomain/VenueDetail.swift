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

    /// Сколько отзывов карточка грузит за раз (`FeedStore.reviewPageSize`).
    public static let reviewPageSize = 50

    /// Рейтинг и число отзывов для заголовка.
    ///
    /// Источник правды — денормализованные `venue.rating`/`venue.reviewCount`,
    /// которые пишет Cloud Function `aggregateReviewRating`. Раньше заголовок
    /// считался по загруженной странице: у заведения с 300 отзывами карточка
    /// показывала «4,9 · 50 отзывов» — среднее последних пятидесяти.
    ///
    /// Живой расчёт по загруженным — только когда это ВЕСЬ набор (пришло меньше
    /// страницы) и он не меньше серверного счётчика: так свежий отзыв, который
    /// функция ещё не учла, виден сразу, а неполная страница не выдаёт себя
    /// за всё заведение.
    public var aggregate: VenueRating {
        let serverRating = venue?.rating ?? 0
        let serverCount = venue?.reviewCount ?? 0
        let complete = reviews.count < Self.reviewPageSize
        if !reviews.isEmpty, complete, reviews.count >= serverCount {
            let a = ReviewStats.aggregate(reviews: reviews, fallbackRating: serverRating,
                                          fallbackCount: serverCount)
            return VenueRating(rating: a.rating, count: a.count)
        }
        return VenueRating(rating: serverRating, count: serverCount)
    }

    /// Разбивка 5★…1★ → количество (ключи 1…5 всегда есть) — по ЗАГРУЖЕННЫМ отзывам.
    public var ratingBreakdown: [Int: Int] { ReviewStats.ratingBreakdown(reviews: reviews) }

    /// Разбивка построена не по всем отзывам заведения, а по загруженной
    /// странице — экран подписывает её «по последним N отзывам».
    public var ratingBreakdownIsPartial: Bool { reviews.count < aggregate.count }

    /// Отзыв текущего пользователя на заведение целиком или на конкретный объект
    /// (блюдо/услугу). Гость своих отзывов не имеет.
    public func myReview(itemID: String? = nil) -> Review? {
        guard !currentUserID.isEmpty else { return nil }
        let wanted = ReviewIdentity.normalizedItemID(itemID)
        return reviews.first {
            $0.authorID == currentUserID && ReviewIdentity.normalizedItemID($0.itemID) == wanted
        }
    }

    public func isFavorite(_ dealID: String) -> Bool { favoriteDealIDs.contains(dealID) }

    /// Может ли пользователь сохранять заведение и писать отзывы.
    public var canContribute: Bool { !isGuest && !currentUserID.isEmpty }
}

/// Id документа отзыва: `{uid}_{venueID}_{itemID|venue}`.
///
/// Детерминированный, как у жалоб и погашений: один отзыв на (автор, заведение,
/// объект) держится самим id, а не тем, нашёл ли клиент старый отзыв в кэше.
/// Правила Firestore требуют этот id при создании. Правка существующего
/// отзыва сохраняет его прежний id (старые отзывы — `ur_…`).
public enum ReviewIdentity {
    /// Суффикс отзыва о заведении в целом (без объекта).
    public static let venueLevel = "venue"

    public static func documentID(authorID: String, venueID: String, itemID: String?) -> String {
        let item = (itemID?.isEmpty == false) ? itemID! : venueLevel
        return "\(authorID)_\(venueID)_\(item)"
    }

    /// Пустой id объекта — то же, что отзыв о заведении в целом.
    public static func normalizedItemID(_ itemID: String?) -> String? {
        guard let itemID, !itemID.isEmpty, itemID != venueLevel else { return nil }
        return itemID
    }
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
