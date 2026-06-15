import SwiftUI
import CoreLocation

/// Глобальное состояние приложения (пользовательская сторона).
@MainActor
final class AppStore: ObservableObject {

    // MARK: - Данные из репозитория (+ контент хоста)
    @Published var venues: [Venue] = []
    @Published var deals: [Deal] = []
    @Published var reviews: [Review] = []
    @Published var isLoading = false
    @Published var loadError: String?

    // Сырые данные из репозитория и наложенный поверх контент хоста.
    private var repoVenues: [Venue] = []
    private var repoDeals: [Deal] = []
    private var hostVenues: [Venue] = []
    private var hostDeals: [Deal] = []

    // Текущий пользователь (для «Мои отзывы» / авторства)
    var currentUserID = "me"
    var currentUserName = "Вы"
    @Published var isGuest = false   // гость не может сохранять/оставлять отзывы

    private let repository: DataRepository = AppConfig.makeDataRepository()
    private let analytics: AnalyticsService = AppConfig.makeAnalyticsService()

    /// Лог события аналитики (просмотр/сохранение/звонок/маршрут/клик по акции).
    func log(_ metric: String, for venueID: String) {
        analytics.log(venueID: venueID, metric: metric)
    }

    /// Статистика заведения за период (для хост-аналитики).
    func analyticsStats(venueID: String, days: Int) async -> [String: Int] {
        (try? await analytics.fetchStats(venueID: venueID, days: days)) ?? [:]
    }

    init() {
        favoriteDealIDs = Set(UserDefaults.standard.stringArray(forKey: Self.dealsKey) ?? [])
        savedVenueIDs = Set(UserDefaults.standard.stringArray(forKey: Self.venuesKey) ?? [])
        selectedCitySlug = UserDefaults.standard.string(forKey: Self.cityKey) ?? City.bishkek.id
        reviews = MockData.reviews
    }

    func load() async {
        isLoading = true
        loadError = nil
        // Заведения и предложения — критично. Грузим их вместе.
        do {
            async let v = repository.fetchVenues()
            async let d = repository.fetchDeals()
            (repoVenues, repoDeals) = try await (v, d)
        } catch {
            loadError = error.localizedDescription
        }
        recombine()
        // Отзывы — некритично: ошибка (нет коллекции / правила доступа)
        // не должна обнулять ленту. Фолбэк на демо-отзывы.
        do {
            baseReviews = try await repository.fetchReviews()
        } catch {
            print("⚠️ reviews fetch failed, using demo reviews: \(error.localizedDescription)")
            baseReviews = MockData.reviews
        }
        mergeReviews()
        isLoading = false
    }

    func setCurrentUser(id: String?, name: String?, isGuest: Bool = false) {
        currentUserID = id ?? "me"
        currentUserName = name ?? "Вы"
        self.isGuest = isGuest
    }

    // MARK: - Контент хоста (наложение поверх данных репозитория)

    /// Хост-сторона передаёт сюда свои заведения/предложения — они появляются
    /// и в пользовательской ленте. Заведение/предложение хоста перекрывает
    /// одноимённое из репозитория (правки хоста «выигрывают»).
    func setHostContent(venues v: [Venue], deals d: [Deal]) {
        hostVenues = v
        hostDeals = d
        recombine()
    }

    private func recombine() {
        var vmap: [String: Venue] = [:]
        for x in repoVenues { vmap[x.id] = x }
        for x in hostVenues { vmap[x.id] = x }
        venues = Array(vmap.values)

        var dmap: [String: Deal] = [:]
        for x in repoDeals { dmap[x.id] = x }
        for x in hostDeals { dmap[x.id] = x }
        deals = Array(dmap.values)
    }

    // MARK: - Город (скоуп ленты, поиска)

    @Published var selectedCitySlug: String {
        didSet { UserDefaults.standard.set(selectedCitySlug, forKey: Self.cityKey) }
    }
    private static let cityKey = "san.city"

    var selectedCity: City { MockData.city(slug: selectedCitySlug) }

    var hasSelectedCity: Bool {
        UserDefaults.standard.string(forKey: Self.cityKey) != nil
    }

    func venuesInSelectedCity() -> [Venue] {
        // Только одобренные модерацией и не на паузе — на пользовательской стороне.
        venues.filter { $0.citySlug == selectedCitySlug && $0.isApproved && !$0.isPaused }
    }

    // MARK: - Предложения

    var activeDeals: [Deal] {
        deals.filter(\.isActive).sorted { $0.validUntil < $1.validUntil }
    }

    func deals(for venue: Venue) -> [Deal] {
        deals.filter { $0.venueID == venue.id && $0.isActive }
    }

    func allDeals(for venue: Venue) -> [Deal] {
        deals.filter { $0.venueID == venue.id }
    }

    func venue(for deal: Deal) -> Venue? {
        venues.first { $0.id == deal.venueID }
    }

    func venue(id: String) -> Venue? {
        venues.first { $0.id == id }
    }

    // MARK: - Сохранённые предложения (Saved Deals)

    @Published var favoriteDealIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(favoriteDealIDs), forKey: Self.dealsKey) }
    }
    private static let dealsKey = "san.favorites"

    var favoriteDeals: [Deal] {
        favoriteDealIDs
            .compactMap { id in deals.first { $0.id == id } }
            .filter(\.isActive)
            .sorted { $0.validUntil < $1.validUntil }
    }

    func isFavorite(_ deal: Deal) -> Bool { favoriteDealIDs.contains(deal.id) }

    func toggleFavorite(_ deal: Deal) {
        guard !isGuest else { return }
        if favoriteDealIDs.contains(deal.id) { favoriteDealIDs.remove(deal.id) }
        else { favoriteDealIDs.insert(deal.id) }
    }

    func unsaveDeal(_ deal: Deal) { favoriteDealIDs.remove(deal.id) }

    // MARK: - Сохранённые заведения (Saved Venues)

    @Published var savedVenueIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(savedVenueIDs), forKey: Self.venuesKey) }
    }
    private static let venuesKey = "san.savedVenues"

    var savedVenues: [Venue] {
        savedVenueIDs.compactMap { id in venues.first { $0.id == id } }
            .sorted { $0.name < $1.name }
    }

    func isSaved(_ venue: Venue) -> Bool { savedVenueIDs.contains(venue.id) }

    func toggleSave(_ venue: Venue) {
        guard !isGuest else { return }
        if savedVenueIDs.contains(venue.id) { savedVenueIDs.remove(venue.id) }
        else { savedVenueIDs.insert(venue.id) }
    }

    func unsaveVenue(_ venue: Venue) { savedVenueIDs.remove(venue.id) }

    // MARK: - Сегодняшний специал

    /// Специалы только сохранённых заведений — для верхней ленты на Главной.
    var savedTodaySpecials: [Venue] {
        savedVenues.filter(\.hasTodaySpecial)
    }

    // MARK: - Отзывы

    private static let userReviewsKey = "san.userReviews"

    /// Базовые отзывы из репозитория (Firestore/Mock); пользовательские хранятся отдельно.
    private var baseReviews: [Review] = MockData.reviews

    // Ответы владельца (режим хоста), keyed by reviewID, persisted.
    private static let hostRepliesKey = "san.hostReplies"
    private var hostReplies: [String: HostReply] = {
        guard let data = UserDefaults.standard.data(forKey: AppStore.hostRepliesKey),
              let dict = try? JSONDecoder().decode([String: HostReply].self, from: data)
        else { return [:] }
        return dict
    }()

    /// Объединяет отзывы из репозитория с локальными отзывами пользователя
    /// и накладывает ответы владельца.
    private func mergeReviews() {
        var combined = baseReviews
        if let data = UserDefaults.standard.data(forKey: Self.userReviewsKey),
           let mine = try? JSONDecoder().decode([Review].self, from: data) {
            let baseIDs = Set(combined.map(\.id))
            combined.append(contentsOf: mine.filter { !baseIDs.contains($0.id) })
        }
        // Накладываем ответы владельца.
        for i in combined.indices {
            if let reply = hostReplies[combined[i].id] { combined[i].hostReply = reply }
        }
        reviews = combined
    }

    /// Отзывы для заведений хоста (агрегированный инбокс).
    func reviews(forVenueIDs ids: Set<String>) -> [Review] {
        reviews.filter { ids.contains($0.venueID) }
    }

    /// Владелец отвечает на отзыв (виден всем на странице заведения).
    func setHostReply(reviewID: String, text: String) {
        let now = Date()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            hostReplies[reviewID] = nil
        } else {
            let existing = hostReplies[reviewID]
            hostReplies[reviewID] = HostReply(text: trimmed,
                                              createdAt: existing?.createdAt ?? now,
                                              updatedAt: now)
        }
        if let data = try? JSONEncoder().encode(hostReplies) {
            UserDefaults.standard.set(data, forKey: Self.hostRepliesKey)
        }
        if let idx = reviews.firstIndex(where: { $0.id == reviewID }) {
            reviews[idx].hostReply = hostReplies[reviewID]
        }
        // Публикуем ответ владельца в документ отзыва (виден всем).
        let reply = hostReplies[reviewID]
        Task { try? await repository.updateReviewReply(reviewID: reviewID, reply: reply) }
    }

    private func persistUserReviews() {
        let mine = reviews.filter { $0.authorID == currentUserID }
        if let data = try? JSONEncoder().encode(mine) {
            UserDefaults.standard.set(data, forKey: Self.userReviewsKey)
        }
    }

    func reviews(for venue: Venue) -> [Review] {
        reviews.filter { $0.venueID == venue.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Отзыв текущего пользователя для заведения в целом (без объекта).
    func myReview(for venue: Venue) -> Review? {
        reviews.first { $0.venueID == venue.id && $0.authorID == currentUserID && $0.itemID == nil }
    }

    /// Отзыв текущего пользователя для конкретного объекта (или заведения, если itemID == nil).
    func myReview(venueID: String, itemID: String?) -> Review? {
        reviews.first { $0.venueID == venueID && $0.authorID == currentUserID && $0.itemID == itemID }
    }

    var myReviews: [Review] {
        reviews.filter { $0.authorID == currentUserID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Агрегированный рейтинг и число отзывов (живой расчёт + фолбэк на seed).
    func aggregate(for venue: Venue) -> (rating: Double, count: Int) {
        let vr = reviews(for: venue)
        if vr.isEmpty {
            return (venue.rating, venue.reviewCount)
        }
        let avg = Double(vr.reduce(0) { $0 + $1.rating }) / Double(vr.count)
        return (avg, vr.count)
    }

    /// Разбивка 5★…1★ → количество.
    func ratingBreakdown(for venue: Venue) -> [Int: Int] {
        var counts = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
        for r in reviews(for: venue) { counts[r.rating, default: 0] += 1 }
        return counts
    }

    /// Создать или обновить отзыв. Один отзыв на (пользователь, заведение, объект).
    /// itemID == nil — отзыв о заведении в целом.
    func saveReview(venueID: String, rating: Int, text: String, photos: [String],
                    itemID: String? = nil, itemName: String? = nil) {
        guard !isGuest else { return }
        let saved: Review
        if let idx = reviews.firstIndex(where: {
            $0.venueID == venueID && $0.authorID == currentUserID && $0.itemID == itemID
        }) {
            reviews[idx].rating = rating
            reviews[idx].text = text
            reviews[idx].photoEmojis = photos
            reviews[idx].itemName = itemName
            reviews[idx].updatedAt = .now
            saved = reviews[idx]
        } else {
            let r = Review(id: "ur_\(UUID().uuidString.prefix(8))", venueID: venueID,
                           authorID: currentUserID, authorName: currentUserName,
                           rating: rating, text: text, photoEmojis: photos,
                           createdAt: .now, updatedAt: .now, hostReply: nil,
                           itemID: itemID, itemName: itemName)
            reviews.append(r)
            saved = r
        }
        persistUserReviews()
        // Публикуем отзыв в Firestore — виден всем и хосту.
        Task { try? await repository.saveReview(saved) }
    }

    func deleteReview(_ review: Review) {
        reviews.removeAll { $0.id == review.id }
        persistUserReviews()
        Task { try? await repository.deleteReview(id: review.id) }
    }

    // MARK: - Лента (v1, органическое ранжирование)

    /// Заведения выбранного города, отфильтрованные по категории и отсортированные
    /// по органическому скору. userCoord — последняя позиция (если есть).
    func rankedFeed(category: VenueCategory?, userCoord: CLLocationCoordinate2D?) -> [Venue] {
        venuesInSelectedCity()
            .filter { category == nil || $0.category == category }
            .map { (venue: $0, score: feedScore($0, userCoord: userCoord)) }
            .sorted { $0.score > $1.score }
            .map(\.venue)
    }

    private func feedScore(_ venue: Venue, userCoord: CLLocationCoordinate2D?) -> Double {
        var score = 0.0
        // Distance (High): чем ближе — тем выше; <1км — максимум.
        if let c = userCoord {
            let km = LocationManager.haversine(c.latitude, c.longitude, venue.latitude, venue.longitude)
            score += max(0, 5 - km) * 3.0
        }
        // Rating (Medium): score × log(review_count) — штрафует одиночные отзывы.
        let agg = aggregate(for: venue)
        score += agg.rating * _DarwinFoundation1.log(Double(max(agg.count, 1)) + 1) * 1.5
        // Deal recency (Medium): свежее предложение (<48ч) — буст.
        if allDeals(for: venue).contains(where: \.isFresh) { score += 4 }
        // Today's Special (Medium).
        if venue.hasTodaySpecial { score += 4 }
        // Deal count (Low).
        score += Double(deals(for: venue).count) * 0.5
        return score
    }
}
