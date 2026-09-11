package kg.ayant.app.ui.vm

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kg.ayant.app.domain.contract.AnalyticsService
import kg.ayant.app.domain.Clock
import kg.ayant.app.domain.SystemClock
import kg.ayant.app.domain.DataRepository
import kg.ayant.app.domain.MockData
import kg.ayant.app.domain.FeedBuilder
import kg.ayant.app.domain.FeedCatalog
import kg.ayant.app.domain.FeedIntent
import kg.ayant.app.domain.VenueRating
import kg.ayant.app.domain.ProfileIntent
import kg.ayant.app.domain.FeedState
import kg.ayant.app.domain.ProfileState
import kg.ayant.app.domain.Ranking
import kg.ayant.app.domain.ReviewStats
import kg.ayant.app.domain.RankingWeights
import kg.ayant.app.domain.RankingEvent
import kg.ayant.app.domain.contract.RankingEventService
import kg.ayant.app.domain.RankingEventType
import kg.ayant.app.domain.RankingItemFeatures
import kg.ayant.app.domain.model.City
import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.FeedItem
import kg.ayant.app.domain.model.Review
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenueCategory
import kg.ayant.app.domain.GiftInfo
import kg.ayant.app.domain.contract.DistanceSource
import kg.ayant.app.domain.contract.PushService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.Calendar
import java.util.Date
import java.util.UUID

/**
 * Global user-side app state. Mirrors AppStore.swift: feed ranking, saves,
 * reviews, aggregates and the selected city.
 *
 * DI: зависимости — параметры конструктора; реальные подставляет композиционный
 * корень (`AyantViewModels` в app-слое), тесты — свои подделки.
 * `@JvmOverloads` generates the `(Application)`-only constructor that `viewModel()` uses,
 * while tests can inject fakes via `AppViewModel(app, repo, analytics)`.
 */
/** Сессия пользователя и выбранный город — то немногое, чем ещё владеет AppViewModel. */
data class AppSessionState(
    val isGuest: Boolean = false,
    val citySlug: String = City.BISHKEK.id,
)

class AppViewModel @JvmOverloads constructor(
    app: Application,
    /**
     * Источник «сейчас». Ниже слоя UI системное время напрямую не читаем —
     * иначе логика не воспроизводится в тесте (см. [Clock] в домене).
     */
    private val clock: Clock = SystemClock,
    private val repository: DataRepository,
    private val analytics: AnalyticsService,
    private val rankingLog: RankingEventService,
    private val push: PushService,
) : AndroidViewModel(app) {

    private val prefs = app.getSharedPreferences("ayant.store", 0)

    /** Log an analytics event (view/save/call/map/dealTap). Fire-and-forget. */
    fun log(metric: String, venueID: String) = analytics.log(venueID, metric)

    // Session/render ids for stitching impression → tap/redeem in the ranking log.
    val sessionID: String = UUID.randomUUID().toString()
    private var lastRenderID: String = UUID.randomUUID().toString()
    private var lastImpressionSignature = ""

    /** Ranking weights: default → overridden by published (config/rankingWeights) in
     *  load(). Learned offline from the rankingEvents log; see ml/README.md. */
    private var rankingWeights = RankingWeights.DEFAULT

    /**
     * Каталог переехал в [FeedViewModel] — он владеет загрузкой, оверлеем хоста и
     * отзывами. Здесь остались адаптеры, чтобы поиск, избранное и карточка
     * заведения продолжали работать без правок.
     */
    val venues: List<Venue> get() = feed?.catalogVenues ?: emptyList()
    val deals: List<Deal> get() = feed?.catalogDeals ?: emptyList()
    val reviews: List<Review> get() = feed?.reviews ?: emptyList()
    val isLoading: Boolean get() = feed?.state?.value?.catalog?.isLoading ?: false
    val loadError: String? get() = feed?.loadError

    /** Host side pushes its venues/deals here so they appear in the user feed. */
    fun setHostContent(venues: List<Venue>, deals: List<Deal>) {
        feed?.setHostContent(venues, deals)
    }

    /**
     * Стор ленты. `AppViewModel` остаётся владельцем загрузки каталога (его же
     * читают поиск, избранное и карточка заведения) и публикует снимок сюда —
     * второй раз Firestore не читается.
     */
    private var feed: FeedViewModel? = null

    /**
     * Наблюдаемые состояния владельцев данных.
     *
     * Адаптеры ниже (`venues`, `savedVenues`, `aggregate`, `reviews`) — обычные
     * геттеры поверх `state.value` ленты и профиля: Compose про них ничего не
     * знает и сам не перерисует экран. Поэтому экран, который ими пользуется,
     * подписывается на эти потоки — тогда после загрузки каталога или смены
     * сохранённого он перечитает адаптеры уже с новыми значениями.
     */
    private val _feedState = MutableStateFlow(FeedState())
    val feedState: StateFlow<FeedState> = _feedState.asStateFlow()

    private val _profileFlow = MutableStateFlow(ProfileState())
    val profileFlow: StateFlow<ProfileState> = _profileFlow.asStateFlow()

    /** Связывает ленту: с этого момента каждый пересбор каталога уезжает в неё. */
    fun bindFeed(feed: FeedViewModel) {
        this.feed = feed
        viewModelScope.launch { feed.state.collect { _feedState.value = it } }
        feed.send(FeedIntent.SelectCity(selectedCitySlug))
        feed.currentUserID = currentUserID
    }

    private fun publishCatalog() {
        feed?.send(FeedIntent.SetCatalog(catalogSnapshot()))
    }

    // Current user
    var currentUserID = "me"
    var currentUserName = "Вы"
    /** Сессия и город — `StateFlow`, а не `mutableStateOf` (§4 спеки). */
    private val _session = MutableStateFlow(AppSessionState())
    val session: StateFlow<AppSessionState> = _session.asStateFlow()

    var isGuest: Boolean
        get() = _session.value.isGuest
        set(v) { _session.update { it.copy(isGuest = v) } }

    /**
     * Личная библиотека переехала в [ProfileViewModel] — он владеет множествами
     * и их персистентностью. Здесь остались адаптеры, чтобы вызовы по приложению
     * не пришлось править разом.
     */
    private var profile: ProfileViewModel? = null

    /** Связывает профиль: с этого момента сохранённое/избранное живёт там. */
    fun bindProfile(profile: ProfileViewModel) {
        this.profile = profile
        viewModelScope.launch { profile.state.collect { _profileFlow.value = it } }
        profile.send(ProfileIntent.SetUser(currentUserID, currentUserName, isGuest))
    }

    private val profileState get() = profile?.state?.value ?: ProfileState()

    val savedVenueIDs: Set<String> get() = profileState.savedVenueIDs
    val favoriteDealIDs: Set<String> get() = profileState.favoriteDealIDs

    var selectedCitySlug: String
        get() = _session.value.citySlug
        private set(v) { _session.update { it.copy(citySlug = v) } }

    init {
        selectedCitySlug = prefs.getString(KEY_CITY, City.BISHKEK.id) ?: City.BISHKEK.id
    }

    fun setCurrentUser(id: String?, name: String?, guest: Boolean) {
        currentUserID = id ?: "me"
        currentUserName = name ?: "Вы"
        isGuest = guest
        feed?.currentUserID = currentUserID
        profile?.send(ProfileIntent.SetUser(currentUserID, currentUserName, isGuest))
    }

    fun load() { feed?.load() }

    // MARK: - City

    val selectedCity: City get() = MockData.city(selectedCitySlug)

    fun setCity(slug: String) {
        selectedCitySlug = slug
        feed?.send(FeedIntent.SelectCity(slug))
        prefs.edit().putString(KEY_CITY, slug).apply()
    }

    fun venuesInSelectedCity(): List<Venue> =
        venues.filter { it.citySlug == selectedCitySlug && it.isApproved && !it.isPaused }

    fun rankedVenues(category: VenueCategory? = null): List<Venue> =
        FeedBuilder.rankedVenues(catalogSnapshot(), selectedCitySlug, category,
            rankingWeights, clock.nowMs)

    // MARK: - Ranking (делегируется чистому FeedBuilder из домена)

    /**
     * Снимок для чистых функций ранжирования. Пока `AppViewModel` владеет каталогом,
     * собираем его на месте; после перевода `venue`/`profile` на новую форму снимок
     * будет жить в [FeedViewModel] и собираться один раз.
     */
    private fun catalogSnapshot(): FeedCatalog {
        val ratings = venues.associate { v ->
            val agg = aggregate(v)
            v.id to VenueRating(agg.first, agg.second)
        }
        return FeedCatalog(venues.toList(), deals.toList(), ratings)
    }

    fun venueScore(v: Venue): Double =
        FeedBuilder.venueScore(v, catalogSnapshot(), rankingWeights, clock.nowMs)

    fun dealScore(d: Deal): Double =
        FeedBuilder.dealScore(d, catalogSnapshot(), rankingWeights, clock.nowMs)

    // MARK: - Deals

    val activeDeals: List<Deal>
        get() = deals.filter { it.isActive }.sortedBy { it.validUntil }

    fun deals(forVenue: Venue): List<Deal> =
        deals.filter { it.venueID == forVenue.id && it.isActive }

    fun allDeals(forVenue: Venue): List<Deal> = deals.filter { it.venueID == forVenue.id }

    fun feedDeals(category: VenueCategory?): List<Deal> =
        FeedBuilder.rankedDeals(catalogSnapshot(), selectedCitySlug, category,
            rankingWeights, clock.nowMs)

    /** Boosted venues in rotation (for sponsored cards in the feed). */
    fun boostedVenuesRotated(category: VenueCategory?): List<Venue> =
        FeedBuilder.boostedVenues(catalogSnapshot(), selectedCitySlug, category,
            clock.nowMs)

    /** Mixed feed: active deals with sponsored venue cards inserted at the 4th, 9th… slot. */
    fun feedItems(category: VenueCategory?): List<FeedItem> =
        FeedBuilder.items(catalogSnapshot(), selectedCitySlug, category,
            rankingWeights, clock.nowMs)

    fun venue(forDeal: Deal): Venue? = venues.firstOrNull { it.id == forDeal.venueID }
    fun venue(id: String): Venue? = venues.firstOrNull { it.id == id }

    // MARK: - Ranking event log (learning-to-rank)

    /** Rank-time feature snapshot of a deal (see [RankingItemFeatures]). Reads the
     *  same signals as [dealScore] so the log doesn't drift from the score. */
    private fun rankingFeatures(deal: Deal, position: Int, location: DistanceSource?): RankingItemFeatures {
        val v = venue(forDeal = deal)
        val agg = v?.let { aggregate(it) } ?: (0.0 to 0)
        val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        val now = clock.nowMs
        return RankingItemFeatures(
            dealID = deal.id, venueID = deal.venueID, position = position, kind = "deal",
            score = dealScore(deal),
            bayesRating = Ranking.bayesianRating(agg.first, agg.second),
            reviewCount = agg.second, savedByCount = v?.savedByCount ?: 0,
            isVerified = v?.isVerified ?: false, hasTodaySpecial = v?.hasTodaySpecial ?: false,
            activeDealCount = v?.let { ven -> deals.count { it.venueID == ven.id && it.isActive } } ?: 0,
            isFresh = deal.isFresh,
            daysSinceStart = deal.startDate?.let { (now - it.time) / 86_400_000.0 },
            discountPercent = deal.effectiveDiscountPercent,
            hoursUntilExpiry = (deal.validUntil.time - now) / 3_600_000.0,
            distanceKm = v?.let { location?.distanceKm(it.latitude, it.longitude) },
            timeRelevance = v?.category?.timeRelevance(hour) ?: 0.5,
        )
    }

    private fun makeEvent(type: RankingEventType, category: VenueCategory?, renderID: String): RankingEvent {
        val cal = Calendar.getInstance()
        return RankingEvent(
            type = type, userID = currentUserID, sessionID = sessionID, renderID = renderID,
            citySlug = selectedCitySlug, category = category?.rawValue,
            hour = cal.get(Calendar.HOUR_OF_DAY),
            weekday = (cal.get(Calendar.DAY_OF_WEEK) + 5) % 7,   // 0 = Monday
            clientTs = clock.nowMs.toDouble(),
        )
    }

    /** Logs a feed impression (the shown slate with rank-time features). Deduped by
     *  signature (category + ordered ids) so recompositions don't spam events.
     *  Call from the feed screen's LaunchedEffect. */
    fun logFeedImpression(category: VenueCategory?, location: DistanceSource?, limit: Int = 20) {
        val slate = feedDeals(category).take(limit)
        val signature = "${category?.rawValue ?: "*"}|${slate.joinToString(",") { it.id }}"
        if (signature == lastImpressionSignature || slate.isEmpty()) return
        lastImpressionSignature = signature
        lastRenderID = UUID.randomUUID().toString()
        val items = slate.mapIndexed { idx, d -> rankingFeatures(d, idx, location) }
        rankingLog.log(makeEvent(RankingEventType.IMPRESSION, category, lastRenderID).copy(items = items))
    }

    /** Logs a deal open (tap). [position] is the rank if known. */
    fun logRankingTap(deal: Deal, position: Int? = null, category: VenueCategory? = null) {
        rankingLog.log(
            makeEvent(RankingEventType.TAP, category, lastRenderID)
                .copy(dealID = deal.id, venueID = deal.venueID, position = position),
        )
    }

    // MARK: - Saved venues

    val savedVenues: List<Venue>
        get() = profileState.savedVenues(catalogSnapshot()).sortedBy { it.name }

    fun isSaved(v: Venue) = profileState.isSaved(v.id)

    fun toggleSave(v: Venue) {
        val wasSaved = profileState.isSaved(v.id)
        profile?.send(ProfileIntent.ToggleSave(v.id))
        if (profileState.isSaved(v.id) == wasSaved) return   // гость — ничего не изменилось
        // Подписка на push-тему заведения — через контракт: стор не знает ни про
        // FCM, ни про фасад `Push` из app-слоя.
        if (wasSaved) push.unsubscribeVenue(v.id)
        else push.subscribeVenue(v.id)     // new deals at this venue
    }

    fun unsaveVenue(v: Venue) { profile?.send(ProfileIntent.UnsaveVenue(v.id)) }

    val savedTodaySpecials: List<Venue> get() = savedVenues.filter { it.hasTodaySpecial }

    // MARK: - Favorite deals

    val favoriteDeals: List<Deal>
        get() = profileState.favoriteDeals(catalogSnapshot(), clock.nowMs)

    fun isFavorite(d: Deal) = profileState.isFavorite(d.id)

    fun toggleFavorite(d: Deal) { profile?.send(ProfileIntent.ToggleFavorite(d.id)) }

    fun unsaveDeal(d: Deal) { profile?.send(ProfileIntent.UnsaveDeal(d.id)) }

    // MARK: - Отметки «нравится»
    //
    // Отдельно от «Сохранённого»: закладка кладёт акцию в личную библиотеку,
    // сердечко — только реакция. Хранится на устройстве, поэтому доступно и
    // гостю (сохранение — нет, оно привязано к аккаунту).

    fun isLiked(d: Deal) = profileState.isLiked(d.id)

    fun toggleLike(d: Deal) { profile?.send(ProfileIntent.ToggleLike(d.id)) }

    // MARK: - Reviews

    fun reviews(forVenue: Venue): List<Review> =
        reviews.filter { it.venueID == forVenue.id }.sortedByDescending { it.createdAt }

    fun myReviews(): List<Review> =
        reviews.filter { it.authorID == currentUserID }.sortedByDescending { it.updatedAt }

    /** Reviews across a set of venues (host inbox). */
    fun reviews(forVenueIDs: Set<String>): List<Review> = reviews.filter { it.venueID in forVenueIDs }

    // --- Подгрузка отзывов ---------------------------------------------------
    //
    // Отзывы больше не приезжают все разом при старте — экран просит свои.
    // Адаптеры ниже пробрасывают запрос во `FeedViewModel` (владельца каталога),
    // чтобы вызывающим не нужно было знать про него. Зеркалит `AppStore` на iOS.

    /** Карточка заведения: первая страница отзывов. */
    fun loadReviews(forVenue: Venue) { feed?.loadReviewsForVenue(forVenue.id) }

    /** Инбокс владельца: отзывы по его заведениям. */
    fun loadReviews(forVenueIDs: Set<String>) { feed?.loadReviewsForVenues(forVenueIDs.toList()) }

    /** Профиль: отзывы текущего пользователя. */
    fun loadMyReviews() { feed?.loadMyReviews(currentUserID) }

    /** Owner replies to a review (visible to all on the venue page). Write-through to Firestore. */
    fun setHostReply(reviewID: String, text: String) {
        val i = reviews.indexOfFirst { it.id == reviewID }
        if (i < 0) return
        val trimmed = text.trim()
        val now = Date(clock.nowMs)
        // Хранение — в FeedViewModel (отзывы часть каталога); здесь только правило
        // «пустой текст = снять ответ» и публикация в Firestore.
        feed?.upsertUserReview(
            reviews[i].copy(
                hostReply = if (trimmed.isEmpty()) null
                else kg.ayant.app.domain.model.HostReply(trimmed, reviews[i].hostReply?.createdAt ?: now, now)
            )
        )
        viewModelScope.launch { runCatching { repository.updateReviewReply(reviewID, trimmed.ifEmpty { null }) } }
    }

    // MARK: - Referral + gift + redemption (backend)

    /** Personal referral code = user id. */
    val referralCode: String get() = currentUserID

    /** Records a referral (backend rewards the inviter). */
    fun recordReferral(referrerID: String) {
        if (isGuest || referrerID.isEmpty() || referrerID == currentUserID) return
        viewModelScope.launch { runCatching { repository.recordReferral(currentUserID, referrerID) } }
    }

    /** Claims server-granted bonuses (referral rewards). Returns total to add to the balance. */
    suspend fun claimBonusGrantsTotal(): Int =
        if (isGuest) 0 else runCatching { repository.claimBonusGrants(currentUserID) }.getOrDefault(0)

    /** Creates a gift coupon doc so the receiver's link can claim it. */
    fun createGiftBackend(title: String, code: String, fromName: String) {
        viewModelScope.launch { runCatching { repository.createGiftCoupon(title, code, fromName) } }
    }

    /** Claims a gift by code (once). Returns title+code or null. */
    suspend fun claimGift(code: String): GiftInfo? =
        if (isGuest || code.isEmpty()) null else runCatching { repository.claimGiftCoupon(code) }.getOrNull()

    fun myReview(venueID: String, itemID: String?): Review? =
        reviews.firstOrNull { it.venueID == venueID && it.authorID == currentUserID && it.itemID == itemID }

    /** Live rating + count with fallback to seed values. Делегирует чистому ReviewStats. */
    fun aggregate(v: Venue): Pair<Double, Int> =
        ReviewStats.aggregate(reviews(forVenue = v), v.rating, v.reviewCount)

    fun ratingBreakdown(v: Venue): Map<Int, Int> =
        ReviewStats.ratingBreakdown(reviews(forVenue = v))

    fun saveReview(venueID: String, rating: Int, text: String, itemID: String? = null, itemName: String? = null) {
        if (isGuest) return
        val idx = reviews.indexOfFirst {
            it.venueID == venueID && it.authorID == currentUserID && it.itemID == itemID
        }
        val saved = if (idx >= 0) {
            reviews[idx].copy(rating = rating, text = text, itemName = itemName, updatedAt = Date(clock.nowMs))
        } else {
            Review(
                id = "ur_${UUID.randomUUID().toString().take(8)}",
                venueID = venueID, authorID = currentUserID, authorName = currentUserName,
                rating = rating, text = text, createdAt = Date(clock.nowMs), updatedAt = Date(clock.nowMs),
                itemID = itemID, itemName = itemName,
            )
        }
        feed?.upsertUserReview(saved)
        viewModelScope.launch { runCatching { repository.saveReview(saved) } }
    }

    fun deleteReview(review: Review) {
        feed?.removeReview(review.id)
        viewModelScope.launch { runCatching { repository.deleteReview(review.id) } }
    }

    // MARK: - Feed (organic ranking with distance)

    fun rankedFeed(category: VenueCategory?, location: DistanceSource): List<Venue> =
        venuesInSelectedCity()
            .filter { category == null || it.category == category }
            .sortedByDescending { feedScore(it, location) }

    private fun feedScore(v: Venue, location: DistanceSource): Double {
        val agg = aggregate(v)
        val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        return Ranking.feedScore(
            distanceKm = location.distanceKm(v.latitude, v.longitude),
            rating = agg.first, reviewCount = agg.second,
            hasFreshDeal = allDeals(forVenue = v).any { it.isFresh },
            hasTodaySpecial = v.hasTodaySpecial,
            dealCount = deals(forVenue = v).size,
            timeRelevance = v.category.timeRelevance(hour),
            w = rankingWeights,
        )
    }


    companion object {
        private const val KEY_CITY = "san.city"
    }
}
