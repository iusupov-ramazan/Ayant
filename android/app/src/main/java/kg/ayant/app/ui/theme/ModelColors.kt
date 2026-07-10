package kg.ayant.app.ui.theme

import androidx.compose.ui.graphics.Color
import kg.ayant.app.data.model.DealType
import kg.ayant.app.data.model.Venue

/**
 * UI-layer color mappers. The data layer stores colors as plain ARGB [Long]s so it
 * carries no Compose dependency; these extensions turn them into Compose [Color]s.
 */

/** Venue card gradient stops as Compose colors. */
val Venue.gradientColors: List<Color>
    get() = gradient.map { Color(it) }

/** Per-deal-type accent color (mirrors Models.swift DealType.color). */
val DealType.color: Color
    get() = when (this) {
        DealType.DISCOUNT -> Accent
        DealType.PROMO -> DealPromo
        DealType.NOVELTY -> DealNovelty
        DealType.ANNOUNCEMENT -> DealAnnouncement
    }
