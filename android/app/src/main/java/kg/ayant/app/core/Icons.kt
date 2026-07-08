package kg.ayant.app.core

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.BakeryDining
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.EmojiFoodBeverage
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.LocalCafe
import androidx.compose.material.icons.filled.LocalOffer
import androidx.compose.material.icons.filled.LunchDining
import androidx.compose.material.icons.filled.NewReleases
import androidx.compose.material.icons.filled.Percent
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Storefront
import androidx.compose.material.icons.filled.WineBar
import androidx.compose.ui.graphics.vector.ImageVector
import kg.ayant.app.data.model.DealType

/** Resolves a category icon key (from VenueCategory.icon) to a Material icon. */
fun categoryIcon(key: String): ImageVector = when (key) {
    "restaurant" -> Icons.Filled.Restaurant
    "local_cafe" -> Icons.Filled.LocalCafe
    "lunch_dining" -> Icons.Filled.LunchDining
    "wine_bar" -> Icons.Filled.WineBar
    "emoji_food_beverage" -> Icons.Filled.EmojiFoodBeverage
    "bakery_dining" -> Icons.Filled.BakeryDining
    "grid" -> Icons.Filled.GridView
    else -> Icons.Filled.LocalOffer
}

/** Deal-type badge icon (mirrors DealType.icon SF Symbols). */
fun dealTypeIcon(type: DealType): ImageVector = when (type) {
    DealType.DISCOUNT -> Icons.Filled.Percent
    DealType.PROMO -> Icons.Filled.CardGiftcard
    DealType.NOVELTY -> Icons.Filled.NewReleases
    DealType.ANNOUNCEMENT -> Icons.Filled.Campaign
}

val storefrontIcon: ImageVector get() = Icons.Filled.Storefront
val menuBookIcon: ImageVector get() = Icons.AutoMirrored.Filled.MenuBook
