package kg.ayant.app.domain

import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.Review
import kg.ayant.app.domain.model.Venue

/*
 * Фича «Заведение» (карточка заведения): состояние и намерения.
 * Имена полей совпадают с `VenueDetail.swift` в AyantDomain.
 */

/**
 * Всё, что показывает карточка заведения, — одним значением.
 *
 * Производные величины (рейтинг, разбивка по звёздам, «мой отзыв») здесь —
 * функции состояния, а не хранимые поля: иначе они разъезжаются с отзывами.
 * Считает их чистый [ReviewStats], тот же, что и раньше во ViewModel.
 */
data class VenueDetailState(
    /** `null` — экран ещё не открыт (или заведение исчезло из каталога). */
    val venue: Venue? = null,
    val deals: List<Deal> = emptyList(),
    val reviews: List<Review> = emptyList(),
    val isSaved: Boolean = false,
    val favoriteDealIDs: Set<String> = emptySet(),
    /** Пусто — гость: сохранять и писать отзывы нельзя. */
    val currentUserID: String = "",
    val isGuest: Boolean = true,
    val submission: ReviewSubmission = ReviewSubmission.Idle,
) {
    /** Рейтинг и число отзывов. Пока отзывов нет — seed-значения из документа. */
    val aggregate: VenueRating
        get() {
            val a = ReviewStats.aggregate(
                reviews = reviews,
                fallbackRating = venue?.rating ?: 0.0,
                fallbackCount = venue?.reviewCount ?: 0,
            )
            return VenueRating(a.first, a.second)
        }

    /** Разбивка 5★…1★ → количество (ключи 1…5 всегда есть). */
    val ratingBreakdown: Map<Int, Int> get() = ReviewStats.ratingBreakdown(reviews)

    /**
     * Отзыв текущего пользователя на заведение целиком или на конкретный объект
     * (блюдо/услугу). Гость своих отзывов не имеет.
     */
    fun myReview(itemID: String? = null): Review? {
        if (currentUserID.isEmpty()) return null
        return reviews.firstOrNull { it.authorID == currentUserID && it.itemID == itemID }
    }

    fun isFavorite(dealID: String): Boolean = dealID in favoriteDealIDs

    /** Может ли пользователь сохранять заведение и писать отзывы. */
    val canContribute: Boolean get() = !isGuest && currentUserID.isNotEmpty()
}

/**
 * Фаза публикации отзыва. Отдельно от списка: карточка остаётся видимой,
 * пока отзыв отправляется.
 */
sealed interface ReviewSubmission {
    data object Idle : ReviewSubmission
    data object Sending : ReviewSubmission
    data class Failed(val error: AppError) : ReviewSubmission

    val isSending: Boolean get() = this is Sending
}

/** Единственный вход во ViewModel карточки заведения. */
sealed interface VenueDetailIntent {
    /** Экран открыт для этого заведения (логирует просмотр). */
    data class Open(val venueID: String) : VenueDetailIntent
    data object Close : VenueDetailIntent
    data object ToggleSave : VenueDetailIntent
    data class ToggleFavorite(val dealID: String) : VenueDetailIntent
    /** Публикация/правка отзыва. [itemID] — объект отзыва (блюдо/услуга) или null. */
    data class SubmitReview(
        val rating: Int,
        val text: String,
        val photos: List<String>,
        val itemID: String?,
        val itemName: String?,
    ) : VenueDetailIntent
    data class DeleteReview(val reviewID: String) : VenueDetailIntent
    data object DismissSubmission : VenueDetailIntent
    /** Пользователь позвонил / построил маршрут — событие для аналитики заведения. */
    data class LogContact(val action: ContactAction) : VenueDetailIntent
}

/** Действия, которые заведение считает как обращения. */
enum class ContactAction(val metric: String) {
    CALL("calls"),
    MAPS("maps"),
}
