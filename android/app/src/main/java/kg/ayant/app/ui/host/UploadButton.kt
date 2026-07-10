package kg.ayant.app.ui.host

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.UploadFile
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.firebase.storage.FirebaseStorage
import kg.ayant.app.R
import kg.ayant.app.core.AppConfig
import kg.ayant.app.ui.theme.AyantTheme
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import java.util.UUID

/**
 * Picks a file from the device (image or PDF), uploads it to Firebase Storage and
 * returns the public download URL. Mirrors ImagePickerField/PDFPickerField on iOS.
 * Requires Firebase configured (google-services.json) + Storage rules allowing
 * authenticated writes. If Firebase is off, the row is hidden.
 */
@Composable
fun UploadButton(
    label: String,
    mimeType: String,      // "image/*" or "application/pdf"
    folder: String,        // storage folder, e.g. "venues" / "menus"
    onUploaded: (String) -> Unit,
) {
    if (!AppConfig.useFirebase) return
    val c = AyantTheme.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var uploading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        uploading = true; error = null
        scope.launch {
            val url = runCatching {
                val ext = if (mimeType.startsWith("image")) "jpg" else "pdf"
                val ref = FirebaseStorage.getInstance().reference.child("$folder/${UUID.randomUUID()}.$ext")
                ref.putFile(uri).await()
                ref.downloadUrl.await().toString()
            }.getOrElse { error = context.getString(R.string.host_upload_failed); null }
            uploading = false
            if (url != null) onUploaded(url)
        }
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.clickable(enabled = !uploading) { launcher.launch(mimeType) }.padding(vertical = 4.dp),
    ) {
        if (uploading) {
            CircularProgressIndicator(strokeWidth = 2.dp, modifier = Modifier.size(16.dp), color = c.accent)
            Text("  " + stringResource(R.string.host_uploading), fontSize = 13.sp, color = c.inkSoft)
        } else {
            Icon(Icons.Filled.UploadFile, null, tint = c.accent, modifier = Modifier.size(16.dp))
            Text("  ${error ?: label}", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = if (error != null) androidx.compose.ui.graphics.Color(0xFFD32F2F) else c.accent)
        }
    }
}
