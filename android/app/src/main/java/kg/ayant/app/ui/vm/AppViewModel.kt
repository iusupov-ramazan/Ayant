package kg.ayant.app.ui.vm

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateList
import androidx.compose.runtime.mutableStateListOf
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kg.ayant.app.core.AppConfig
import kg.ayant.app.data.AnalyticsService
import kg.ayant.app.data.DataRepository
import kg.ayant.app.data.MockData
import kg.ayant.app.data.Ranking
import kg.ayant.app.data.model.City
import kg.ayant.app.data.model.Deal
import kg.ayant.app.data.model.FeedItem
import kg.ayant.app.data.model.Review
import kg.ayant.app.data.model.Venue
import kg.ayant.app.data.model.VenueCategory
import kg.ayant.app.location.LocationManager
import kotlinx.coroutines.launch
import java.util.Date
import java.util.UUID

/**
 * Global user-side app state. Mirrors AppStore.swift: feed ranking, saves,
 * reviews, aggregates and the selected city.
 *
 * DI: dependencies are constructor parameters with production defaults from [AppConfig].
 * `@JvmOverloads` generates the `(Application)`-only constructor that `viewModel()` uses,
 * while tests can inject fakes via `AppViewModel(app, repo, analytics)`.
 */
class AppViewModel @JvmOverloads constructor(
    app: Application,
    private val repository: DataRepository = AppConfig.makeDataRepository(),
    private val analytics: AnalyticsService = AppConfig.makeAnalyticsService(),
) : AndroidViewModel(app) {

    private val prefs = app.getSharedPreferences("ayant.store", 0)

    /** Log an analytics event (view/save/call/map/dealTap). Fire-and-forget. */
    fun log(metric: String, venueID: String) = analytics.log(venueID, metric)

    // Data
    var venues by mutableStateOf<List<Venue>>(emptyList())
        private set
    var deals by mutableStateOf<List<Deal>>(emptyList())
        private set
    var reviews = mutableStateListOf<Review>()
        private set
    var isLoading by mutableStateOf(false)
        private set
    var loadError by mutableStateOf<String?>(null)
        private set

    private var baseReviews: List<Review> = MockData.reviews

    // Raw repo data + host overlay (host edits win by id). Mirrors AppStore.recombine.
    private var repoVenues: List<Venue> = emptyList()
    private var repoDeals: List<Deal> = emptyList()
    private var hostVenues: List<Venue> = emptyList()
    private var hostDeals: List<Deal> = emptyList()

    /** Host side pushes its venues/deals here so they appear in the user feed. */
    fun setHostContent(venues: List<Venue>, deals: List<Deal>) {
        hostVenues = venues
        hostDeals = deals
        recombine()
    }

    private fun recombine() {
        val vmap = LinkedHashMap<String, Venue>()
        repoVenues.forEach { vmap[it.id] = it }
        hostVenues.forEach { vmap[it.id] = it }
        venues = vmap.values.toList()
        val dmap = LinkedHashMap<String, Deal>()
        repoDeals.forEach { dmap[it.id] = it }
        hostDeals.forEach { dmap[it.id] = it }
        deals = dmap.values.toList()
    }

    // Current user
    var currentUserID = "me"
    var currentUserName = "Вы"
    var isGuest by mutableStateOf(false)

    // Saved sets (persisted)
    val savedVenueIDs: SnapshotStateList<String> = mutableStateListOf()
    val favoriteDealIDs: SnapshotStateList<String> = mutableStateListOf()

    var selectedCitySlug by mutableStateOf(City.BISHKEK.id)
        private set

    init {
        savedVenueIDs.addAll(prefs.getStringSet(KEY_SAVED, emptySet()) ?: emptySet())
        favoriteDealIDs.addAll(prefs.getStringSet(KEY_FAV, emptySet()) ?: emptySet())
        selectedCitySlug = prefs.getString(KEY_CITY, City.BISHKEK.id) ?: City.BISHKEK.id
        reviews.addAll(MockData.reviews)
    }

    fun setCurrentUser(id: String?, name: String?, guest: Boolean) {
        currentUserID = id ?: "me"
        currentUserName = name ?: "Вы"
        isGuest = guest
    }

    fun load() {
        viewModelScope.launch {
            isLoading = true
            loadError = null
            try {
                repoVenues = repository.fetchVenues()
                repoDeals = repository.fetchDeals()
            } catch (e: Exception) {
                loadError = e.localizedMessage
            }
            // Never show a blank feed: if the backend read failed or returned nothing
            // (empty collection / permission denied), fall back to demo data.
            if (repoVenues.isEmpty()) {
                repoVenues = MockData.venues
                repoDeals = MockData.deals
            }
            recombine()
            baseReviews = try {
                repository.fetchReviews().ifEmpty { MockData.reviews }
            } catch (e: Exception) {
                MockData.reviews
            }
            mergeReviews()
            isLoading = false
        }
    }

    private fun mergeReviews() {
        val combined = baseReviews.toMutableList()
        val baseIDs = combined.map { it.id }.toSet()
        // keep locally-authored reviews not present in base
        reviews.filter { it.authorID == currentUserID && it.id !in baseIDs }
            .forEach { combined.add(it) }
        reviews.clear()
        reviews.addAll(combined)
    }

    // MARK: - City

    val selectedCity: City get() = MockData.city(selectedCitySlug)

    fun setCity(slug: String) {
        selectedCitySlug = slug
        prefs.edit().putString(KEY_CITY, slug).apply()
    }

    fun venuesInSelectedCity(): List<Venue> =
        venues.filter { it.citySlug == selectedCitySlug && it.isApproved && !it.isPaused }

    fun rankedVenues(category: VenueCategory? = null): List<Venue> =
        venuesInSelectedCity()
            .filter { category == null || it.category == category }
            .sortedByDescending { venueScore(it) }

    // MARK: - Ranking

    fun venueScore(v: Venue): Double {
        val agg = aggregate(v)
        val activeDeals = deals.count { it.venueID == v.id && it.isActive }
        return Ranking.venueScore(
            rating = agg.first, reviewCount = agg.second, savedByCount = v.savedByCount,
            isVerified = v.isVerified, hasTodaySpecial = v.hasTodaySpecial,
            isOpenNow = v.isOpenNow, activeDealCount = activeDeals,
        )
    }

    fun dealScore(d: Deal): Double {
        val base = venue(forDeal = d)?.let { venueScore(it) } ?: 0.0
        val days = d.startDate?.let { (Date().time - it.time) / 86_400_000.0 }
        return Ranking.dealScore(base, d.isFresh, days)
    }

    // MARK: - Deals

    val activeDeals: List<Deal>
        get() = deals.filter { it.isActive }.sortedBy { it.validUntil }

    fun deals(forVenue: Venue): List<Deal> =
        deals.filter { it.venueID == forVenue.id && it.isActive }

    fun allDeals(forVenue: Venue): List<Deal> = deals.filter { it.venueID == forVenue.id }

    fun feedDeals(category: VenueCategory?): List<Deal> {
        val cityVenues = venuesInSelectedCity().filter { category == null || it.category == category }
        val ids = cityVenues.map { it.id }.toSet()
        return deals.filter { it.isActive && ids.contains(it.venueID) }
            .sortedByDescending { dealScore(it) }
    }

    /** Boosted venues in rotation (for sponsored cards in the feed). Mirrors boostedVenuesRotated. */
    fun boostedVenuesRotated(category: VenueCategory?): List<Venue> {
        val rot = (System.currentTimeMillis() / 1_800_000).toInt()   // rotate every 30 min
        return venuesInSelectedCity()
            .filter { (category == null || it.category == category) && it.isBoosted }
            .sortedBy { it.id.hashCode() + rot }
    }

    /** Mixed feed: active deals with sponsored venue cards inserted at the 4th, 9th… slot. */
    fun feedItems(category: VenueCategory?): List<FeedItem> =
        Ranking.feed(feedDeals(category), boostedVenuesRotated(category))

    fun venue(forDeal: Deal): Venue? = venues.firstOrNull { it.id == forDeal.venueID }
    fun venue(id: String): Venue? = venues.firstOrNull { it.id == id }

    // MARK: - Saved venues

    val savedVenues: List<Venue>
        get() = savedVenueIDs.mapNotNull { id -> venues.firstOrNull { it.id == id } }
            .sortedBy { it.name }

    fun isSaved(v: Venue) = savedVenueIDs.contains(v.id)

    fun toggleSave(v: Venue) {
        if (isGuest) return
        if (savedVenueIDs.contains(v.id)) {
            savedVenueIDs.remove(v.id)
            kg.ayant.app.push.Push.unsubscribeVenue(v.id)
        } else {
            savedVenueIDs.add(v.id)
            kg.ayant.app.push.Push.subscribeVenue(v.id)   // new deals at this venue
        }
        persistSaved()
    }

    fun unsaveVenue(v: Venue) { savedVenueIDs.remove(v.id); persistSaved() }

    val savedTodaySpecials: List<Venue> get() = savedVenues.filter { it.hasTodaySpecial }

    // MARK: - Favorite deals

    val favoriteDeals: List<Deal>
        get() = favoriteDealIDs.mapNotNull { id -> deals.firstOrNull { it.id == id } }
            .filter { it.isActive }.sortedBy { it.validUntil }

    fun isFavorite(d: Deal) = favoriteDealIDs.contains(d.id)

    fun toggleFavorite(d: Deal) {
        if (isGuest) return
        if (favoriteDealIDs.contains(d.id)) favoriteDealIDs.remove(d.id) else favoriteDealIDs.add(d.id)
        persistFav()
    }

    fun unsaveDeal(d: Deal) { favoriteDealIDs.remove(d.id); persistFav() }

    // MARK: - Reviews

    fun reviews(forVenue: Venue): List<Review> =
        reviews.filter { it.venueID == forVenue.id }.sortedByDescending { it.createdAt }

    fun myReviews(): List<Review> =
        reviews.filter { it.authorID == currentUserID }.sortedByDescending { it.updatedAt }

    /** Reviews across a set of venues (host inbox). */
    fun reviews(forVenueIDs: Set<String>): List<Review> = reviews.filter { it.venueID in forVenueIDs }

    /** Owner replies to a review (visible to all on the venue page). Write-through to Firestore. */
    fun setHostReply(reviewID: String, text: String) {
        val i = reviews.indexOfFirst { it.id == reviewID }
        if (i < 0) return
        val trimmed = text.trim()
        val now = Date()
        reviews[i] = reviews[i].copy(
            hostReply = if (trimmed.isEmpty()) null
            else kg.ayant.app.data.model.HostReply(trimmed, reviews[i].hostReply?.createdAt ?: now, now)
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
    suspend fun claimGift(code: String): kg.ayant.app.data.GiftInfo? =
        if (isGuest || code.isEmpty()) null else runCatching { repository.claimGiftCoupon(code) }.getOrNull()

    fun myReview(venueID: String, itemID: String?): Review? =
        reviews.firstOrNull { it.venueID == venueID && it.authorID == currentUserID && it.itemID == itemID }

    /** Live rating + count with fallback to seed values. */
    fun aggregate(v: Venue): Pair<Double, Int> {
        val vr = reviews(forVenue = v)
        if (vr.isEmpty()) return v.rating to v.reviewCount
        val avg = vr.sumOf { it.rating }.toDouble() / vr.size
        return avg to vr.size
    }

    fun ratingBreakdown(v: Venue): Map<Int, Int> {
        val counts = mutableMapOf(1 to 0, 2 to 0, 3 to 0, 4 to 0, 5 to 0)
        for (r in reviews(forVenue = v)) counts[r.rating] = (counts[r.rating] ?: 0) + 1
        return counts
    }

    fun saveReview(venueID: String, rating: Int, text: String, itemID: String? = null, itemName: String? = null) {
        if (isGuest) return
        val idx = reviews.indexOfFirst {
            it.venueID == venueID && it.authorID == currentUserID && it.itemID == itemID
        }
        if (idx >= 0) {
            reviews[idx] = reviews[idx].copy(rating = rating, text = text, itemName = itemName, updatedAt = Date())
        } else {
            reviews.add(
                Review(
                    id = "ur_${UUID.randomUUID().toString().take(8)}",
                    venueID = venueID, authorID = currentUserID, authorName = currentUserName,
                    rating = rating, text = text, createdAt = Date(), updatedAt = Date(),
                    itemID = itemID, itemName = itemName,
                )
            )
        }
        viewModelScope.launch { runCatching { repository.saveReview(reviews[reviews.indexOfLast { it.venueID == venueID && it.authorID == currentUserID && it.itemID == itemID }]) } }
    }

    fun deleteReview(review: Review) {
        reviews.removeAll { it.id == review.id }
        viewModelScope.launch { runCatching { repository.deleteReview(review.id) } }
    }

    // MARK: - Feed (organic ranking with distance)

    fun rankedFeed(category: VenueCategory?, location: LocationManager): List<Venue> =
        venuesInSelectedCity()
            .filter { category == null || it.category == category }
            .sortedByDescending { feedScore(it, location) }

    private fun feedScore(v: Venue, location: LocationManager): Double {
        val agg = aggregate(v)
        return Ranking.feedScore(
            distanceKm = location.distanceKm(v.latitude, v.longitude),
            rating = agg.first, reviewCount = agg.second,
            hasFreshDeal = allDeals(forVenue = v).any { it.isFresh },
            hasTodaySpecial = v.hasTodaySpecial,
            dealCount = deals(forVenue = v).size,
        )
    }

    private fun persistSaved() {
        prefs.edit().putStringSet(KEY_SAVED, savedVenueIDs.toSet()).apply()
    }
    private fun persistFav() {
        prefs.edit().putStringSet(KEY_FAV, favoriteDealIDs.toSet()).apply()
    }

    companion object {
        private const val KEY_SAVED = "san.savedVenues"
        private const val KEY_FAV = "san.favorites"
        private const val KEY_CITY = "san.city"
    }
}
