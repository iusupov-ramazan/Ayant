import SwiftUI
import AyantDomain

/// Стор карточки заведения — третья фича на новой форме (после баллов и ленты):
/// одно значение состояния наружу и один вход `send(_:)`.
///
/// Что изменилось: экран больше не дёргает восемь методов `AppStore`
/// (`aggregate(for:)`, `ratingBreakdown(for:)`, `myReview(...)`, `isSaved(_:)`,
/// `reviews(for:)`, `deals(for:)`, `log(_:for:)`) и не считает ничего сам —
/// он читает `state`. Производные величины считает чистый `ReviewStats`
/// через `VenueDetailState`.
///
/// Каталог, отзывы и сохранённые id по-прежнему принадлежат `AppStore` — их
/// читают поиск, избранное и лента. Здесь они проецируются в состояние экрана,
/// а мутации уходят обратно в `AppStore`, который владеет персистентностью.
/// Полное владение переедет сюда вместе с `profile` (там же живут «сохранённые»).
///
/// Зеркалит `VenueDetailViewModel.kt` на Android.
@MainActor
public final class VenueDetailStore: ObservableObject {
    /// Явный public init: синтезированный — internal.
    public init() {}

    @Published public private(set) var state = VenueDetailState()

    /// Связывается уже после создания: `@StateObject` во вьюхе строится до того,
    /// как доступен `@EnvironmentObject`.
    private weak var app: AppStore?

    public func bind(_ app: AppStore) { self.app = app }

    public func send(_ intent: VenueDetailIntent) {
        guard let app else { return }
        switch intent {
        case .open(let venueID):
            open(venueID: venueID)

        case .close:
            state = VenueDetailState()

        case .toggleSave:
            guard let venue = state.venue, state.canContribute else { return }
            app.toggleSave(venue)
            app.log(AnalyticsMetric.saves, for: venue.id)
            refresh()

        case .toggleFavorite(let dealID):
            guard let deal = state.deals.first(where: { $0.id == dealID }) else { return }
            app.toggleFavorite(deal)
            refresh()

        case .submitReview(let rating, let text, let photos, let itemID, let itemName):
            submitReview(rating: rating, text: text, photos: photos,
                         itemID: itemID, itemName: itemName)

        case .deleteReview(let reviewID):
            guard let review = state.reviews.first(where: { $0.id == reviewID }) else { return }
            app.deleteReview(review)
            refresh()

        case .dismissSubmission:
            state.submission = .idle

        case .logContact(let action):
            guard let venue = state.venue else { return }
            app.log(action.rawValue, for: venue.id)
        }
    }

    // MARK: - Проекция состояния

    private func open(venueID: String) {
        guard let app, let venue = app.venue(id: venueID) else {
            state = VenueDetailState()
            return
        }
        app.log(AnalyticsMetric.views, for: venue.id)
        state.venue = venue
        refresh()
        // Отзывы этого заведения больше не лежат в памяти заранее — забираем их
        // страницей при открытии карточки. `refresh()` уже показал экран с тем,
        // что есть (обычно пусто), подгрузка обновит его следующим кадром.
        Task { [weak self] in
            await app.loadReviews(for: venue)
            self?.refresh()
        }
    }

    /// Пересобирает срез из `AppStore`. Зовётся после каждой мутации — стор
    /// владельца уже обновился, экрану нужен свежий снимок.
    public func refresh() {
        guard let app, let venue = state.venue.flatMap({ app.venue(id: $0.id) }) else { return }
        state.venue = venue
        state.deals = app.deals(for: venue)
        state.reviews = app.reviews(for: venue)
        state.isSaved = app.isSaved(venue)
        state.favoriteDealIDs = app.favoriteDealIDs
        state.currentUserID = app.currentUserID
        state.isGuest = app.isGuest
    }

    // MARK: - Отзывы

    private func submitReview(rating: Int, text: String, photos: [String],
                              itemID: String?, itemName: String?) {
        guard let app, let venue = state.venue, state.canContribute else {
            state.submission = .failed(.unauthenticated)
            return
        }
        guard !state.submission.isSending else { return }   // второй тап игнорируем

        state.submission = .sending
        app.saveReview(venueID: venue.id, rating: rating, text: text, photos: photos,
                       itemID: itemID, itemName: itemName)
        state.submission = .idle
        refresh()
    }
}
