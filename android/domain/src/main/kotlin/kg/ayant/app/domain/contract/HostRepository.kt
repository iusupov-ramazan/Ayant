package kg.ayant.app.domain.contract

import kg.ayant.app.domain.model.HostVenueDTO

/**
 * Запись хост-заведения на сервер. Зеркалит `HostRepository.saveVenue` на iOS.
 *
 * До сих пор кабинет на Android жил только в SharedPreferences (см.
 * `HostViewModel.reload`), и конфиг баллов САН можно было лишь читать. Теперь
 * правка с вкладки «Лояльность» уезжает в `venues/{id}` — те же поля, что читают
 * `scanCoupon` и админ-панель. Остальная синхронизация кабинета (загрузка своих
 * заведений, акции, профиль) на Android по-прежнему не реализована.
 */
interface HostRepository {
    /**
     * Пишет DTO целиком с merge-семантикой: поля, которых DTO не знает (рейтинг,
     * счётчики, служебные), остаются нетронутыми — как `setData(merge: true)` на iOS.
     */
    suspend fun saveVenue(dto: HostVenueDTO, ownerID: String)
}
