package kg.ayant.app.ui.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
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
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import coil.compose.AsyncImage
import kg.ayant.app.R
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.ui.host.UploadButton
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.AppViewModel

/** Максимум фото в отзыве — как `MultiImagePickerField(maxCount: 3)` на iOS. */
private const val MAX_REVIEW_PHOTOS = 3

/**
 * Написать / изменить отзыв. Зеркалит `WriteReviewView` — полноэкранный лист
 * с формой: объект (блюдо/услуга), звёзды, текст, до 3 фото. Доступно всем —
 * без визита/покупки. Отзыв всегда про конкретный объект: по умолчанию —
 * первый объект заведения.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WriteReviewDialog(
    venue: Venue,
    app: AppViewModel,
    preselectItemID: String?,
    onDismiss: () -> Unit,
) {
    val c = AyantTheme.colors
    val hasItems = venue.items.isNotEmpty()
    var selectedItemID by remember { mutableStateOf(preselectItemID ?: venue.items.firstOrNull()?.id) }
    // Подставляем существующий отзыв для выбранного объекта.
    val existing = app.myReview(venue.id, selectedItemID)
    var rating by remember(selectedItemID) { mutableIntStateOf(existing?.rating ?: 0) }
    var text by remember(selectedItemID) { mutableStateOf(existing?.text ?: "") }
    var photos by remember(selectedItemID) { mutableStateOf(existing?.photos ?: emptyList()) }
    var itemMenu by remember { mutableStateOf(false) }
    // Как на iOS: без объекта публиковать нельзя.
    val canPublish = rating > 0 && selectedItemID != null

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            containerColor = c.canvas,
            topBar = {
                TopAppBar(
                    title = {
                        Text(
                            if (existing == null) stringResource(R.string.review_new_title) else stringResource(R.string.review_edit_title),
                            fontWeight = FontWeight.Bold, maxLines = 1,
                        )
                    },
                    navigationIcon = {
                        TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_cancel), color = c.accentText) }
                    },
                    actions = {
                        TextButton(
                            enabled = canPublish,
                            onClick = {
                                val item = venue.items.firstOrNull { it.id == selectedItemID }
                                app.saveReview(
                                    venue.id, rating, text.trim(), photos,
                                    itemID = selectedItemID, itemName = item?.name,
                                )
                                onDismiss()
                            },
                        ) {
                            Text(
                                stringResource(R.string.action_publish),
                                fontWeight = FontWeight.Bold,
                                color = if (canPublish) c.accentText else c.inkSoft,
                            )
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = c.canvas, titleContentColor = c.ink),
                )
            },
        ) { padding ->
            Column(
                Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                // Что оцениваете
                if (!hasItems) {
                    FormSection(null) {
                        Text(stringResource(R.string.review_no_items_body), fontSize = 14.sp, color = c.inkSoft)
                    }
                } else {
                    FormSection(stringResource(R.string.review_what_rating)) {
                        val sel = venue.items.firstOrNull { it.id == selectedItemID }
                        Box {
                            Row(
                                Modifier.fillMaxWidth().clickable { itemMenu = true }.padding(vertical = 4.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(stringResource(R.string.detail_review_item_label), fontSize = 16.sp, color = c.ink)
                                Spacer(Modifier.weight(1f))
                                Text(
                                    "${sel?.emoji ?: ""} ${sel?.name ?: stringResource(R.string.action_choose)}",
                                    fontSize = 16.sp, color = c.inkSoft,
                                )
                                Icon(Icons.Filled.ExpandMore, null, tint = c.inkSoft, modifier = Modifier.size(18.dp))
                            }
                            DropdownMenu(expanded = itemMenu, onDismissRequest = { itemMenu = false }) {
                                venue.items.forEach { item ->
                                    DropdownMenuItem(
                                        text = { Text("${item.emoji} ${item.name}") },
                                        onClick = { selectedItemID = item.id; itemMenu = false },
                                    )
                                }
                            }
                        }
                    }
                }

                // Оценка
                FormSection(stringResource(R.string.detail_review_section_rating)) {
                    Row(
                        Modifier.fillMaxWidth().padding(vertical = 4.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                    ) {
                        for (i in 1..5) {
                            Icon(
                                if (i <= rating) Icons.Filled.Star else Icons.Filled.StarBorder,
                                contentDescription = "$i",
                                tint = Color(0xFFF5C518),
                                modifier = Modifier.size(34.dp).clickable { rating = i },
                            )
                        }
                    }
                }

                // Отзыв
                FormSection(stringResource(R.string.detail_review_section_text)) {
                    OutlinedTextField(
                        value = text, onValueChange = { text = it },
                        placeholder = { Text(stringResource(R.string.detail_review_text_placeholder)) },
                        minLines = 4, maxLines = 8,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }

                // Фото (до 3)
                FormSection(stringResource(R.string.detail_review_section_photos)) {
                    if (photos.isNotEmpty()) {
                        Row(
                            Modifier.horizontalScroll(rememberScrollState()),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            photos.forEach { u ->
                                Box(Modifier.size(72.dp)) {
                                    AsyncImage(
                                        model = u, contentDescription = null, contentScale = ContentScale.Crop,
                                        modifier = Modifier.fillMaxSize().clip(RoundedCornerShape(10.dp)).background(c.surfaceMuted),
                                    )
                                    Icon(
                                        Icons.Filled.Cancel,
                                        contentDescription = stringResource(R.string.detail_review_remove_photo),
                                        tint = Color.White,
                                        modifier = Modifier
                                            .align(Alignment.TopEnd)
                                            .padding(2.dp)
                                            .size(20.dp)
                                            .clickable { photos = photos.filterNot { it == u } },
                                    )
                                }
                            }
                        }
                    }
                    if (photos.size < MAX_REVIEW_PHOTOS) {
                        UploadButton(
                            label = stringResource(R.string.detail_review_add_photo, MAX_REVIEW_PHOTOS),
                            mimeType = "image/*",
                            folder = "reviews",
                        ) { url -> if (photos.size < MAX_REVIEW_PHOTOS) photos = photos + url }
                    }
                }
            }
        }
    }
}

/** Секция формы в духе iOS `Form`: заголовок капителью + карточка. */
@Composable
private fun FormSection(title: String?, content: @Composable () -> Unit) {
    val c = AyantTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (title != null) {
            Text(title.uppercase(), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = c.inkSoft, modifier = Modifier.padding(start = 4.dp))
        }
        Column(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.surface).padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) { content() }
    }
}
