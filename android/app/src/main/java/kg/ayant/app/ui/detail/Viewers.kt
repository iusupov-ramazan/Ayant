package kg.ayant.app.ui.detail

import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.material3.Text
import coil.compose.AsyncImage

/** Fullscreen photo viewer with swipe. Mirrors PhotoViewerView. */
@Composable
fun PhotoViewerDialog(photos: List<String>, startIndex: Int, onDismiss: () -> Unit) {
    if (photos.isEmpty()) { onDismiss(); return }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black)) {
            val pager = rememberPagerState(initialPage = startIndex.coerceIn(0, photos.size - 1)) { photos.size }
            HorizontalPager(state = pager, modifier = Modifier.fillMaxSize()) { i ->
                val p = photos[i]
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    if (p.startsWith("http")) {
                        AsyncImage(model = p, contentDescription = null, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize())
                    } else {
                        Text(p, fontSize = 140.sp)
                    }
                }
            }
            IconButton(onClick = onDismiss, modifier = Modifier.align(Alignment.TopStart).padding(8.dp)) {
                Icon(Icons.Filled.Close, "Закрыть", tint = Color.White)
            }
        }
    }
}

/** In-app PDF/price-list viewer (WebView). Mirrors PDFMenuView. */
@Composable
fun PdfMenuDialog(urlString: String, onDismiss: () -> Unit) {
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize().background(Color.White)) {
            AndroidView(
                factory = { ctx ->
                    WebView(ctx).apply {
                        webViewClient = WebViewClient()
                        settings.javaScriptEnabled = true
                        // Render remote PDFs via Google Docs viewer.
                        val u = if (urlString.endsWith(".pdf")) "https://docs.google.com/gview?embedded=true&url=$urlString" else urlString
                        loadUrl(u)
                    }
                },
                modifier = Modifier.fillMaxSize().padding(top = 48.dp),
            )
            IconButton(onClick = onDismiss, modifier = Modifier.align(Alignment.TopEnd).padding(8.dp)) {
                Icon(Icons.Filled.Close, "Закрыть", tint = Color.Black)
            }
        }
    }
}
