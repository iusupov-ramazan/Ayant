package kg.ayant.app.ui.detail

import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil.compose.AsyncImage
import kg.ayant.app.R
import kg.ayant.app.domain.model.ReviewReportReason
import kg.ayant.app.ui.theme.AyantTheme

/**
 * Полноэкранный просмотр фото со свайпом и жалобой. Зеркалит `PhotoViewerView`.
 *
 * Жалоба на фото, как и на iOS, пока не уходит на сервер — только
 * подтверждение пользователю (у фото нет отдельной очереди модерации).
 */
@Composable
fun PhotoViewerDialog(photos: List<String>, startIndex: Int, onDismiss: () -> Unit) {
    if (photos.isEmpty()) { onDismiss(); return }
    var showReport by remember { mutableStateOf(false) }
    var reported by remember { mutableStateOf(false) }

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
            Row(Modifier.fillMaxWidth().statusBarsPadding().padding(4.dp)) {
                IconButton(onClick = onDismiss) {
                    Icon(Icons.Filled.Close, stringResource(R.string.action_close), tint = Color.White)
                }
                Spacer(Modifier.weight(1f))
                IconButton(onClick = { showReport = true }) {
                    Icon(Icons.Filled.Flag, stringResource(R.string.review_report_action), tint = Color.White)
                }
            }
            if (reported) {
                Text(
                    stringResource(R.string.detail_photo_report_thanks),
                    fontSize = 12.sp, color = Color.White,
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .navigationBarsPadding()
                        .padding(bottom = 30.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.2f))
                        .padding(horizontal = 12.dp, vertical = 6.dp),
                )
            }
        }
    }

    if (showReport) {
        // Причины — те же три, что у отзывов (домен), в том же порядке, что на iOS.
        AlertDialog(
            onDismissRequest = { showReport = false },
            title = { Text(stringResource(R.string.detail_photo_report_title)) },
            text = {
                Column {
                    ReviewReportReason.entries.forEach { reason ->
                        TextButton(onClick = { showReport = false; reported = true }) {
                            Text(stringResource(reason.labelRes()), color = Color(0xFFD32F2F))
                        }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { showReport = false }) { Text(stringResource(R.string.action_cancel)) } },
        )
    }
}

/** Подпись причины жалобы. Домен не знает про каталог переводов — локализует UI. */
internal fun ReviewReportReason.labelRes(): Int = when (this) {
    ReviewReportReason.FAKE -> R.string.review_report_fake
    ReviewReportReason.SPAM -> R.string.review_report_spam
    ReviewReportReason.OFFENSIVE -> R.string.review_report_offensive
}

/**
 * In-app просмотр прайс-листа/меню (WebView). Зеркалит `PDFMenuView`: заголовок
 * «Прайс-лист», кнопка «Готово», заглушка, если ссылку не удалось разобрать.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PdfMenuDialog(urlString: String, onDismiss: () -> Unit) {
    val c = AyantTheme.colors
    val valid = runCatching { android.net.Uri.parse(urlString) }
        .getOrNull()?.scheme?.let { it == "http" || it == "https" } == true
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            containerColor = c.canvas,
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.detail_pdf_title), fontWeight = FontWeight.Bold) },
                    actions = {
                        TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_done), color = c.accentText) }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = c.canvas, titleContentColor = c.ink),
                )
            },
        ) { padding ->
            if (!valid) {
                Column(
                    Modifier.fillMaxSize().padding(padding),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = androidx.compose.foundation.layout.Arrangement.Center,
                ) {
                    Icon(Icons.Filled.Description, null, tint = c.inkSoft, modifier = Modifier.padding(bottom = 8.dp))
                    Text(stringResource(R.string.detail_pdf_error), fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = c.ink)
                }
                return@Scaffold
            }
            AndroidView(
                factory = { ctx ->
                    WebView(ctx).apply {
                        webViewClient = WebViewClient()
                        settings.javaScriptEnabled = true
                        // Удалённые PDF рендерим через Google Docs viewer — WebView сам их не открывает.
                        val u = if (urlString.endsWith(".pdf")) "https://docs.google.com/gview?embedded=true&url=$urlString" else urlString
                        loadUrl(u)
                    }
                },
                modifier = Modifier.fillMaxSize().padding(padding),
            )
        }
    }
}
