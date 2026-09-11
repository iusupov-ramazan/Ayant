package kg.ayant.app.ui.vm

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import kg.ayant.app.domain.MockData
import kg.ayant.app.domain.AppError
import kg.ayant.app.domain.DataRepository
import kg.ayant.app.domain.FeedBuilder
import kg.ayant.app.domain.FeedCatalog
import kg.ayant.app.domain.RankingWeights
import kg.ayant.app.domain.ReviewStats
import kg.ayant.app.domain.VenueRating
import kg.ayant.app.domain.model.Review
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.launch
import kg.ayant.app.domain.Clock
import kg.ayant.app.domain.FeedIntent
import kg.ayant.app.domain.FeedState
import kg.ayant.app.domain.LoadState
import kg.ayant.app.domain.SystemClock
import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.FeedItem
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenueCategory
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * ViewModel ленты — вторая фича на новой форме (после баллов): одно значение
 * состояния наружу и один вход [send].
 *
 * Что изменилось по сравнению с прежней лентой в `AppViewModel`:
 *  • порядок выдачи считает чистая `FeedBuilder` из домена, а не методы VM;
 *  • «сейчас» приходит из [Clock], поэтому лента воспроизводима в тесте —
 *    раньше скоринг звал `Date()` и `Calendar.getInstance()` прямо внутри;
 *  • загрузка и ошибка — часть состояния (`LoadState`), а не отдельные поля.
 *
 * **Владелец каталога.** Заведения, акции, отзывы и веса ранжирования грузятся
 * и живут здесь; `AppViewModel` читает их через тонкие адаптеры (`venues`,
 * `deals`, `reviews`), поэтому вызовы по приложению не менялись. Раньше
 * владельцем был `AppViewModel`, а сюда каталог приезжал намерением SetCatalog.
 *
 * Зеркалит `FeedStore.swift` на iOS.
 */
class FeedViewModel @JvmOverloads constructor(
    app: Application,
    private val clock: Clock = SystemClock,
    private val repository: DataRepository,
) : AndroidViewModel(app) {

    private val _state = MutableStateFlow(FeedState(reviews = MockData.reviews))
    val state: StateFlow<FeedState> = _state.asStateFlow()

    // Сырые слои каталога: репозиторий + оверлей хоста (правки хоста «выигрывают»).
    private var repoVenues: List<Venue> = emptyList()
    private var repoDeals: List<Deal> = emptyList()
    private var hostVenues: List<Venue> = emptyList()
    private var hostDeals: List<Deal> = emptyList()

    // Отзывы: база из репозитория + локальные пользовательские.
    //
    // ВАЖНО: это КЭШ, а не полный набор. Вся коллекция больше не выгружается
    // (см. docs/design/system-design.md §4.2) — сюда попадают только отзывы,
    // которые кто-то явно запросил: карточка заведения, инбокс владельца,
    // профиль. Поэтому рейтинг для ленты по этому списку считать НЕЛЬЗЯ:
    // он придёт неполным. Для ленты источник правды — денормализованные
    // `venue.rating`/`venue.reviewCount`, которые пишет Cloud Function.
    private var baseReviews: List<Review> = MockData.reviews
    /** Единственный владелец отзывов — состояние; отдельного списка больше нет. */
    val reviews: List<Review> get() = _state.value.reviews

    /**
     * Заведения, отзывы которых загружены ПОЛНОСТЬЮ (пришло меньше страницы —
     * значит, это всё). Только для них живой пересчёт агрегата точнее
     * денормализованного; для остальных отдаём фолбэк на документ заведения.
     *
     * Демо-набор локальный и полный, поэтому его заведения помечены сразу.
     * Заведения из Firestore сюда не попадут (другие id) и останутся на
     * денормализованном рейтинге, как и задумано.
     */
    private val fullyLoadedReviewVenueIDs: MutableSet<String> =
        MockData.reviews.map { it.venueID }.toMutableSet()

    private val _loadError = MutableStateFlow<String?>(null)
    /** Сырое сообщение ошибки загрузки; типизированная ошибка — в `state.catalog`. */
    val loadErrorFlow: StateFlow<String?> = _loadError.asStateFlow()
    val loadError: String? get() = _loadError.value
    var currentUserID: String = "me"

    /** Сырой каталог (без фильтра города/категории) — его читают поиск и избранное. */
    /**
     * Только то, что пользователю разрешено видеть: без отклонённых модерацией
     * и поставленных на паузу. Сырой каталог остаётся внутри VM — он нужен
     * сборке ленты и оверлею хоста.
     */
    val catalogVenues: List<Venue>
        get() = FeedBuilder.userVisibleVenues(_state.value.catalog.valueOrNull()?.venues ?: emptyList())
    val catalogDeals: List<Deal>
        get() {
            val catalog = _state.value.catalog.valueOrNull()
            return FeedBuilder.userVisibleDeals(catalog?.deals ?: emptyList(), catalog?.venues ?: emptyList())
        }

    fun load() {
        viewModelScope.launch {
            _loadError.value = null
            send(FeedIntent.SetLoading)
            try {
                repoVenues = repository.fetchVenues()
                repoDeals = repository.fetchDeals()
            } catch (e: Exception) {
                _loadError.value = e.localizedMessage
                send(FeedIntent.SetFailure(AppError.Network))
            }
            // Никогда не показываем пустую ленту: бэкенд молчит → демо-данные.
            if (repoVenues.isEmpty()) {
                repoVenues = MockData.venues
                repoDeals = MockData.deals
            }
            try {
                repository.fetchRankingWeights()?.let { send(FeedIntent.SetWeights(RankingWeights.from(it))) }
            } catch (_: Exception) { /* остаёмся на дефолтах */ }
            // Отзывы здесь БОЛЬШЕ НЕ ГРУЗЯТСЯ. Раньше на этом месте выгружалась
            // вся коллекция `reviews` ради двух чисел на карточке — рейтинга и
            // счётчика. Теперь их пишет на документ заведения Cloud Function
            // `aggregateReviewRating`, а сами отзывы подтягивает тот экран,
            // которому они нужны: loadReviewsForVenue / ...ForVenues / ...ByAuthor.
            mergeReviews()
            recombine()
        }
    }

    /** Хост-сторона передаёт свои заведения/акции — они появляются в ленте. */
    fun setHostContent(venues: List<Venue>, deals: List<Deal>) {
        hostVenues = venues
        hostDeals = deals
        recombine()
    }

    /** Пересобирает каталог: репозиторий + оверлей хоста + агрегаты отзывов. */
    private fun recombine() {
        val vmap = LinkedHashMap<String, Venue>()
        repoVenues.forEach { vmap[it.id] = it }
        hostVenues.forEach { vmap[it.id] = it }
        val dmap = LinkedHashMap<String, Deal>()
        repoDeals.forEach { dmap[it.id] = it }
        hostDeals.forEach { dmap[it.id] = it }

        val venues = vmap.values.toList()
        // Живой агрегат считаем ТОЛЬКО для заведений с полностью загруженными
        // отзывами. Для остальных запись не создаём — и `FeedState.aggregate`
        // берёт денормализованные `venue.rating`/`venue.reviewCount`. Иначе
        // заведение с 300 отзывами показывало бы рейтинг по первой странице из 50.
        val complete = venues.filter { it.id in fullyLoadedReviewVenueIDs }
        // Один проход по отзывам вместо фильтра всего массива на каждое заведение.
        val ratings = ReviewStats.aggregateAll(complete, _state.value.reviews)
        send(FeedIntent.SetCatalog(FeedCatalog(venues, dmap.values.toList(), ratings)))
    }

    // --- Подгрузка отзывов (заменила выгрузку всей коллекции) ----------------

    /**
     * Отзывы одного заведения — зовёт карточка заведения при открытии.
     * Если пришло меньше страницы, значит это весь набор: помечаем заведение
     * «полным», и его рейтинг дальше считается живьём, а не по документу.
     */
    fun loadReviewsForVenue(venueID: String) {
        viewModelScope.launch {
            val fetched = try {
                repository.fetchReviews(venueID, REVIEW_PAGE_SIZE)
            } catch (_: Exception) { return@launch }
            if (fetched.size < REVIEW_PAGE_SIZE) fullyLoadedReviewVenueIDs += venueID
            absorb(fetched)
        }
    }

    /** Инбокс владельца: отзывы по всем его заведениям. */
    fun loadReviewsForVenues(venueIDs: List<String>) {
        if (venueIDs.isEmpty()) return
        viewModelScope.launch {
            val fetched = try {
                repository.fetchReviews(venueIDs, REVIEW_PAGE_SIZE)
            } catch (_: Exception) { return@launch }
            absorb(fetched)
        }
    }

    /** Отзывы текущего пользователя — для профиля. */
    fun loadMyReviews(authorID: String) {
        viewModelScope.launch {
            val fetched = try {
                repository.fetchReviewsByAuthor(authorID, REVIEW_PAGE_SIZE)
            } catch (_: Exception) { return@launch }
            absorb(fetched)
        }
    }

    /**
     * Вливает пришедшую страницу в кэш: дедуп по id, свежая версия выигрывает,
     * локальные отзывы пользователя не теряются.
     */
    private fun absorb(fetched: List<Review>) {
        if (fetched.isEmpty()) return
        val incoming = fetched.map { it.id }.toSet()
        baseReviews = baseReviews.filterNot { it.id in incoming } + fetched
        mergeReviews()
        recombine()
    }

    private fun mergeReviews() {
        val current = reviews
        val mine = current.filter { it.authorID == currentUserID && baseReviews.none { b -> b.id == it.id } }
        send(FeedIntent.SetReviews(ReviewStats.merge(baseReviews, mine, emptyMap())))
    }

    /** Добавляет/заменяет отзыв пользователя. */
    fun upsertUserReview(review: Review) {
        val current = reviews
        val next = if (current.any { it.id == review.id }) {
            current.map { if (it.id == review.id) review else it }
        } else {
            current + review
        }
        send(FeedIntent.SetReviews(next))
        recombine()
    }

    fun removeReview(id: String) {
        send(FeedIntent.SetReviews(reviews.filterNot { it.id == id }))
        recombine()
    }

    fun send(intent: FeedIntent) {
        when (intent) {
            is FeedIntent.SetCatalog -> _state.update { it.copy(catalog = LoadState.Loaded(intent.catalog)) }
            // Первую загрузку показываем спиннером, обновление поверх готовой
            // ленты — нет: список не должен схлопываться на pull-to-refresh.
            is FeedIntent.SetLoading -> _state.update {
                if (it.catalog.valueOrNull() == null) it.copy(catalog = LoadState.Loading) else it
            }
            is FeedIntent.SetFailure -> _state.update {
                if (it.catalog.valueOrNull() == null) it.copy(catalog = LoadState.Failed(intent.error)) else it
            }
            is FeedIntent.SetWeights -> _state.update { it.copy(weights = intent.weights) }
            is FeedIntent.SetReviews -> _state.update { it.copy(reviews = intent.reviews) }
            is FeedIntent.SelectCity -> _state.update { it.copy(citySlug = intent.citySlug) }
            is FeedIntent.SelectCategory -> _state.update { it.copy(category = intent.category) }
        }
    }

    // ── Производные значения (функции состояния, не хранимые поля) ───────────

    fun items(category: VenueCategory? = _state.value.category): List<FeedItem> =
        _state.value.copy(category = category).items(clock.nowMs)

    fun deals(category: VenueCategory? = _state.value.category): List<Deal> =
        _state.value.copy(category = category).deals(clock.nowMs)

    fun venues(category: VenueCategory? = _state.value.category): List<Venue> =
        _state.value.copy(category = category).venues(clock.nowMs)

    val isLoading: Boolean get() = _state.value.catalog.isLoading

    /**
     * Загрузка каталога упала. Отличать обязательно: без этого экран показывал
     * «в городе пока нет заведений» — пустой экран вместо ошибки, и повторить
     * попытку было нечем. Зеркалит `FeedStore.loadFailed` на iOS.
     */
    val loadFailed: Boolean get() = _state.value.catalog.errorOrNull() != null
    val hasVenuesInCity: Boolean get() = _state.value.hasVenuesInCity

    companion object {
        /**
         * Сколько отзывов тянем за раз. Карточка заведения показывает первую
         * страницу; если пришло ровно столько — значит, есть ещё, и агрегат
         * считать по кэшу нельзя. Держать в паре с `FeedStore.reviewPageSize` на iOS.
         */
        const val REVIEW_PAGE_SIZE = 50
    }
}
