package kg.ayant.app.data.model

import java.util.Date

/** Reward from the catalog (what bonuses can buy). Mirrors Reward. */
data class Reward(
    val id: String,
    val title: String,
    val cost: Int,
    val emoji: String,
)

/** Coupon earned/claimed by the user (shown to staff). Mirrors Coupon. */
data class Coupon(
    val id: String,
    val title: String,
    val code: String,
    val createdAt: Date,
    val used: Boolean = false,
    val venueID: String = "",
    val venueName: String = "",
    val kind: String = "bonus",   // bonus | loyalty | deal | gift
    val dealID: String = "",
) {
    val isVenueBound: Boolean get() = venueID.isNotEmpty()
}

/** Loyalty card (per venue). Mirrors LoyaltyCard. */
data class LoyaltyCard(
    val venueID: String,
    val venueName: String,
    val stamps: Int = 0,
    val completedRounds: Int = 0,
    val goal: Int = 6,
    val reward: String = "Награда за лояльность",
)
