package kg.ayant.app.ui.vm

import kg.ayant.app.domain.SystemClock
import kg.ayant.app.domain.Clock
import android.app.Application
import androidx.lifecycle.AndroidViewModel
import kg.ayant.app.domain.model.City
import kg.ayant.app.domain.contract.AnalyticsService
import kg.ayant.app.domain.contract.PushService
import kg.ayant.app.domain.HostState
import kg.ayant.app.domain.HostIntent
import kg.ayant.app.domain.HostForms
import kg.ayant.app.domain.BusinessInfo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kg.ayant.app.domain.model.AdCampaign
import kg.ayant.app.domain.model.HostDealDTO
import kg.ayant.app.domain.model.HostProfile
import kg.ayant.app.domain.model.HostVenueDTO
import kg.ayant.app.domain.model.VenueCategory
import kg.ayant.app.domain.model.VenueItem
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.Date
import java.util.UUID

/**
 * Host (business) side state. Mirrors HostStore.swift — profile, venues, deals,
 * campaigns, CRUD; pushes host content into the user feed via AppViewModel.
 * Persists locally (kotlinx.serialization JSON in prefs) keyed by owner id.
 *
 * DI: [analytics] is a constructor param with a production default; `@JvmOverloads`
 * keeps the `(Application)` constructor that `viewModel()` needs while letting tests
 * inject a fake.
 */
class HostViewModel @JvmOverloads constructor(
    app: Application,
    private val analytics: AnalyticsService,
    private val push: PushService,
    /** «Сейчас» — из [clock]: иначе время-зависимую логику не проверить тестом. */
    private val clock: Clock = SystemClock,
) : AndroidViewModel(app) {

    private val prefs = app.getSharedPreferences("ayant.host", 0)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    /** Всё состояние кабинета одним значением; вход — только [send]. */
    private val _state = MutableStateFlow(HostState())
    val state: StateFlow<HostState> = _state.asStateFlow()

    // Внутренние алиасы: тело VM работает с полями состояния как раньше.
    private var profile: HostProfile?
        get() = _state.value.profile
        set(v) { _state.update { it.copy(profile = v) } }
    private val venues: MutableList<HostVenueDTO>
        get() = _state.value.venues.toMutableList()
    private val deals: MutableList<HostDealDTO>
        get() = _state.value.deals.toMutableList()
    private val campaigns: MutableList<AdCampaign>
        get() = _state.value.campaigns.toMutableList()

    private fun setVenues(v: List<HostVenueDTO>) { _state.update { it.copy(venues = v) } }
    private fun setDeals(d: List<HostDealDTO>) { _state.update { it.copy(deals = d) } }
    private fun setCampaigns(c: List<AdCampaign>) { _state.update { it.copy(campaigns = c) } }

    private var ownerID: String
        get() = _state.value.ownerID
        set(v) { _state.update { it.copy(ownerID = v) } }

    private var appVm: AppViewModel? = null

    /** Единственный вход. Читать — через [state]. */
    fun send(intent: HostIntent) {
        when (intent) {
            is HostIntent.Configure -> configure(intent.ownerID)
            is HostIntent.Sync -> { /* Android держит кабинет локально; синка нет */ }
            is HostIntent.CreateAccount ->
                createAccount(intent.businessName, intent.category, intent.phone, intent.email)
            is HostIntent.UpdateBusinessInfo -> updateBusinessInfo(intent.info)
            is HostIntent.RequestVerification -> requestVerification()
            is HostIntent.SaveVenue -> saveVenue(intent.existing, intent.fields)
            is HostIntent.TogglePause -> togglePause(intent.venueID)
            is HostIntent.SetTodaySpecial -> setTodaySpecial(intent.venueID, intent.text)
            is HostIntent.DeleteVenue -> deleteVenue(intent.id)
            is HostIntent.AddItem ->
                addItem(intent.venueID, intent.name, intent.emoji, intent.kind, intent.imageURL)
            is HostIntent.DeleteItem -> deleteItem(intent.venueID, intent.itemID)
            is HostIntent.BoostVenue -> boostVenue(intent.id, intent.until)
            is HostIntent.SaveDeal -> saveDealForm(intent.existing, intent.fields)
            is HostIntent.SetDealStatus -> setDealStatus(intent.id, intent.status.name.lowercase())
            is HostIntent.DeleteDeal -> deleteDeal(intent.id)
            is HostIntent.AddCampaign -> addCampaign(intent.campaign)
            is HostIntent.LaunchPush ->
                launchPush(intent.headline, intent.body, intent.venueID, intent.dealID)
            is HostIntent.CancelCampaign -> cancelCampaign(intent.id)
        }
    }

    /** Сборка DTO — в чистом HostForms; здесь только запись. */
    private fun saveVenue(existing: HostVenueDTO?, fields: HostForms.VenueFields) {
        val dto = HostForms.venue(existing, fields) { newVenueID() }
        if (existing == null) addVenue(dto) else updateVenue(dto)
    }

    private fun saveDealForm(existing: HostDealDTO?, fields: HostForms.DealFields) {
        saveDeal(HostForms.deal(existing, fields, Date(clock.nowMs)) { newDealID() })
    }

    private fun updateBusinessInfo(info: BusinessInfo) {
        updateBusinessInfo(
            info.businessName, info.category, info.phone, info.email,
            info.legalForm, info.legalName, info.inn,
            info.registrationAddress, info.website, info.about,
        )
    }

    val hasAccount: Boolean get() = profile != null
    val ownedVenueIDs: Set<String> get() = venues.map { it.id }.toSet()

    fun bind(app: AppViewModel) { appVm = app; pushToApp() }

    fun configure(owner: String?) {
        val newOwner = owner ?: ""
        if (newOwner == ownerID) return
        ownerID = newOwner
        reload()
    }

    // MARK: - Account

    fun createAccount(businessName: String, category: VenueCategory, phone: String, email: String) {
        profile = HostProfile(businessName, category.rawValue, phone, email)
        persistProfile()
    }

    fun updateBusinessInfo(
        businessName: String, category: VenueCategory, phone: String, email: String,
        legalForm: String, legalName: String, inn: String, regAddress: String, website: String, about: String,
    ) {
        val p = profile ?: HostProfile(businessName, category.rawValue, phone, email)
        profile = p.copy(
            businessName = businessName, categoryRaw = category.rawValue, phone = phone, email = email,
            legalForm = legalForm, legalName = legalName, inn = inn,
            registrationAddress = regAddress, website = website, about = about,
        )
        persistProfile()
    }

    fun requestVerification() {
        profile = profile?.copy(verification = kg.ayant.app.domain.model.VerificationStatus.PENDING)
        persistProfile()
    }

    // MARK: - Venues

    fun venue(id: String): HostVenueDTO? = venues.firstOrNull { it.id == id }

    fun addVenue(dto: HostVenueDTO) {
        venues.add(dto)
        persistVenues()
    }

    fun updateVenue(dto: HostVenueDTO) {
        val i = venues.indexOfFirst { it.id == dto.id }
        if (i >= 0) venues[i] = dto else venues.add(dto)
        persistVenues()
    }

    fun togglePause(id: String) {
        val i = venues.indexOfFirst { it.id == id }
        if (i >= 0) { venues[i] = venues[i].copy(isPaused = !venues[i].isPaused); persistVenues() }
    }

    fun setTodaySpecial(id: String, text: String) {
        val i = venues.indexOfFirst { it.id == id }
        if (i >= 0) { venues[i] = venues[i].copy(todaySpecial = text.trim()); persistVenues() }
    }

    fun deleteVenue(id: String) {
        venues.removeAll { it.id == id }
        deals.removeAll { it.venueID == id }
        persistVenues(); persistDeals()
    }

    fun newVenueID() = "hv_${UUID.randomUUID().toString().take(8)}"

    // MARK: - Items

    fun addItem(venueID: String, name: String, emoji: String, kind: String, imageURL: String = "") {
        val i = venues.indexOfFirst { it.id == venueID } ; if (i < 0) return
        val item = VenueItem("it_${UUID.randomUUID().toString().take(8)}", name.trim(), emoji.ifEmpty { "🍽" }, kind, imageURL.trim())
        venues[i] = venues[i].copy(items = venues[i].items + item)
        persistVenues()
    }

    fun deleteItem(venueID: String, itemID: String) {
        val i = venues.indexOfFirst { it.id == venueID } ; if (i < 0) return
        venues[i] = venues[i].copy(items = venues[i].items.filterNot { it.id == itemID })
        persistVenues()
    }

    // MARK: - Deals

    fun deals(forVenue: String): List<HostDealDTO> = deals.filter { it.venueID == forVenue }.sortedByDescending { it.startDate }

    fun saveDeal(dto: HostDealDTO) {
        val i = deals.indexOfFirst { it.id == dto.id }
        if (i >= 0) deals[i] = dto else deals.add(dto)
        persistDeals()
    }

    fun newDealID() = "hd_${UUID.randomUUID().toString().take(8)}"

    fun setDealStatus(id: String, statusRaw: String) {
        val i = deals.indexOfFirst { it.id == id }
        if (i >= 0) { deals[i] = deals[i].copy(statusRaw = statusRaw); persistDeals() }
    }

    fun deleteDeal(id: String) { deals.removeAll { it.id == id }; persistDeals() }

    // MARK: - Campaigns

    fun addCampaign(c: AdCampaign) { campaigns.add(0, c); persistCampaigns() }

    /** Queue a push campaign in Firestore; the Cloud Function (sendPushCampaign)
     *  delivers FCM to the city topic / saved-venue subscribers. Mirrors launchPush. */
    private fun launchPush(headline: String, body: String, venueID: String, dealID: String?) {
        // Запись — в слое данных (см. PushService); VM про Firestore не знает.
        push.queuePushCampaign(
            headline = headline, body = body, citySlug = City.BISHKEK.id,
            venueID = venueID, dealID = dealID, ownerID = ownerID,
        )
    }
    fun cancelCampaign(id: String) {
        val i = campaigns.indexOfFirst { it.id == id }
        if (i >= 0) { campaigns[i] = campaigns[i].copy(status = AdCampaign.Status.CANCELLED); persistCampaigns() }
    }
    fun campaignID() = "ad_${UUID.randomUUID().toString().take(8)}"

    fun boostVenue(id: String, until: Date) {
        val i = venues.indexOfFirst { it.id == id }
        if (i >= 0) { venues[i] = venues[i].copy(boostedUntil = until); persistVenues() }
    }

    // MARK: - Analytics

    /** Deterministic fallback used for instant display before/without backend data. */
    fun stat(venueID: String, metric: String, days: Int): Int {
        val seed = (venueID + metric).sumOf { it.code }
        val base = mapOf("views" to 40, "dealTaps" to 12, "saves" to 6, "calls" to 3, "maps" to 4, "redemptions" to 5)[metric] ?: 5
        return (seed % 7 + 1) * base * days / 7
    }

    /** Real stats from Firestore (empty map on error / no data). */
    suspend fun statsRemote(venueID: String, days: Int): Map<String, Int> =
        runCatching { analytics.fetchStats(venueID, days) }.getOrDefault(emptyMap())

    /** Метрики по дням — нужен графику «Аналитики»; суммы схлопывают ряд. */
    suspend fun dailyRemote(venueID: String, days: Int): Map<String, Map<String, Int>> =
        runCatching { analytics.fetchDailyStats(venueID, days) }.getOrDefault(emptyMap())

    // MARK: - Persistence

    private fun key(base: String) = if (ownerID.isEmpty()) base else "$base.$ownerID"

    private fun reload() {
        profile = loadProfile()
        venues.clear(); venues.addAll(loadVenues())
        deals.clear(); deals.addAll(loadDeals())
        campaigns.clear(); campaigns.addAll(loadCampaigns())
        pushToApp()
    }

    private fun pushToApp() {
        appVm?.setHostContent(venues.map { it.asVenue }, deals.map { it.asDeal })
    }

    private fun persistProfile() {
        prefs.edit().putString(key("profile"), profile?.let { json.encodeToString(it) }).apply()
    }
    private fun persistVenues() { prefs.edit().putString(key("venues"), json.encodeToString(venues.toList())).apply(); pushToApp() }
    private fun persistDeals() { prefs.edit().putString(key("deals"), json.encodeToString(deals.toList())).apply(); pushToApp() }
    private fun persistCampaigns() { prefs.edit().putString(key("campaigns"), json.encodeToString(campaigns.toList())).apply() }

    // --- Load (kotlinx.serialization). Any legacy/corrupt payload degrades to empty. ---

    private fun loadProfile(): HostProfile? {
        val raw = prefs.getString(key("profile"), null) ?: return null
        return runCatching { json.decodeFromString<HostProfile>(raw) }.getOrNull()
    }

    private fun loadVenues(): List<HostVenueDTO> {
        val raw = prefs.getString(key("venues"), null) ?: return emptyList()
        return runCatching { json.decodeFromString<List<HostVenueDTO>>(raw) }.getOrDefault(emptyList())
    }

    private fun loadDeals(): List<HostDealDTO> {
        val raw = prefs.getString(key("deals"), null) ?: return emptyList()
        return runCatching { json.decodeFromString<List<HostDealDTO>>(raw) }.getOrDefault(emptyList())
    }

    private fun loadCampaigns(): List<AdCampaign> {
        val raw = prefs.getString(key("campaigns"), null) ?: return emptyList()
        return runCatching { json.decodeFromString<List<AdCampaign>>(raw) }.getOrDefault(emptyList())
    }
}
