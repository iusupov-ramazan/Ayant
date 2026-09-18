package kg.ayant.app.domain.model

import java.util.Date

/** Reward from the catalog (what bonuses can buy). Mirrors Reward. */
data class Reward(
    val id: String,
    val title: String,
    val cost: Int,
    val emoji: String,
    /**
     * Заведение-партнёр, которое гасит награду.
     *
     * Без него награда бесполезна: `scanCoupon` сверяет `coupon.venueID` с
     * заведением сканера и отвечает `wrong_venue`. Поэтому награды без
     * партнёра не показываются (см. [isRedeemable]).
     */
    val venueID: String = "",
    val venueName: String = "",
) {
    /** Награду можно предъявить в заведении. Без партнёра — нельзя. */
    val isRedeemable: Boolean get() = venueID.isNotEmpty()
}

/**
 * Встроенный список наград — ШАБЛОН, а не то, что видит пользователь:
 * у наград здесь нет партнёра. Реальный каталог приходит из
 * `config/globalRewards`. Зеркалит `CouponCatalog`.
 */
object CouponCatalog {
    val builtIn = listOf(
        Reward("disc10", "−10% к любой акции", 100, "🏷️"),
        Reward("coffee", "Бесплатный кофе у партнёра", 300, "☕️"),
        Reward("dessert", "Десерт в подарок", 400, "🍰"),
        Reward("vip", "VIP-доступ к новинкам", 500, "⭐️"),
    )
}

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

/** САН points card (per venue). Mirrors VenuePointsCard. */
data class VenuePointsCard(
    val venueID: String,
    val venueName: String,
    val balance: Int = 0,
    val lifetimeEarned: Int = 0,
    val lifetimeRedeemed: Int = 0,
)
