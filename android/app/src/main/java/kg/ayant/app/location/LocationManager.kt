package kg.ayant.app.location

import android.annotation.SuppressLint
import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * "While using" location. Publishes only the last position (no history), mirroring
 * LocationManager.swift. If permission isn't granted, distances stay hidden.
 */
class LocationManager(app: Application) : AndroidViewModel(app) {

    private val client = LocationServices.getFusedLocationProviderClient(app.applicationContext)

    var lastLat by mutableStateOf<Double?>(null)
        private set
    var lastLng by mutableStateOf<Double?>(null)
        private set

    /** Call after the permission is granted. Safe to call repeatedly. */
    @SuppressLint("MissingPermission")
    fun refresh() {
        try {
            client.getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, null)
                .addOnSuccessListener { loc ->
                    if (loc != null) {
                        lastLat = loc.latitude
                        lastLng = loc.longitude
                    }
                }
        } catch (_: SecurityException) {
            // Permission not granted — distances remain hidden.
        }
    }

    /** Distance from user to a point, or null if position is unknown. */
    fun distanceKm(lat: Double, lng: Double): Double? {
        val meLat = lastLat ?: return null
        val meLng = lastLng ?: return null
        return haversine(meLat, meLng, lat, lng)
    }

    companion object {
        fun haversine(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
            val r = 6371.0
            val dLat = (lat2 - lat1) * Math.PI / 180
            val dLon = (lon2 - lon1) * Math.PI / 180
            val a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * Math.PI / 180) * cos(lat2 * Math.PI / 180) *
                sin(dLon / 2) * sin(dLon / 2)
            return r * 2 * atan2(sqrt(a), sqrt(1 - a))
        }
    }
}
