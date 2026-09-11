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
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.statusBarsPadding
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
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
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
import androidx.compose.runtime.collectAsState
import androidx.lifecycle.viewmodel.compose.viewModel
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
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.location.LocationManager
import kg.ayant.app.ui.components.CoverImage
import kg.ayant.app.ui.components.RatingBreakdown
import kg.ayant.app.ui.components.StarRating
import kg.ayant.app.ui.components.VenueAvatar
import kg.ayant.app.ui.components.VenuePhoto
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.bonus.AyantProgressBar
import kg.ayant.app.ui.bonus.pointsModeLabel
import kg.ayant.app.ui.theme.gradientColors
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.ui.vm.SessionViewModel
import kg.ayant.app.domain.model.Deal
import kg.ayant.app.ui.theme.AyantRadius
import androidx.compose.foundation.layout.aspectRatio
import kg.ayant.app.domain.pointsActive
import kg.ayant.app.domain.stampsActive

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VenueDetailScreen(
    venueID: String,
    app: AppViewModel,
    session: SessionViewModel,
    location: LocationManager,
    points: kg.ayant.app.ui.vm.PointsViewModel,
    onBack: () -> Unit,
    onDeal: (String) -> Unit,
    onLoyalty: (String) -> Unit = {},
    onPoints: (String) -> Unit = {},
) {
    val c = AyantTheme.colors
    val context = LocalContext.current
    val venue = app.venue(id = venueID) ?: run {
        Box(Modifier.fillMaxSize().background(c.canvas), contentAlignment = Alignment.Center) { Text(stringResource(R.string.venue_not_found)) }
        return
    }
    // Состояние карточки — одним значением из VenueDetailViewModel (state + send).
    val detail: kg.ayant.app.ui.vm.VenueDetailViewModel = viewModel(factory = kg.ayant.app.core.ayantFactory())
    val detailState by detail.state.collectAsState()
    // Каталог/отзывы принадлежат ленте и профилю — пересобираем срез, когда они менялись.
    val feedState by app.feedState.collectAsState()
    val profileState by app.profileFlow.collectAsState()

    val agg = detailState.aggregate.let { it.rating to it.count }
    val deals = detailState.deals
    val reviews = detailState.reviews
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
    var showAllBranches by remember { mutableStateOf(false) }
    var showWriteReview by remember { mutableStateOf(false) }
    var writeReviewItemID by remember { mutableStateOf<String?>(null) }
    var photoViewerStart by remember { mutableStateOf<Int?>(null) }
    var showGuestPrompt by remember { mutableStateOf(false) }
    var showGuestQr by remember { mutableStateOf(false) }

    if (showGuestQr) {
        kg.ayant.app.ui.auth.GuestAlert(session, kg.ayant.app.ui.auth.GuestGate.QR) { showGuestQr = false }
    }
    var showPdf by remember { mutableStateOf(false) }
    var showMapOptions by remember { mutableStateOf(false) }
    var reportingReview by remember { mutableStateOf<kg.ayant.app.domain.model.Review?>(null) }

    // Баланс баллов приходит snapshot-листенером — без подписки карточка не обновится.
    val pointsState by points.state.collectAsState()

    androidx.compose.runtime.LaunchedEffect(venue.id) {
        detail.bind(app)
        detail.send(kg.ayant.app.domain.VenueDetailIntent.Open(venue.id))
    }
    androidx.compose.runtime.LaunchedEffect(feedState, profileState) { detail.refresh() }

    // Вкладки листа (SCREENS.md G3). Разделы прежней страницы разложены по ним
    // целиком — редизайн меняет порядок и подачу, а не состав.
    var tab by remember { mutableStateOf(VenueTab.Deals) }

    Scaffold(
        containerColor = c.canvas,
        bottomBar = {
            VenueStickyBar(
                isSaved = detailState.isSaved,
                // Личный QR привязан к аккаунту: заведению некуда начислять
                // баллы гостя, поэтому вместо кода — приглашение войти.
                onShowQr = { if (session.isGuest) showGuestQr = true else onPoints(venue.id) },
                onToggleSave = {
                    if (session.isGuest) showGuestPrompt = true
                    else detail.send(kg.ayant.app.domain.VenueDetailIntent.ToggleSave)
                },
            )
        },
    ) { padding ->
      Box(Modifier.fillMaxSize().padding(bottom = padding.calculateBottomPadding())) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
        ) {
            // Обложка 330. Кнопки НЕ здесь — см. закреплённый ряд ниже.
            Box(Modifier.fillMaxWidth().height(330.dp)) {
                VenuePhoto(venue.imageURL, venue.gradientColors, Modifier.fillMaxSize())
                Box(
                    Modifier.fillMaxWidth().height(150.dp).background(
                        Brush.verticalGradient(
                            listOf(Color(0xFF17130F).copy(alpha = 0.30f), Color.Transparent)
                        )
                    )
                )
            }

            // Лист, накрывающий обложку
            Column(
                Modifier
                    .fillMaxWidth()
                    .offset(y = (-36).dp)
                    .clip(RoundedCornerShape(topStart = 34.dp, topEnd = 34.dp))
                    .background(c.canvas)
                    .padding(top = 22.dp, bottom = 30.dp),
            ) {
                Column(Modifier.padding(horizontal = 20.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                            Icon(Icons.Filled.Star, null, tint = Color(0xFFFF9500), modifier = Modifier.size(13.dp))
                            Text(ratingText(agg.first), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = c.ink)
                        }
                        Text(
                            "· ${agg.second} ${reviewsWord(agg.second)}",
                            fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = c.inkSoft,
                        )
                        if (venue.isVerified) {
                            Icon(Icons.Filled.Verified, null, tint = Color(0xFF4DA3FF), modifier = Modifier.size(13.dp))
                        }
                    }
                    Spacer(Modifier.height(10.dp))
                    Text(
                        venue.name, fontSize = 36.sp, fontWeight = FontWeight.Black,
                        letterSpacing = (-1.9).sp, lineHeight = 35.sp, color = c.ink,
                    )
                    Spacer(Modifier.height(9.dp))
                    Text(
                        buildString {
                            append(venue.category.rawValue)
                            append(" · ").append(venue.district)
                            location.distanceKm(venue.latitude, venue.longitude)?.let {
                                append(" · ").append(it.distanceText())
                            }
                        },
                        fontSize = 14.sp, color = c.inkSoft,
                    )

                    // Чипы: только то, что реально есть в модели (полей удобств нет).
                    Spacer(Modifier.height(16.dp))
                    Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                        val openColor = if (venue.isOpenNow) c.open else c.inkSoft
                        Row(
                            Modifier.clip(CircleShape).background(openColor.copy(alpha = 0.12f))
                                .padding(horizontal = 13.dp, vertical = 8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Box(Modifier.size(6.dp).clip(CircleShape).background(openColor))
                            Text(venue.hoursStatusText, fontSize = 12.5.sp, fontWeight = FontWeight.Bold, color = openColor)
                        }
                        if (venue.branches.isNotEmpty()) {
                            Text(
                                "${venue.branches.size + 1} адреса",
                                fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold, color = c.inkSoft,
                                modifier = Modifier.clip(CircleShape).background(c.surface)
                                    .padding(horizontal = 13.dp, vertical = 8.dp),
                            )
                        }
                    }

                    // Баллы САН — герой-карточка
                    if (venue.pointsActive) {
                        Spacer(Modifier.height(20.dp))
                        VenuePointsHeroCard(venue, pointsState.balance(venue.id)) { onPoints(venue.id) }
                    }
                }

                // Сегментированный переключатель
                Spacer(Modifier.height(22.dp))
                Row(
                    Modifier.padding(horizontal = 20.dp).clip(RoundedCornerShape(16.dp))
                        .background(c.surfaceMuted).padding(4.dp),
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    VenueTab.entries.forEach { t ->
                        VenueTabButton(t, tab == t, Modifier.weight(1f)) { tab = t }
                    }
                }
                Spacer(Modifier.height(16.dp))

                // Содержимое вкладки. Блоки сохраняют свой padding 16 — внешние 4
                // добирают до 20 экрана, чтобы не править каждый из них.
                Column(
                    Modifier.padding(horizontal = 4.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                ) {
                    when (tab) {
                        VenueTab.Deals -> {
                            if (deals.isEmpty()) {
                                Text(
                                    stringResource(R.string.venue_no_deals),
                                    fontSize = 14.sp, color = c.inkSoft,
                                    modifier = Modifier.padding(horizontal = 16.dp),
                                )
                            } else {
                                VenuePublicationsGrid(deals, venue) { onDeal(it) }
                            }
                        }
                        VenueTab.Reviews -> {
                        // Reviews
                        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                            Text(stringResource(R.string.reviews), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink, modifier = Modifier.padding(horizontal = 16.dp))
                            Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(20.dp), verticalAlignment = Alignment.CenterVertically) {
                                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                    Text("%.1f".format(agg.first), fontSize = 40.sp, fontWeight = FontWeight.Bold, color = c.ink)
                                    StarRating(rating = agg.first, size = 12)
                                    Text(stringResource(R.string.venue_reviews_count, agg.second), fontSize = 11.sp, color = c.inkSoft)
                                }
                                RatingBreakdown(detailState.ratingBreakdown, Modifier.weight(1f))
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
                        VenueTab.Info -> {
                        // Today's special
                        if (venue.hasTodaySpecial) {
                            Row(
                                Modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.accent.copy(alpha = 0.1f)).padding(14.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text("⭐️", fontSize = 22.sp)
                                Column(Modifier.padding(start = 10.dp)) {
                                    Text(stringResource(R.string.today), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = c.accentText)
                                    Text(venue.todaySpecialText ?: "", fontSize = 14.sp, fontWeight = FontWeight.Medium, color = c.ink)
                                }
                            }
                        }
                        // Action row
                        Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            if (venue.phone.isNotBlank()) ActionButton(stringResource(R.string.act_call), Icons.Filled.Call, Modifier.weight(1f)) {
                                detail.send(kg.ayant.app.domain.VenueDetailIntent.LogContact(kg.ayant.app.domain.ContactAction.CALL))
                                context.dial(venue.phone)
                            }
                            if (venue.address.isNotBlank()) ActionButton(stringResource(R.string.act_route), Icons.Filled.Directions, Modifier.weight(1f)) {
                                detail.send(kg.ayant.app.domain.VenueDetailIntent.LogContact(kg.ayant.app.domain.ContactAction.MAPS))
                                showMapOptions = true
                            }
                            ActionButton(if (detailState.isSaved) stringResource(R.string.act_saved) else stringResource(R.string.act_save), if (detailState.isSaved) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder, Modifier.weight(1f)) {
                                if (session.isGuest) showGuestPrompt = true else detail.send(kg.ayant.app.domain.VenueDetailIntent.ToggleSave)
                            }
                            ActionButton(stringResource(R.string.act_share), Icons.Filled.Share, Modifier.weight(1f)) {
                                context.shareText(context.getString(R.string.venue_share_text, venue.name, venue.address, Links.venue(venue.id)), venue.name)
                            }
                        }
                        // Loyalty banner
                        // Штампы показываем, только если баллы выключены:
                        // механика одна на заведение.
                        if (venue.stampsActive) {
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
                                InfoRow(Icons.Filled.Call, venue.phone) {
                                    detail.send(kg.ayant.app.domain.VenueDetailIntent.LogContact(kg.ayant.app.domain.ContactAction.CALL))
                                    context.dial(venue.phone)
                                }
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
                            // Branches — свёрнуты за кнопкой «Посмотреть все адреса».
                            if (venue.branches.isNotEmpty()) {
                                Row(Modifier.fillMaxWidth().clickable { showAllBranches = !showAllBranches }, verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Filled.LocationOn, null, tint = c.accentText, modifier = Modifier.size(18.dp))
                                    Text(
                                        if (showAllBranches) " Скрыть адреса"
                                        else " Посмотреть все адреса (${venue.branches.size + 1})",
                                        fontSize = 14.sp, fontWeight = FontWeight.Medium, color = c.accentText
                                    )
                                    Spacer(Modifier.weight(1f))
                                    Icon(if (showAllBranches) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null, tint = c.accentText, modifier = Modifier.size(18.dp))
                                }
                                if (showAllBranches) {
                                    venue.branches.forEach { b ->
                                        InfoRow(Icons.Filled.LocationOn, b.address) { context.openUrl(Dir.dgis(b.latitude, b.longitude)) }
                                    }
                                }
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
                                    Icon(Icons.AutoMirrored.Filled.MenuBook, null, tint = c.accentText, modifier = Modifier.size(18.dp))
                                    Text(" " + stringResource(R.string.venue_pdf_menu), fontSize = 14.sp, color = c.ink)
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
                        }
                    }
                }
            }
        }

        // Кнопки «назад / в закладки / поделиться» закреплены поверх экрана, а
        // не лежат в обложке внутри скролла: иначе выход уезжает вместе с фото.
        Row(
            Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .padding(horizontal = 18.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            FloatingIconButton(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.action_back), onBack)
            Spacer(Modifier.weight(1f))
            FloatingIconButton(
                if (detailState.isSaved) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
                stringResource(R.string.act_save),
            ) {
                if (session.isGuest) showGuestPrompt = true
                else detail.send(kg.ayant.app.domain.VenueDetailIntent.ToggleSave)
            }
            Spacer(Modifier.width(8.dp))
            FloatingIconButton(Icons.Filled.Share, stringResource(R.string.act_share)) {
                context.shareText(
                    context.getString(R.string.venue_share_text, venue.name, venue.address, Links.venue(venue.id)),
                    venue.name,
                )
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
        Icon(icon, null, tint = c.accentText, modifier = Modifier.size(18.dp))
        Text(title, fontSize = 11.sp, color = c.accentText, maxLines = 1)
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
private fun ReviewRow(r: kg.ayant.app.domain.model.Review, onReport: (() -> Unit)? = null) {
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
            Text(stringResource(R.string.review_about_item, itemName), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = c.accentText, modifier = Modifier.clip(RoundedCornerShape(50)).background(c.accent.copy(alpha = 0.12f)).padding(horizontal = 8.dp, vertical = 3.dp))
        }
        if (r.text.isNotEmpty()) Text(r.text, fontSize = 14.sp, color = c.ink)
        r.hostReply?.let { reply ->
            Column(Modifier.padding(start = 12.dp).fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(c.surfaceMuted).padding(10.dp)) {
                Text(stringResource(R.string.review_host_reply), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = c.accentText)
                Text(reply.text, fontSize = 13.sp, color = c.ink)
            }
        }
    }
}

// MARK: - Redesign pieces (SCREENS.md G3). Mirror DetailViews.swift.

enum class VenueTab(val labelRes: Int) {
    Deals(R.string.venue_tab_deals),
    Reviews(R.string.venue_tab_reviews),
    Info(R.string.venue_tab_info),
}

@Composable
private fun VenueTabButton(tab: VenueTab, isOn: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val c = AyantTheme.colors
    Box(
        modifier
            .clip(RoundedCornerShape(13.dp))
            .then(if (isOn) Modifier.background(c.surface) else Modifier)
            .clickable(onClick = onClick)
            .padding(vertical = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            stringResource(tab.labelRes),
            fontSize = 13.5.sp,
            fontWeight = if (isOn) FontWeight.Bold else FontWeight.SemiBold,
            color = if (isOn) c.ink else c.inkSoft,
        )
    }
}

/** Плавающая кнопка поверх обложки. */
@Composable
private fun FloatingIconButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    onClick: () -> Unit,
) {
    val c = AyantTheme.colors
    Box(
        Modifier
            .size(42.dp)
            .clip(RoundedCornerShape(15.dp))
            .background(Color.White.copy(alpha = 0.9f))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = label, tint = c.ink, modifier = Modifier.size(16.dp))
    }
}

/** Нижняя панель: «Показать QR» + сердечко. Таб-бар на этом экране скрыт. */
@Composable
private fun VenueStickyBar(isSaved: Boolean, onShowQr: () -> Unit, onToggleSave: () -> Unit) {
    val c = AyantTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .background(c.canvas.copy(alpha = 0.94f))
            .navigationBarsPadding()
            .padding(horizontal = 18.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .weight(1f)
                .clip(RoundedCornerShape(18.dp))
                .background(c.accentGradient)
                .clickable(onClick = onShowQr)
                .padding(vertical = 16.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(stringResource(R.string.venue_show_qr), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Color.White)
        }
        Box(
            Modifier
                .size(width = 56.dp, height = 54.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(c.surface)
                .clickable(onClick = onToggleSave),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                if (isSaved) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                contentDescription = stringResource(R.string.act_save),
                tint = c.accentText, modifier = Modifier.size(19.dp),
            )
        }
    }
}

/** Акцентная карточка баллов (SCREENS.md G3 §5). */
@Composable
private fun VenuePointsHeroCard(venue: Venue, balance: Int, onClick: () -> Unit) {
    val c = AyantTheme.colors
    val next = venue.pointsRewards.filter { it.active && it.cost > balance }.minByOrNull { it.cost }
    val fraction = next?.let { (balance.toFloat() / it.cost.coerceAtLeast(1)).coerceAtMost(1f) } ?: 1f
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(26.dp))
            .background(c.accentGradient)
            .clickable(onClick = onClick)
            .padding(20.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.venue_your_points), fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.9f))
                Text(
                    "$balance", fontSize = 42.sp, fontWeight = FontWeight.Black,
                    letterSpacing = (-2).sp, lineHeight = 42.sp, color = Color.White,
                )
            }
            venue.pointsModeLabel()?.let {
                Text(
                    it, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.White,
                    modifier = Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.2f))
                        .padding(horizontal = 12.dp, vertical = 7.dp),
                )
            }
        }
        Spacer(Modifier.height(16.dp))
        AyantProgressBar(fraction = fraction, height = 8.dp)
        Spacer(Modifier.height(10.dp))
        Text(
            next?.let { "Ещё ${it.cost - balance} до «${it.title}»" }
                ?: stringResource(R.string.venue_points_rewards_available),
            fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.94f),
        )
    }
}

/** Предложения списком (SCREENS.md G3 §7). */
@Composable
private fun VenueDealRows(
    deals: List<kg.ayant.app.domain.model.Deal>,
    venue: Venue,
    onDeal: (String) -> Unit,
) {
    val c = AyantTheme.colors
    Column(
        Modifier.padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        deals.forEach { d ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(22.dp))
                    .background(c.surface)
                    .clickable { onDeal(d.id) }
                    .padding(14.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Box(Modifier.size(66.dp).clip(RoundedCornerShape(17.dp))) {
                    CoverImage(d.imageURL, venue.gradientColors, d.emoji, Modifier.fillMaxSize(), emojiSize = 28)
                }
                Column(Modifier.weight(1f)) {
                    Text(
                        d.title, fontSize = 15.sp, fontWeight = FontWeight.Bold,
                        letterSpacing = (-0.3).sp, lineHeight = 19.sp, color = c.ink, maxLines = 2,
                    )
                    Text(
                        d.details, fontSize = 12.5.sp, color = c.inkSoft, maxLines = 1,
                        modifier = Modifier.padding(top = 5.dp),
                    )
                    Row(
                        Modifier.padding(top = 7.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.Bottom,
                    ) {
                        d.newPrice?.let {
                            Text(
                                stringResource(R.string.price_som, it), fontSize = 17.sp,
                                fontWeight = FontWeight.Black, letterSpacing = (-0.4).sp,
                                // Акцент мелким текстом — контрастный вариант.
                                color = c.accentText,
                            )
                        }
                        d.oldPrice?.let {
                            Text(
                                stringResource(R.string.price_som, it), fontSize = 13.sp,
                                color = Color(0xFF9A9188),
                                textDecoration = androidx.compose.ui.text.style.TextDecoration.LineThrough,
                            )
                        }
                    }
                }
            }
        }
    }
}

/** «4,8» — рейтинг с десятичной запятой. */
private fun ratingText(v: Double): String = String.format("%.1f", v).replace('.', ',')

private fun reviewsWord(n: Int): String {
    val n10 = n % 10
    val n100 = n % 100
    return when {
        n10 == 1 && n100 != 11 -> "отзыв"
        n10 in 2..4 && n100 !in 12..14 -> "отзыва"
        else -> "отзывов"
    }
}

// MARK: - Публикации: кладка в две колонки
//
// Вкладка называется «Публикации», а не «Акции»: `DealType` давно не только
// скидки — там же новинки и объявления. Раскладка как в Instagram: плитки разной
// высоты в две колонки, на экран влезает вчетверо больше. Зеркалит
// `publicationsGrid` в `DetailViews.swift`.
//
// В Compose есть штатная кладка — `LazyVerticalStaggeredGrid`, но здесь она уже
// внутри вертикального скролла, поэтому колонки раскладываем сами: вложенный
// ленивый скролл той же оси падает с «infinite height».

/**
 * Пропорция плитки (ширина/высота). Берётся из id, а не из загруженной картинки:
 * так сетка не перекладывается по мере загрузки фотографий и не прыгает.
 */
private fun tileAspect(deal: Deal): Float {
    val variants = floatArrayOf(0.78f, 1.0f, 1.3f)
    return variants[kotlin.math.abs(deal.id.hashCode()) % variants.size]
}

@Composable
private fun VenuePublicationsGrid(deals: List<Deal>, venue: Venue, onDeal: (String) -> Unit) {
    // Жадная раскладка: что короче, в ту колонку и кладём.
    val columns = remember(deals) {
        val buckets = listOf(mutableListOf<Deal>(), mutableListOf<Deal>())
        val heights = floatArrayOf(0f, 0f)
        deals.forEach { d ->
            val i = if (heights[0] <= heights[1]) 0 else 1
            buckets[i].add(d)
            heights[i] += 1f / tileAspect(d)
        }
        buckets
    }
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        columns.forEach { column ->
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                column.forEach { deal -> PublicationTile(deal, venue) { onDeal(deal.id) } }
            }
        }
    }
}

@Composable
private fun PublicationTile(deal: Deal, venue: Venue, onClick: () -> Unit) {
    val c = AyantTheme.colors
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AyantRadius.card))
            .background(c.surface)
            .clickable(onClick = onClick),
    ) {
        Box {
            VenuePhoto(
                deal.allImages.firstOrNull(), venue.gradientColors,
                Modifier.fillMaxWidth().aspectRatio(tileAspect(deal)),
            )
            deal.effectiveDiscountPercent?.let { percent ->
                Text(
                    "−$percent%",
                    fontSize = 12.5.sp, fontWeight = FontWeight.Black, color = Color.White,
                    modifier = Modifier
                        .padding(8.dp)
                        .clip(CircleShape)
                        .background(c.accentGradient)
                        .padding(horizontal = 9.dp, vertical = 5.dp),
                )
            }
        }
        Column(Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                deal.title,
                fontSize = 14.sp, fontWeight = FontWeight.Bold, color = c.ink,
                maxLines = 2, lineHeight = 17.sp,
            )
            deal.newPrice?.let {
                Text(
                    stringResource(R.string.price_som, it),
                    fontSize = 14.sp, fontWeight = FontWeight.Black, color = c.accentText,
                )
            }
        }
    }
}
