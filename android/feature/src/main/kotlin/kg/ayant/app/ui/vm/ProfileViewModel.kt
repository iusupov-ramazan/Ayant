package kg.ayant.app.ui.vm

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import kg.ayant.app.domain.ProfileIntent
import kg.ayant.app.domain.ProfileState
import kg.ayant.app.domain.ProfileStorage
import kg.ayant.app.domain.ProfileStorageKey
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/**
 * ViewModel профиля — четвёртая фича на новой форме и первая, которая **владеет**
 * своими данными, а не проецирует чужие.
 *
 * Личная библиотека (сохранённые заведения, избранные акции, погашенные купоны)
 * живёт здесь и пишется в SharedPreferences отсюда. `AppViewModel` больше не
 * хранит эти множества — он делегирует сюда, поэтому старые вызовы (`isSaved`,
 * `toggleFavorite`, `savedVenues`) продолжают работать без правок вызывающих.
 *
 * Ключи хранилища load-bearing: их читают уже установленные приложения
 * (см. [ProfileStorageKey]).
 *
 * Зеркалит `ProfileStore.swift` на iOS.
 */
class ProfileViewModel @JvmOverloads constructor(
    app: Application,
    private val storage: ProfileStorage = SharedPrefsProfileStorage(app),
) : AndroidViewModel(app) {

    private val _state = MutableStateFlow(
        ProfileState(
            savedVenueIDs = storage.loadIDs(ProfileStorageKey.SAVED_VENUES),
            favoriteDealIDs = storage.loadIDs(ProfileStorageKey.FAVORITE_DEALS),
            redeemedDealIDs = storage.loadIDs(ProfileStorageKey.REDEEMED_DEALS),
            likedDealIDs = storage.loadIDs(ProfileStorageKey.LIKED_DEALS),
        )
    )
    val state: StateFlow<ProfileState> = _state.asStateFlow()

    fun send(intent: ProfileIntent) {
        when (intent) {
            is ProfileIntent.SetUser -> _state.update {
                it.copy(userID = intent.id, userName = intent.name, isGuest = intent.isGuest)
            }

            is ProfileIntent.ToggleSave -> {
                if (!_state.value.canContribute) return
                toggle(intent.venueID, ProfileStorageKey.SAVED_VENUES)
            }

            is ProfileIntent.UnsaveVenue -> update(ProfileStorageKey.SAVED_VENUES) {
                it - intent.venueID
            }

            is ProfileIntent.ToggleFavorite -> {
                if (!_state.value.canContribute) return
                toggle(intent.dealID, ProfileStorageKey.FAVORITE_DEALS)
            }

            // Лайк — тоже действие аккаунта: он кормит ранжирование и должен
            // переезжать с пользователем на другое устройство. Раньше гостю
            // разрешалось лайкать «потому что лайк локальный» — на деле лайки
            // оставались на устройстве и доставались следующему вошедшему.
            is ProfileIntent.ToggleLike -> {
                if (!_state.value.canContribute) return
                toggle(intent.dealID, ProfileStorageKey.LIKED_DEALS)
            }

            is ProfileIntent.UnsaveDeal -> update(ProfileStorageKey.FAVORITE_DEALS) {
                it - intent.dealID
            }

            is ProfileIntent.MarkRedeemed -> update(ProfileStorageKey.REDEEMED_DEALS) {
                it + intent.dealID
            }
        }
    }

    /**
     * Стирает личную библиотеку при смене пользователя: ключи хранилища общие
     * для устройства, и без этого сохранённые места и избранные акции
     * переходят следующему вошедшему. Зеркалит `ProfileStore.resetForNewUser()`.
     */
    fun resetForNewUser() {
        for (key in listOf(
            ProfileStorageKey.SAVED_VENUES, ProfileStorageKey.FAVORITE_DEALS,
            ProfileStorageKey.REDEEMED_DEALS, ProfileStorageKey.LIKED_DEALS,
        )) storage.saveIDs(emptySet(), key)
        _state.update {
            it.copy(savedVenueIDs = emptySet(), favoriteDealIDs = emptySet(),
                    redeemedDealIDs = emptySet(), likedDealIDs = emptySet())
        }
    }

    private fun toggle(id: String, key: String) = update(key) {
        if (id in it) it - id else it + id
    }

    /** Меняет нужное множество и сразу сохраняет его. */
    private fun update(key: String, transform: (Set<String>) -> Set<String>) {
        _state.update { current ->
            val next = transform(current.idsFor(key))
            storage.saveIDs(next, key)
            current.withIDs(next, key)
        }
    }

    private fun ProfileState.idsFor(key: String): Set<String> = when (key) {
        ProfileStorageKey.SAVED_VENUES -> savedVenueIDs
        ProfileStorageKey.FAVORITE_DEALS -> favoriteDealIDs
        ProfileStorageKey.LIKED_DEALS -> likedDealIDs
        else -> redeemedDealIDs
    }

    private fun ProfileState.withIDs(ids: Set<String>, key: String): ProfileState = when (key) {
        ProfileStorageKey.SAVED_VENUES -> copy(savedVenueIDs = ids)
        ProfileStorageKey.FAVORITE_DEALS -> copy(favoriteDealIDs = ids)
        ProfileStorageKey.LIKED_DEALS -> copy(likedDealIDs = ids)
        else -> copy(redeemedDealIDs = ids)
    }
}

/** Личная библиотека поверх SharedPreferences. */
class SharedPrefsProfileStorage(app: Application) : ProfileStorage {
    private val prefs = app.getSharedPreferences("ayant.store", 0)

    override fun loadIDs(key: String): Set<String> =
        prefs.getStringSet(key, emptySet()) ?: emptySet()

    override fun saveIDs(ids: Set<String>, key: String) {
        prefs.edit().putStringSet(key, ids).apply()
    }
}
