package kg.ayant.app.push

import kg.ayant.app.core.AppConfig

/**
 * Тонкий фасад над [kg.ayant.app.data.PushService] — его зовут экраны и
 * настройки, менять их незачем. Сам Firebase живёт в слое данных.
 *
 * Раньше здесь напрямую вызывались `FirebaseMessaging` и `FirebaseFirestore`,
 * из-за чего UI-слой зависел от SDK и не подменялся в оффлайн-режиме.
 */
object Push {
    const val CHANNEL_ID = "ayant_deals"

    private val service get() = AppConfig.makePushService()

    /** Подписка на городские темы (рекламные кампании). */
    fun subscribeDefaults(citySlug: String) = service.subscribeDefaults(citySlug)

    fun subscribeVenue(venueID: String) = service.subscribeVenue(venueID)

    fun unsubscribeVenue(venueID: String) = service.unsubscribeVenue(venueID)

    /** Записывает FCM-токен устройства в userTokens/{token} для адресной рассылки. */
    fun registerToken(uid: String?, citySlug: String) = service.registerToken(uid, citySlug)

    /** Выход: снять темы и удалить токен устройства (см. `PushService`). */
    suspend fun unregisterDevice(citySlug: String) = service.unregisterDevice(citySlug)
}
