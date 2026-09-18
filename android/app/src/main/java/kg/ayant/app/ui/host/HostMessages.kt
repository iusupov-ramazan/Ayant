package kg.ayant.app.ui.host

import android.content.Context
import androidx.annotation.StringRes
import kg.ayant.app.R

/**
 * Коды ошибок `scanCoupon` / `redeemVenuePoints` (те же `{"error": ...}`, что
 * отдаёт сервер и `PointsMath` на клиенте) → текст для сотрудника заведения.
 * Один словарь на оба сканера ([HostScannerFlow] и [HostScannerDialog]), чтобы
 * тексты не расходились. Зеркалит таблицу кодов в `HostScannerView.swift`.
 *
 * @return `null`, если код неизвестен — вызывающий подставляет свой fallback.
 */
@StringRes
fun hostScanErrorRes(code: String?): Int? = when (code) {
    "coupon_not_found" -> R.string.host_err_coupon_not_found
    "wrong_venue" -> R.string.host_err_wrong_venue
    "loyalty_off" -> R.string.host_err_loyalty_off
    "already_used" -> R.string.host_err_already_used
    "not_owner" -> R.string.host_err_not_owner
    "venue_not_found" -> R.string.host_err_venue_not_found
    "no_token", "bad_token" -> R.string.host_err_no_token
    "missing_params" -> R.string.host_err_missing_params
    "points_off" -> R.string.host_err_points_off
    "cooldown" -> R.string.host_err_cooldown
    "missing_amount" -> R.string.host_err_missing_amount
    "bad_band" -> R.string.host_err_bad_band
    "no_points" -> R.string.host_err_no_points
    "bad_code" -> R.string.host_err_bad_code
    "insufficient" -> R.string.host_err_insufficient
    "reward_not_found" -> R.string.host_err_reward_not_found
    "redeem_not_allowed" -> R.string.host_err_redeem_not_allowed
    "below_min" -> R.string.host_err_below_min
    "missing_user" -> R.string.host_err_missing_user
    else -> null
}

fun hostScanErrorText(context: Context, code: String?, fallback: () -> String): String =
    hostScanErrorRes(code)?.let { context.getString(it) } ?: fallback()

/** «Списано N баллов (−M сом). Остаток: K.» / «… Выдайте награду гостю.» */
fun hostRedeemedText(context: Context, redeemed: Int, balance: Int, somOff: Int?): String =
    if (somOff != null) context.getString(R.string.host_redeemed_som, redeemed, somOff, balance)
    else context.getString(R.string.host_redeemed_item, redeemed, balance)

/** «до 500 сом» / «1500+ сом» — подпись диапазона суммы чека. */
fun bandLabel(context: Context, maxAmount: Int, isLast: Boolean): String =
    if (isLast) context.getString(R.string.host_band_plus, maxAmount)
    else context.getString(R.string.host_band_upto, maxAmount)
