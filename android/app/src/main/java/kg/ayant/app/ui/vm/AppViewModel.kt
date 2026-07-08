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
import kg.ayant.app.data.MockData
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
import kotlin.math.ln
import kotlin.math.min

/**
 * Global user-side app state. Mirrors AppStore.swift: feed ranking, saves,
 * reviews, aggregates and the selected city.
 */
class AppViewModel(app: Application) : AndroidViewModel(app) {

    private val prefs = app.getSharedPreferences("ayant.store", 0)
    private val repository = AppConfig.makeDataRepository()

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
                venues = repository.fetchVenues()
                deals = repository.fetchDeals()
            } catch (e: Exception) {
                loadError = e.localizedMessage
            }
            baseReviews = try {
                repository.fetchReviews()
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
        var s = 0.0
        s += agg.first * 2.0
        s += ln(agg.second + 1.0) * 1.5
        s += ln(v.savedByCount + 1.0) * 1.0
        if (v.isVerified) s += 3.0
        if (v.hasTodaySpecial) s += 1.5
        if (v.isOpenNow) s += 1.0
        val activeDeals = deals.count { it.venueID == v.id && it.isActive }
        s += min(activeDeals.toDouble(), 5.0) * 0.8
        return s
    }

    fun dealScore(d: Deal): Double {
        var s = venue(forDeal = d)?.let { venueScore(it) } ?: 0.0
        if (d.isFresh) s += 6.0
        d.startDate?.let { start ->
            val days = (Date().time - start.time) / 86_400_000.0
            s += maxOf(0.0, 10 - days)
        }
        return s
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

    /** Sponsored venue cards are inserted at the 4th, 9th… positions (feedItems). */
    fun feedItems(category: VenueCategory?): List<FeedItem> {
        val feed = feedDeals(category)
        return feed.map { FeedItem.DealItem(it) }
    }

    fun venue(forDeal: Deal): Venue? = venues.firstOrNull { it.id == forDeal.venueID }
    fun venue(id: String): Venue? = venues.firstOrNull { it.id == id }

    // MARK: - Saved venues

    val savedVenues: List<Venue>
        get() = savedVenueIDs.mapNotNull { id -> venues.firstOrNull { it.id == id } }
            .sortedBy { it.name }

    fun isSaved(v: Venue) = savedVenueIDs.contains(v.id)

    fun toggleSave(v: Venue) {
        if (isGuest) return
        if (savedVenueIDs.contains(v.id)) savedVenueIDs.remove(v.id) else savedVenueIDs.add(v.id)
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
        var score = 0.0
        location.distanceKm(v.latitude, v.longitude)?.let { km ->
            score += maxOf(0.0, 5 - km) * 3.0
        }
        val agg = aggregate(v)
        score += agg.first * ln(maxOf(agg.second, 1) + 1.0) * 1.5
        if (allDeals(forVenue = v).any { it.isFresh }) score += 4
        if (v.hasTodaySpecial) score += 4
        score += deals(forVenue = v).size * 0.5
        return score
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
