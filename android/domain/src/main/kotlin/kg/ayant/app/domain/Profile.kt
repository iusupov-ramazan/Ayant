package kg.ayant.app.domain

import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.Review
import kg.ayant.app.domain.model.Venue

/*
 * Фича «Профиль» — личная библиотека пользователя: сохранённые заведения,
 * избранные акции, погашенные купоны, свои отзывы.
 * Имена полей совпадают с `Profile.swift` в AyantDomain.
 */

/**
 * Состояние профиля одним значением.
 *
 * Здесь лежат **только идентификаторы** — сами заведения и акции живут в
 * каталоге. Списки собираются функциями ([savedVenues]), поэтому не могут
 * разъехаться с каталогом: удалённое заведение просто перестаёт находиться.
 *
 * В отличие от ленты и карточки заведения, этот стор — **владелец** своих
 * данных: он их читает из хранилища настроек и пишет обратно.
 */
data class ProfileState(
    val userID: String = "",
    val userName: String = "",
    val isGuest: Boolean = true,
    val savedVenueIDs: Set<String> = emptySet(),
    val favoriteDealIDs: Set<String> = emptySet(),
    /**
     * Отметки «нравится» на акциях.
     *
     * Отдельно от [favoriteDealIDs]: закладка кладёт акцию в «Сохранённое»,
     * сердечко — только реакция. В ленте это две разные кнопки, и склеивать их
     * нельзя: человек лайкает много, а сохраняет то, куда собирается пойти.
     * Живёт на устройстве — общего счётчика лайков на сервере нет.
     */
    val likedDealIDs: Set<String> = emptySet(),
    /** Погашенные купоны — по ним считается «был в заведении» для отзыва. */
    val redeemedDealIDs: Set<String> = emptySet(),
) {
    fun isSaved(venueID: String): Boolean = venueID in savedVenueIDs
    fun isFavorite(dealID: String): Boolean = dealID in favoriteDealIDs
    fun isLiked(dealID: String): Boolean = dealID in likedDealIDs
    fun hasRedeemed(dealID: String): Boolean = dealID in redeemedDealIDs

    /**
     * Был ли пользователь в заведении — то есть гасил ли там купон.
     * Отзыв такого автора помечается как проверенный визит.
     */
    fun hasVisited(venueID: String, catalog: FeedCatalog): Boolean =
        catalog.deals.any { it.venueID == venueID && it.id in redeemedDealIDs }

    /** Гость не может сохранять и писать отзывы. */
    val canContribute: Boolean get() = !isGuest && userID.isNotEmpty()

    /** Реферальный код — это и есть id пользователя. */
    val referralCode: String get() = userID

    /**
     * Сохранённые заведения в порядке каталога. Исчезнувшие из каталога
     * пропускаются — id остаётся, но показывать нечего.
     */
    fun savedVenues(catalog: FeedCatalog): List<Venue> =
        catalog.venues.filter { it.id in savedVenueIDs }

    /** Избранные акции; протухшие не показываем. */
    fun favoriteDeals(catalog: FeedCatalog, nowMs: Long): List<Deal> =
        catalog.deals
            .filter { it.id in favoriteDealIDs && it.isActiveAt(nowMs) }
            .sortedBy { it.validUntil }

    /** Отзывы, написанные этим пользователем, — новые сверху. */
    fun myReviews(reviews: List<Review>): List<Review> {
        if (userID.isEmpty()) return emptyList()
        return reviews.filter { it.authorID == userID }.sortedByDescending { it.createdAt }
    }
}

/** Единственный вход во ViewModel профиля. */
sealed interface ProfileIntent {
    data class SetUser(val id: String, val name: String, val isGuest: Boolean) : ProfileIntent
    data class ToggleSave(val venueID: String) : ProfileIntent
    data class UnsaveVenue(val venueID: String) : ProfileIntent
    data class ToggleFavorite(val dealID: String) : ProfileIntent
    data class ToggleLike(val dealID: String) : ProfileIntent
    data class UnsaveDeal(val dealID: String) : ProfileIntent
    /** Купон погашен — запоминаем, чтобы отзыв пометился проверенным визитом. */
    data class MarkRedeemed(val dealID: String) : ProfileIntent
}

/**
 * Хранилище личной библиотеки между запусками.
 *
 * Ключи load-bearing: их читают уже установленные приложения, переименование
 * потеряет пользовательские данные.
 */
interface ProfileStorage {
    fun loadIDs(key: String): Set<String>
    fun saveIDs(ids: Set<String>, key: String)
}

object ProfileStorageKey {
    // ВНИМАНИЕ: значения совпадают с тем, что уже лежит на устройствах
    // пользователей. Переименование = потеря сохранённых заведений и избранного.
    const val SAVED_VENUES = "san.savedVenues"
    const val FAVORITE_DEALS = "san.favorites"
    const val REDEEMED_DEALS = "san.redeemed"
    const val LIKED_DEALS = "san.liked"
}
