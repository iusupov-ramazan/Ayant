package kg.ayant.app.domain

import kg.ayant.app.domain.model.AdCampaign
import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.DealStatus
import kg.ayant.app.domain.model.HostDealDTO
import kg.ayant.app.domain.model.HostProfile
import kg.ayant.app.domain.model.HostVenueDTO
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenueCategory
import java.util.Date

/*
 * Фича «Бизнес-кабинет»: состояние и намерения.
 * Имена полей совпадают с `Host.swift` в AyantDomain.
 */

/**
 * Всё состояние хост-стороны одним значением.
 *
 * Кэш заведений/акций читается с диска сразу, поэтому «загрузки» как таковой
 * нет — есть фаза синхронизации с сервером поверх уже показанных данных
 * ([sync]). Это отличается от ленты, где до первой загрузки показывать нечего.
 */
data class HostState(
    /** uid владельца. Пусто — пользователь не вошёл; кэш тогда общий (легаси). */
    val ownerID: String = "",
    val profile: HostProfile? = null,
    val venues: List<HostVenueDTO> = emptyList(),
    val deals: List<HostDealDTO> = emptyList(),
    val campaigns: List<AdCampaign> = emptyList(),
    val sync: SyncPhase = SyncPhase.Idle,
) {
    /** Кабинет заведён — профиль создан. */
    val hasAccount: Boolean get() = profile != null

    val ownedVenueIDs: Set<String> get() = venues.map { it.id }.toSet()

    fun venue(id: String): HostVenueDTO? = venues.firstOrNull { it.id == id }

    /** Акции заведения, новые сверху. */
    fun deals(forVenue: String): List<HostDealDTO> =
        deals.filter { it.venueID == forVenue }.sortedByDescending { it.startDate }

    /** Контент хоста в виде пользовательских моделей — им он накладывается на ленту. */
    val publicVenues: List<Venue> get() = venues.map { it.asVenue }
    val publicDeals: List<Deal> get() = deals.map { it.asDeal }
}

/** Фаза синхронизации с сервером. Ошибка не стирает кэш — он остаётся видимым. */
sealed interface SyncPhase {
    data object Idle : SyncPhase
    data object Syncing : SyncPhase
    data class Failed(val error: AppError) : SyncPhase

    val isSyncing: Boolean get() = this is Syncing
}

/** Реквизиты бизнеса — отдельный тип, чтобы не тащить 10 аргументов в намерение. */
data class BusinessInfo(
    val businessName: String,
    val category: VenueCategory,
    val phone: String,
    val email: String,
    val legalForm: String = "",
    val legalName: String = "",
    val inn: String = "",
    val registrationAddress: String = "",
    val website: String = "",
    val about: String = "",
)

/** Единственный вход во ViewModel бизнес-кабинета. */
sealed interface HostIntent {
    /** Сменить владельца (вход/выход/другой аккаунт) — перечитывает его кэш. */
    data class Configure(val ownerID: String?) : HostIntent
    /** Подтянуть заведения/акции/профиль с сервера поверх кэша. */
    data object Sync : HostIntent

    // Аккаунт
    data class CreateAccount(
        val businessName: String, val category: VenueCategory,
        val phone: String, val email: String,
    ) : HostIntent
    data class UpdateBusinessInfo(val info: BusinessInfo) : HostIntent
    data object RequestVerification : HostIntent

    // Заведения
    data class SaveVenue(
        val existing: HostVenueDTO?, val fields: HostForms.VenueFields,
    ) : HostIntent
    data class TogglePause(val venueID: String) : HostIntent
    data class SetTodaySpecial(val venueID: String, val text: String) : HostIntent
    data class DeleteVenue(val id: String) : HostIntent
    data class AddItem(
        val venueID: String, val name: String, val emoji: String,
        val kind: String, val imageURL: String,
    ) : HostIntent
    data class DeleteItem(val venueID: String, val itemID: String) : HostIntent
    data class BoostVenue(val id: String, val until: Date) : HostIntent

    // Акции
    data class SaveDeal(val existing: HostDealDTO?, val fields: HostForms.DealFields) : HostIntent
    data class SetDealStatus(val id: String, val status: DealStatus) : HostIntent
    data class DeleteDeal(val id: String) : HostIntent

    // Продвижение
    data class AddCampaign(val campaign: AdCampaign) : HostIntent
    data class LaunchPush(
        val headline: String, val body: String, val venueID: String, val dealID: String?,
    ) : HostIntent
    data class CancelCampaign(val id: String) : HostIntent
}
