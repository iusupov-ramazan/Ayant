package kg.ayant.app.ui.host

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.mlkit.vision.MlKitAnalyzer
import androidx.camera.view.CameraController
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.barcode.BarcodeScanning

/**
 * Live camera QR scanner (CameraX LifecycleCameraController + ML Kit MlKitAnalyzer).
 * Emits the first decoded value once. If permission is denied, `onNoPermission` fires
 * so the caller can fall back to manual entry. Mirrors HostScannerView (VisionKit).
 */
@Composable
fun QrScannerView(
    modifier: Modifier = Modifier,
    onResult: (String) -> Unit,
    onNoPermission: () -> Unit,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var granted by remember {
        mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED)
    }
    var handled by remember { mutableStateOf(false) }

    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        granted = ok
        if (!ok) onNoPermission()
    }

    LaunchedEffect(Unit) { if (!granted) launcher.launch(Manifest.permission.CAMERA) }

    if (!granted) return

    Box(modifier) {
        AndroidView(
            modifier = Modifier.fillMaxWidth().height(280.dp),
            factory = { ctx ->
                val previewView = PreviewView(ctx)
                val controller = LifecycleCameraController(ctx)
                val scanner = BarcodeScanning.getClient()
                val executor = ContextCompat.getMainExecutor(ctx)
                controller.setImageAnalysisAnalyzer(
                    executor,
                    MlKitAnalyzer(listOf(scanner), CameraController.COORDINATE_SYSTEM_VIEW_REFERENCED, executor) { result ->
                        val value = result?.getValue(scanner)?.firstOrNull()?.rawValue
                        if (value != null && !handled) { handled = true; onResult(value) }
                    },
                )
                controller.bindToLifecycle(lifecycleOwner)
                previewView.controller = controller
                previewView
            },
        )
    }
}
