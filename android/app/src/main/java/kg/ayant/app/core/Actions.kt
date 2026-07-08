package kg.ayant.app.core

import android.content.Context
import android.content.Intent
import android.net.Uri

/** Deep-link URLs mirroring DeepLinkRouter (custom scheme + https). */
object Links {
    fun venue(id: String) = "https://ayant.kg/venue/$id"
    fun deal(id: String) = "https://ayant.kg/deal/$id"
    fun referral(code: String) = "https://ayant.kg/invite/$code"
}

/** Directions — 2GIS default (dominant in Central Asia), Google fallback. */
object Directions {
    fun dgis(lat: Double, lng: Double) = "https://2gis.kg/geo/$lng,$lat?m=$lng,$lat/16"
    fun google(lat: Double, lng: Double) = "https://www.google.com/maps/dir/?api=1&destination=$lat,$lng"
}

fun Context.shareText(text: String, subject: String? = null) {
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        if (subject != null) putExtra(Intent.EXTRA_SUBJECT, subject)
        putExtra(Intent.EXTRA_TEXT, text)
    }
    val chooser = Intent.createChooser(intent, subject ?: "Поделиться").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { startActivity(chooser) }
}

fun Context.openUrl(url: String) {
    runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

fun Context.dial(phone: String) {
    val clean = phone.filter { !it.isWhitespace() }
    runCatching { startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:$clean")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}
