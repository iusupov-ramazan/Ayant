package kg.ayant.app.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import android.content.Intent
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.domain.model.FeedItem
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenueCategory
import kg.ayant.app.location.LocationManager
import kg.ayant.app.ui.theme.AyantMetrics
import kg.ayant.app.ui.theme.AyantRadius
import kotlinx.coroutines.launch
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantPressScale
import kg.ayant.app.ui.theme.AyantTiming
import kg.ayant.app.ui.theme.ayantRise
import kg.ayant.app.ui.theme.ayantScreenEnter
import kg.ayant.app.ui.theme.gradientColors
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.ui.vm.FeedViewModel
import kg.ayant.app.domain.model.Deal
import kg.ayant.app.ui.components.VenuePhoto

/**
 * Главная (SCREENS.md G2) — the defining screen of the redesign.
 * Mirrors `HomeFeedView.swift`.
 *
 * Editorial «Сегодня» header, a sticky rail of text chips, and full-bleed 600dp
 * cards. The old `CategoryTile` story circles are retired — the cards carry the
 * imagery now.
 */
@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun HomeScreen(
    app: AppViewModel,
    location: LocationManager,
    feed: FeedViewModel,
    session: kg.ayant.app.ui.vm.SessionViewModel,
    onVenue: (String) -> Unit,
    onDeal: (String) -> Unit,
    onSaved: () -> Unit = {},
) {
    val c = AyantTheme.colors
    var category by remember { mutableStateOf<VenueCategory?>(null) }
    // Сохранение и лайк принадлежат аккаунту: гостю объясняем это диалогом,
    // а не молчаливым «ничего не произошло».
    var guestMessage by remember { mutableStateOf<String?>(null) }
    val scope = androidx.compose.runtime.rememberCoroutineScope()

    // ВНИМАНИЕ: общие ViewModel приходят параметром из RootScaffold. Вызов
    // viewModel() здесь дал бы экземпляр НА МАРШРУТ (владелец — NavBackStackEntry).
    val feedState by feed.state.collectAsState()
    // Избранным владеет профиль: без подписки сердечко не перекрасится.
    val profileState by app.profileFlow.collectAsState()
    val feedItems = feed.items(category)
    val shareContext = LocalContext.current
    val specials = remember(feedState, profileState) { app.savedTodaySpecials }

    androidx.compose.runtime.LaunchedEffect(category, feedItems.map { it.id }) {
        app.logFeedImpression(category, location)
    }

    // Смена категории возвращает ленту в самое начало.
    //
    // Без этого экран уезжал в пустоту: прокрутка остаётся там, где была, а
    // подборка по категории — плитки в две колонки — втрое короче полноэкранной
    // ленты. Позиция оказывалась за концом нового содержимого, и человек видел
    // чистый холст. Без анимации: фильтр должен срабатывать мгновенно.
    val listState = rememberLazyListState()
    var lastCategory by remember { mutableStateOf(category) }
    androidx.compose.runtime.LaunchedEffect(category) {
        if (category != lastCategory) {
            lastCategory = category
            listState.scrollToItem(0)
        }
    }

    Scaffold(containerColor = c.canvas) { padding ->
        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(bottom = 26.dp),
            verticalArrangement = Arrangement.spacedBy(0.dp),
        ) {
            item(key = "header") {
                FeedHeader(
                    city = app.selectedCity.name,
                    onSaved = onSaved,
                    modifier = Modifier.ayantScreenEnter(),
                )
            }

            // Липкий ряд категорий: крупный заголовок уезжает под него.
            stickyHeader(key = "rail") {
                CategoryRail(selected = category, onSelect = { category = it })
            }

            if (specials.isNotEmpty()) {
                item(key = "specials") {
                    TodaySpecialStrip(specials, onVenue)
                    Spacer(Modifier.height(18.dp))
                }
            }

            when {
                feedState.catalog.isLoading -> item(key = "skeleton") { FeedSkeleton() }

                // Ошибка загрузки раньше попадала в «нет заведений в городе»:
                // пустой экран без объяснения и без кнопки повторить.
                feedState.catalog.errorOrNull() != null -> item(key = "loadFailure") {
                    LoadFailureState(
                        title = stringResource(R.string.feed_load_failed_title),
                        subtitle = feed.loadError ?: stringResource(R.string.feed_load_failed_body),
                        onRetry = { scope.launch { app.load() } },
                    )
                }

                !feedState.hasVenuesInCity -> item(key = "emptyCity") {
                    EmptyState(
                        stringResource(R.string.home_empty_city_title, app.selectedCity.name),
                        stringResource(R.string.home_empty_city_body),
                    )
                }

                feedItems.isEmpty() -> item(key = "emptyCat") {
                    EmptyState(
                        stringResource(R.string.feed_empty_cat_title),
                        stringResource(R.string.feed_empty_cat_body),
                    )
                }

                // Выбрана категория — это ПОДБОР, а не лента: человек сравнивает
                // варианты. Полноэкранные карточки дают одно предложение на
                // экран, плитки — вчетверо больше. Зеркалит `categoryGrid`
                // в `HomeFeedView.swift`.
                category != null -> {
                    val deals = feedItems.filterIsInstance<FeedItem.DealItem>().map { it.deal }
                    items(deals.chunked(2), key = { row -> row.first().id }) { row ->
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            row.forEach { deal ->
                                Box(Modifier.weight(1f)) {
                                    CategoryTile(
                                        deal = deal,
                                        venue = app.venue(forDeal = deal),
                                    ) { onDeal(deal.id) }
                                }
                            }
                            // Нечётный хвост: пустая половина, чтобы плитка не
                            // растянулась на всю ширину.
                            if (row.size == 1) Spacer(Modifier.weight(1f))
                        }
                    }
                }

                else -> itemsIndexed(feedItems, key = { _, it -> it.id }) { index, item ->
                    Box(Modifier.ayantRise(index, key = item.id, cap = AyantTiming.FEED_STAGGER_CAP)) {
                        when (item) {
                            is FeedItem.DealItem -> {
                                val deal = item.deal
                                val venue = app.venue(forDeal = deal)
                                FeedDealCard(
                                    deal = deal,
                                    venue = venue,
                                    distanceKm = venue?.let { location.distanceKm(it.latitude, it.longitude) },
                                    isSaved = deal.id in profileState.favoriteDealIDs,
                                    isLiked = deal.id in profileState.likedDealIDs,
                                    onOpen = { onDeal(deal.id) },
                                    onVenue = { venue?.let { onVenue(it.id) } },
                                    onSave = {
                                        if (app.isGuest) guestMessage = kg.ayant.app.ui.auth.GuestGate.SAVE_DEAL
                                        else app.toggleFavorite(deal)
                                    },
                                    onLike = {
                                        if (app.isGuest) guestMessage = kg.ayant.app.ui.auth.GuestGate.LIKE
                                        else app.toggleLike(deal)
                                    },
                                    onShare = { shareDeal(shareContext, deal, venue) },
                                )
                            }
                            is FeedItem.AdVenue -> {
                                val v = item.venue
                                FeedAdVenueCard(
                                    venue = v,
                                    distanceKm = location.distanceKm(v.latitude, v.longitude),
                                    isSaved = app.isSaved(v),
                                    onOpen = { onVenue(v.id) },
                                    onSave = {
                                        if (app.isGuest) guestMessage = kg.ayant.app.ui.auth.GuestGate.SAVE_VENUE
                                        else app.toggleSave(v)
                                    },
                                )
                            }
                        }
                    }
                    Spacer(Modifier.height(10.dp))
                }
            }
        }
    }

    guestMessage?.let { message ->
        kg.ayant.app.ui.auth.GuestAlert(session, message) { guestMessage = null }
    }
}

@Composable
private fun FeedHeader(city: String, onSaved: () -> Unit, modifier: Modifier = Modifier) {
    val c = AyantTheme.colors
    Column(
        modifier
            .fillMaxWidth()
            .padding(horizontal = AyantMetrics.screenPadding)
            .padding(top = 12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(Icons.Filled.LocationOn, null, tint = c.accentText, modifier = Modifier.size(13.dp))
                Text(
                    city, fontSize = 13.5.sp, fontWeight = FontWeight.Bold,
                    letterSpacing = (-0.2).sp, color = c.ink,
                )
                Icon(
                    Icons.Filled.KeyboardArrowDown, null,
                    tint = Color(0xFF9A9188), modifier = Modifier.size(14.dp),
                )
            }
            Spacer(Modifier.weight(1f))
            HeaderIconButton(Icons.Filled.Bookmark, stringResource(R.string.tab_saved), onSaved)
            Spacer(Modifier.width(8.dp))
            NotificationsBellButton()
        }

        Spacer(Modifier.height(16.dp))
        Text(
            stringResource(R.string.feed_title_today),
            fontSize = 46.sp, fontWeight = FontWeight.Black,
            letterSpacing = (-2.6).sp, lineHeight = 43.sp, color = c.ink,
        )
        Spacer(Modifier.height(10.dp))
        Text(
            stringResource(R.string.feed_subtitle),
            fontSize = 14.sp, lineHeight = 20.sp, color = c.inkSoft,
            modifier = Modifier.widthIn(max = 270.dp),
        )
    }
}

/**
 * Колокольчик. Экрана уведомлений в приложении нет, поэтому кнопка ведёт в
 * системные настройки, а точка горит, когда уведомления НЕ разрешены — то есть
 * сигналит «включи», а не «есть непрочитанное». Так же и на iOS.
 */
@Composable
private fun NotificationsBellButton() {
    val c = AyantTheme.colors
    val context = LocalContext.current
    val enabled = remember(context) {
        NotificationManagerCompat.from(context).areNotificationsEnabled()
    }
    Box {
        HeaderIconButton(Icons.Filled.Notifications, stringResource(R.string.tab_notifications)) {
            context.startActivity(
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                    .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            )
        }
        if (!enabled) {
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 8.dp, end = 9.dp)
                    .size(11.dp)
                    .clip(CircleShape)
                    .background(c.surface),
                contentAlignment = Alignment.Center,
            ) {
                Box(Modifier.size(7.dp).clip(CircleShape).background(c.accentDeep))
            }
        }
    }
}

@Composable
private fun HeaderIconButton(icon: ImageVector, label: String, onClick: () -> Unit) {
    val c = AyantTheme.colors
    val interaction = remember { MutableInteractionSource() }
    Box(
        Modifier
            .size(38.dp)
            .clip(RoundedCornerShape(13.dp))
            .background(c.surface)
            .selectable(
                selected = false,
                interactionSource = interaction,
                indication = null,
                role = Role.Button,
                onClick = onClick,
            )
            .ayantPressScale(interaction, scale = 0.90f),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = label, tint = c.ink, modifier = Modifier.size(15.dp))
    }
}

@Composable
private fun CategoryRail(selected: VenueCategory?, onSelect: (VenueCategory?) -> Unit) {
    val c = AyantTheme.colors
    Box(
        Modifier
            .fillMaxWidth()
            // Градиентная маска, из-под которой уезжает крупный заголовок.
            .background(
                Brush.verticalGradient(
                    0f to c.canvas,
                    0.62f to c.canvas,
                    1f to c.canvas.copy(alpha = 0f),
                )
            )
            .padding(top = 18.dp, bottom = 14.dp)
    ) {
        LazyRow(
            contentPadding = PaddingValues(horizontal = AyantMetrics.screenPadding),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item {
                CategoryChip(stringResource(R.string.category_all), selected == null) { onSelect(null) }
            }
            items(VenueCategory.all) { cat ->
                CategoryChip(cat.rawValue, selected == cat) {
                    onSelect(if (selected == cat) null else cat)
                }
            }
        }
    }
}

@Composable
private fun CategoryChip(label: String, isOn: Boolean, onClick: () -> Unit) {
    val c = AyantTheme.colors
    val interaction = remember { MutableInteractionSource() }
    Box(
        Modifier
            .clip(CircleShape)
            .then(
                if (isOn) Modifier.background(c.accentGradient)
                else Modifier.background(c.surface)
            )
            .selectable(
                selected = isOn,
                interactionSource = interaction,
                indication = null,
                role = Role.Tab,
                onClick = onClick,
            )
            .ayantPressScale(interaction, scale = 0.93f)
            .padding(horizontal = 16.dp, vertical = 10.dp),
    ) {
        Text(
            label,
            fontSize = 13.5.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.2).sp,
            color = if (isOn) Color.White else c.inkSoft, maxLines = 1,
        )
    }
}

/**
 * «Сегодня в избранном» — существующая функция, которой нет в макете.
 * Оставлена над лентой, чтобы редизайн ничего молча не удалил.
 */
@Composable
private fun TodaySpecialStrip(specials: List<Venue>, onVenue: (String) -> Unit) {
    val c = AyantTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            stringResource(R.string.home_today_saved).uppercase(),
            fontSize = 11.5.sp, fontWeight = FontWeight.Black, letterSpacing = 1.2.sp,
            color = c.inkSoft,
            modifier = Modifier.padding(horizontal = AyantMetrics.screenPadding),
        )
        LazyRow(
            contentPadding = PaddingValues(horizontal = AyantMetrics.screenPadding),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(specials) { v -> SpecialCard(v) { onVenue(v.id) } }
        }
    }
}

@Composable
private fun SpecialCard(venue: Venue, onClick: () -> Unit) {
    val c = AyantTheme.colors
    val shape = RoundedCornerShape(AyantRadius.card)
    Column(
        Modifier
            .width(200.dp)
            .clip(shape)
            .background(c.surface)
            .border(0.5.dp, c.hairline, shape)
            .clickable(onClick = onClick),
    ) {
        Box(
            Modifier.fillMaxWidth().height(74.dp)
                .background(Brush.linearGradient(venue.gradientColors)),
            contentAlignment = Alignment.Center,
        ) {
            Text(venue.emoji, fontSize = 32.sp)
        }
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                venue.name, fontSize = 14.sp, fontWeight = FontWeight.Bold,
                letterSpacing = (-0.25).sp, color = c.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
            Text(
                venue.todaySpecialText ?: "", fontSize = 11.5.sp, color = c.inkSoft,
                maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

/** Ошибка загрузки ленты с кнопкой повторить. Зеркалит `loadFailure` на iOS. */
@Composable
private fun LoadFailureState(title: String, subtitle: String, onRetry: () -> Unit) {
    val c = AyantTheme.colors
    Column(
        Modifier.fillMaxWidth().padding(top = 60.dp, start = 32.dp, end = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(title, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink)
        Text(subtitle, fontSize = 14.sp, color = c.inkSoft)
        androidx.compose.material3.TextButton(onClick = onRetry) {
            Text(stringResource(R.string.action_retry), color = c.accentText, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun EmptyState(title: String, subtitle: String) {
    val c = AyantTheme.colors
    Column(
        Modifier.fillMaxWidth().padding(top = 60.dp, start = 32.dp, end = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(title, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink)
        Text(subtitle, fontSize = 14.sp, color = c.inkSoft)
    }
}

/**
 * Плитка подбора по категории. Зеркалит `categoryTile` в `HomeFeedView.swift`.
 */
@Composable
private fun CategoryTile(deal: Deal, venue: Venue?, onClick: () -> Unit) {
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
                deal.allImages.firstOrNull(),
                venue?.gradientColors ?: listOf(c.accent, Color(0xFFFF9500)),
                Modifier.fillMaxWidth().height(118.dp),
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
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(
                deal.title,
                fontSize = 14.sp, fontWeight = FontWeight.Bold, color = c.ink,
                maxLines = 2, lineHeight = 17.sp,
            )
            venue?.let {
                Text(it.name, fontSize = 11.5.sp, color = c.inkSoft, maxLines = 1)
            }
            deal.newPrice?.let {
                Text(
                    stringResource(R.string.price_som, it),
                    fontSize = 14.sp, fontWeight = FontWeight.Black, color = c.accentText,
                )
            }
        }
    }
}


/**
 * Системный лист «Поделиться».
 *
 * Текст без ссылки: у приложения нет публичных веб-страниц предложений, а
 * выдуманный адрес открывался бы в никуда. Зеркалит `DealShare` в `HomeFeedView.swift`.
 */
private fun shareDeal(context: android.content.Context, deal: Deal, venue: Venue?) {
    val parts = buildList {
        add(deal.title)
        venue?.let { add(it.name) }
        deal.newPrice?.let { add("$it сом") }
    }
    val intent = android.content.Intent(android.content.Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(android.content.Intent.EXTRA_TEXT, parts.joinToString(" · "))
    }
    context.startActivity(android.content.Intent.createChooser(intent, null))
}
