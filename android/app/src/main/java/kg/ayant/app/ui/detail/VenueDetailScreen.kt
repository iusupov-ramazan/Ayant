package kg.ayant.app.ui.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Directions
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import kg.ayant.app.R
import kg.ayant.app.core.AppLanguage
import kg.ayant.app.core.Directions as Dir
import kg.ayant.app.core.Links
import kg.ayant.app.core.ayantFactory
import kg.ayant.app.core.dial
import kg.ayant.app.core.distanceText
import kg.ayant.app.core.localizedHoursStatus
import kg.ayant.app.core.localizedLabel
import kg.ayant.app.core.localizedName
import kg.ayant.app.core.openUrl
import kg.ayant.app.core.shareText
import kg.ayant.app.core.weekdayLongRes
import kg.ayant.app.domain.ContactAction
import kg.ayant.app.domain.VenueDetailIntent
import kg.ayant.app.domain.contract.AnalyticsMetric
import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.Review
import kg.ayant.app.domain.model.ReviewReportReason
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.pointsActive
import kg.ayant.app.domain.stampsActive
import kg.ayant.app.location.LocationManager
import kg.ayant.app.ui.auth.GuestAlert
import kg.ayant.app.ui.auth.GuestGate
import kg.ayant.app.ui.bonus.AyantProgressBar
import kg.ayant.app.ui.bonus.MyQrScreen
import kg.ayant.app.ui.bonus.pointsModeLabel
import kg.ayant.app.ui.components.CoverImage
import kg.ayant.app.ui.components.ImageCarousel
import kg.ayant.app.ui.components.RatingBreakdown
import kg.ayant.app.ui.components.StarRating
import kg.ayant.app.ui.components.VenuePhoto
import kg.ayant.app.ui.theme.AyantRadius
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.gradientColors
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.ui.vm.LoyaltyViewModel
import kg.ayant.app.ui.vm.PointsViewModel
import kg.ayant.app.ui.vm.SessionViewModel
import kg.ayant.app.ui.vm.VenueDetailViewModel
import java.text.SimpleDateFormat

/**
 * Страница заведения. Зеркалит `VenueDetailView` в `DetailViews.swift`:
 * обложка → лист (рейтинг, название, мета, чипы, герой баллов, «Сегодня»,
 * вкладки «Публикации / Отзывы / Инфо») → нижняя панель «Показать QR» + сердечко.
 *
 * [loyalty] — общая `LoyaltyViewModel` из `RootScaffold` (штампы на баннере карты
 * лояльности). Пока корень её не передаёт, счётчик штампов на баннере скрыт.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VenueDetailScreen(
    venueID: String,
    app: AppViewModel,
    session: SessionViewModel,
    location: LocationManager,
    points: PointsViewModel,
    onBack: () -> Unit,
    onDeal: (String) -> Unit,
    onLoyalty: (String) -> Unit = {},
    onPoints: (String) -> Unit = {},
    loyalty: LoyaltyViewModel? = null,
) {
    val c = AyantTheme.colors
    val context = LocalContext.current
    val venue = app.venue(id = venueID) ?: run {
        Box(Modifier.fillMaxSize().background(c.canvas), contentAlignment = Alignment.Center) { Text(stringResource(R.string.venue_not_found)) }
        return
    }
    // Состояние карточки — одним значением из VenueDetailViewModel (state + send).
    // Единственная VM, которая сознательно живёт per-route (см. CLAUDE.md).
    val detail: VenueDetailViewModel = viewModel(factory = ayantFactory())
    val detailState by detail.state.collectAsState()
    // Каталог/отзывы принадлежат ленте и профилю — пересобираем срез, когда они менялись.
    val feedState by app.feedState.collectAsState()
    val profileState by app.profileFlow.collectAsState()

    val agg = detailState.aggregate
    val deals = detailState.deals
    val reviews = detailState.reviews
    // Реальные фото (обложка, объекты, фото из отзывов) + легаси-эмодзи как фолбэк. Зеркалит galleryPhotos.
    val galleryPhotos = remember(venue, reviews) {
        buildList {
            venue.imageURL?.takeIf { it.isNotEmpty() }?.let { add(it) }
            venue.items.forEach { if (it.imageURL.isNotEmpty()) add(it.imageURL) }
            reviews.forEach { addAll(it.photos) }
            addAll(venue.photoEmojis)
            reviews.forEach { addAll(it.photoEmojis) }
        }
    }

    var hoursExpanded by remember { mutableStateOf(false) }
    var showAllBranches by remember { mutableStateOf(false) }
    var showWriteReview by remember { mutableStateOf(false) }
    var writeReviewItemID by remember { mutableStateOf<String?>(null) }
    var photoViewerStart by remember { mutableStateOf<Int?>(null) }
    var showPdf by remember { mutableStateOf(false) }
    var showMapOptions by remember { mutableStateOf(false) }
    var showMyQr by remember { mutableStateOf(false) }
    var reportingReview by remember { mutableStateOf<Review?>(null) }
    // Показываем подтверждение: молчаливая жалоба неотличима от сломанной кнопки.
    var reportSent by remember { mutableStateOf(false) }
    // Отказ гостю — с текстом под конкретное действие (GuestGate), как на iOS.
    var guestGate by remember { mutableStateOf<Int?>(null) }

    // Баланс баллов приходит snapshot-листенером — без подписки карточка не обновится.
    val pointsState by points.state.collectAsState()

    LaunchedEffect(venue.id) {
        detail.bind(app)
        detail.send(VenueDetailIntent.Open(venue.id))
    }
    LaunchedEffect(feedState, profileState) { detail.refresh() }

    fun toggleSave() {
        if (session.isGuest) guestGate = GuestGate.SAVE_VENUE
        else detail.send(VenueDetailIntent.ToggleSave)
    }
    fun writeReview(itemID: String?) {
        if (session.isGuest) guestGate = GuestGate.REVIEW
        else { writeReviewItemID = itemID; showWriteReview = true }
    }
    fun share() {
        context.shareText(context.getString(R.string.venue_share_text, venue.name, venue.address, Links.venue(venue.id)), venue.name)
    }

    // Вкладки листа (SCREENS.md G3). Разделы прежней страницы разложены по ним
    // целиком — редизайн меняет порядок и подачу, а не состав.
    var tab by remember { mutableStateOf(VenueTab.Deals) }

    Scaffold(
        containerColor = c.canvas,
        bottomBar = {
            VenueStickyBar(
                isSaved = detailState.isSaved,
                onShowQr = {
                    // Личный QR привязан к аккаунту: заведению некуда начислять
                    // баллы гостя, поэтому вместо кода — приглашение войти.
                    when {
                        session.isGuest -> guestGate = GuestGate.QR
                        venue.pointsActive -> onPoints(venue.id)
                        else -> showMyQr = true
                    }
                },
                onToggleSave = ::toggleSave,
            )
        },
    ) { padding ->
      Box(Modifier.fillMaxSize().padding(bottom = padding.calculateBottomPadding())) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
        ) {
            // Обложка 330: карусель, когда фото больше одного; иначе фото или
            // эмодзи на градиенте. Кнопки НЕ здесь — см. закреплённый ряд ниже.
            Box(Modifier.fillMaxWidth().height(330.dp)) {
                val httpPhotos = galleryPhotos.filter { it.startsWith("http") }
                if (httpPhotos.size > 1) {
                    ImageCarousel(httpPhotos, venue.gradientColors, venue.emoji, Modifier.fillMaxSize(), height = 330, emojiSize = 64)
                } else {
                    CoverImage(venue.imageURL, venue.gradientColors, venue.emoji, Modifier.fillMaxSize(), emojiSize = 64)
                }
                // Верхний скрим — под плавающими кнопками.
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
                    .clip(RoundedCornerShape(topStart = AyantRadius.panel, topEnd = AyantRadius.panel))
                    .background(c.canvas)
                    .padding(top = 22.dp, bottom = 30.dp),
            ) {
                Column(Modifier.padding(horizontal = 20.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                            Icon(Icons.Filled.Star, null, tint = Color(0xFFFF9500), modifier = Modifier.size(13.dp))
                            Text(ratingText(agg.rating), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = c.ink)
                        }
                        Text(
                            "· " + pluralStringResource(R.plurals.reviews_word, agg.count, agg.count),
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
                            append(venue.category.localizedName())
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
                            Text(venue.localizedHoursStatus(), fontSize = 12.5.sp, fontWeight = FontWeight.Bold, color = openColor)
                        }
                        if (venue.branches.isNotEmpty()) {
                            Text(
                                pluralStringResource(R.plurals.addresses_count, venue.branches.size + 1, venue.branches.size + 1),
                                fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold, color = c.inkSoft,
                                modifier = Modifier.clip(CircleShape).background(c.surface)
                                    .border(0.5.dp, c.hairline, CircleShape)
                                    .padding(horizontal = 13.dp, vertical = 8.dp),
                            )
                        }
                    }

                    // Баллы САН — герой-карточка
                    if (venue.pointsActive) {
                        Spacer(Modifier.height(20.dp))
                        VenuePointsHeroCard(venue, pointsState.balance(venue.id)) { onPoints(venue.id) }
                    }
                    // Сегодняшний специал — в шапке, над вкладками, как на iOS.
                    if (venue.hasTodaySpecial) {
                        Spacer(Modifier.height(16.dp))
                        TodaySpecialBanner(venue)
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
                                EmptyTabNote(stringResource(R.string.venue_no_deals))
                            } else {
                                VenuePublicationsGrid(deals, venue) { onDeal(it) }
                            }
                        }

                        VenueTab.Reviews -> ReviewsSection(
                            venue = venue,
                            rating = agg.rating, count = agg.count,
                            breakdown = detailState.ratingBreakdown,
                            reviews = reviews,
                            currentUserID = app.currentUserID,
                            onWriteReview = { writeReview(null) },
                            onReport = { reportingReview = it },
                        )

                        VenueTab.Info -> {
                            // Порядок как на iOS: действия → инфо → карта лояльности → фото → объекты.
                            Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                if (venue.phone.isNotBlank()) ActionButton(stringResource(R.string.act_call), Icons.Filled.Call, Modifier.weight(1f)) {
                                    detail.send(VenueDetailIntent.LogContact(ContactAction.CALL))
                                    context.dial(venue.phone)
                                }
                                if (venue.address.isNotBlank()) ActionButton(stringResource(R.string.act_route), Icons.Filled.Directions, Modifier.weight(1f)) {
                                    // Вкладка «Поиск» скрыта (ReleaseFlags.SEARCH_TAB) —
                                    // маршрут открываем во внешних картах, 2GIS по умолчанию.
                                    detail.send(VenueDetailIntent.LogContact(ContactAction.MAPS))
                                    context.openUrl(Dir.dgis(venue.latitude, venue.longitude))
                                }
                                ActionButton(
                                    if (detailState.isSaved) stringResource(R.string.act_saved) else stringResource(R.string.act_save),
                                    if (detailState.isSaved) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
                                    Modifier.weight(1f),
                                ) { toggleSave() }
                                ActionButton(stringResource(R.string.act_share), Icons.Filled.Share, Modifier.weight(1f)) { share() }
                            }

                            // Инфо: адрес → филиалы → телефон → соцсети → часы → PDF.
                            Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                                if (venue.address.isNotBlank()) {
                                    Row(
                                        Modifier.fillMaxWidth().clickable {
                                            app.log(AnalyticsMetric.MAPS, venue.id)
                                            showMapOptions = true
                                        },
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        Icon(Icons.Filled.LocationOn, null, tint = c.inkSoft, modifier = Modifier.size(18.dp))
                                        Text(" ${venue.address}", fontSize = 14.sp, color = c.ink, modifier = Modifier.weight(1f))
                                        Icon(Icons.Filled.Map, null, tint = c.accentText, modifier = Modifier.size(18.dp))
                                    }
                                }
                                // Дополнительные адреса (филиалы) — свёрнуты за кнопкой «Посмотреть все адреса».
                                if (venue.branches.isNotEmpty()) {
                                    Row(Modifier.fillMaxWidth().clickable { showAllBranches = !showAllBranches }, verticalAlignment = Alignment.CenterVertically) {
                                        Icon(Icons.Filled.LocationOn, null, tint = c.accentText, modifier = Modifier.size(18.dp))
                                        Text(
                                            if (showAllBranches) " " + stringResource(R.string.venue_hide_addresses)
                                            else " " + stringResource(R.string.venue_show_all_addresses, venue.branches.size + 1),
                                            fontSize = 14.sp, fontWeight = FontWeight.Medium, color = c.ink,
                                        )
                                        Spacer(Modifier.weight(1f))
                                        Icon(if (showAllBranches) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null, tint = c.accentText, modifier = Modifier.size(18.dp))
                                    }
                                    if (showAllBranches) {
                                        venue.branches.forEach { b ->
                                            Row(
                                                Modifier.fillMaxWidth().clickable {
                                                    detail.send(VenueDetailIntent.LogContact(ContactAction.MAPS))
                                                    context.openUrl(Dir.dgis(b.latitude, b.longitude))
                                                },
                                                verticalAlignment = Alignment.CenterVertically,
                                            ) {
                                                Icon(Icons.Filled.LocationOn, null, tint = c.inkSoft, modifier = Modifier.size(18.dp))
                                                Text(" ${b.address}", fontSize = 14.sp, color = c.ink, modifier = Modifier.weight(1f))
                                                Icon(Icons.Filled.Map, null, tint = c.accentText, modifier = Modifier.size(18.dp))
                                            }
                                        }
                                    }
                                }
                                if (venue.phone.isNotBlank()) {
                                    // Тап по номеру считается обращением наравне с кнопкой «Позвонить».
                                    InfoRow(Icons.Filled.Call, venue.phone, tint = c.accentText) {
                                        detail.send(VenueDetailIntent.LogContact(ContactAction.CALL))
                                        context.dial(venue.phone)
                                    }
                                }
                                // Соцсети. Порядок как на iOS: WhatsApp, Telegram, Instagram.
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
                                // Часы (раскрываются)
                                Row(Modifier.fillMaxWidth().clickable { hoursExpanded = !hoursExpanded }, verticalAlignment = Alignment.CenterVertically) {
                                    Icon(Icons.Filled.Schedule, null, tint = if (venue.isOpenNow) c.open else c.inkSoft, modifier = Modifier.size(18.dp))
                                    Text(" ${venue.localizedHoursStatus()}", fontSize = 14.sp, color = if (venue.isOpenNow) c.open else c.inkSoft)
                                    Spacer(Modifier.weight(1f))
                                    Icon(if (hoursExpanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null, tint = c.inkSoft, modifier = Modifier.size(18.dp))
                                }
                                if (hoursExpanded) {
                                    Column(Modifier.padding(start = 28.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                        for (i in 0 until 7) {
                                            val isToday = i == Venue.todayIndex
                                            Row(Modifier.fillMaxWidth()) {
                                                Text(stringResource(weekdayLongRes(i)), fontSize = 12.sp, fontWeight = if (isToday) FontWeight.SemiBold else FontWeight.Normal, color = if (isToday) c.ink else c.inkSoft)
                                                Spacer(Modifier.weight(1f))
                                                Text(venue.hours(i).localizedLabel(), fontSize = 12.sp, color = if (venue.hours(i).closed) c.inkSoft else c.ink)
                                            }
                                        }
                                    }
                                }
                                // Прайс-лист / каталог (PDF)
                                if (!venue.pdfMenuURL.isNullOrEmpty()) {
                                    InfoRow(Icons.Filled.Description, stringResource(R.string.venue_pdf_menu)) { showPdf = true }
                                }
                            }

                            // Карта лояльности — только если баллы выключены: механика одна.
                            if (venue.stampsActive) {
                                LoyaltyBanner(venue, loyalty) { onLoyalty(venue.id) }
                            }

                            // Галерея фото (реальные + эмодзи-фолбэк)
                            if (galleryPhotos.isNotEmpty()) {
                                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Text(stringResource(R.string.photos), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink, modifier = Modifier.padding(horizontal = 16.dp))
                                    Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                        galleryPhotos.forEachIndexed { i, p ->
                                            GalleryThumb(p, 90, emojiSize = 40, Modifier.clip(RoundedCornerShape(12.dp)).clickable { photoViewerStart = i })
                                        }
                                    }
                                }
                            }
                            // Объекты для отзывов (блюда/услуги)
                            if (venue.items.isNotEmpty()) {
                                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                    Text(stringResource(R.string.rate_item), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink, modifier = Modifier.padding(horizontal = 16.dp))
                                    Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                                        venue.items.forEach { item ->
                                            Column(
                                                horizontalAlignment = Alignment.CenterHorizontally,
                                                verticalArrangement = Arrangement.spacedBy(6.dp),
                                                modifier = Modifier.width(80.dp).clickable { writeReview(item.id) },
                                            ) {
                                                // Как `ItemThumb`: фото объекта, если есть, иначе эмодзи.
                                                Box(Modifier.size(70.dp).clip(RoundedCornerShape(14.dp)).background(c.surfaceMuted), contentAlignment = Alignment.Center) {
                                                    if (item.imageURL.isNotEmpty()) {
                                                        AsyncImage(model = item.imageURL, contentDescription = item.name, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                                                    } else {
                                                        Text(item.emoji, fontSize = 32.sp)
                                                    }
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
            ) { toggleSave() }
            Spacer(Modifier.width(8.dp))
            FloatingIconButton(Icons.Filled.Share, stringResource(R.string.act_share)) { share() }
        }
      }
    }

    // ── Листы и диалоги ──────────────────────────────────────────────────────

    if (showWriteReview) {
        WriteReviewDialog(venue = venue, app = app, preselectItemID = writeReviewItemID, onDismiss = { showWriteReview = false })
    }
    photoViewerStart?.let { start ->
        PhotoViewerDialog(photos = galleryPhotos, startIndex = start, onDismiss = { photoViewerStart = null })
    }
    if (showPdf && !venue.pdfMenuURL.isNullOrEmpty()) {
        PdfMenuDialog(venue.pdfMenuURL!!, onDismiss = { showPdf = false })
    }
    // Личный QR — листом, когда у заведения нет баллов САН (iOS: `VenueSheet.qr`).
    if (showMyQr) {
        Dialog(onDismissRequest = { showMyQr = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            Box(Modifier.fillMaxSize().background(c.canvas)) {
                MyQrScreen(app, points, location, onBack = { showMyQr = false })
            }
        }
    }
    guestGate?.let { gate ->
        GuestAlert(session, gate) { guestGate = null }
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
    // Жалоба уходит в Firestore и попадает в очередь модерации админ-панели.
    // Причины перечисляем из домена, а не литералами: список один и тот же
    // на обеих платформах и в админ-панели.
    reportingReview?.let { review ->
        AlertDialog(
            onDismissRequest = { reportingReview = null },
            title = { Text(stringResource(R.string.review_report_title)) },
            text = {
                Column {
                    ReviewReportReason.entries.forEach { reason ->
                        TextButton(onClick = {
                            reportingReview = null
                            app.reportReview(review, reason)
                            reportSent = true
                        }) { Text(stringResource(reason.labelRes()), color = Color(0xFFD32F2F)) }
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { reportingReview = null }) { Text(stringResource(R.string.action_cancel)) } },
        )
    }
    if (reportSent) {
        AlertDialog(
            onDismissRequest = { reportSent = false },
            title = { Text(stringResource(R.string.detail_report_sent_title)) },
            text = { Text(stringResource(R.string.detail_report_sent_body)) },
            confirmButton = { TextButton(onClick = { reportSent = false }) { Text(stringResource(R.string.action_ok)) } },
        )
    }
}

// MARK: - Секции

/** Пустая вкладка — карточкой, как `emptyTabNote` на iOS. */
@Composable
private fun EmptyTabNote(text: String) {
    val c = AyantTheme.colors
    Text(
        text, fontSize = 14.sp, color = c.inkSoft,
        modifier = Modifier
            .padding(horizontal = 16.dp)
            .fillMaxWidth()
            .clip(RoundedCornerShape(AyantRadius.card))
            .background(c.surface)
            .border(0.5.dp, c.hairline, RoundedCornerShape(AyantRadius.card))
            .padding(18.dp),
    )
}

/** Сегодняшний специал. Зеркалит `todaySpecialBanner`. */
@Composable
private fun TodaySpecialBanner(venue: Venue) {
    val c = AyantTheme.colors
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.accent.copy(alpha = 0.1f)).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("⭐️", fontSize = 22.sp)
        Column(Modifier.padding(start = 10.dp)) {
            Text(stringResource(R.string.today), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = c.accentText)
            Text(venue.todaySpecialText ?: "", fontSize = 14.sp, fontWeight = FontWeight.Medium, color = c.ink)
        }
    }
}

/** Вкладка «Отзывы». Зеркалит `reviewsSection`. */
@Composable
private fun ReviewsSection(
    venue: Venue,
    rating: Double,
    count: Int,
    breakdown: Map<Int, Int>,
    reviews: List<Review>,
    currentUserID: String,
    onWriteReview: () -> Unit,
    onReport: (Review) -> Unit,
) {
    val c = AyantTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Text(stringResource(R.string.reviews), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink, modifier = Modifier.padding(horizontal = 16.dp))
        Row(Modifier.padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(20.dp), verticalAlignment = Alignment.CenterVertically) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(ratingText(rating), fontSize = 40.sp, fontWeight = FontWeight.Bold, color = c.ink)
                StarRating(rating = rating, size = 12)
                Text(pluralStringResource(R.plurals.reviews_word, count, count), fontSize = 11.sp, color = c.inkSoft)
            }
            RatingBreakdown(breakdown, Modifier.weight(1f))
        }
        if (venue.items.isEmpty()) {
            Text(stringResource(R.string.venue_reviews_no_items), fontSize = 13.sp, color = c.inkSoft, modifier = Modifier.padding(horizontal = 16.dp))
        } else {
            Row(
                Modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(c.accent)
                    .clickable(onClick = onWriteReview).padding(vertical = 12.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Edit, null, tint = Color.White, modifier = Modifier.size(16.dp))
                Text(" " + stringResource(R.string.rate_item), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Color.White, textAlign = TextAlign.Center)
            }
        }
        if (reviews.isEmpty()) {
            Text(stringResource(R.string.no_reviews), fontSize = 14.sp, color = c.inkSoft, modifier = Modifier.padding(horizontal = 16.dp))
        } else {
            Column(Modifier.padding(horizontal = 16.dp)) {
                reviews.forEach { r ->
                    ReviewRow(r, onReport = if (r.authorID != currentUserID) ({ onReport(r) }) else null)
                    Box(Modifier.fillMaxWidth().height(0.5.dp).background(c.hairline))
                }
            }
        }
    }
}

/** Строка отзыва (с ответом владельца). Зеркалит `ReviewRow` в `ReviewViews.swift`. */
@Composable
private fun ReviewRow(r: Review, onReport: (() -> Unit)? = null) {
    val c = AyantTheme.colors
    Column(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(
                Modifier.size(38.dp).clip(CircleShape)
                    .background(Brush.linearGradient(listOf(c.accent, Color(0xFFFFCC00)))),
                contentAlignment = Alignment.Center,
            ) {
                Text(r.initial, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Color.White)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text(r.authorName, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = c.ink)
                    if (r.verifiedVisit) {
                        Icon(Icons.Filled.Verified, stringResource(R.string.detail_review_verified_visit), tint = c.open, modifier = Modifier.size(13.dp))
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    StarRating(rating = r.rating.toDouble(), size = 11)
                    Text("· " + reviewDateText(r), fontSize = 11.sp, color = c.inkSoft)
                }
            }
            if (r.verifiedVisit) {
                Text(stringResource(R.string.review_verified_visit), fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = c.open, modifier = Modifier.clip(RoundedCornerShape(50)).background(c.open.copy(alpha = 0.15f)).padding(horizontal = 7.dp, vertical = 3.dp))
            }
            if (onReport != null) {
                // iOS: контекстное меню по долгому нажатию; здесь — явная иконка, та же роль.
                Icon(Icons.Filled.Flag, stringResource(R.string.review_report_action), tint = c.inkSoft, modifier = Modifier.size(18.dp).clickable(onClick = onReport))
            }
        }
        r.itemName?.takeIf { it.isNotEmpty() }?.let { itemName ->
            Text(stringResource(R.string.review_about_item, itemName), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = c.accentText, modifier = Modifier.clip(RoundedCornerShape(50)).background(c.accent.copy(alpha = 0.12f)).padding(horizontal = 8.dp, vertical = 3.dp))
        }
        if (r.text.isNotEmpty()) Text(r.text, fontSize = 14.sp, color = c.ink)
        val reviewPhotos = r.photos + r.photoEmojis
        if (reviewPhotos.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                reviewPhotos.forEach { p -> GalleryThumb(p, 56, emojiSize = 24, Modifier.clip(RoundedCornerShape(10.dp))) }
            }
        }
        r.hostReply?.let { reply ->
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(c.surfaceMuted).padding(10.dp),
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(Icons.Filled.Verified, null, tint = Color(0xFF4DA3FF), modifier = Modifier.size(13.dp))
                    Text(stringResource(R.string.review_host_reply), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color(0xFF4DA3FF))
                }
                Text(reply.text, fontSize = 12.sp, color = c.inkSoft)
            }
        }
    }
}

/** «12 сент. 2026» — дата отзыва на языке приложения. Зеркалит `Review.dateText`. */
private fun reviewDateText(r: Review): String =
    SimpleDateFormat("d MMM yyyy", AppLanguage.locale).format(r.createdAt)

/** Миниатюра галереи: фото по URL или эмодзи-фолбэк. Зеркалит `GalleryImage`. */
@Composable
private fun GalleryThumb(value: String, size: Int, emojiSize: Int, modifier: Modifier = Modifier) {
    val c = AyantTheme.colors
    Box(modifier.size(size.dp).background(c.surfaceMuted), contentAlignment = Alignment.Center) {
        if (value.startsWith("http")) {
            AsyncImage(model = value, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        } else {
            Text(value, fontSize = emojiSize.sp)
        }
    }
}

/**
 * Карта лояльности (штампы). Зеркалит `loyaltyBanner`: заголовок, «N визитов → награда»,
 * счётчик «stamps/goal», ряд печатей и подсказка, что штамп ставит сотрудник по QR.
 * Без [loyalty] (корень ещё не передаёт VM) счётчик и печати скрыты — «0/6»
 * при трёх реальных штампах хуже, чем ничего.
 */
@Composable
private fun LoyaltyBanner(venue: Venue, loyalty: LoyaltyViewModel?, onClick: () -> Unit) {
    val cards = loyalty?.cards?.collectAsState()?.value
    val card = cards?.firstOrNull { it.venueID == venue.id }
    val stamps = card?.stamps ?: 0
    val goal = venue.loyaltyGoal
    val rounds = card?.completedRounds ?: 0
    val white = Color.White
    Column(
        Modifier
            .padding(horizontal = 16.dp)
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Brush.linearGradient(listOf(Color(0xFFFF4D29), Color(0xFFFFB300))))
            .clickable(onClick = onClick)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Filled.CreditCard, null, tint = white, modifier = Modifier.size(20.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(stringResource(R.string.venue_loyalty_card), fontSize = 14.sp, fontWeight = FontWeight.Bold, color = white)
                Text(stringResource(R.string.venue_loyalty_progress, goal, venue.loyaltyReward), fontSize = 12.sp, color = white.copy(alpha = 0.9f))
            }
            if (loyalty != null) {
                Text(
                    "$stamps/$goal", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = white,
                    modifier = Modifier.clip(CircleShape).background(white.copy(alpha = 0.25f)).padding(horizontal = 8.dp, vertical = 4.dp),
                )
            }
        }
        if (loyalty != null) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (i in 0 until goal) {
                    Icon(
                        if (i < stamps) Icons.Filled.Verified else Icons.Filled.StarBorder, null,
                        tint = if (i < stamps) white else white.copy(alpha = 0.45f),
                        modifier = Modifier.size(14.dp),
                    )
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Filled.Info, null, tint = white.copy(alpha = 0.9f), modifier = Modifier.size(12.dp))
            // Штамп ставит только сервер, когда сотрудник сканирует QR
            // карты (`scanCoupon`, ветка A) — не за купон.
            Text(
                if (rounds > 0) stringResource(R.string.detail_loyalty_rounds_hint, rounds)
                else stringResource(R.string.detail_loyalty_stamp_hint),
                fontSize = 11.sp, color = white.copy(alpha = 0.9f), modifier = Modifier.weight(1f),
            )
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = white.copy(alpha = 0.9f), modifier = Modifier.size(14.dp))
        }
    }
}

@Composable
private fun ActionButton(title: String, icon: ImageVector, modifier: Modifier, onClick: () -> Unit) {
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
private fun InfoRow(icon: ImageVector, text: String, tint: Color? = null, onClick: () -> Unit) {
    val c = AyantTheme.colors
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = tint ?: c.inkSoft, modifier = Modifier.size(18.dp))
        Text(" $text", fontSize = 14.sp, color = tint ?: c.ink)
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
    icon: ImageVector,
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
    Column(Modifier.fillMaxWidth().background(c.canvas.copy(alpha = 0.94f))) {
        Box(Modifier.fillMaxWidth().height(0.5.dp).background(c.hairline))
        Row(
            Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 18.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(AyantRadius.button))
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
                    .clip(RoundedCornerShape(AyantRadius.button))
                    .background(c.surface)
                    .border(0.5.dp, c.hairline, RoundedCornerShape(AyantRadius.button))
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
}

/** Акцентная карточка баллов (SCREENS.md G3 §5). */
@Composable
private fun VenuePointsHeroCard(venue: Venue, balance: Int, onClick: () -> Unit) {
    val c = AyantTheme.colors
    // Ближайшая доступная награда задаёт цель прогресса.
    val next = venue.pointsRewards.filter { it.active && it.cost > balance }.minByOrNull { it.cost }
    val fraction = next?.let { (balance.toFloat() / it.cost.coerceAtLeast(1)).coerceAtMost(1f) } ?: 1f
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AyantRadius.hero))
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
            next?.let { stringResource(R.string.points_until_reward, it.cost - balance, it.title) }
                ?: stringResource(R.string.venue_points_rewards_available),
            fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.94f),
        )
    }
}

/** «4,8» — рейтинг с десятичной запятой. */
private fun ratingText(v: Double): String = String.format(AppLanguage.locale, "%.1f", v)

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
            .border(0.5.dp, c.hairline, RoundedCornerShape(AyantRadius.card))
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
