package kg.ayant.app.domain.contract

/**
 * Расстояние до точки в километрах.
 *
 * Ранжированию нужен только километраж, а не Android-локация: раньше стор брал
 * `LocationManager` целиком и вместе с ним — Play Services. Контракт разрывает
 * эту связь, поэтому фича-слой собирается без Google-зависимостей, а в тесте
 * расстояние подставляется константой.
 *
 * `null` — координаты пользователя ещё неизвестны (нет разрешения или фикса).
 */
fun interface DistanceSource {
    fun distanceKm(latitude: Double, longitude: Double): Double?
}
