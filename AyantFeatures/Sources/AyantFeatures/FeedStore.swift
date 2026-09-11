import SwiftUI
import AyantDomain

/// Стор ленты — вторая фича на новой форме (после баллов): одно значение
/// состояния наружу и один вход `send(_:)`.
///
/// Что изменилось по сравнению с прежней лентой в `AppStore`:
///  • порядок выдачи считает чистая `FeedBuilder` из домена, а не методы стора;
///  • «сейчас» приходит из `Clock`, поэтому лента воспроизводима в тесте —
///    раньше скоринг звал `Date()` и `Calendar.current` прямо внутри;
///  • загрузка и ошибка — часть состояния (`LoadState`), а не два разных поля.
///
/// **Владелец каталога.** Заведения, акции, отзывы и веса ранжирования грузятся
/// и живут здесь; `AppStore` читает их через тонкие адаптеры (`venues`, `deals`,
/// `reviews`), поэтому существующие вызовы по приложению не менялись. Раньше
/// владельцем был `AppStore`, а сюда каталог приезжал намерением `.setCatalog`.
///
/// Зеркалит `FeedViewModel.kt` на Android.
@MainActor
public final class FeedStore: ObservableObject {
    @Published public private(set) var state = FeedState()

    private let clock: Clock
    private let repository: DataRepository

    // Сырые слои каталога: репозиторий + оверлей хоста (правки хоста «выигрывают»).
    private var repoVenues: [Venue] = []
    private var repoDeals: [Deal] = []
    private var hostVenues: [Venue] = []
    private var hostDeals: [Deal] = []

    // Отзывы: база из репозитория + локальные пользовательские + ответы владельца.
    //
    // ВАЖНО: это КЭШ, а не полный набор. Вся коллекция больше не выгружается
    // (см. docs/design/system-design.md §4.2) — сюда попадают только отзывы,
    // которые кто-то явно запросил: карточка заведения, инбокс владельца,
    // профиль. Поэтому рейтинг для ленты по этому массиву считать НЕЛЬЗЯ:
    // он придёт неполным. Для ленты источник правды — денормализованные
    // `venue.rating`/`venue.reviewCount`, которые пишет Cloud Function.
    //
    // На старте кэш ПУСТ. Раньше сюда клали `MockData.reviews`, а их venueID
    // (`navat`, `sierra`, …) совпадают с реальными заведениями в Firestore —
    // выдуманные отзывы показывались как настоящие. Отзывы приходят только
    // из репозитория (`loadReviews…`); в мок-режиме их отдаёт `MockDataRepository`.
    private var baseReviews: [Review] = []
    public private(set) var reviews: [Review] = []
    private var hostReplies: [String: HostReply] = [:]

    /// Заведения, отзывы которых загружены ПОЛНОСТЬЮ (пришло меньше лимита —
    /// значит, это всё). Только для них живой пересчёт агрегата точнее
    /// денормализованного; для остальных отдаём фолбэк на документ заведения.
    private var fullyLoadedReviewVenueIDs: Set<String> = []

    /// Сколько отзывов тянем за раз. Карточка заведения показывает первую
    /// страницу; если пришло ровно столько — значит, есть ещё, и агрегат
    /// считать по кэшу нельзя.
    public static let reviewPageSize = 50

    @Published public private(set) var loadError: String?

    private enum Key {
        static let userReviews = "san.userReviews"
        static let hostReplies = "san.hostReplies"
    }

    public init(clock: Clock = SystemClock(),
         repository: DataRepository) {
        self.clock = clock
        self.repository = repository
        if let data = UserDefaults.standard.data(forKey: Key.hostReplies),
           let dict = try? JSONDecoder().decode([String: HostReply].self, from: data) {
            hostReplies = dict
        }
        // «Полностью загруженных» заведений на старте нет: до первого
        // `loadReviews(forVenue:)` все остаются на денормализованном рейтинге.
        mergeReviews()
    }

    // MARK: - Загрузка каталога

    public func load() async {
        loadError = nil
        send(.setLoading)
        // Заведения и предложения — критично. Грузим их вместе.
        do {
            async let v = repository.fetchVenues()
            async let d = repository.fetchDeals()
            (repoVenues, repoDeals) = try await (v, d)
        } catch {
            loadError = error.localizedDescription
            send(.setFailure(.network))
        }
        // Веса ранжирования — некритично: ошибка/отсутствие → остаёмся на дефолтах.
        if let m = try? await repository.fetchRankingWeights() {
            send(.setWeights(.from(m)))
        }
        // Отзывы здесь БОЛЬШЕ НЕ ГРУЗЯТСЯ. Раньше на этом месте выгружалась вся
        // коллекция `reviews` ради двух чисел на карточке — рейтинга и счётчика.
        // Теперь их пишет на документ заведения Cloud Function
        // `aggregateReviewRating`, а сами отзывы подтягивает тот экран, которому
        // они нужны: `loadReviews(forVenue:)` / `(forVenueIDs:)` / `(authorID:)`.
        mergeReviews()
        recombine()
    }

    /// Хост-сторона передаёт свои заведения/акции — они появляются в ленте.
    public func setHostContent(venues: [Venue], deals: [Deal]) {
        hostVenues = venues
        hostDeals = deals
        recombine()
    }

    /// Пересобирает каталог: репозиторий + оверлей хоста + агрегаты отзывов.
    private func recombine() {
        var vmap: [String: Venue] = [:]
        for x in repoVenues { vmap[x.id] = x }
        for x in hostVenues { vmap[x.id] = x }

        var dmap: [String: Deal] = [:]
        for x in repoDeals { dmap[x.id] = x }
        for x in hostDeals { dmap[x.id] = x }

        let venues = Array(vmap.values)
        let deals = Array(dmap.values)
        // Живой агрегат считаем ТОЛЬКО для заведений с полностью загруженными
        // отзывами. Для остальных запись не создаём — и `FeedState.aggregate`
        // берёт денормализованные `venue.rating`/`venue.reviewCount`. Иначе
        // заведение с 300 отзывами показывало бы рейтинг по первой странице из 50.
        let complete = venues.filter { fullyLoadedReviewVenueIDs.contains($0.id) }
        // Один проход по отзывам вместо фильтра всего массива на каждое заведение.
        let ratings = ReviewStats.aggregateAll(venues: complete, reviews: reviews)
        send(.setCatalog(FeedCatalog(venues: venues, deals: deals, ratings: ratings)))
    }

    // MARK: - Отзывы (часть каталога: влияют на ранг)

    /// Сырой каталог (без фильтра города/категории) — его читают поиск,
    /// избранное и карточка заведения через адаптеры `AppStore`.
    /// Не путать с `venues`/`deals` ниже — те уже отранжированы для ленты.
    /// Только то, что пользователю разрешено видеть: без отклонённых модерацией
    /// и поставленных на паузу. Сырой каталог остаётся внутри стора — он нужен
    /// сборке ленты и оверлею хоста.
    public var catalogVenues: [Venue] {
        FeedBuilder.userVisible(venues: state.catalog.value?.venues ?? [])
    }
    public var catalogDeals: [Deal] {
        let catalog = state.catalog.value
        return FeedBuilder.userVisible(deals: catalog?.deals ?? [], venues: catalog?.venues ?? [])
    }

    // MARK: - Подгрузка отзывов (заменила выгрузку всей коллекции)

    /// Отзывы одного заведения — зовёт карточка заведения при открытии.
    /// Если пришло меньше страницы, значит это весь набор: помечаем заведение
    /// «полным», и его рейтинг дальше считается живьём, а не по документу.
    public func loadReviews(forVenue venueID: String) async {
        guard let fetched = try? await repository.fetchReviews(
            venueID: venueID, limit: Self.reviewPageSize) else { return }
        if fetched.count < Self.reviewPageSize {
            fullyLoadedReviewVenueIDs.insert(venueID)
        }
        absorb(fetched)
    }

    /// Инбокс владельца: отзывы по всем его заведениям.
    public func loadReviews(forVenueIDs ids: [String]) async {
        guard !ids.isEmpty,
              let fetched = try? await repository.fetchReviews(
                venueIDs: ids, limit: Self.reviewPageSize) else { return }
        absorb(fetched)
    }

    /// Отзывы текущего пользователя — для профиля.
    public func loadMyReviews(authorID: String) async {
        guard let fetched = try? await repository.fetchReviews(
            authorID: authorID, limit: Self.reviewPageSize) else { return }
        absorb(fetched)
    }

    /// Вливает пришедшую страницу в кэш: дедуп по id, свежая версия выигрывает,
    /// локальные отзывы пользователя и ответы владельца не теряются.
    private func absorb(_ fetched: [Review]) {
        guard !fetched.isEmpty else { return }
        let incoming = Set(fetched.map(\.id))
        baseReviews = baseReviews.filter { !incoming.contains($0.id) } + fetched
        mergeReviews()
        recombine()
    }

    /// Объединяет базу, локальные отзывы пользователя и ответы владельца.
    private func mergeReviews() {
        var mine: [Review] = []
        if let data = UserDefaults.standard.data(forKey: Key.userReviews),
           let decoded = try? JSONDecoder().decode([Review].self, from: data) {
            mine = decoded
        }
        reviews = ReviewStats.merge(base: baseReviews, userReviews: mine, hostReplies: hostReplies)
    }

    /// Добавляет/заменяет отзыв пользователя и сохраняет его локально.
    public func upsertUserReview(_ review: Review) {
        if let i = reviews.firstIndex(where: { $0.id == review.id }) { reviews[i] = review }
        else { reviews.append(review) }
        persistUserReviews()
        recombine()
    }

    public func removeReview(id: String) {
        reviews.removeAll { $0.id == id }
        persistUserReviews()
        recombine()
    }

    /// Ответ владельца на отзыв (виден всем).
    public func setHostReply(reviewID: String, reply: HostReply?) {
        hostReplies[reviewID] = reply
        if let data = try? JSONEncoder().encode(hostReplies) {
            UserDefaults.standard.set(data, forKey: Key.hostReplies)
        }
        if let i = reviews.firstIndex(where: { $0.id == reviewID }) {
            reviews[i].hostReply = reply
        }
        recombine()
    }

    /// Локально хранятся только отзывы текущего пользователя — остальные приедут
    /// из репозитория. `currentUserID` задаёт владелец сессии (`AppStore`).
    public var currentUserID = "me"

    private func persistUserReviews() {
        let mine = reviews.filter { $0.authorID == currentUserID }
        if let data = try? JSONEncoder().encode(mine) {
            UserDefaults.standard.set(data, forKey: Key.userReviews)
        }
    }

    public func send(_ intent: FeedIntent) {
        switch intent {
        case .setCatalog(let catalog): state.catalog = .loaded(catalog)
        case .setLoading:
            // Первую загрузку показываем спиннером, обновление поверх готовой
            // ленты — нет: список не должен схлопываться на pull-to-refresh.
            if state.catalog.value == nil { state.catalog = .loading }
        case .setFailure(let error):
            if state.catalog.value == nil { state.catalog = .failed(error) }
        case .setWeights(let weights):     state.weights = weights
        case .selectCity(let slug):        state.citySlug = slug
        case .selectCategory(let category): state.category = category
        }
    }

    // MARK: - Производные значения (функции состояния, не хранимые поля)

    public var items: [FeedItem] { state.items(now: clock.now) }
    public var deals: [Deal] { state.deals(now: clock.now) }
    public var venues: [Venue] { state.venues(now: clock.now) }

    /// Лента для конкретной категории, не меняя выбранный фильтр (нужно вкладкам).
    public func items(category: VenueCategory?) -> [FeedItem] {
        var scoped = state
        scoped.category = category
        return scoped.items(now: clock.now)
    }

    public func deals(category: VenueCategory?) -> [Deal] {
        var scoped = state
        scoped.category = category
        return scoped.deals(now: clock.now)
    }

    /// Заведения города для категории — тот же `FeedBuilder.rankedVenues`, что
    /// и `venues`: только одобренные и не на паузе, отсортированные по рангу.
    /// Нужно секции «Заведения» на главной, пока вкладка поиска скрыта.
    public func venues(category: VenueCategory?) -> [Venue] {
        var scoped = state
        scoped.category = category
        return scoped.venues(now: clock.now)
    }

    public var isLoading: Bool { state.catalog.isLoading }
    public var hasVenuesInCity: Bool { state.hasVenuesInCity }
    /// Загрузка каталога упала. Отличать обязательно: без этого экран показывал
    /// «в городе пока нет заведений» — то есть пустой экран вместо ошибки, и
    /// повторить попытку было нечем.
    public var loadFailed: Bool { state.catalog.error != nil }
}
