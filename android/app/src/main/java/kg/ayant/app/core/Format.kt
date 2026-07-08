package kg.ayant.app.core

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private val ru = Locale("ru", "RU")

/** «15 июня» — mirrors Date.sanShort. */
fun Date.sanShort(): String = SimpleDateFormat("d MMMM", ru).format(this)

/** «15 июн 2026» — mirrors Review.dateText. */
fun Date.reviewDate(): String = SimpleDateFormat("d MMM yyyy", ru).format(this)

/** «290 сом» — mirrors Int.som. */
val Int.som: String get() = "$this сом"

/** «0.8 км» / «350 м» — mirrors Double.distanceText. */
fun Double.distanceText(): String =
    if (this < 1) "${(this * 1000).toInt()} м" else "%.1f км".format(this)
