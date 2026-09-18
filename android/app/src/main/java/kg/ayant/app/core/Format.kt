package kg.ayant.app.core

import kg.ayant.app.R
import java.text.SimpleDateFormat
import java.util.Date

// Все форматтеры берут локаль ПРИЛОЖЕНИЯ (`AppLanguage.locale`), а не `ru_RU`:
// кыргызский интерфейс раньше получал русские месяцы и «сом/км» из русской ветки.

/** «15 июня» — mirrors Date.sanShort. */
fun Date.sanShort(): String = SimpleDateFormat("d MMMM", AppLanguage.locale).format(this)

/** «15 июн 2026» — mirrors Review.dateText. */
fun Date.reviewDate(): String = SimpleDateFormat("d MMM yyyy", AppLanguage.locale).format(this)

/** «290 сом» — mirrors Int.som. */
val Int.som: String get() = LS(R.string.price_som, this)

/** «0.8 км» / «350 м» — mirrors Double.distanceText. */
fun Double.distanceText(): String =
    if (this < 1) LS(R.string.distance_m, (this * 1000).toInt())
    else LS(R.string.distance_km, String.format(AppLanguage.locale, "%.1f", this))
