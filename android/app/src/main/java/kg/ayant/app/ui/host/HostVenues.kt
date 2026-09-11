package kg.ayant.app.ui.host

import androidx.compose.foundation.background
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalConfiguration
import kotlinx.coroutines.launch
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.LocalOffer
import androidx.compose.material3.LocalTextStyle
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import kg.ayant.app.domain.model.HostDealDTO
import kg.ayant.app.ui.theme.AyantTiming
import kg.ayant.app.ui.theme.ayantPressScale
import kg.ayant.app.ui.theme.ayantRise
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Storefront
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.domain.model.HostVenueDTO
import kg.ayant.app.domain.model.VenueCategory
import kg.ayant.app.ui.components.VenuePhoto
import kg.ayant.app.ui.theme.AyantIconTile
import kg.ayant.app.ui.theme.AyantPrimaryButton
import kg.ayant.app.ui.theme.AyantScreenTitle
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantCard
import kg.ayant.app.ui.theme.ayantGroupCard
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.domain.HostIntent
import kg.ayant.app.ui.vm.HostViewModel

// MARK: - Onboarding

@Composable
fun HostOnboarding(host: HostViewModel, onCancel: () -> Unit) {
    val c = AyantTheme.colors
    var name by remember { mutableStateOf("") }
    var category by remember { mutableStateOf(VenueCategory.CAFE) }
    var phone by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }

    Column(Modifier.fillMaxSize().background(c.canvas).verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onCancel) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.action_back)) }
            Text(stringResource(R.string.profile_host_mode), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = c.ink)
        }
        Text(stringResource(R.string.host_onb_body), fontSize = 14.sp, color = c.inkSoft)
        OutlinedTextField(name, { name = it }, label = { Text(stringResource(R.string.host_onb_business_name)) }, singleLine = true, modifier = Modifier.fillMaxWidth())
        CategoryDropdown(category) { category = it }
        OutlinedTextField(phone, { phone = it }, label = { Text(stringResource(R.string.host_onb_phone)) }, singleLine = true, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(email, { email = it }, label = { Text(stringResource(R.string.hprofile_email)) }, singleLine = true, modifier = Modifier.fillMaxWidth())
        AyantPrimaryButton(stringResource(R.string.host_onb_continue), enabled = name.isNotBlank(), onClick = {
            host.send(HostIntent.CreateAccount(name.trim(), category, phone.trim(), email.trim()))
        })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CategoryDropdown(selected: VenueCategory, onSelect: (VenueCategory) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = selected.rawValue, onValueChange = {}, readOnly = true,
            label = { Text(stringResource(R.string.filter_category)) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
            modifier = Modifier.menuAnchor().fillMaxWidth(),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            VenueCategory.all.forEach { cat ->
                DropdownMenuItem(text = { Text(cat.rawValue) }, onClick = { onSelect(cat); expanded = false })
            }
        }
    }
}

// MARK: - Venues list
//
// Витрина, а не список. Прежний экран показывал карточки с обложкой 120dp: на
// экран влезало три заведения, между ними жил ряд кнопок, и «Заведения»
// читались как раздел настроек. Сетка 3×N квадратами встык показывает девять и
// отвечает на два вопроса без единого тапа — что опубликовано и где нет акций.
//
// Зеркалит `HostVenuesView.swift`.

/** Какая витрина открыта. Это фильтр одной и той же сетки, а не навигация. */
private enum class HostGridTab { VENUES, DEALS }

/** Затемнение снизу — единственное, что держит белый текст читаемым на
 *  произвольной фотографии. Останавливается на 62 %, чтобы не пачкать кадр. */
private val TileScrim = Brush.verticalGradient(
    0f to Color(0x0017130F), 0.38f to Color(0x5717130F), 1f to Color(0xDB17130F),
)

private val StatusLive = Color(0xFF4ADE80)
private val StatusReview = Color(0xFFFFB347)
private val StatusPaused = Color(0xFFB9B0A6)
private val StatusRejected = Color(0xFFE5484D)
private val TileEmpty = Color(0xFFEFEAE2)

/**
 * Плитка акции — прямоугольник 4:5 (ширина/высота), как пост в Instagram.
 * Заведение — это обложка, ему квадрата хватает; у акции под скримом живут
 * заголовок и название заведения, и на квадрате они жмутся к самому краю.
 * Пропорция ОДНА для всех акций: разнобой здесь читался бы как разный вес
 * предложений, а его нет — это просто витрина.
 */
private const val DEAL_ASPECT = 0.8f

/** Зазор сетки. */
private val GRID_GAP = 2.dp

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun HostVenuesScreen(
    host: HostViewModel,
    app: AppViewModel,
    onVenue: (String) -> Unit,
    onExitHost: () -> Unit,
    onProfile: () -> Unit = {},
) {
    val hostState by host.state.collectAsState()
    val c = AyantTheme.colors
    var showForm by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<HostVenueDTO?>(null) }
    var editingDeal by remember { mutableStateOf<HostDealDTO?>(null) }
    var addDealVenue by remember { mutableStateOf<String?>(null) }
    var statsVenue by remember { mutableStateOf<String?>(null) }
    var menuVenue by remember { mutableStateOf<HostVenueDTO?>(null) }
    var pickVenueForDeal by remember { mutableStateOf(false) }
    val pagerState = rememberPagerState(pageCount = { 2 })
    val scope = rememberCoroutineScope()
    val gridTab = if (pagerState.currentPage == 0) HostGridTab.VENUES else HostGridTab.DEALS
    // Выезд плиток уже проигран — дальше страницы просто листаются.
    var didStagger by remember { mutableStateOf(false) }
    var lastPage by remember { mutableIntStateOf(pagerState.currentPage) }
    LaunchedEffect(pagerState.currentPage) {
        if (pagerState.currentPage != lastPage) { didStagger = true; lastPage = pagerState.currentPage }
    }

    // Все акции всех заведений: порядок заведений, внутри — порядок акций
    // (`deals(forVenue)` уже отдаёт новые сверху).
    val allDeals = remember(hostState.venues, hostState.deals) {
        hostState.venues.flatMap { v -> hostState.deals(forVenue = v.id).map { it to v } }
    }

    // Высота страницы считается, а не измеряется: `HorizontalPager` внутри
    // вертикальной прокрутки получает бесконечный maxHeight и без явной высоты
    // не складывается. Плитки — фиксированной пропорции, так что высота ряда
    // известна заранее. Берём максимум из двух витрин: страницы лежат рядом, и
    // прыгающая при листании высота читалась бы как рывок.
    val screenWidth = LocalConfiguration.current.screenWidthDp.dp
    val tileWidth = (screenWidth - GRID_GAP * 2) / 3
    val venueRows = ((hostState.venues.size + 1) + 2) / 3
    val dealRows = ((allDeals.size + 1) + 2) / 3
    val venuesHeight = tileWidth * venueRows + GRID_GAP * (venueRows - 1)
    val dealsHeight = tileWidth / DEAL_ASPECT * dealRows + GRID_GAP * (dealRows - 1)

    // …и не меньше того, что осталось на экране под шапкой. Иначе страница
    // ровно по своим плиткам, а пустота под ними принадлежит уже вертикальной
    // прокрутке: пролистать витрину можно было бы только по самим плиткам. У
    // заведения с одной-двумя карточками это почти весь экран.
    val density = LocalDensity.current
    var viewportHeight by remember { mutableStateOf(0.dp) }
    var headerHeight by remember { mutableStateOf(0.dp) }
    var tabsHeight by remember { mutableStateOf(0.dp) }
    val pageHeight = maxOf(venuesHeight, dealsHeight, viewportHeight - headerHeight - tabsHeight)

    Scaffold(containerColor = c.canvas) { padding ->
        Box(
            Modifier.fillMaxSize().padding(bottom = padding.calculateBottomPadding())
                .onSizeChanged { with(density) { viewportHeight = it.height.toDp() } },
        ) {
            // `LazyColumn` + `stickyHeader` — ради закрепления вкладок: шапка
            // уезжает, переключатель витрин остаётся под часами. Обычная
            // `Column(verticalScroll)` этого не умеет.
            LazyColumn(Modifier.fillMaxSize()) {
                // Песочная шапка (SCREENS.md H2)
                item {
                    HostSandHeader(
                        flat = true,
                        modifier = Modifier.onSizeChanged {
                            with(density) { headerHeight = it.height.toDp() }
                        },
                    ) {
                        Row(
                            Modifier.fillMaxWidth().padding(top = 2.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            HostModeChip()
                            Spacer(Modifier.weight(1f))
                            HostGuestPill(onExitHost)
                            Box(
                                Modifier.size(44.dp).clickable(onClick = onProfile),
                                contentAlignment = Alignment.Center,
                            ) {
                                Box(
                                    Modifier.size(36.dp).clip(RoundedCornerShape(13.dp))
                                        .background(c.accentGradient),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Icon(Icons.Filled.Person, stringResource(R.string.htab_profile),
                                        tint = Color.White, modifier = Modifier.size(15.dp))
                                }
                            }
                        }
                        Spacer(Modifier.height(18.dp))
                        Text(
                            stringResource(R.string.htab_venues), fontSize = 42.sp,
                            fontWeight = FontWeight.Black, letterSpacing = (-2.3).sp,
                            lineHeight = 40.sp, color = c.ink,
                        )
                        Spacer(Modifier.height(16.dp))
                        // Счётчики — реальные метрики, а не выдуманные «за сегодня».
                        Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                            val active = hostState.deals.count { it.status.name == "ACTIVE" }
                            val views = hostState.venues.sumOf { host.stat(it.id, "views", 30) }
                            HostCounter("${hostState.venues.size}",
                                stringResource(R.string.host_stat_venues))
                            HostCounter("$active",
                                stringResource(R.string.host_stat_active_deals), accent = true)
                            HostCounter("$views", stringResource(R.string.host_stat_views))
                        }
                    }
                }

                // Закреплённая полоса. Прокручивается по горизонтали, как в
                // профиле Instagram: вкладки шириной по содержимому, а не по
                // 1/N экрана — третья въедет сюда, ничего не ломая. Заливка
                // канвасом обязательна: сквозь прозрачный фон было бы видно
                // едущие под полосой плитки.
                stickyHeader {
                    Row(
                        Modifier.fillMaxWidth()
                            .background(c.canvas)
                            .onSizeChanged { with(density) { tabsHeight = it.height.toDp() } }
                            .drawBehind {
                                drawRect(c.hairline, topLeft = Offset(0f, size.height - 0.5f),
                                    size = Size(size.width, 0.5f))
                            }
                            .horizontalScroll(rememberScrollState()),
                    ) {
                        HostGridTabButton(
                            icon = Icons.Filled.GridView,
                            label = stringResource(R.string.htab_venues),
                            count = hostState.venues.size,
                            active = gridTab == HostGridTab.VENUES,
                        ) { scope.launch { pagerState.animateScrollToPage(0) } }
                        HostGridTabButton(
                            icon = Icons.Filled.LocalOffer,
                            label = stringResource(R.string.host_grid_deals),
                            count = hostState.deals.size,
                            active = gridTab == HostGridTab.DEALS,
                        ) { scope.launch { pagerState.animateScrollToPage(1) } }
                    }
                }

                if (hostState.venues.isEmpty()) {
                    item {
                        Column(
                            Modifier.fillMaxWidth().padding(24.dp).padding(top = 24.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            AyantIconTile(Icons.Filled.Storefront, filled = true, size = 64)
                            Text(stringResource(R.string.host_no_venues_title), fontSize = 18.sp,
                                fontWeight = FontWeight.Bold, color = c.ink)
                            Text(stringResource(R.string.host_no_venues_body), fontSize = 15.sp,
                                color = c.inkSoft, textAlign = TextAlign.Center)
                        }
                    }
                }

                // Две витрины лежат рядом и листаются постранично: содержимое
                // едет за пальцем и защёлкивается на странице.
                item {
                    HorizontalPager(state = pagerState, modifier = Modifier.height(pageHeight)) { page ->
                        if (page == 0) {
                            HostTileGrid(
                                count = hostState.venues.size,
                                addTile = {
                                    HostAddTile(stringResource(R.string.host_tile_add_venue)) {
                                        editing = null; showForm = true
                                    }
                                },
                            ) { index ->
                                val v = hostState.venues[index]
                                HostVenueTile(
                                    v = v,
                                    dealCount = hostState.deals(forVenue = v.id).size,
                                    index = index,
                                    staggered = !didStagger,
                                    onClick = { onVenue(v.id) },
                                    onLongClick = { menuVenue = v },
                                )
                            }
                        } else {
                            HostTileGrid(
                                count = allDeals.size,
                                addTile = {
                                    HostAddTile(stringResource(R.string.host_tile_add_deal),
                                        aspect = DEAL_ASPECT) {
                                        // Акция всегда принадлежит заведению: без
                                        // заведений вести некуда.
                                        when {
                                            hostState.venues.isEmpty() -> { editing = null; showForm = true }
                                            hostState.venues.size == 1 -> addDealVenue = hostState.venues[0].id
                                            else -> pickVenueForDeal = true
                                        }
                                    }
                                },
                            ) { index ->
                                val (d, v) = allDeals[index]
                                HostDealTile(d, v, index, staggered = !didStagger) { editingDeal = d }
                            }
                        }
                    }
                }
            }
        }
    }


    // Действия заведения переехали с ряда кнопок под карточкой в долгий тап по
    // плитке: на квадрате 1/3 ширины кнопкам места нет, а сами действия нужны.
    menuVenue?.let { v ->
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { menuVenue = null },
            title = { Text(v.name) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    PillBtn(stringResource(R.string.host_add_deal_short), Modifier.fillMaxWidth(), accent = true) {
                        menuVenue = null; addDealVenue = v.id
                    }
                    PillBtn(stringResource(R.string.htab_analytics), Modifier.fillMaxWidth()) {
                        menuVenue = null; statsVenue = v.id
                    }
                    PillBtn(stringResource(R.string.action_edit), Modifier.fillMaxWidth()) {
                        menuVenue = null; editing = v; showForm = true
                    }
                }
            },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { menuVenue = null }) {
                    Text(stringResource(R.string.action_cancel))
                }
            },
        )
    }

    if (pickVenueForDeal) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { pickVenueForDeal = false },
            title = { Text(stringResource(R.string.host_pick_venue)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    hostState.venues.forEach { v ->
                        PillBtn(v.name, Modifier.fillMaxWidth()) {
                            pickVenueForDeal = false; addDealVenue = v.id
                        }
                    }
                }
            },
            confirmButton = {
                androidx.compose.material3.TextButton(onClick = { pickVenueForDeal = false }) {
                    Text(stringResource(R.string.action_cancel))
                }
            },
        )
    }

    if (showForm) HostVenueForm(host, editing) { showForm = false }
    addDealVenue?.let { vid -> HostDealForm(host, vid, null) { addDealVenue = null } }
    editingDeal?.let { d -> HostDealForm(host, d.venueID, d) { editingDeal = null } }
    statsVenue?.let { vid -> HostVenueStatsSheet(host, vid) { statsVenue = null } }
}

/**
 * Сетка одной страницы: 3 колонки, ряды встык, последним идёт плитка «+».
 *
 * Не ленивая нарочно: у страницы фиксированная высота внутри вертикальной
 * прокрутки, и `LazyVerticalGrid` внутри неё был бы вложенным скроллом. У
 * заведения десятки объектов, а не тысячи, — считать их все дешевле, чем
 * городить вложенную прокрутку.
 */
@Composable
private fun HostTileGrid(
    count: Int,
    addTile: @Composable () -> Unit,
    tile: @Composable (Int) -> Unit,
) {
    val total = count + 1                       // +1 — плитка «+»
    val rows = (total + 2) / 3
    // Заливка канвасом не украшение: прозрачная область не ловит касания, и
    // пустота под плитками не листалась бы.
    Column(
        Modifier.fillMaxSize().background(AyantTheme.colors.canvas),
        verticalArrangement = Arrangement.spacedBy(GRID_GAP),
    ) {
        repeat(rows) { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(GRID_GAP)) {
                repeat(3) { column ->
                    val index = row * 3 + column
                    Box(Modifier.weight(1f)) {
                        when {
                            index < count -> tile(index)
                            index == count -> addTile()
                            else -> Unit        // добивка ряда, чтобы не тянуть плитки
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Переключатель витрин

@Composable
private fun HostGridTabButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    count: Int,
    active: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val c = AyantTheme.colors
    val tint = if (active) c.ink else c.tabIdle
    Row(
        modifier
            .heightIn(min = 48.dp)
            .clickable(enabled = !active, onClick = onClick)
            .padding(horizontal = 20.dp)
            .drawBehind {
                if (active) {
                    drawRect(c.ink, topLeft = Offset(0f, size.height - 2.dp.toPx()),
                        size = Size(size.width, 2.dp.toPx()))
                }
            },
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(15.dp))
        Spacer(Modifier.width(6.dp))
        Text(
            "${label.uppercase()} $count", fontSize = 12.5.sp,
            fontWeight = FontWeight.Black, letterSpacing = 0.3.sp, color = tint,
        )
    }
}

// MARK: - Плитки

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun HostVenueTile(
    v: HostVenueDTO,
    dealCount: Int,
    index: Int,
    staggered: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    val c = AyantTheme.colors
    val interaction = remember { MutableInteractionSource() }
    Box(
        Modifier
            .fillMaxWidth()
            .aspectRatio(1f)
            .ayantRise(index, key = v.id, staggerMs = AyantTiming.HOST_GRID_STAGGER_MS,
                durationMs = AyantTiming.HOST_GRID_RISE_MS,
                cap = AyantTiming.GRID_STAGGER_CAP, enabled = staggered)
            .ayantPressScale(interaction)
            .combinedClickable(interaction, null, onLongClick = onLongClick, onClick = onClick),
    ) {
        VenuePhoto(v.imageURL.ifEmpty { null }, listOf(c.accent, c.accentDeep), Modifier.fillMaxSize())
        Box(Modifier.fillMaxSize().background(TileScrim))
        Column(Modifier.fillMaxSize().padding(7.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                if (v.moderation.name != "APPROVED") ModerationTag(v.moderation.name)
                Spacer(Modifier.weight(1f))
                DealCountBadge(dealCount)
            }
            Spacer(Modifier.weight(1f))
            Row(verticalAlignment = Alignment.Top) {
                StatusDot(venueColor(v.moderation.name), 6.dp, Color(0x8017130F),
                    Modifier.padding(top = 3.dp))
                Spacer(Modifier.width(5.dp))
                Column {
                    TileText(v.name, 11.sp, FontWeight.Black, Color.White)
                    TileText("${v.category.rawValue} · ${v.district}", 9.5.sp,
                        FontWeight.Bold, Color.White.copy(alpha = 0.86f))
                }
            }
        }
    }
}

@Composable
private fun HostDealTile(
    d: HostDealDTO,
    venue: HostVenueDTO,
    index: Int,
    staggered: Boolean,
    onClick: () -> Unit,
) {
    val c = AyantTheme.colors
    val interaction = remember { MutableInteractionSource() }
    val cover = d.imageURL
    Box(
        Modifier
            .fillMaxWidth()
            .aspectRatio(DEAL_ASPECT)
            .ayantRise(index, key = d.id, staggerMs = AyantTiming.HOST_GRID_STAGGER_MS,
                durationMs = AyantTiming.HOST_GRID_RISE_MS,
                cap = AyantTiming.GRID_STAGGER_CAP, enabled = staggered)
            .ayantPressScale(interaction)
            .clickable(interaction, null, onClick = onClick),
    ) {
        VenuePhoto(cover.ifEmpty { null }, listOf(c.accent, c.accentDeep), Modifier.fillMaxSize())
        Box(Modifier.fillMaxSize().background(TileScrim))
        Column(Modifier.fillMaxSize().padding(7.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                DiscountBadge(d)
                Spacer(Modifier.weight(1f))
                StatusDot(dealColor(d.status.name), 9.dp, Color.White.copy(alpha = 0.9f))
            }
            Spacer(Modifier.weight(1f))
            TileText(d.title, 11.5.sp, FontWeight.Black, Color.White)
            TileText(venue.name, 9.5.sp, FontWeight.Bold, Color.White.copy(alpha = 0.86f))
        }
    }
}

@Composable
private fun HostAddTile(label: String, aspect: Float = 1f, onClick: () -> Unit) {
    val c = AyantTheme.colors
    val interaction = remember { MutableInteractionSource() }
    Box(
        Modifier.fillMaxWidth().aspectRatio(aspect).background(TileEmpty)
            .ayantPressScale(interaction)
            .clickable(interaction, null, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Filled.Add, null, tint = c.accentText, modifier = Modifier.size(20.dp))
            Text(label, fontSize = 10.5.sp, fontWeight = FontWeight.Black, color = c.inkSoft)
        }
    }
}

// MARK: - Мелочи плиток

/** Подпись на фотографии: тень — то, что держит её читаемой на светлом кадре. */
@Composable
private fun TileText(text: String, size: androidx.compose.ui.unit.TextUnit,
                     weight: FontWeight, color: Color) {
    Text(
        text, fontSize = size, fontWeight = weight, color = color,
        maxLines = 1, overflow = TextOverflow.Ellipsis,
        style = LocalTextStyle.current.copy(
            shadow = Shadow(Color.Black.copy(alpha = 0.5f), Offset(0f, 1f), 6f),
        ),
    )
}

/**
 * Значок числа акций. Ноль — тоже сигнал, поэтому плитка есть у любого
 * заведения, а «0» просто гасится: витрина без акций видна с одного взгляда.
 */
@Composable
private fun DealCountBadge(n: Int) {
    Box(
        Modifier
            .defaultMinSize(minWidth = 20.dp, minHeight = 20.dp)
            .clip(RoundedCornerShape(7.dp))
            .background(if (n > 0) Color.White.copy(alpha = 0.92f) else Color(0x8C17130F))
            .padding(horizontal = 5.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text("$n", fontSize = 11.sp, fontWeight = FontWeight.Black,
            color = if (n > 0) Color(0xFF17130F) else Color.White)
    }
}

@Composable
private fun ModerationTag(statusName: String) {
    val rejected = statusName == "REJECTED"
    Text(
        stringResource(if (rejected) R.string.host_tag_rejected else R.string.host_tag_moderation)
            .uppercase(),
        fontSize = 9.sp, fontWeight = FontWeight.Black, letterSpacing = 0.4.sp,
        color = Color.White, maxLines = 1,
        modifier = Modifier
            .clip(RoundedCornerShape(6.dp))
            .background(venueColor(statusName).copy(alpha = 0.94f))
            .padding(horizontal = 6.dp, vertical = 3.dp),
    )
}

/**
 * Скидка, если она есть; иначе — тип публикации. Пустой угол ничего не
 * сообщает, а «Новинка» отвечает на тот же вопрос, что и «−40 %».
 */
@Composable
private fun DiscountBadge(d: HostDealDTO) {
    val c = AyantTheme.colors
    Text(
        d.discountPercent?.let { "−$it%" } ?: d.type.title,
        fontSize = 11.sp, fontWeight = FontWeight.Black, color = Color.White, maxLines = 1,
        modifier = Modifier
            .clip(RoundedCornerShape(8.dp))
            .background(c.accentGradient)
            .padding(horizontal = 7.dp, vertical = 4.dp),
    )
}

/**
 * Точка статуса с кольцом СНАРУЖИ: рисовать его внутрь значило бы съесть
 * половину шестипиксельной точки и оставить три пикселя цвета.
 */
@Composable
private fun StatusDot(color: Color, size: Dp, ring: Color, modifier: Modifier = Modifier) {
    Box(
        modifier.clip(CircleShape).background(ring).padding(1.5.dp),
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(size).clip(CircleShape).background(color))
    }
}

private fun venueColor(statusName: String): Color = when (statusName) {
    "APPROVED" -> StatusLive
    "REJECTED" -> StatusRejected
    else -> StatusReview
}

private fun dealColor(statusName: String): Color = when (statusName) {
    "ACTIVE" -> StatusLive
    "DRAFT" -> StatusReview
    else -> StatusPaused
}

@Composable
private fun HostVenueStatsSheet(host: HostViewModel, venueID: String, onDismiss: () -> Unit) {
    val hostState by host.state.collectAsState()
    val c = AyantTheme.colors
    var period by remember { mutableStateOf(30) }
    val metrics = listOf(
        stringResource(R.string.analytics_views) to "views", stringResource(R.string.analytics_redemptions) to "redemptions", stringResource(R.string.analytics_deal_taps) to "dealTaps",
        stringResource(R.string.analytics_saves) to "saves", stringResource(R.string.analytics_calls) to "calls", stringResource(R.string.analytics_maps) to "maps",
    )
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(hostState.venue(venueID)?.name ?: stringResource(R.string.htab_analytics)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(7, 30, 90).forEach { d -> PillBtn(stringResource(R.string.analytics_days_short, d), Modifier.weight(1f), accent = period == d) { period = d } }
                }
                metrics.forEach { (title, key) ->
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(title, fontSize = 14.sp, color = c.inkSoft, modifier = Modifier.weight(1f))
                        Text("${host.stat(venueID, key, period)}", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = c.ink)
                    }
                }
            }
        },
        confirmButton = { androidx.compose.material3.TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_done)) } },
    )
}

@Composable
private fun StatCard(value: String, label: String, modifier: Modifier = Modifier, accent: Boolean = false) {
    val c = AyantTheme.colors
    Column(modifier.ayantCard(padding = 16)) {
        Text(value, fontSize = 26.sp, fontWeight = FontWeight.Black, color = if (accent) c.accent else c.ink)
        Text(label, fontSize = 12.sp, color = c.inkSoft)
    }
}

@Composable
fun PillBtn(text: String, modifier: Modifier = Modifier, accent: Boolean = false, onClick: () -> Unit) {
    val c = AyantTheme.colors
    Text(
        text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
        color = if (accent) c.accent else c.ink,
        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        maxLines = 1,
        overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
        modifier = modifier.clip(RoundedCornerShape(14.dp)).background(if (accent) c.accent.copy(alpha = 0.12f) else c.surfaceMuted).clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 12.dp),
    )
}

/** Счётчик в песочной шапке. */
@Composable
private fun HostCounter(value: String, label: String, accent: Boolean = false) {
    val c = AyantTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(
            value, fontSize = 24.sp, fontWeight = FontWeight.Black,
            letterSpacing = (-1).sp,
            color = if (accent) Color(0xFFE04206) else c.ink,
        )
        Text(label, fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold, color = c.hostCaption)
    }
}

/** Карточка быстрого действия под шапкой. */
@Composable
private fun HostQuickCard(
    title: String,
    sub: String,
    filled: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val c = AyantTheme.colors
    val shape = RoundedCornerShape(22.dp)
    Column(
        modifier
            .clip(shape)
            .then(if (filled) Modifier.background(c.accentGradient) else Modifier.background(c.surface))
            .clickable(onClick = onClick)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            title, fontSize = 14.5.sp, fontWeight = FontWeight.Black,
            color = if (filled) Color.White else c.ink,
        )
        Text(
            sub, fontSize = 11.5.sp,
            color = if (filled) Color.White.copy(alpha = 0.86f) else c.inkSoft,
        )
    }
}
