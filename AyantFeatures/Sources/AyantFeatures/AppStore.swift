import SwiftUI
import Combine
import CoreLocation
import AyantDomain

// FeedItem и чистая математика ранжирования вынесены в Domain/Ranking.swift.

/// Глобальное состояние приложения (пользовательская сторона).
@MainActor
public final class AppStore: ObservableObject {

    // MARK: - Данные из репозитория (+ контент хоста)
    /// Каталог переехал в `FeedStore` — он владеет загрузкой, оверлеем хоста и
    /// отзывами. Здесь остались адаптеры, чтобы поиск, избранное и карточка
    /// заведения продолжали работать без правок.
    public var venues: [Venue] { feed.catalogVenues ?? [] }
    public var deals: [Deal] { feed.catalogDeals ?? [] }
    public var reviews: [Review] { feed.reviews ?? [] }
    public var isLoading: Bool { feed.state.catalog.isLoading ?? false }
    public var loadError: String? { feed.loadError }

    // Сырые данные из репозитория и наложенный поверх контент хоста.

    // Текущий пользователь (для «Мои отзывы» / авторства)
    public var currentUserID = "me"
    public var currentUserName = "Вы"
    @Published public var isGuest = false   // гость не может сохранять/оставлять отзывы
    @Published public var toastMessage: String?   // всплывающее уведомление (подарки и т. п.)

    /// Стор ленты. `AppStore` остаётся владельцем загрузки каталога (его же читают
    /// поиск, избранное и карточка заведения) и публикует снимок сюда — второй
    /// раз Firestore не читается.
    /// Владелец каталога. Создаётся здесь же на инжектированном репозитории,
    /// поэтому `AppStore` в тесте самодостаточен (иначе каталог был бы пуст).
    public let feed: FeedStore

    /// Владелец личной библиотеки (сохранённые/избранные/погашенные).
    public let profile: ProfileStore
    /// Множества переехали в `ProfileStore` и перестали быть `@Published` здесь.
    /// Пробрасываем его изменения дальше, иначе экраны, подписанные только на
    /// `AppStore`, перестали бы обновляться при сохранении/избранном.
    private var profileChanges: AnyCancellable?
    private var catalogChanges: AnyCancellable?

    /// Источник «сейчас». Ниже слоя UI системное время напрямую не читаем —
    /// иначе логика не воспроизводится в тесте (см. `Clock` в домене).
    private let clock: Clock

    private let repository: DataRepository
    private let analytics: AnalyticsService
    private let push: PushService
    /// Журнал событий ранжирования (learning-to-rank). Fire-and-forget.
    private let rankingLog: RankingEventService
    /// Локальное хранилище настроек (UserDefaults по умолчанию; в тестах — стаб).
    private let prefs: LocalPreferencesStore

    // Идентификаторы сессии/рендера для склейки impression → tap/redeem.
    public let sessionID = UUID().uuidString
    private var lastRenderID = UUID().uuidString
    private var lastImpressionSignature = ""

    /// Веса ранжирования: дефолт → переопределяются опубликованными (config/rankingWeights)
    /// при `load()`. Учат офлайн на логе rankingEvents; см. ml/README.md.
    private var rankingWeights: RankingWeights = .default

    /// Пользователь реально посетил заведение (погасил у него хотя бы один купон).
    public func hasVisited(_ venueID: String) -> Bool {
        deals.contains { $0.venueID == venueID && redeemedDealIDs.contains($0.id) }
    }

    /// Лог события аналитики (просмотр/сохранение/звонок/маршрут/клик по акции).
    public func log(_ metric: String, for venueID: String) {
        analytics.log(venueID: venueID, metric: metric)
    }

    /// Статистика заведения за период (для хост-аналитики).
    public func analyticsStats(venueID: String, days: Int) async -> [String: Int] {
        (try? await analytics.fetchStats(venueID: venueID, days: days)) ?? [:]
    }

    /// Метрики по дням — нужен графику «Аналитики»; суммы схлопывают ряд.
    public func analyticsDaily(venueID: String, days: Int) async -> [String: [String: Int]] {
        (try? await analytics.fetchDailyStats(venueID: venueID, days: days)) ?? [:]
    }

    public init(clock: Clock = SystemClock(),
         profile: ProfileStore? = nil,
         feed: FeedStore? = nil,
         repository: DataRepository,
         analytics: AnalyticsService,
         push: PushService,
         rankingLog: RankingEventService,
         prefs: LocalPreferencesStore) {
        // Дефолтный профиль строим на ИНЖЕКТИРОВАННОМ хранилище настроек, иначе
        // тест с InMemoryPreferences всё равно читал бы реальные UserDefaults.
        self.clock = clock
        self.profile = profile ?? ProfileStore(storage: UserDefaultsProfileStorage(prefs: prefs))
        self.feed = feed ?? FeedStore(repository: repository)
        self.repository = repository
        self.analytics = analytics
        self.push = push
        self.rankingLog = rankingLog
        self.prefs = prefs
        selectedCitySlug = prefs.string(forKey: Self.cityKey) ?? City.bishkek.id
        self.feed.send(.selectCity(selectedCitySlug))
        self.feed.currentUserID = currentUserID
        // Каталог и личная библиотека больше не @Published здесь — пробрасываем
        // изменения владельцев, иначе экраны, подписанные только на AppStore, замрут.
        profileChanges = self.profile.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        catalogChanges = self.feed.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    public func load() async {
        await feed.load()
    }

    /// Забывает всё, что принадлежало вышедшему пользователю: личную библиотеку
    /// и привязку к его id (`myReviews` считается от него). Каталог — общий для
    /// всех — остаётся.
    public func resetForNewUser() {
        profile.resetForNewUser()
        currentUserID = "me"
        currentUserName = "Вы"
        isGuest = false
        feed.currentUserID = currentUserID
    }

    public func setCurrentUser(id: String?, name: String?, isGuest: Bool = false) {
        currentUserID = id ?? "me"
        currentUserName = name ?? "Вы"
        self.isGuest = isGuest
        feed.currentUserID = currentUserID
        profile.send(.setUser(id: currentUserID, name: currentUserName, isGuest: isGuest))
    }

    // MARK: - Контент хоста (наложение поверх данных репозитория)

    /// Хост-сторона передаёт сюда свои заведения/предложения — они появляются
    /// и в пользовательской ленте. Заведение/предложение хоста перекрывает
    /// одноимённое из репозитория (правки хоста «выигрывают»).
    /// Связывает стор ленты: с этого момента каждый пересбор каталога уезжает в него.
    public func setHostContent(venues v: [Venue], deals d: [Deal]) {
        feed.setHostContent(venues: v, deals: d)
    }

    // MARK: - Город (скоуп ленты, поиска)

    @Published public var selectedCitySlug: String {
        didSet {
            prefs.setString(selectedCitySlug, forKey: Self.cityKey)
            feed.send(.selectCity(selectedCitySlug))
        }
    }
    private static let cityKey = "san.city"

    public var selectedCity: City { MockData.city(slug: selectedCitySlug) }

    public func venuesInSelectedCity() -> [Venue] {
        // Только одобренные модерацией и не на паузе — на пользовательской стороне.
        venues.filter { $0.citySlug == selectedCitySlug && $0.isApproved && !$0.isPaused }
    }

    /// Заведения города, отсортированные по релевантности (рейтинг, отзывы,
    /// сохранения, верификация, спецпредложения, активные акции, «открыто сейчас»).
    public func rankedVenues(category: VenueCategory? = nil) -> [Venue] {
        FeedBuilder.rankedVenues(catalogSnapshot(), citySlug: selectedCitySlug,
                                 category: category, weights: rankingWeights, now: clock.now)
    }

    // MARK: - Ранжирование (алгоритм выдачи)

    /// Оценка привлекательности заведения. Чем выше — тем выше в списках.
    /// Тонкий адаптер: собирает агрегаты и делегирует чистой `Ranking.venueScore`.
    public func venueScore(_ v: Venue) -> Double {
        FeedBuilder.venueScore(v, catalog: catalogSnapshot(), weights: rankingWeights, now: clock.now)
    }

    /// Снимок для чистых функций ранжирования. Пока `AppStore` владеет каталогом,
    /// собираем его на месте; после перевода `venue`/`profile` на новую форму
    /// снимок будет жить в `FeedStore` и собираться один раз.
    ///
    /// КЭШИРУЕТСЯ. Раньше каждый вызов проходил по всем заведениям и для каждого
    /// звал `aggregate(for:)`, а тот фильтрует ВЕСЬ список отзывов и ещё
    /// сортирует его. То есть один снимок стоил O(заведения × отзывы) плюс
    /// сортировка на каждое заведение — а снимок собирался заново в семи местах,
    /// в том числе на каждый вызов `dealScore`. На полсотни заведений и сотни
    /// отзывов это давало кадры за сотню миллисекунд.
    ///
    /// Теперь рейтинги считаются ОДНИМ проходом по отзывам, а результат живёт до
    /// следующего изменения каталога.
    private var cachedSnapshot: FeedCatalog?
    private var cachedSnapshotKey: Int?

    private func catalogSnapshot() -> FeedCatalog {
        // Дешёвый ключ: пересобираем, только если каталог реально поменялся.
        var hasher = Hasher()
        hasher.combine(venues.count)
        hasher.combine(deals.count)
        hasher.combine(reviews.count)
        hasher.combine(venues.last?.id)
        hasher.combine(reviews.last?.id)
        let key = hasher.finalize()
        if key == cachedSnapshotKey, let cachedSnapshot { return cachedSnapshot }

        // Один проход по отзывам вместо одного прохода НА КАЖДОЕ заведение.
        var sums: [String: (total: Int, count: Int)] = [:]
        sums.reserveCapacity(venues.count)
        for r in reviews {
            let previous = sums[r.venueID] ?? (0, 0)
            sums[r.venueID] = (previous.total + r.rating, previous.count + 1)
        }
        var ratings: [String: VenueRating] = [:]
        ratings.reserveCapacity(venues.count)
        for v in venues {
            if let s = sums[v.id], s.count > 0 {
                ratings[v.id] = VenueRating(rating: Double(s.total) / Double(s.count), count: s.count)
            } else {
                ratings[v.id] = VenueRating(rating: v.rating, count: v.reviewCount)
            }
        }
        let snapshot = FeedCatalog(venues: venues, deals: deals, ratings: ratings)
        cachedSnapshot = snapshot
        cachedSnapshotKey = key
        return snapshot
    }

    /// Рейтинг заведения из уже посчитанного снимка — без повторного прохода по
    /// отзывам и без сортировки.
    public func cachedAggregate(for venue: Venue) -> (rating: Double, count: Int) {
        let r = catalogSnapshot().ratings[venue.id]
        return (r?.rating ?? venue.rating, r?.count ?? venue.reviewCount)
    }

    /// Органическая оценка предложения: релевантность заведения + свежесть + новизна +
    /// глубина скидки + мягкий буст «скоро закончится». Платный буст — отдельно в feedDeals.
    public func dealScore(_ d: Deal) -> Double {
        FeedBuilder.dealScore(d, catalog: catalogSnapshot(), weights: rankingWeights, now: clock.now)
    }

    // MARK: - Предложения

    public var activeDeals: [Deal] {
        deals.filter(\.isActive).sorted { $0.validUntil < $1.validUntil }
    }

    public func deals(for venue: Venue) -> [Deal] {
        deals.filter { $0.venueID == venue.id && $0.isActive }
    }

    /// Лента предложений: активные акции заведений выбранного города. Акции — как есть.
    public func feedDeals(category: VenueCategory?) -> [Deal] {
        FeedBuilder.rankedDeals(catalogSnapshot(), citySlug: selectedCitySlug,
                                category: category, weights: rankingWeights, now: clock.now)
    }

    /// Заведения с активным платным бустом (для рекламных карточек в ленте), в ротации.
    public func boostedVenuesRotated(category: VenueCategory?) -> [Venue] {
        FeedBuilder.boostedVenues(catalogSnapshot(), citySlug: selectedCitySlug,
                                  category: category, now: clock.now)
    }

    /// Смешанная лента: акции как есть + рекламные карточки заведений вставлены через интервал.
    public func feedItems(category: VenueCategory?) -> [FeedItem] {
        FeedBuilder.items(catalogSnapshot(), citySlug: selectedCitySlug,
                          category: category, weights: rankingWeights, now: clock.now)
    }

    // MARK: - Журнал ранжирования (learning-to-rank)

    /// Снимок фич предложения на момент показа (`RankingItemFeatures`). Читает те же
    /// сигналы, что и `dealScore`, чтобы лог не расходился со скором.
    private func rankingFeatures(for deal: Deal, position: Int,
                                 userCoord: CLLocationCoordinate2D?) -> RankingItemFeatures {
        let v = venue(for: deal)
        let agg = v.map(aggregate(for:)) ?? (rating: 0, count: 0)
        let hour = Calendar.current.component(.hour, from: clock.now)
        let distanceKm = (v.flatMap { ven in userCoord.map { ($0, ven) } }).map {
            Ranking.haversineKm($0.0.latitude, $0.0.longitude, $0.1.latitude, $0.1.longitude)
        }
        return RankingItemFeatures(
            dealID: deal.id, venueID: deal.venueID, position: position, kind: "deal",
            score: dealScore(deal),
            bayesRating: Ranking.bayesianRating(rating: agg.rating, reviewCount: agg.count),
            reviewCount: agg.count, savedByCount: v?.savedByCount ?? 0,
            isVerified: v?.isVerified ?? false, hasTodaySpecial: v?.hasTodaySpecial ?? false,
            activeDealCount: v.map { ven in deals.filter { $0.venueID == ven.id && $0.isActive }.count } ?? 0,
            isFresh: deal.isFresh,
            daysSinceStart: deal.startDate.map { -$0.timeIntervalSinceNow / 86_400 },
            discountPercent: deal.effectiveDiscountPercent,
            hoursUntilExpiry: deal.validUntil.timeIntervalSinceNow / 3600,
            distanceKm: distanceKm,
            timeRelevance: v?.category.timeRelevance(hour: hour) ?? 0.5)
    }

    /// Общий конверт события (сессия, город, час, дата). renderID подставляют вызовы.
    private func makeEvent(_ type: RankingEventType, category: VenueCategory?,
                           renderID: String) -> RankingEvent {
        let now = clock.now
        return RankingEvent(
            type: type, userID: currentUserID, sessionID: sessionID, renderID: renderID,
            citySlug: selectedCitySlug, category: category?.rawValue,
            hour: Calendar.current.component(.hour, from: now),
            weekday: Venue.todayIndex,
            clientTs: now.timeIntervalSince1970 * 1000)
    }

    /// Логирует показ ленты предложений (impression-слейт с фичами). Дедупит по
    /// сигнатуре (категория + порядок id), чтобы перерисовки не плодили события.
    public func logFeedImpression(category: VenueCategory?, userCoord: CLLocationCoordinate2D?,
                           limit: Int = 20) {
        let slate = Array(feedDeals(category: category).prefix(limit))
        let signature = "\(category?.rawValue ?? "*")|\(slate.map(\.id).joined(separator: ","))"
        guard signature != lastImpressionSignature, !slate.isEmpty else { return }
        lastImpressionSignature = signature
        lastRenderID = UUID().uuidString
        var event = makeEvent(.impression, category: category, renderID: lastRenderID)
        event.items = slate.enumerated().map { idx, d in
            rankingFeatures(for: d, position: idx, userCoord: userCoord)
        }
        rankingLog.log(event)
    }

    /// Логирует открытие предложения (tap). `position` — ранг, если известен.
    public func logRankingTap(_ deal: Deal, position: Int? = nil, category: VenueCategory? = nil) {
        var event = makeEvent(.tap, category: category, renderID: lastRenderID)
        event.dealID = deal.id
        event.venueID = deal.venueID
        event.position = position
        rankingLog.log(event)
    }

    public func allDeals(for venue: Venue) -> [Deal] {
        deals.filter { $0.venueID == venue.id }
    }

    public func venue(for deal: Deal) -> Venue? {
        venues.first { $0.id == deal.venueID }
    }

    public func venue(id: String) -> Venue? {
        venues.first { $0.id == id }
    }

    // MARK: - Сохранённые предложения (Saved Deals)

    /// Личная библиотека переехала в `ProfileStore` — он владеет множествами и
    /// их персистентностью. Здесь остались адаптеры, чтобы ~30 вызовов по
    /// приложению не пришлось править разом.
    public var favoriteDealIDs: Set<String> { profile.state.favoriteDealIDs }
    private static let dealsKey = "san.favorites"

    public var favoriteDeals: [Deal] {
        favoriteDealIDs
            .compactMap { id in deals.first { $0.id == id } }
            .filter(\.isActive)
            .sorted { $0.validUntil < $1.validUntil }
    }

    public func isFavorite(_ deal: Deal) -> Bool { favoriteDealIDs.contains(deal.id) }

    public func toggleFavorite(_ deal: Deal) {
        guard !isGuest else { return }
        profile.send(.toggleFavorite(dealID: deal.id))
    }

    // MARK: - Отметки «нравится»
    //
    // Отдельно от «Сохранённого»: закладка кладёт акцию в личную библиотеку,
    // сердечко — только реакция. Хранится на устройстве, поэтому доступно и
    // гостю (сохранение — нет, оно привязано к аккаунту).

    public var likedDealIDs: Set<String> { profile.state.likedDealIDs }

    public func isLiked(_ deal: Deal) -> Bool { likedDealIDs.contains(deal.id) }

    public func toggleLike(_ deal: Deal) {
        profile.send(.toggleLike(dealID: deal.id))
    }

    // MARK: - Погашение купонов (ключевая метрика)

    public var redeemedDealIDs: Set<String> { profile.state.redeemedDealIDs }
    private static let redeemedKey = "san.redeemed"

    public func hasRedeemed(_ deal: Deal) -> Bool { redeemedDealIDs.contains(deal.id) }

    /// Пользователь погасил купон в заведении. Одноразово на устройстве.
    /// Считает метрику для хост-аналитики и шлёт продуктовое событие.
    public func redeem(_ deal: Deal) {
        guard !isGuest, !redeemedDealIDs.contains(deal.id) else { return }
        profile.send(.markRedeemed(dealID: deal.id))
        AnalyticsLog.log(.dealRedeem, ["deal_id": deal.id, "venue_id": deal.venueID,
                                       "type": deal.type.rawValue])
        // Целевая метка для обучения весов выдачи (склеивается с impression по renderID).
        var event = makeEvent(.redeem, category: nil, renderID: lastRenderID)
        event.dealID = deal.id
        event.venueID = deal.venueID
        rankingLog.log(event)
        // Серверный счётчик redemptions делает Cloud Function по этому документу.
        Task { try? await repository.logRedemption(userID: currentUserID,
                                                    dealID: deal.id, venueID: deal.venueID) }
    }

    // MARK: - Рефералка

    /// Личный код пользователя для приглашений.
    public var referralCode: String { currentUserID }

    /// Начисляет приветственный бонус приглашённому при первом входе по чужой ссылке.
    /// Награду пригласившему раздаёт бэкенд (по событию referral_join).
    public func grantPendingReferral(bonus: BonusEngine) {
        guard !isGuest else { return }
        let d = UserDefaults.standard
        guard !d.bool(forKey: "san.referrer.credited"),
              let ref = d.string(forKey: DeepLinks.pendingReferrerKey), !ref.isEmpty,
              ref != currentUserID else { return }
        d.set(true, forKey: "san.referrer.credited")
        bonus.addFromGame(100)   // приветственный бонус приглашённому
        AnalyticsLog.log(.referralJoin, ["referrer_id": ref, "user_id": currentUserID])
        // Записываем реферал — Cloud Function начислит бонус пригласившему.
        Task { try? await repository.recordReferral(inviteeID: currentUserID, referrerID: ref) }
    }

    // MARK: - Подарочные купоны

    /// Покупает подарочный купон за бонусы и возвращает ссылку для отправки другу.
    public func createGift(_ reward: Reward, bonus: BonusEngine) -> URL? {
        guard !isGuest, bonus.spend(reward.cost) else { return nil }
        let code = "GIFT-\(UUID().uuidString.prefix(8).uppercased())"
        Task { try? await repository.createGiftCoupon(title: reward.title, code: code, fromName: currentUserName) }
        AnalyticsLog.log(.couponClaim, ["reward_id": reward.id, "gift": true])
        return DeepLinks.giftURL(code)
    }

    /// Забирает подарок по коду и кладёт купон в кошелёк получателя (с уведомлением).
    public func claimGift(code: String, into coupons: CouponStore) {
        guard !isGuest, !code.isEmpty else { return }
        Task {
            if let g = try? await repository.claimGiftCoupon(code: code) {
                coupons.addGifted(title: g.title, code: g.code)
                toastMessage = "🎁 Подарок получен — купон в «Мои купоны»!"
            } else {
                toastMessage = "Этот подарок уже забрали или ссылка недействительна"
            }
        }
    }

    /// Если есть отложенный подарок из ссылки и пользователь вошёл — забираем.
    public func claimPendingGift(into coupons: CouponStore) {
        guard !isGuest else { return }
        let d = UserDefaults.standard
        guard let code = d.string(forKey: DeepLinks.pendingGiftKey), !code.isEmpty else { return }
        d.removeObject(forKey: DeepLinks.pendingGiftKey)
        claimGift(code: code, into: coupons)
    }

    /// Забирает серверные бонусы (награды за приглашённых) при запуске.
    public func claimReferralBonuses(bonus: BonusEngine) {
        guard !isGuest else { return }
        Task {
            let total = (try? await repository.claimBonusGrants(userID: currentUserID)) ?? 0
            if total > 0 { bonus.addFromGame(total) }
        }
    }

    public func unsaveDeal(_ deal: Deal) { profile.send(.unsaveDeal(dealID: deal.id)) }

    // MARK: - Сохранённые заведения (Saved Venues)

    public var savedVenueIDs: Set<String> { profile.state.savedVenueIDs }
    private static let venuesKey = "san.savedVenues"

    public var savedVenues: [Venue] {
        savedVenueIDs.compactMap { id in venues.first { $0.id == id } }
            .sorted { $0.name < $1.name }
    }

    public func isSaved(_ venue: Venue) -> Bool { savedVenueIDs.contains(venue.id) }

    public func toggleSave(_ venue: Venue) {
        let wasSaved = profile.state.isSaved(venue.id)
        profile.send(.toggleSave(venueID: venue.id))
        guard profile.state.isSaved(venue.id) != wasSaved else { return }   // гость — ничего не изменилось
        if wasSaved {
            push.unsubscribe(topic: "venue_\(venue.id)")
        } else {
            // Подписка на новые акции этого заведения (доставку делает бэкенд-функция).
            push.subscribe(topic: "venue_\(venue.id)")
            AnalyticsLog.log(.saveDeal, ["venue_id": venue.id])
        }
    }

    public func unsaveVenue(_ venue: Venue) { profile.send(.unsaveVenue(venueID: venue.id)) }

    // MARK: - Сегодняшний специал

    /// Специалы только сохранённых заведений — для верхней ленты на Главной.
    public var savedTodaySpecials: [Venue] {
        savedVenues.filter(\.hasTodaySpecial)
    }

    // MARK: - Отзывы

    /// Отзывы для заведений хоста (агрегированный инбокс).
    public func reviews(forVenueIDs ids: Set<String>) -> [Review] {
        reviews.filter { ids.contains($0.venueID) }
    }

    /// Владелец отвечает на отзыв (виден всем на странице заведения).
    /// Хранение — в `FeedStore` (отзывы часть каталога), здесь только правило
    /// «пустой текст = снять ответ» и публикация в Firestore.
    public func setHostReply(reviewID: String, text: String) {
        let now = clock.now
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = reviews.first { $0.id == reviewID }?.hostReply
        let reply: HostReply? = trimmed.isEmpty ? nil
            : HostReply(text: trimmed, createdAt: existing?.createdAt ?? now, updatedAt: now)
        feed.setHostReply(reviewID: reviewID, reply: reply)
        Task { try? await repository.updateReviewReply(reviewID: reviewID, reply: reply) }
    }

    public func reviews(for venue: Venue) -> [Review] {
        reviews.filter { $0.venueID == venue.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Подгрузка отзывов
    //
    // Отзывы больше не приезжают все разом при старте — экран просит свои.
    // Адаптеры ниже просто пробрасывают запрос во `FeedStore` (владельца
    // каталога), чтобы вызывающим не нужно было знать про него.

    /// Карточка заведения: первая страница отзывов.
    public func loadReviews(for venue: Venue) async {
        await feed.loadReviews(forVenue: venue.id)
    }

    /// Инбокс владельца: отзывы по его заведениям.
    public func loadReviews(forVenueIDs ids: Set<String>) async {
        await feed.loadReviews(forVenueIDs: Array(ids))
    }

    /// Профиль: отзывы текущего пользователя.
    public func loadMyReviews() async {
        await feed.loadMyReviews(authorID: currentUserID)
    }

    /// Отзыв текущего пользователя для заведения в целом (без объекта).
    public func myReview(for venue: Venue) -> Review? {
        reviews.first { $0.venueID == venue.id && $0.authorID == currentUserID && $0.itemID == nil }
    }

    /// Отзыв текущего пользователя для конкретного объекта (или заведения, если itemID == nil).
    public func myReview(venueID: String, itemID: String?) -> Review? {
        reviews.first { $0.venueID == venueID && $0.authorID == currentUserID && $0.itemID == itemID }
    }

    public var myReviews: [Review] {
        reviews.filter { $0.authorID == currentUserID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Агрегированный рейтинг и число отзывов (живой расчёт + фолбэк на seed).
    public func aggregate(for venue: Venue) -> (rating: Double, count: Int) {
        let vr = reviews(for: venue)
        if vr.isEmpty {
            return (venue.rating, venue.reviewCount)
        }
        let avg = Double(vr.reduce(0) { $0 + $1.rating }) / Double(vr.count)
        return (avg, vr.count)
    }

    /// Разбивка 5★…1★ → количество.
    public func ratingBreakdown(for venue: Venue) -> [Int: Int] {
        var counts = [1: 0, 2: 0, 3: 0, 4: 0, 5: 0]
        for r in reviews(for: venue) { counts[r.rating, default: 0] += 1 }
        return counts
    }

    /// Создать или обновить отзыв. Один отзыв на (пользователь, заведение, объект).
    /// itemID == nil — отзыв о заведении в целом.
    public func saveReview(venueID: String, rating: Int, text: String, photos: [String],
                    itemID: String? = nil, itemName: String? = nil) {
        guard !isGuest else { return }
        let verified = hasVisited(venueID)
        let existing = reviews.first {
            $0.venueID == venueID && $0.authorID == currentUserID && $0.itemID == itemID
        }
        var saved = existing ?? Review(
            id: "ur_\(UUID().uuidString.prefix(8))", venueID: venueID,
            authorID: currentUserID, authorName: currentUserName,
            rating: rating, text: text, photoEmojis: [],
            createdAt: clock.now, updatedAt: clock.now, hostReply: nil,
            itemID: itemID, itemName: itemName, photos: photos,
            verifiedVisit: verified)
        saved.rating = rating
        saved.text = text
        saved.photos = photos        // URL-фото
        saved.itemName = itemName
        saved.verifiedVisit = verified
        saved.updatedAt = clock.now
        feed.upsertUserReview(saved)

        AnalyticsLog.log(.reviewPosted, ["venue_id": venueID, "rating": rating,
                                         "verified": verified])
        // Публикуем отзыв в Firestore — виден всем и хосту.
        Task { try? await repository.saveReview(saved) }
    }

    public func deleteReview(_ review: Review) {
        feed.removeReview(id: review.id)
        Task { try? await repository.deleteReview(id: review.id) }
    }

    // MARK: - Лента (v1, органическое ранжирование)

    /// Заведения выбранного города, отфильтрованные по категории и отсортированные
    /// по органическому скору. userCoord — последняя позиция (если есть).
    public func rankedFeed(category: VenueCategory?, userCoord: CLLocationCoordinate2D?) -> [Venue] {
        venuesInSelectedCity()
            .filter { category == nil || $0.category == category }
            .map { (venue: $0, score: feedScore($0, userCoord: userCoord)) }
            .sorted { $0.score > $1.score }
            .map(\.venue)
    }

    private func feedScore(_ venue: Venue, userCoord: CLLocationCoordinate2D?) -> Double {
        let agg = aggregate(for: venue)
        let distanceKm = userCoord.map {
            Ranking.haversineKm($0.latitude, $0.longitude, venue.latitude, venue.longitude)
        }
        let hour = Calendar.current.component(.hour, from: clock.now)
        return Ranking.feedScore(distanceKm: distanceKm, rating: agg.rating, reviewCount: agg.count,
                                 hasFreshDeal: allDeals(for: venue).contains(where: \.isFresh),
                                 hasTodaySpecial: venue.hasTodaySpecial,
                                 dealCount: deals(for: venue).count,
                                 timeRelevance: venue.category.timeRelevance(hour: hour),
                                 w: rankingWeights)
    }
}
