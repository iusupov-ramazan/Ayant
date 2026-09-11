package kg.ayant.app.domain.contract


/**
 * Push-темы и регистрация токена устройства. Зеркалит `PushService` на iOS.
 *
 * Вынесено из `push/Push.kt` в слой данных: экраны и сервис сообщений теперь
 * не импортируют Firebase — они зовут этот контракт, а какая реализация за ним,
 * решает `AppConfig`.
 */
interface PushService {
    /** Городские темы (рекламные кампании). */
    fun subscribeDefaults(citySlug: String)
    fun subscribeVenue(venueID: String)
    fun unsubscribeVenue(venueID: String)

    /** Запросить у FCM токен устройства и записать его для адресной рассылки. */
    fun registerToken(uid: String?, citySlug: String)

    /**
     * Выход из аккаунта: снять городские темы, удалить `userTokens/<token>` и
     * сам токен FCM. Без этого адресные кампании старого uid продолжают
     * приходить на устройство. Зеркалит `unregisterDevice` на iOS.
     */
    suspend fun unregisterDevice(citySlug: String)

    /**
     * Записать уже известный токен — FCM отдаёт его в `onNewToken`, повторно
     * спрашивать не нужно.
     */
    fun registerKnownToken(token: String, uid: String?, citySlug: String)

    /**
     * Ставит push-кампанию в очередь (`pushCampaigns`). Рассылает Cloud Function
     * ПОСЛЕ одобрения админом — статус создаётся как `pending`.
     */
    fun queuePushCampaign(
        headline: String, body: String, citySlug: String,
        venueID: String, dealID: String?, ownerID: String,
    )
}

/** Оффлайн-режим: подписки и запись токена не делают ничего. */
