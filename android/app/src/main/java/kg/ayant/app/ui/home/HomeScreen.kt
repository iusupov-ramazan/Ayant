package kg.ayant.app.ui.home

import android.content.Intent
import android.provider.Settings
import androidx.activity.compose.BackHandler
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.NotificationManagerCompat
import kg.ayant.app.R
import kg.ayant.app.core.Links
import kg.ayant.app.core.localizedName
import kg.ayant.app.core.shareText
import kg.ayant.app.core.storefrontIcon
import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.FeedItem
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenueCategory
import kg.ayant.app.location.LocationManager
import kg.ayant.app.ui.auth.GuestAlert
import kg.ayant.app.ui.auth.GuestGate
import kg.ayant.app.ui.components.AyantCategoryRail
import kg.ayant.app.ui.components.AyantUnavailableView
import kg.ayant.app.ui.components.VenuePhoto
import kg.ayant.app.ui.theme.AyantMetrics
import kg.ayant.app.ui.theme.AyantRadius
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.AyantTiming
import kg.ayant.app.ui.theme.ayantPressScale
import kg.ayant.app.ui.theme.ayantRise
import kg.ayant.app.ui.theme.ayantScreenEnter
import kg.ayant.app.ui.theme.gradientColors
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.ui.vm.FeedViewModel
import kg.ayant.app.ui.vm.SessionViewModel
import kotlinx.coroutines.launch

/**
 * Главная (SCREENS.md G2) — определяющий экран редизайна.
 * Зеркалит `HomeFeedView.swift`.
 *
 * Шапка с редакторским «Сегодня», липкий ряд текстовых чипов категорий, ряд
 * «Заведения» и лента постов: белая полоса, фото 4:5, весь текст под
 * фотографией (см. `FeedCard.kt`).
 */
private const val VENUE_RAIL_LIMIT = 12

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class, ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    app: AppViewModel,
    location: LocationManager,
    feed: FeedViewModel,
    session: SessionViewModel,
    onVenue: (String) -> Unit,
    onDeal: (String) -> Unit,
    onSaved: () -> Unit = {},
    /**
     * Полный список заведений (`FeedRoute.allVenues` на iOS) на текущем фильтре.
     * Пока `RootScaffold` не объявил маршрут, экран открывается ПОВЕРХ ленты
     * (внутренний фолбэк ниже) — поведение то же, стек навигации другой.
     */
    onAllVenues: ((VenueCategory?) -> Unit)? = null,
) {
    val c = AyantTheme.colors
    var category by remember { mutableStateOf<VenueCategory?>(null) }
    // Сохранение и лайк принадлежат аккаунту: гостю объясняем это диалогом,
    // а не молчаливым «ничего не произошло».
    var guestMessage by remember { mutableStateOf<Int?>(null) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    // ВНИМАНИЕ: общие ViewModel приходят параметром из RootScaffold. Вызов
    // viewModel() здесь дал бы экземпляр НА МАРШРУТ (владелец — NavBackStackEntry).
    val feedState by feed.state.collectAsState()
    // Избранным владеет профиль: без подписки сердечко не перекрасится.
    val profileState by app.profileFlow.collectAsState()
    val feedItems = remember(feedState, category) { feed.items(category) }
    val categoryDeals = remember(feedState, category) { feed.deals(category) }
    // Ранжированный каталог по категории (одобренные, не на паузе). Целиком его
    // показывает «Заведения»; на главной — счётчик в шапке ряда и первые
    // VENUE_RAIL_LIMIT плиток.
    val categoryVenues = remember(feedState, category) { feed.venues(category) }
    val railVenues = categoryVenues.take(VENUE_RAIL_LIMIT)
    val specials = remember(feedState, profileState) { app.savedTodaySpecials }
    val isLoading = feedState.catalog.isLoading
    val loadFailed = feedState.catalog.errorOrNull() != null
    // Ряд есть только у готовой ленты: на скелетоне, ошибке и пустом городе
    // показывать нечего. Для выбранной категории ряд остаётся — он полезнее
    // всего, когда акций в категории ещё нет.
    val showsVenueRail = !isLoading && !loadFailed && railVenues.isNotEmpty()

    // Фолбэк для «Все заведения», пока маршрута в RootScaffold нет.
    var allVenuesOpen by remember { mutableStateOf(false) }
    fun openAllVenues() {
        if (onAllVenues != null) onAllVenues(category) else allVenuesOpen = true
    }
    if (allVenuesOpen) {
        BackHandler { allVenuesOpen = false }
        AllVenuesScreen(
            app = app, feed = feed, location = location,
            initialCategory = category,
            onVenue = onVenue,
            onBack = { allVenuesOpen = false },
        )
        return
    }

    LaunchedEffect(category, feedItems.map { it.id }) {
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
    LaunchedEffect(category) {
        if (category != lastCategory) {
            lastCategory = category
            listState.scrollToItem(0)
        }
    }

    var refreshing by remember { mutableStateOf(false) }

    Scaffold(containerColor = c.canvas) { padding ->
        PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = {
                scope.launch { refreshing = true; app.refresh(); refreshing = false }
            },
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxSize(),
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

            // «Сегодня в избранном» — существующая функция, которой нет в
            // макете. Оставлена над лентой, чтобы редизайн ничего молча не удалил.
            if (specials.isNotEmpty()) {
                item(key = "specials") {
                    TodaySpecialStrip(specials, onVenue)
                    Spacer(Modifier.height(18.dp))
                }
            }

            // Пока вкладка «Поиск» скрыта (`ReleaseFlags.SEARCH_TAB`), это
            // единственный список заведений в приложении — без него человек
            // видел бы только акции.
            if (showsVenueRail) {
                item(key = "venueRail") {
                    VenueRail(
                        venues = railVenues,
                        totalCount = categoryVenues.size,
                        rating = { app.aggregate(it).first },
                        distanceKm = { location.distanceKm(it.latitude, it.longitude) },
                        onVenue = { onVenue(it.id) },
                        onAll = { openAllVenues() },
                    )
                    Spacer(Modifier.height(18.dp))
                }
            }

            when {
                isLoading -> item(key = "skeleton") { FeedSkeleton() }

                // Ошибка загрузки раньше попадала в «нет заведений в городе»:
                // пустой экран без объяснения и без кнопки повторить.
                loadFailed -> item(key = "loadFailure") {
                    AyantUnavailableView(
                        icon = Icons.Filled.WifiOff,
                        title = stringResource(R.string.feed_load_failed_title),
                        body = feed.loadError ?: stringResource(R.string.feed_load_failed_body),
                        actionLabel = stringResource(R.string.action_retry),
                        onAction = { app.load() },
                    )
                }

                !feedState.hasVenuesInCity -> item(key = "emptyCity") {
                    AyantUnavailableView(
                        icon = storefrontIcon,
                        title = stringResource(R.string.home_empty_city_title, app.selectedCity.name),
                        body = stringResource(R.string.home_empty_city_body),
                    )
                }

                categoryDeals.isEmpty() -> item(key = "emptyCat") {
                    AyantUnavailableView(
                        icon = Icons.Outlined.Inbox,
                        title = stringResource(R.string.feed_empty_cat_title),
                        body = stringResource(
                            R.string.home_empty_cat_body_fmt,
                            category?.localizedName() ?: "", app.selectedCity.name,
                        ),
                        actionLabel = stringResource(R.string.home_reset_filter),
                        onAction = { category = null },
                    )
                }

                // Выбрана категория — это ПОДБОР, а не лента: человек сравнивает
                // варианты. Полноэкранные карточки дают одно предложение на
                // экран, плитки — вчетверо больше. Зеркалит `categoryGrid`
                // в `HomeFeedView.swift`.
                category != null -> {
                    itemsIndexed(categoryDeals.chunked(2), key = { _, row -> row.first().id }) { rowIndex, row ->
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = AyantMetrics.screenPadding),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            row.forEachIndexed { i, deal ->
                                Box(
                                    Modifier
                                        .weight(1f)
                                        .ayantRise(
                                            index = rowIndex * 2 + i, key = deal.id,
                                            staggerMs = AyantTiming.GRID_TILE_STAGGER_MS,
                                            durationMs = AyantTiming.GRID_TILE_RISE_MS,
                                            cap = AyantTiming.GRID_STAGGER_CAP,
                                        ),
                                ) {
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
                        Spacer(Modifier.height(12.dp))
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
                                        if (app.isGuest) guestMessage = GuestGate.SAVE_DEAL
                                        else app.toggleFavorite(deal)
                                    },
                                    // Лайк тоже требует аккаунта: он кормит ранжирование
                                    // и должен переезжать с пользователем.
                                    onLike = {
                                        if (app.isGuest) guestMessage = GuestGate.LIKE
                                        else app.toggleLike(deal)
                                    },
                                    onShare = { context.shareText(shareText(context, deal, venue)) },
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
                                        if (app.isGuest) guestMessage = GuestGate.SAVE_VENUE
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
    }

    guestMessage?.let { message ->
        GuestAlert(session, message) { guestMessage = null }
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
            // Без шеврона: города пока не выбираются, и стрелка обещала бы
            // меню, которого нет. Это подпись, а не кнопка.
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(Icons.Filled.LocationOn, null, tint = c.accentText, modifier = Modifier.size(13.dp))
                Text(
                    city, fontSize = 13.5.sp, fontWeight = FontWeight.Bold,
                    letterSpacing = (-0.2).sp, color = c.ink,
                )
            }
            Spacer(Modifier.weight(1f))
            HeaderIconButton(Icons.Outlined.BookmarkBorder, stringResource(R.string.tab_saved), onSaved)
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
        HeaderIconButton(Icons.Outlined.Notifications, stringResource(R.string.tab_notifications)) {
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
        AyantCategoryRail(selected = selected, onSelect = onSelect)
    }
}

/** Заголовок-«бровь» секции: капслок, 11.5/Black, разрядка. Зеркалит `sanEyebrowText`. */
@Composable
private fun SectionEyebrow(text: String, modifier: Modifier = Modifier) {
    Text(
        text.uppercase(),
        fontSize = 11.5.sp, fontWeight = FontWeight.Black, letterSpacing = 1.2.sp,
        color = AyantTheme.colors.inkSoft,
        modifier = modifier,
    )
}

/**
 * Ряд «Заведения»: первые [VENUE_RAIL_LIMIT] плиток каталога категории и хвост
 * «Все заведения →». Зеркалит `venueRail` в `HomeFeedView.swift`.
 */
@Composable
private fun VenueRail(
    venues: List<Venue>,
    totalCount: Int,
    rating: (Venue) -> Double,
    distanceKm: (Venue) -> Double?,
    onVenue: (Venue) -> Unit,
    onAll: () -> Unit,
) {
    val c = AyantTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = AyantMetrics.screenPadding),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SectionEyebrow(stringResource(R.string.home_rail_venues))
            Spacer(Modifier.weight(1f))
            // «Все · N» — N считается по всему каталогу категории, а не по
            // дюжине плиток ряда: число обещает, сколько ждёт в списке.
            val interaction = remember { MutableInteractionSource() }
            Row(
                Modifier
                    .clickable(interaction, null, role = Role.Button, onClick = onAll)
                    .ayantPressScale(interaction, 0.93f)
                    .padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                Text(
                    stringResource(R.string.home_rail_all_count, totalCount),
                    fontSize = 12.5.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.2).sp,
                    color = c.accentText,
                )
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = stringResource(R.string.home_all_venues),
                    tint = c.accentText, modifier = Modifier.size(14.dp),
                )
            }
        }
        LazyRow(
            contentPadding = PaddingValues(horizontal = AyantMetrics.screenPadding),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(venues, key = { it.id }) { venue ->
                // Тот же маршрут, что у рекламной карточки в ленте.
                FeedVenueTile(
                    venue = venue,
                    rating = rating(venue),
                    distanceKm = distanceKm(venue),
                    onClick = { onVenue(venue) },
                )
            }
            // Хвост ряда ведёт туда же, куда «Все · N» в шапке: человек,
            // долиставший до конца, не должен возвращаться к заголовку.
            item(key = "more") { FeedVenueMoreTile(count = totalCount, onClick = onAll) }
        }
    }
}

/**
 * «Сегодня в избранном» — существующая функция, которой нет в макете.
 * Оставлена над лентой, чтобы редизайн ничего молча не удалил.
 */
@Composable
private fun TodaySpecialStrip(specials: List<Venue>, onVenue: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionEyebrow(
            stringResource(R.string.home_today_saved),
            modifier = Modifier.padding(horizontal = AyantMetrics.screenPadding),
        )
        LazyRow(
            contentPadding = PaddingValues(horizontal = AyantMetrics.screenPadding),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            items(specials, key = { it.id }) { v -> SpecialCard(v) { onVenue(v.id) } }
        }
    }
}

@Composable
private fun SpecialCard(venue: Venue, onClick: () -> Unit) {
    val c = AyantTheme.colors
    val shape = RoundedCornerShape(AyantRadius.card)
    val interaction = remember { MutableInteractionSource() }
    Column(
        Modifier
            .width(200.dp)
            .clip(shape)
            .background(c.surface)
            .border(0.5.dp, c.hairline, shape)
            .clickable(interaction, null, onClick = onClick)
            .ayantPressScale(interaction, 0.97f),
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

/**
 * Плитка подбора по категории. Зеркалит `categoryTile` в `HomeFeedView.swift`.
 */
@Composable
private fun CategoryTile(deal: Deal, venue: Venue?, onClick: () -> Unit) {
    val c = AyantTheme.colors
    val shape = RoundedCornerShape(AyantRadius.card)
    val interaction = remember { MutableInteractionSource() }
    Column(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(c.surface)
            .border(0.5.dp, c.hairline, shape)
            .clickable(interaction, null, onClick = onClick)
            .ayantPressScale(interaction, 0.97f),
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
                fontSize = 14.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.25).sp, color = c.ink,
                maxLines = 2, lineHeight = 17.sp, overflow = TextOverflow.Ellipsis,
            )
            venue?.let {
                Text(it.name, fontSize = 11.5.sp, color = c.inkSoft, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            deal.newPrice?.let {
                Text(
                    stringResource(R.string.price_som, it),
                    fontSize = 14.sp, fontWeight = FontWeight.Black, letterSpacing = (-0.3).sp, color = c.accentText,
                )
            }
        }
    }
}

/**
 * Текст «Поделиться»: «Название · Заведение · 350 сом» и Universal Link на
 * акцию — тот же, что в шаринге с экрана предложения: получатель откроет её
 * в приложении. Зеркалит `DealShare.text` в `HomeFeedView.swift`.
 */
private fun shareText(context: android.content.Context, deal: Deal, venue: Venue?): String {
    val parts = buildList {
        add(deal.title)
        venue?.let { add(it.name) }
        deal.newPrice?.let { add(context.getString(R.string.price_som, it)) }
    }
    return parts.joinToString(" · ") + "\n" + Links.deal(deal.id)
}
