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
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Directions
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Verified
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import kg.ayant.app.R
import kg.ayant.app.core.Directions as Dir
import kg.ayant.app.core.Links
import kg.ayant.app.core.dial
import kg.ayant.app.core.distanceText
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
import kg.ayant.app.ui.theme.gradientColors
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
    onLoyalty: (String) -> Unit = {},
) {
    val c = AyantTheme.colors
    val context = LocalContext.current
    val venue = app.venue(id = venueID) ?: run {
        Box(Modifier.fillMaxSize().background(c.canvas), contentAlignment = Alignment.Center) { Text(stringResource(R.string.venue_not_found)) }
        return
    }
    val agg = app.aggregate(venue)
    val deals = app.deals(forVenue = venue)
    val reviews = app.reviews(forVenue = venue)
    // Real photos (cover, item images, review photos) + emoji fallbacks. Mirrors galleryPhotos.
    val galleryPhotos = remember(venue, reviews) {
        buildList {
            venue.imageURL?.takeIf { it.isNotEmpty() }?.let { add(it) }
            venue.items.forEach { if (it.imageURL.isNotEmpty()) add(it.imageURL) }
            reviews.forEach { addAll(it.photos) }
            addAll(venue.photoEmojis)
            reviews.forEach { addAll(it.photoEmojis) }
        }
    }
    var showAllDeals by remember { mutableStateOf(false) }
    var hoursExpanded by remember { mutableStateOf(false) }
    var showWriteReview by remember { mutableStateOf(false) }
    var writeReviewItemID by remember { mutableStateOf<String?>(null) }
    var photoViewerStart by remember { mutableStateOf<Int?>(null) }
    var showGuestPrompt by remember { mutableStateOf(false) }
    var showPdf by remember { mutableStateOf(false) }
    var showMapOptions by remember { mutableStateOf(false) }
    var reportingReview by remember { mutableStateOf<kg.ayant.app.data.model.Review?>(null) }

    androidx.compose.runtime.LaunchedEffect(venue.id) { app.log(kg.ayant.app.data.AnalyticsMetric.VIEWS, venue.id) }

    Scaffold(
        containerColor = c.canvas,
        topBar = {
            TopAppBar(
                title = { Text(venue.name, fontWeight = FontWeight.Bold, maxLines = 1) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.action_back)) } },
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
                    VenuePhoto(venue.imageURL, venue.gradientColors, Modifier.fillMaxWidth().height(190.dp))
                    Box(Modifier.offset(x = 16.dp, y = 32.dp)) {
                        Box(Modifier.size(70.dp).clip(CircleShape).background(c.canvas), contentAlignment = Alignment.Center) {
                            VenueAvatar(venue.gradientColors, venue.imageURL, 64)
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
                    val distanceKm = location.distanceKm(venue.latitude, venue.longitude)
                    if (distanceKm != null) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.LocationOn, null, tint = c.inkSoft, modifier = Modifier.size(13.dp))
                            Text(" " + stringResource(R.string.venue_distance_from_you, distanceKm.distanceText()), fontSize = 12.sp, color = c.inkSoft)
                        }
                    }
                    if (venue.savedByCount > 0) {
                        Text(stringResource(R.string.venue_saved_by_count, venue.savedByCount), fontSize = 12.sp, color = c.inkSoft)
                    }
                }
            }

            // Action row
            Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                if (venue.phone.isNotBlank()) ActionButton(stringResource(R.string.act_call), Icons.Filled.Call, Modifier.weight(1f)) { context.dial(venue.phone) }
                if (venue.address.isNotBlank()) ActionButton(stringResource(R.string.act_route), Icons.Filled.Directions, Modifier.weight(1f)) { showMapOptions = true }
                ActionButton(if (app.isSaved(venue)) stringResource(R.string.act_saved) else stringResource(R.string.act_save), if (app.isSaved(venue)) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder, Modifier.weight(1f)) {
                    if (session.isGuest) showGuestPrompt = true else app.toggleSave(venue)
                }
                ActionButton(stringResource(R.string.act_share), Icons.Filled.Share, Modifier.weight(1f)) {
                    context.shareText(context.getString(R.string.venue_share_text, venue.name, venue.address, Links.venue(venue.id)), venue.name)
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
                        Text(stringResource(R.string.today), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = c.accent)
                        Text(venue.todaySpecialText ?: "", fontSize = 14.sp, fontWeight = FontWeight.Medium, color = c.ink)
                    }
                }
            }

            // Loyalty banner
            if (venue.loyaltyEnabled) {
                Column(
                    Modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.accentGradient)
                        .clickable { onLoyalty(venue.id) }.padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.venue_loyalty_card), fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.White)
                        Spacer(Modifier.weight(1f))
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Color.White, modifier = Modifier.size(18.dp))
                    }
                    Text(stringResource(R.string.venue_loyalty_progress, venue.loyaltyGoal, venue.loyaltyReward), fontSize = 12.sp, color = Color.White.copy(alpha = 0.9f))
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
                // Branches
                venue.branches.forEach { b ->
                    InfoRow(Icons.Filled.LocationOn, b.address) { context.openUrl(Dir.dgis(b.latitude, b.longitude)) }
                }
                // Social links
                val socials = buildList {
                    venue.whatsappURL?.let { add(Triple("WhatsApp", Color(0xFF25D366), it)) }
                    venue.telegramURL?.let { add(Triple("Telegram", Color(0xFF2AABEE), it)) }
                    venue.instagramURL?.let { add(Triple("Instagram", Color(0xFFE1306C), it)) }
                }
                if (socials.isNotEmpty()) {
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        socials.forEach { (name, col, url) ->
                            Box(
                                Modifier.size(40.dp).clip(CircleShape).background(col).clickable { context.openUrl(url) },
                                contentAlignment = Alignment.Center,
                            ) { Text(name.take(1), color = Color.White, fontWeight = FontWeight.Bold) }
                        }
                    }
                }
                // PDF menu
                if (!venue.pdfMenuURL.isNullOrEmpty()) {
                    Row(Modifier.fillMaxWidth().clickable { showPdf = true }, verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.AutoMirrored.Filled.MenuBook, null, tint = c.accent, modifier = Modifier.size(18.dp))
                        Text(" " + stringResource(R.string.venue_pdf_menu), fontSize = 14.sp, color = c.ink)
                    }
                }
            }

            // Deals grid (first 6, then "смотреть все")
            if (deals.isNotEmpty()) {
                val shownDeals = if (showAllDeals) deals else deals.take(6)
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.publications), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink)
                        Spacer(Modifier.weight(1f))
                        if (deals.size > 6 && !showAllDeals) {
                            Text(stringResource(R.string.venue_see_all_count, deals.size), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = c.accent, modifier = Modifier.clickable { showAllDeals = true })
                        }
                    }
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(3),
                        modifier = Modifier.padding(horizontal = 16.dp).height(((shownDeals.size + 2) / 3 * 116).dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        userScrollEnabled = false,
                    ) {
                        items(shownDeals) { d ->
                            Box(
                                Modifier.height(108.dp).clip(RoundedCornerShape(10.dp)).clickable { onDeal(d.id) },
                            ) {
                                CoverImage(d.imageURL, venue.gradientColors, d.emoji, Modifier.fillMaxSize(), emojiSize = 34)
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

            // Photos gallery (real photos + emoji fallbacks)
            if (galleryPhotos.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(stringResource(R.string.photos), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink, modifier = Modifier.padding(horizontal = 16.dp))
                    Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        galleryPhotos.forEachIndexed { i, p ->
                            Box(Modifier.size(90.dp).clip(RoundedCornerShape(12.dp)).background(c.surfaceMuted).clickable { photoViewerStart = i }, contentAlignment = Alignment.Center) {
                                if (p.startsWith("http")) {
                                    coil.compose.AsyncImage(model = p, contentDescription = null, contentScale = androidx.compose.ui.layout.ContentScale.Crop, modifier = Modifier.fillMaxSize())
                                } else {
                                    Text(p, fontSize = 40.sp)
                                }
                            }
                        }
                    }
                }
            }

            // Review objects (dishes / services)
            if (venue.items.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(stringResource(R.string.rate_item), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink, modifier = Modifier.padding(horizontal = 16.dp))
                    Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        venue.items.forEach { item ->
                            Column(
                                horizontalAlignment = Alignment.CenterHorizontally,
                                modifier = Modifier.width(80.dp).clickable {
                                    if (session.isGuest) showGuestPrompt = true
                                    else { writeReviewItemID = item.id; showWriteReview = true }
                                },
                            ) {
                                Box(Modifier.size(70.dp).clip(RoundedCornerShape(14.dp)).background(c.surfaceMuted), contentAlignment = Alignment.Center) {
                                    Text(item.emoji, fontSize = 32.sp)
                                }
                                Text(item.name, fontSize = 12.sp, color = c.ink, maxLines = 1)
                            }
                        }
                    }
                }
            }

            // Reviews
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Text(stringResource(R.string.reviews), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink, modifier = Modifier.padding(horizontal = 16.dp))
                Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(20.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("%.1f".format(agg.first), fontSize = 40.sp, fontWeight = FontWeight.Bold, color = c.ink)
                        StarRating(rating = agg.first, size = 12)
                        Text(stringResource(R.string.venue_reviews_count, agg.second), fontSize = 11.sp, color = c.inkSoft)
                    }
                    RatingBreakdown(app.ratingBreakdown(venue), Modifier.weight(1f))
                }
                if (venue.items.isEmpty()) {
                    Text(stringResource(R.string.venue_reviews_no_items), fontSize = 13.sp, color = c.inkSoft, modifier = Modifier.padding(horizontal = 16.dp))
                } else {
                    Text(
                        stringResource(R.string.rate_item),
                        fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Color.White,
                        modifier = Modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(c.accent).clickable {
                            if (session.isGuest) showGuestPrompt = true else { writeReviewItemID = null; showWriteReview = true }
                        }.padding(vertical = 12.dp),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    )
                }
                if (reviews.isEmpty()) {
                    Text(stringResource(R.string.no_reviews), fontSize = 14.sp, color = c.inkSoft, modifier = Modifier.padding(horizontal = 16.dp))
                } else {
                    Column(Modifier.padding(horizontal = 16.dp)) {
                        reviews.forEach { r ->
                            ReviewRow(r, onReport = if (r.authorID != app.currentUserID) ({ reportingReview = r }) else null)
                            Box(Modifier.fillMaxWidth().height(0.5.dp).background(c.hairline))
                        }
                    }
                }
            }
        }
    }

    if (showWriteReview) {
        WriteReviewDialog(venue = venue, app = app, preselectItemID = writeReviewItemID, onDismiss = { showWriteReview = false })
    }
    photoViewerStart?.let { start ->
        PhotoViewerDialog(photos = galleryPhotos, startIndex = start, onDismiss = { photoViewerStart = null })
    }
    if (showPdf && !venue.pdfMenuURL.isNullOrEmpty()) {
        PdfMenuDialog(venue.pdfMenuURL!!, onDismiss = { showPdf = false })
    }
    if (showGuestPrompt) {
        AlertDialog(
            onDismissRequest = { showGuestPrompt = false },
            title = { Text(stringResource(R.string.guest_title)) },
            text = { Text(stringResource(R.string.guest_body)) },
            confirmButton = { TextButton(onClick = { showGuestPrompt = false }) { Text(stringResource(R.string.action_ok)) } },
        )
    }
    if (showMapOptions) {
        AlertDialog(
            onDismissRequest = { showMapOptions = false },
            title = { Text(stringResource(R.string.open_on_map)) },
            text = { Text(stringResource(R.string.map_choose_app)) },
            confirmButton = { TextButton(onClick = { showMapOptions = false; context.openUrl(Dir.dgis(venue.latitude, venue.longitude)) }) { Text("2GIS") } },
            dismissButton = { TextButton(onClick = { showMapOptions = false; context.openUrl(Dir.google(venue.latitude, venue.longitude)) }) { Text("Google Maps") } },
        )
    }
    if (reportingReview != null) {
        var reported by remember { mutableStateOf(false) }
        AlertDialog(
            onDismissRequest = { reportingReview = null },
            title = { Text(if (reported) stringResource(R.string.review_report_thanks_title) else stringResource(R.string.review_report_title)) },
            text = { Text(if (reported) stringResource(R.string.review_report_sent) else stringResource(R.string.review_report_choose)) },
            confirmButton = {
                if (reported) TextButton(onClick = { reportingReview = null }) { Text(stringResource(R.string.action_done)) }
                else TextButton(onClick = { reported = true }) { Text(stringResource(R.string.review_report_spam)) }
            },
            dismissButton = {
                if (!reported) TextButton(onClick = { reported = true }) { Text(stringResource(R.string.review_report_offensive)) }
            },
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
private fun ReviewRow(r: kg.ayant.app.data.model.Review, onReport: (() -> Unit)? = null) {
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
            if (r.verifiedVisit) {
                Text(stringResource(R.string.review_verified_visit), fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = c.open, modifier = Modifier.clip(RoundedCornerShape(50)).background(c.open.copy(alpha = 0.15f)).padding(horizontal = 7.dp, vertical = 3.dp))
            }
            if (onReport != null) {
                Icon(Icons.Filled.Flag, stringResource(R.string.review_report_action), tint = c.inkSoft, modifier = Modifier.padding(start = 6.dp).size(18.dp).clickable(onClick = onReport))
            }
        }
        r.itemName?.takeIf { it.isNotEmpty() }?.let { itemName ->
            Text(stringResource(R.string.review_about_item, itemName), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = c.accent, modifier = Modifier.clip(RoundedCornerShape(50)).background(c.accent.copy(alpha = 0.12f)).padding(horizontal = 8.dp, vertical = 3.dp))
        }
        if (r.text.isNotEmpty()) Text(r.text, fontSize = 14.sp, color = c.ink)
        r.hostReply?.let { reply ->
            Column(Modifier.padding(start = 12.dp).fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(c.surfaceMuted).padding(10.dp)) {
                Text(stringResource(R.string.review_host_reply), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = c.accent)
                Text(reply.text, fontSize = 13.sp, color = c.ink)
            }
        }
    }
}
