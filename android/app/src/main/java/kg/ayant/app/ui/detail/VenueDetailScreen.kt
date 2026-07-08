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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.border
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Directions
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import kg.ayant.app.core.Directions as Dir
import kg.ayant.app.core.Links
import kg.ayant.app.core.dial
import kg.ayant.app.core.openUrl
import kg.ayant.app.core.shareText
import kg.ayant.app.data.model.Venue
import kg.ayant.app.location.LocationManager
import kg.ayant.app.ui.components.CoverImage
import kg.ayant.app.ui.components.RatingBreakdown
import kg.ayant.app.ui.components.StarRating
import kg.ayant.app.ui.components.VenueAvatar
import kg.ayant.app.ui.components.VenuePhoto
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.ui.vm.SessionViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VenueDetailScreen(
    venueID: String,
    app: AppViewModel,
    session: SessionViewModel,
    location: LocationManager,
    onBack: () -> Unit,
    onDeal: (String) -> Unit,
) {
    val c = AyantTheme.colors
    val context = LocalContext.current
    val venue = app.venue(id = venueID) ?: run {
        Box(Modifier.fillMaxSize().background(c.canvas), contentAlignment = Alignment.Center) { Text("Заведение не найдено") }
        return
    }
    val agg = app.aggregate(venue)
    val deals = app.deals(forVenue = venue)
    val reviews = app.reviews(forVenue = venue)
    var hoursExpanded by remember { mutableStateOf(false) }
    var writeReview by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = c.canvas,
        topBar = {
            TopAppBar(
                title = { Text(venue.name, fontWeight = FontWeight.Bold, maxLines = 1) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = c.canvas, titleContentColor = c.ink),
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            // Header
            Column {
                Box {
                    VenuePhoto(venue.imageURL, venue.gradient, Modifier.fillMaxWidth().height(190.dp))
                    Box(Modifier.offset(x = 16.dp, y = 32.dp)) {
                        Box(Modifier.size(70.dp).clip(CircleShape).background(c.canvas), contentAlignment = Alignment.Center) {
                            VenueAvatar(venue.gradient, venue.imageURL, 64)
                        }
                    }
                }
                Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 40.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(venue.name, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = c.ink)
                        if (venue.isVerified) Icon(Icons.Filled.Verified, null, tint = Color(0xFF2F80ED), modifier = Modifier.padding(start = 6.dp).size(18.dp))
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            venue.category.rawValue, fontSize = 12.sp, color = c.ink,
                            modifier = Modifier.clip(RoundedCornerShape(50)).background(c.surfaceMuted).padding(horizontal = 10.dp, vertical = 4.dp),
                        )
                        StarRating(rating = agg.first, count = agg.second)
                    }
                    if (venue.savedByCount > 0) {
                        Text("Сохранили ${venue.savedByCount} человек", fontSize = 12.sp, color = c.inkSoft)
                    }
                }
            }

            // Action row
            Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (venue.phone.isNotBlank()) ActionButton("Позвонить", Icons.Filled.Call, Modifier.weight(1f)) { context.dial(venue.phone) }
                if (venue.address.isNotBlank()) ActionButton("Маршрут", Icons.Filled.Directions, Modifier.weight(1f)) { context.openUrl(Dir.dgis(venue.latitude, venue.longitude)) }
                ActionButton(if (app.isSaved(venue)) "Сохранено" else "Сохранить", if (app.isSaved(venue)) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder, Modifier.weight(1f)) {
                    if (!session.isGuest) app.toggleSave(venue)
                }
                ActionButton("Поделиться", Icons.Filled.Share, Modifier.weight(1f)) {
                    context.shareText("${venue.name}, ${venue.address}. Нашёл в Ayant! ${Links.venue(venue.id)}", venue.name)
                }
            }

            // Today's special
            if (venue.hasTodaySpecial) {
                Row(
                    Modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.accent.copy(alpha = 0.1f)).padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("⭐️", fontSize = 22.sp)
                    Column(Modifier.padding(start = 10.dp)) {
                        Text("Сегодня", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = c.accent)
                        Text(venue.todaySpecialText ?: "", fontSize = 14.sp, fontWeight = FontWeight.Medium, color = c.ink)
                    }
                }
            }

            // Info section
            Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                if (venue.address.isNotBlank()) {
                    InfoRow(Icons.Filled.LocationOn, venue.address) { context.openUrl(Dir.dgis(venue.latitude, venue.longitude)) }
                }
                if (venue.phone.isNotBlank()) {
                    InfoRow(Icons.Filled.Call, venue.phone) { context.dial(venue.phone) }
                }
                // Hours (expandable)
                Row(Modifier.fillMaxWidth().clickable { hoursExpanded = !hoursExpanded }, verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Schedule, null, tint = if (venue.isOpenNow) c.open else c.inkSoft, modifier = Modifier.size(18.dp))
                    Text(" ${venue.hoursStatusText}", fontSize = 14.sp, color = if (venue.isOpenNow) c.open else c.inkSoft)
                    Spacer(Modifier.weight(1f))
                    Icon(if (hoursExpanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null, tint = c.inkSoft, modifier = Modifier.size(18.dp))
                }
                if (hoursExpanded) {
                    Column(Modifier.padding(start = 28.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        for (i in 0 until 7) {
                            val isToday = i == Venue.todayIndex
                            Row(Modifier.fillMaxWidth()) {
                                Text(Venue.weekdayLong[i], fontSize = 12.sp, fontWeight = if (isToday) FontWeight.SemiBold else FontWeight.Normal, color = if (isToday) c.ink else c.inkSoft)
                                Spacer(Modifier.weight(1f))
                                Text(venue.hours(i).label, fontSize = 12.sp, color = if (venue.hours(i).closed) c.inkSoft else c.ink)
                            }
                        }
                    }
                }
            }

            // Deals grid
            if (deals.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Публикации", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink, modifier = Modifier.padding(horizontal = 16.dp))
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(3),
                        modifier = Modifier.padding(horizontal = 16.dp).height(((deals.size + 2) / 3 * 116).dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        userScrollEnabled = false,
                    ) {
                        items(deals) { d ->
                            Box(
                                Modifier.height(108.dp).clip(RoundedCornerShape(10.dp)).clickable { onDeal(d.id) },
                            ) {
                                CoverImage(d.imageURL, venue.gradient, d.emoji, Modifier.fillMaxSize(), emojiSize = 34)
                                d.discountPercent?.let { pct ->
                                    Text(
                                        "−$pct%", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.White,
                                        modifier = Modifier.align(Alignment.BottomStart).padding(6.dp).clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.4f)).padding(horizontal = 6.dp, vertical = 3.dp),
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // Photos gallery (emoji placeholders)
            val photos = venue.photoEmojis
            if (photos.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Фото", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink, modifier = Modifier.padding(horizontal = 16.dp))
                    Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        photos.forEach { emoji ->
                            Box(Modifier.size(90.dp).clip(RoundedCornerShape(12.dp)).background(c.surfaceMuted), contentAlignment = Alignment.Center) {
                                Text(emoji, fontSize = 40.sp)
                            }
                        }
                    }
                }
            }

            // Reviews
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text("Отзывы", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink, modifier = Modifier.padding(horizontal = 16.dp))
                Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(20.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("%.1f".format(agg.first), fontSize = 40.sp, fontWeight = FontWeight.Bold, color = c.ink)
                        StarRating(rating = agg.first, size = 12)
                        Text("${agg.second} отзывов", fontSize = 11.sp, color = c.inkSoft)
                    }
                    RatingBreakdown(app.ratingBreakdown(venue), Modifier.weight(1f))
                }
                if (!session.isGuest) {
                    Text(
                        "Оставить отзыв",
                        fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Color.White,
                        modifier = Modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(c.accent).clickable { writeReview = true }.padding(vertical = 12.dp),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    )
                }
                if (reviews.isEmpty()) {
                    Text("Пока нет отзывов. Будь первым!", fontSize = 14.sp, color = c.inkSoft, modifier = Modifier.padding(horizontal = 16.dp))
                } else {
                    Column(Modifier.padding(horizontal = 16.dp)) {
                        reviews.forEach { r -> ReviewRow(r); Box(Modifier.fillMaxWidth().height(0.5.dp).background(c.hairline)) }
                    }
                }
            }
        }
    }

    if (writeReview) {
        WriteReviewDialog(
            existing = app.myReview(venue.id, null),
            onDismiss = { writeReview = false },
            onSave = { rating, text -> app.saveReview(venue.id, rating, text); writeReview = false },
        )
    }
}

@Composable
private fun ActionButton(title: String, icon: androidx.compose.ui.graphics.vector.ImageVector, modifier: Modifier, onClick: () -> Unit) {
    val c = AyantTheme.colors
    Column(
        modifier.clip(RoundedCornerShape(12.dp)).background(c.surfaceMuted).clickable(onClick = onClick).padding(vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Icon(icon, null, tint = c.accent, modifier = Modifier.size(18.dp))
        Text(title, fontSize = 11.sp, color = c.accent, maxLines = 1)
    }
}

@Composable
private fun InfoRow(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String, onClick: () -> Unit) {
    val c = AyantTheme.colors
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = c.inkSoft, modifier = Modifier.size(18.dp))
        Text(" $text", fontSize = 14.sp, color = c.ink)
    }
}

@Composable
private fun ReviewRow(r: kg.ayant.app.data.model.Review) {
    val c = AyantTheme.colors
    Column(Modifier.fillMaxWidth().padding(vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(36.dp).clip(CircleShape).background(c.surfaceMuted), contentAlignment = Alignment.Center) {
                Text(r.initial, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = c.ink)
            }
            Column(Modifier.padding(start = 10.dp).weight(1f)) {
                Text(r.authorName, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = c.ink)
                StarRating(rating = r.rating.toDouble(), size = 11)
            }
        }
        if (r.text.isNotEmpty()) Text(r.text, fontSize = 14.sp, color = c.ink)
        r.hostReply?.let { reply ->
            Column(Modifier.padding(start = 12.dp).fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(c.surfaceMuted).padding(10.dp)) {
                Text("Ответ заведения", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = c.accent)
                Text(reply.text, fontSize = 13.sp, color = c.ink)
            }
        }
    }
}
