package kg.ayant.app.ui.host

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import kg.ayant.app.R
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.Marker
import com.google.maps.android.compose.MarkerState
import com.google.maps.android.compose.rememberCameraPositionState

/** Full-screen map: tap to drop the venue pin. Mirrors VenueLocationPicker. */
@Composable
fun MapPickerDialog(
    initialLat: Double,
    initialLng: Double,
    onDismiss: () -> Unit,
    onPick: (Double, Double) -> Unit,
) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        var picked by remember { mutableStateOf(LatLng(initialLat, initialLng)) }
        val cam = rememberCameraPositionState { position = CameraPosition.fromLatLngZoom(picked, 15f) }
        Box(Modifier.fillMaxSize().background(Color.White)) {
            GoogleMap(
                modifier = Modifier.fillMaxSize(),
                cameraPositionState = cam,
                onMapClick = { picked = it },
            ) {
                Marker(state = MarkerState(position = picked), title = stringResource(R.string.venue_section))
            }
            Row(
                Modifier.fillMaxWidth().background(Color.White.copy(alpha = 0.9f)).padding(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onDismiss) { Icon(Icons.Filled.Close, stringResource(R.string.action_close), tint = Color.Black) }
                Text(stringResource(R.string.map_pick_hint), color = Color.Black, modifier = Modifier.weight(1f))
                Button(onClick = { onPick(picked.latitude, picked.longitude); onDismiss() }) { Text(stringResource(R.string.action_done)) }
            }
        }
    }
}
