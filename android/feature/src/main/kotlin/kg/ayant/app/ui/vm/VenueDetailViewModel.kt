package kg.ayant.app.ui.vm

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import kg.ayant.app.domain.AppError
import kg.ayant.app.domain.ReviewSubmission
import kg.ayant.app.domain.VenueDetailIntent
import kg.ayant.app.domain.VenueDetailState
import kg.ayant.app.domain.contract.AnalyticsMetric
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * ViewModel карточки заведения — третья фича на новой форме (после баллов и ленты):
 * одно значение состояния наружу и один вход [send].
 *
 * Что изменилось: экран больше не дёргает восемь методов `AppViewModel`
 * (`aggregate`, `ratingBreakdown`, `myReview`, `isSaved`, `reviews`, `deals`,
 * `log`, `toggleSave`) и не считает ничего сам — он читает [state].
 * Производные величины считает чистый `ReviewStats` через [VenueDetailState].
 *
 * Каталог, отзывы и сохранённые id по-прежнему принадлежат `AppViewModel` — их
 * читают поиск, избранное и лента. Здесь они проецируются в состояние экрана,
 * а мутации уходят обратно в `AppViewModel`, который владеет персистентностью.
 * Полное владение переедет сюда вместе с `profile` (там же живут «сохранённые»).
 *
 * Зеркалит `VenueDetailStore.swift` на iOS.
 */
class VenueDetailViewModel(app: Application) : AndroidViewModel(app) {

    private val _state = MutableStateFlow(VenueDetailState())
    val state: StateFlow<VenueDetailState> = _state.asStateFlow()

    /**
     * Связывается уже после создания: `viewModel()` строит VM до того, как экран
     * получил ссылку на [AppViewModel].
     */
    private var app: AppViewModel? = null

    fun bind(app: AppViewModel) { this.app = app }

    fun send(intent: VenueDetailIntent) {
        val owner = app ?: return
        when (intent) {
            is VenueDetailIntent.Open -> open(owner, intent.venueID)

            is VenueDetailIntent.Close -> _state.value = VenueDetailState()

            is VenueDetailIntent.ToggleSave -> {
                val venue = _state.value.venue ?: return
                if (!_state.value.canContribute) return
                owner.toggleSave(venue)
                owner.log(AnalyticsMetric.SAVES, venue.id)
                refresh()
            }

            is VenueDetailIntent.ToggleFavorite -> {
                val deal = _state.value.deals.firstOrNull { it.id == intent.dealID } ?: return
                owner.toggleFavorite(deal)
                refresh()
            }

            is VenueDetailIntent.SubmitReview -> submitReview(owner, intent)

            is VenueDetailIntent.DeleteReview -> {
                val review = _state.value.reviews.firstOrNull { it.id == intent.reviewID } ?: return
                owner.deleteReview(review)
                refresh()
            }

            is VenueDetailIntent.DismissSubmission ->
                _state.update { it.copy(submission = ReviewSubmission.Idle) }

            is VenueDetailIntent.LogContact -> {
                val venue = _state.value.venue ?: return
                owner.log(intent.action.metric, venue.id)
            }
        }
    }

    // ── Проекция состояния ───────────────────────────────────────────────────

    private fun open(owner: AppViewModel, venueID: String) {
        val venue = owner.venue(id = venueID)
        if (venue == null) {
            _state.value = VenueDetailState()
            return
        }
        owner.log(AnalyticsMetric.VIEWS, venue.id)
        _state.update { it.copy(venue = venue) }
        refresh()
        // Отзывы этого заведения больше не лежат в памяти заранее — забираем их
        // страницей при открытии карточки. `refresh()` уже показал экран с тем,
        // что есть (обычно пусто); подписка на каталог обновит его, когда
        // страница приедет.
        owner.loadReviews(forVenue = venue)
    }

    /**
     * Пересобирает срез из `AppViewModel`. Зовётся после каждой мутации — стор
     * владельца уже обновился, экрану нужен свежий снимок.
     */
    fun refresh() {
        val owner = app ?: return
        val venue = _state.value.venue?.let { owner.venue(id = it.id) } ?: return
        _state.update {
            it.copy(
                venue = venue,
                deals = owner.deals(forVenue = venue),
                reviews = owner.reviews(forVenue = venue),
                isSaved = owner.isSaved(venue),
                favoriteDealIDs = owner.favoriteDealIDs.toSet(),
                currentUserID = owner.currentUserID,
                isGuest = owner.isGuest,
            )
        }
    }

    // ── Отзывы ───────────────────────────────────────────────────────────────

    private fun submitReview(owner: AppViewModel, intent: VenueDetailIntent.SubmitReview) {
        val venue = _state.value.venue
        if (venue == null || !_state.value.canContribute) {
            _state.update { it.copy(submission = ReviewSubmission.Failed(AppError.Unauthenticated)) }
            return
        }
        if (_state.value.submission.isSending) return   // второй тап игнорируем

        _state.update { it.copy(submission = ReviewSubmission.Sending) }
        owner.saveReview(venue.id, intent.rating, intent.text, intent.itemID, intent.itemName)
        _state.update { it.copy(submission = ReviewSubmission.Idle) }
        refresh()
    }
}
