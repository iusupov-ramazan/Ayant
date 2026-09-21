package kg.ayant.app.ui.search

import android.Manifest
import android.content.pm.PackageManager
import androidx.annotation.StringRes
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import com.google.maps.android.clustering.ClusterItem
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.MapUiSettings
import com.google.maps.android.compose.MapsComposeExperimentalApi
import com.google.maps.android.compose.clustering.Clustering
import com.google.maps.android.compose.rememberCameraPositionState
import kg.ayant.app.R
import kg.ayant.app.core.AppLanguage
import kg.ayant.app.core.badgeLabel
import kg.ayant.app.core.distanceText
import kg.ayant.app.core.localizedName
import kg.ayant.app.core.localizedTitle
import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.Review
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenueCategory
import kg.ayant.app.domain.pointsActive
import kg.ayant.app.location.LocationManager
import kg.ayant.app.ui.auth.GuestAlert
import kg.ayant.app.ui.auth.GuestGate
import kg.ayant.app.ui.components.AyantUnavailableView
import kg.ayant.app.ui.components.VenueCompactRow
import kg.ayant.app.ui.components.VenuePhoto
import kg.ayant.app.ui.home.ratingText
import kg.ayant.app.ui.theme.AyantMetrics
import kg.ayant.app.ui.theme.AyantMotion
import kg.ayant.app.ui.theme.AyantRadius
import kg.ayant.app.ui.theme.AyantShadow
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.AyantTiming
import kg.ayant.app.ui.theme.ayantPressScale
import kg.ayant.app.ui.theme.ayantRise
import kg.ayant.app.ui.theme.ayantShadow
import kg.ayant.app.ui.theme.gradientColors
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.ui.vm.SessionViewModel
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Порядок выдачи поиска. Отдельный тип, а не булевы флаги: варианты
 * взаимоисключающие, и чип-меню показывает выбранный прямо в заголовке.
 * Зеркалит `SearchSort` в `SearchView.swift`.
 */
enum class SearchSort(@StringRes val titleRes: Int, @StringRes val chipRes: Int) {
    /** Полное название — в меню; короткое — в самом чипе: строка фильтров и так уезжает за край. */
    BEST(R.string.search_sort_best, R.string.search_sort_chip_best),
    NEAR(R.string.search_sort_near, R.string.search_sort_chip_near),
    RATING(R.string.search_sort_rating, R.string.search_sort_chip_rating),
    DISCOUNT(R.string.search_sort_discount, R.string.search_sort_chip_discount),
}

/**
 * Поиск после редизайна (SCREENS.md G8). Зеркалит `SearchView.swift`.
 *
 * Карта всегда сверху, а лист результатов ездит по ней между четырьмя
 * положениями: на весь экран · по умолчанию · карта крупно · «лист убран»
 * (видна только шапка листа — иначе карту не посмотреть целиком).
 *
 * ВАЖНО про производительность и попадание по «ручке»: карта НИКОГДА не меняет
 * свой размер. `GoogleMap` всегда высотой [MAP_HEIGHT] (= самое нижнее
 * положение листа: ниже него карта обязана быть нарисована), а ниже её просто
 * накрывает непрозрачный лист. Если менять высоту самой карты, `MapView`
 * переразмечается на каждый кадр жеста — и перетаскивание заметно лагает.
 */
private val STOP_EXPANDED = 0.dp      // лист на весь экран
private val STOP_MEDIUM = 270.dp      // по умолчанию, как в макете
/** Режим превью: карта остаётся крупной, но карточке пина хватает места целиком. */
private val STOP_PREVIEW = 400.dp
private val STOP_COLLAPSED = 520.dp   // карта крупно, лист снизу
private val STOP_PEEK = 645.dp        // лист убран вниз, видна только шапка
private val MAP_HEIGHT = STOP_PEEK
/** Сколько пинов рисуем за раз: карта с сотней подписей нечитаема. */
private const val PIN_PAGE_SIZE = 24

@OptIn(ExperimentalMaterial3Api::class, MapsComposeExperimentalApi::class)
@Composable
fun SearchScreen(
    app: AppViewModel,
    location: LocationManager,
    onVenue: (String) -> Unit,
    /** Для диалога гостю при сохранении из выдачи; без него гость просто не сохраняет. */
    session: SessionViewModel? = null,
) {
    val c = AyantTheme.colors
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    var query by remember { mutableStateOf("") }
    // Подписка на владельцев данных: адаптеры `app.*` — обычные геттеры поверх
    // `state.value` ленты и профиля, поэтому без этой строки экран не
    // перерисуется ни после загрузки каталога, ни после изменения сохранённого.
    val feedState by app.feedState.collectAsState()
    val profileState by app.profileFlow.collectAsState()

    var openNow by remember { mutableStateOf(false) }
    var withDeals by remember { mutableStateOf(false) }
    var pointsOnly by remember { mutableStateOf(false) }
    var minRating by remember { mutableStateOf(0) }            // 0 | 3 | 4
    var maxDistance by remember { mutableStateOf<Double?>(null) } // км: 0.5 | 1 | 3
    var category by remember { mutableStateOf<VenueCategory?>(null) }
    var sort by remember { mutableStateOf(SearchSort.BEST) }
    var showFilters by remember { mutableStateOf(false) }
    /** Выбранный на карте пин: лист показывает ОДНУ карточку (режим превью). */
    var previewVenue by remember { mutableStateOf<Venue?>(null) }
    /** Заведения кластера — список листом. */
    var clusterVenues by remember { mutableStateOf<List<Venue>?>(null) }
    var pinBudget by remember { mutableStateOf(PIN_PAGE_SIZE) }
    var guestMessage by remember { mutableStateOf<Int?>(null) }

    val anyFilterOn = openNow || withDeals || pointsOnly || minRating > 0 || maxDistance != null || category != null
    fun resetFilters() {
        openNow = false; withDeals = false; pointsOnly = false
        minRating = 0; maxDistance = null; category = null
    }

    // Подпись текущего фильтра — при её смене сбрасываем порцию пинов.
    val filterSignature = listOf(query, openNow, withDeals, pointsOnly, minRating, maxDistance, category, sort)
    LaunchedEffect(filterSignature) { pinBudget = PIN_PAGE_SIZE }

    // Предложения и отзывы, разложенные по заведениям ОДНИМ проходом: фильтры
    // на каждое заведение звали бы `deals(forVenue)` / `reviews(forVenue)`, а те
    // каждый раз проходят по всему списку.
    val index = remember(feedState) {
        SearchIndex(
            dealsByVenue = feedState.loadedCatalog.deals.filter { it.isActive }.groupBy { it.venueID },
            reviewsByVenue = feedState.reviews.groupBy { it.venueID },
        )
    }

    fun matchesQuery(v: Venue): Boolean {
        if (query.isBlank()) return true
        val q = query.trim()
        if (v.name.contains(q, true) || v.category.rawValue.contains(q, true) ||
            v.district.contains(q, true) || v.address.contains(q, true)
        ) return true
        // Объекты внутри заведения (блюда / услуги)
        if (v.items.any { it.name.contains(q, true) }) return true
        // Предложения (название + описание)
        if (index.dealsByVenue[v.id].orEmpty().any { it.title.contains(q, true) || it.details.contains(q, true) }) return true
        // Отзывы (текст + упомянутый объект)
        if (index.reviewsByVenue[v.id].orEmpty().any { it.text.contains(q, true) || (it.itemName?.contains(q, true) == true) }) return true
        return false
    }

    fun matchesFilters(v: Venue): Boolean {
        if (openNow && !v.isOpenNow) return false
        if (withDeals && index.dealsByVenue[v.id].orEmpty().isEmpty()) return false
        if (pointsOnly && !v.pointsActive) return false
        if (category != null && v.category != category) return false
        if (minRating > 0 && feedState.aggregate(v).first < minRating) return false
        maxDistance?.let { md ->
            val d = location.distanceKm(v.latitude, v.longitude) ?: return false
            if (d > md) return false
        }
        return true
    }

    /** `BEST` — то, что уже посчитал ранжировщик; остальные пересортировывают его результат. */
    fun sorted(venues: List<Venue>): List<Venue> = when (sort) {
        SearchSort.BEST -> venues
        SearchSort.NEAR -> venues.sortedBy { location.distanceKm(it.latitude, it.longitude) ?: Double.MAX_VALUE }
        SearchSort.RATING -> venues.sortedByDescending { feedState.aggregate(it).first }
        SearchSort.DISCOUNT -> venues.sortedByDescending { v ->
            index.dealsByVenue[v.id].orEmpty().mapNotNull { it.effectiveDiscountPercent }.maxOrNull() ?: 0
        }
    }

    // Выдача КЭШИРУЕТСЯ, а не считается на каждую рекомпозицию: во время
    // перетаскивания листа экран рекомпозится каждый кадр, и перебор каталога
    // шёл бы 60 раз в секунду. `rankedVenues()` зовём ОДИН раз: список для
    // карты — те же заведения без текстового фильтра, а выдача — его подмножество.
    val recomputeKey = listOf(filterSignature, feedState, location.lastLat, location.lastLng, pinBudget)
    val computed = remember(recomputeKey) {
        val byFilters = sorted(app.rankedVenues().filter { matchesFilters(it) })
        SearchResults(
            matching = byFilters,
            mapVenues = byFilters.take(pinBudget),
            results = byFilters.filter { matchesQuery(it) },
        )
    }
    val matchingVenues = computed.matching
    val mapVenues = computed.mapVenues
    val results = computed.results

    /** Лучшая активная акция заведения — её ленту показываем на карточке. */
    fun bestDeal(v: Venue): Deal? =
        index.dealsByVenue[v.id].orEmpty().maxByOrNull { it.effectiveDiscountPercent ?: 0 }

    // Положение листа в пикселях. Animatable, а не обычный state: снапинг после
    // отпускания — это анимация, а сам жест должен идти без неё.
    val expandedPx = with(density) { STOP_EXPANDED.toPx() }
    val mediumPx = with(density) { STOP_MEDIUM.toPx() }
    val previewPx = with(density) { STOP_PREVIEW.toPx() }
    val collapsedPx = with(density) { STOP_COLLAPSED.toPx() }
    val peekPx = with(density) { STOP_PEEK.toPx() }
    val overlapPx = with(density) { 24.dp.toPx() }
    val stops = listOf(expandedPx, mediumPx, collapsedPx, peekPx)
    val sheetTop = remember { Animatable(mediumPx) }
    val statusBar = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    // Отступы считаем от ОСЕВШЕГО положения, а не от живого: живое значение,
    // прочитанное в композиции, рекомпозит весь экран на каждый кадр жеста.
    // Само положение применяется в фазе разметки (`offset`-лямбды).
    var settledTop by remember { mutableStateOf(mediumPx) }
    val settledTopDp = with(density) { settledTop.toDp() }
    fun settle(target: Float) {
        settledTop = target
        scope.launch { sheetTop.animateTo(target, tween(350, easing = AyantMotion.EnterEasing)) }
    }
    val dragState = rememberDraggableState { delta ->
        scope.launch { sheetTop.snapTo((sheetTop.value + delta).coerceIn(expandedPx, peekPx)) }
    }
    /** Отпустили лист: прилипаем к ближайшей точке с учётом броска (0.15 с проекции). */
    fun snapToNearest(velocity: Float) {
        val target = (sheetTop.value + velocity * 0.15f).coerceIn(expandedPx, peekPx)
        settle(stops.minByOrNull { abs(it - target) } ?: mediumPx)
    }

    // Как в UberEats: выбор пина отдаёт экран карте, а лист сжимается до
    // карточки этого заведения.
    fun selectPin(v: Venue) { previewVenue = v; settle(previewPx) }
    fun tapEmpty() {
        previewVenue = null
        if (settledTop == previewPx) settle(mediumPx)
    }

    val hasLocationPermission = remember(context) {
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    }

    Box(Modifier.fillMaxSize().background(c.canvas)) {
        // ── Карта ФИКСИРОВАННОЙ высоты, никогда не переразмечается.
        Box(Modifier.fillMaxWidth().height(MAP_HEIGHT)) {
            val cam = rememberCameraPositionState {
                position = CameraPosition.fromLatLngZoom(
                    LatLng(app.selectedCity.latitude, app.selectedCity.longitude), 12f,
                )
            }
            var mapLoaded by remember { mutableStateOf(false) }
            // Подписи пинов — как на iOS: капсула с выгодой, а не иконка.
            val items = remember(mapVenues, feedState) {
                pinItems(context, mapVenues, feedState.loadedCatalog.deals)
            }
            // Вписать все пины в кадр — как `fitAll` на iOS.
            val pinIDs = mapVenues.map { it.id }
            LaunchedEffect(mapLoaded, pinIDs) {
                if (!mapLoaded || mapVenues.isEmpty()) return@LaunchedEffect
                val bounds = LatLngBounds.builder().apply {
                    mapVenues.forEach { include(LatLng(it.latitude, it.longitude)) }
                }.build()
                runCatching { cam.animate(CameraUpdateFactory.newLatLngBounds(bounds, 120)) }
            }
            GoogleMap(
                modifier = Modifier.fillMaxWidth().height(MAP_HEIGHT),
                cameraPositionState = cam,
                properties = MapProperties(isMyLocationEnabled = hasLocationPermission),
                // Штатная кнопка «моё местоположение» держится за верх карты,
                // под строкой фильтров — как `MKUserTrackingButton` на iOS.
                uiSettings = MapUiSettings(
                    myLocationButtonEnabled = hasLocationPermission,
                    zoomControlsEnabled = false,
                    mapToolbarEnabled = false,
                ),
                contentPadding = PaddingValues(top = statusBar + 116.dp),
                onMapLoaded = { mapLoaded = true },
                onMapClick = { tapEmpty() },
            ) {
                Clustering(
                    items = items,
                    onClusterItemClick = { selectPin(it.venue); true },
                    onClusterClick = { cluster ->
                        val vs = cluster.items.map { it.venue }
                        if (vs.size == 1) selectPin(vs[0])
                        else if (vs.isNotEmpty()) { previewVenue = null; clusterVenues = vs }
                        true
                    },
                    clusterItemContent = { item -> MapPinCapsule(item.label, item.style) },
                )
            }
        }

        // ── Лист результатов. Всегда во всю высоту экрана и просто съезжает
        // вниз: анимируется только смещение, поэтому жест остаётся плавным.
        // На весь экран скругление показывало бы карту в углах — убираем.
        Box(
            Modifier
                .fillMaxSize()
                // −24 — нахлёст листа на карту из макета.
                .offset { IntOffset(0, (sheetTop.value - overlapPx).roundToInt().coerceAtLeast(0)) }
                .clip(
                    RoundedCornerShape(
                        topStart = if (settledTop == 0f) 0.dp else AyantRadius.sheet,
                        topEnd = if (settledTop == 0f) 0.dp else AyantRadius.sheet,
                    ),
                )
                .background(c.canvas),
        ) {
            Column(Modifier.fillMaxSize()) {
                // Ручка. Зона захвата — вся ширина и ~40dp по высоте: в саму
                // полоску 4dp пальцем не попасть. По макету: 18 сверху и 16 под
                // полоской; на весь экран лист подъезжает под плавающую панель
                // (поиск 48 + чипы 38 + зазоры) — освобождаем ей место.
                val handleLabel = stringResource(R.string.search_sheet_handle)
                Box(
                    Modifier
                        .fillMaxWidth()
                        .semantics { contentDescription = handleLabel }
                        .draggable(
                            state = dragState,
                            orientation = Orientation.Vertical,
                            onDragStopped = { velocity -> snapToNearest(velocity) },
                        )
                        .padding(
                            top = if (settledTopDp < 130.dp) statusBar + 118.dp else 18.dp,
                            bottom = 16.dp,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier
                            .width(38.dp)
                            .height(4.dp)
                            .clip(CircleShape)
                            .background(Color(0xFFDDD7CE)),
                    )
                }

                val preview = previewVenue
                if (preview != null) {
                    // Режим превью: пин выбран — одна карточка и кнопка возврата к списку.
                    Column(
                        Modifier.fillMaxWidth().padding(horizontal = AyantMetrics.screenPadding),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        VenueResultCard(
                            venue = preview,
                            distanceKm = location.distanceKm(preview.latitude, preview.longitude),
                            deal = bestDeal(preview),
                            rating = feedState.aggregate(preview),
                            compact = true,
                            isSaved = preview.id in profileState.savedVenueIDs,
                            onSave = {
                                if (app.isGuest) guestMessage = GuestGate.SAVE_VENUE else app.toggleSave(preview)
                            },
                            onOpen = { onVenue(preview.id) },
                        )
                        val interaction = remember { MutableInteractionSource() }
                        Row(
                            Modifier
                                .clickable(interaction, null, role = Role.Button) { previewVenue = null; settle(mediumPx) }
                                .ayantPressScale(interaction, 0.96f)
                                .padding(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Icon(Icons.AutoMirrored.Filled.List, null, tint = c.accentText, modifier = Modifier.size(16.dp))
                            Text(
                                stringResource(R.string.search_show_list),
                                fontSize = 14.sp, fontWeight = FontWeight.Bold, color = c.accentText,
                            )
                        }
                    }
                } else {
                    Text(
                        pluralStringResource(R.plurals.search_found_venues, results.size, results.size),
                        fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold, color = c.inkSoft,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = AyantMetrics.screenPadding),
                    )

                    if (results.isEmpty()) {
                        AyantUnavailableView(
                            icon = Icons.Filled.Search,
                            title = stringResource(R.string.search_empty_title),
                            body = stringResource(R.string.search_empty_body),
                        )
                    } else {
                        var refreshing by remember { mutableStateOf(false) }
                        PullToRefreshBox(
                            isRefreshing = refreshing,
                            onRefresh = { scope.launch { refreshing = true; app.refresh(); refreshing = false } },
                            modifier = Modifier.fillMaxSize(),
                        ) {
                            LazyColumn(
                                Modifier.fillMaxSize(),
                                // Лист высотой во весь экран съехал вниз на `sheetTop`, и
                                // ровно столько его хвоста ушло за нижний край —
                                // компенсируем, иначе до последней карточки не долистать.
                                contentPadding = PaddingValues(
                                    start = AyantMetrics.screenPadding,
                                    end = AyantMetrics.screenPadding,
                                    top = 12.dp,
                                    bottom = 20.dp + settledTopDp,
                                ),
                                verticalArrangement = Arrangement.spacedBy(16.dp),
                            ) {
                                itemsIndexed(results, key = { _, v -> v.id }) { index, v ->
                                    VenueResultCard(
                                        venue = v,
                                        distanceKm = location.distanceKm(v.latitude, v.longitude),
                                        deal = bestDeal(v),
                                        rating = feedState.aggregate(v),
                                        isSaved = v.id in profileState.savedVenueIDs,
                                        onSave = {
                                            if (app.isGuest) guestMessage = GuestGate.SAVE_VENUE else app.toggleSave(v)
                                        },
                                        onOpen = { onVenue(v.id) },
                                        modifier = Modifier.ayantRise(
                                            index = index, key = v.id,
                                            durationMs = AyantTiming.DEAL_ROW_RISE_MS,
                                            staggerMs = AyantTiming.DEAL_ROW_STAGGER_MS,
                                        ),
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Поиск + фильтры ОДНИМ блоком поверх карты: в UberEats строка
        // фильтров закреплена под поиском и видна всегда; повторяем это.
        Column(
            Modifier.statusBarsPadding().padding(top = 14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            SearchBar(
                query = query,
                onQuery = { query = it },
                modifier = Modifier.padding(horizontal = 18.dp),
            )
            FilterBar(
                category = category, onCategory = { category = it },
                sort = sort, onSort = { sort = it },
                openNow = openNow, onOpenNow = { openNow = !openNow },
                withDeals = withDeals, onWithDeals = { withDeals = !withDeals },
                pointsOnly = pointsOnly, onPointsOnly = { pointsOnly = !pointsOnly },
                rating4 = minRating >= 4, onRating4 = { minRating = if (minRating >= 4) 0 else 4 },
                nearby = maxDistance != null, onNearby = { maxDistance = if (maxDistance == null) 1.0 else null },
                anyFilterOn = anyFilterOn,
                onAllFilters = { showFilters = true },
                onReset = { resetFilters() },
            )
        }

        // ── «Показать ещё N» — тёмная пилюля над картой, пока часть подходящих
        // заведений не нарисована.
        AnimatedVisibility(
            visible = previewVenue == null && mapVenues.size < matchingVenues.size && settledTop > mediumPx,
            enter = fadeIn() + slideInVertically { -it / 2 },
            exit = fadeOut() + slideOutVertically { -it / 2 },
            modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 116.dp),
        ) {
            val interaction = remember { MutableInteractionSource() }
            Text(
                stringResource(
                    R.string.search_load_more_pins,
                    minOf(PIN_PAGE_SIZE, matchingVenues.size - mapVenues.size),
                ),
                fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Color.White,
                modifier = Modifier
                    .ayantShadow(AyantShadow.Elevated, CircleShape)
                    .clip(CircleShape)
                    .background(c.ink.copy(alpha = 0.92f))
                    .clickable(interaction, null, role = Role.Button) { pinBudget += PIN_PAGE_SIZE }
                    .ayantPressScale(interaction, 0.94f)
                    .padding(horizontal = 16.dp, vertical = 10.dp),
            )
        }
    }

    // ── Заведения одного кластера — списком.
    clusterVenues?.let { vs ->
        ModalBottomSheet(
            onDismissRequest = { clusterVenues = null },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false),
            containerColor = c.canvas,
        ) {
            Column(Modifier.fillMaxWidth().padding(bottom = 28.dp)) {
                Text(
                    stringResource(R.string.search_cluster_title),
                    fontSize = 17.sp, fontWeight = FontWeight.Bold, color = c.ink, textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth().padding(bottom = 8.dp),
                )
                LazyColumn(contentPadding = PaddingValues(horizontal = AyantMetrics.screenPadding)) {
                    items(vs, key = { it.id }) { v ->
                        val agg = feedState.aggregate(v)
                        VenueCompactRow(
                            venue = v,
                            distanceKm = location.distanceKm(v.latitude, v.longitude),
                            rating = agg.first, ratingCount = agg.second,
                            onClick = { clusterVenues = null; onVenue(v.id) },
                            modifier = Modifier.padding(vertical = 4.dp),
                        )
                    }
                }
            }
        }
    }

    // ── Полный набор фильтров.
    if (showFilters) {
        ModalBottomSheet(
            onDismissRequest = { showFilters = false },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false),
            containerColor = c.canvas,
        ) {
            FilterSheet(
                minRating = minRating, onRating = { minRating = it },
                maxDistance = maxDistance, onDistance = { maxDistance = it },
                category = category, onCategory = { category = it },
                anyFilterOn = anyFilterOn,
                onReset = { resetFilters() },
                onDone = { showFilters = false },
            )
        }
    }

    guestMessage?.let { message ->
        if (session != null) GuestAlert(session, message) { guestMessage = null } else guestMessage = null
    }
}

private data class SearchIndex(
    val dealsByVenue: Map<String, List<Deal>>,
    val reviewsByVenue: Map<String, List<Review>>,
)

private data class SearchResults(
    /** Всё, что прошло фильтры-чипы, — из него берём следующую порцию пинов. */
    val matching: List<Venue>,
    /** Для карты: без текстового поиска, ограничено бюджетом пинов. */
    val mapVenues: List<Venue>,
    val results: List<Venue>,
)

/**
 * Поле поиска — во всю ширину. Акцентной кнопки рядом больше нет: она забирала
 * четверть строки, а её содержимое (полный набор фильтров) теперь last-чипом в
 * строке ниже — там же, где все остальные.
 */
@Composable
private fun SearchBar(
    query: String,
    onQuery: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    val placeholder = Color(0xFF9A9188)
    val shape = RoundedCornerShape(18.dp)
    Row(
        modifier
            .fillMaxWidth()
            .ayantShadow(AyantShadow.Elevated, shape)
            .clip(shape)
            // Почти непрозрачная подложка вместо живого размытия: под полем
            // едет карта, и размытие пересчитывалось бы на каждый кадр.
            .background(c.surface.copy(alpha = 0.94f))
            .padding(horizontal = 16.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Icons.Filled.Search, null, tint = placeholder, modifier = Modifier.size(16.dp))
        Box(Modifier.weight(1f)) {
            if (query.isEmpty()) {
                Text(
                    stringResource(R.string.search_hint),
                    fontSize = 14.5.sp, fontWeight = FontWeight.Medium, color = placeholder, maxLines = 1,
                )
            }
            BasicTextField(
                value = query,
                onValueChange = onQuery,
                singleLine = true,
                textStyle = TextStyle(fontSize = 14.5.sp, fontWeight = FontWeight.Medium, color = c.ink),
                cursorBrush = SolidColor(c.accent),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                // Продуктовой аналитики на Android пока нет (на iOS — `AnalyticsLog.search`).
                keyboardActions = KeyboardActions(onSearch = {}),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        if (query.isNotEmpty()) {
            Icon(
                Icons.Filled.Cancel, stringResource(R.string.all_venues_clear_search),
                tint = placeholder,
                modifier = Modifier.size(16.dp).clickable(role = Role.Button) { onQuery("") },
            )
        }
    }
}

/**
 * Строка фильтров: сначала «типизированные» чипы с меню (категория,
 * сортировка), затем переключатели, «Все фильтры» и «Сбросить». Меню вместо
 * отдельного экрана — выбор в один тап, как «Cuisine ▾» у UberEats.
 */
@Composable
private fun FilterBar(
    category: VenueCategory?, onCategory: (VenueCategory?) -> Unit,
    sort: SearchSort, onSort: (SearchSort) -> Unit,
    openNow: Boolean, onOpenNow: () -> Unit,
    withDeals: Boolean, onWithDeals: () -> Unit,
    pointsOnly: Boolean, onPointsOnly: () -> Unit,
    rating4: Boolean, onRating4: () -> Unit,
    nearby: Boolean, onNearby: () -> Unit,
    anyFilterOn: Boolean,
    onAllFilters: () -> Unit,
    onReset: () -> Unit,
) {
    val c = AyantTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = 18.dp, vertical = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Чип-меню категории: заголовок показывает выбранное, а не «Категория».
        MenuChip(
            title = category?.localizedName() ?: stringResource(R.string.search_chip_category),
            isOn = category != null,
        ) { close ->
            DropdownMenuItem(
                text = { Text(stringResource(R.string.filter_category_all)) },
                onClick = { onCategory(null); close() },
            )
            VenueCategory.all.forEach { cat ->
                DropdownMenuItem(text = { Text(cat.localizedName()) }, onClick = { onCategory(cat); close() })
            }
        }
        MenuChip(title = stringResource(sort.chipRes), isOn = sort != SearchSort.BEST) { close ->
            SearchSort.entries.forEach { option ->
                DropdownMenuItem(text = { Text(stringResource(option.titleRes)) }, onClick = { onSort(option); close() })
            }
        }
        QuickChip(stringResource(R.string.filter_open), openNow, onOpenNow)
        QuickChip(stringResource(R.string.search_chip_deals), withDeals, onWithDeals)
        QuickChip(stringResource(R.string.search_chip_points), pointsOnly, onPointsOnly)
        QuickChip(stringResource(R.string.search_chip_rating4), rating4, onRating4)
        QuickChip(stringResource(R.string.search_chip_nearby), nearby, onNearby)

        val allInteraction = remember { MutableInteractionSource() }
        Row(
            Modifier
                .clip(CircleShape)
                .background(c.surface.copy(alpha = 0.94f))
                .border(0.5.dp, c.hairline, CircleShape)
                .clickable(allInteraction, null, role = Role.Button, onClick = onAllFilters)
                .ayantPressScale(allInteraction, 0.93f)
                .padding(horizontal = 15.dp, vertical = 9.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Icon(Icons.Filled.FilterList, null, tint = c.ink, modifier = Modifier.size(12.dp))
            Text(stringResource(R.string.search_all_filters), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = c.ink, maxLines = 1)
        }

        if (anyFilterOn) {
            val resetInteraction = remember { MutableInteractionSource() }
            Row(
                Modifier
                    .clip(CircleShape)
                    .background(c.surface.copy(alpha = 0.94f))
                    .clickable(resetInteraction, null, role = Role.Button, onClick = onReset)
                    .ayantPressScale(resetInteraction, 0.93f)
                    .padding(horizontal = 14.dp, vertical = 9.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                Icon(Icons.Filled.Close, null, tint = c.inkSoft, modifier = Modifier.size(12.dp))
                Text(stringResource(R.string.action_reset), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = c.inkSoft, maxLines = 1)
            }
        }
    }
}

/** Чип с выпадающим меню («Категория ▾», «Лучшие ▾»). Зеркалит `menuChipLabel` + `Menu`. */
@Composable
private fun MenuChip(
    title: String,
    isOn: Boolean,
    items: @Composable (close: () -> Unit) -> Unit,
) {
    val c = AyantTheme.colors
    var expanded by remember { mutableStateOf(false) }
    val interaction = remember { MutableInteractionSource() }
    Box {
        Row(
            Modifier
                .clip(CircleShape)
                .then(
                    if (isOn) Modifier.background(c.accentGradient)
                    else Modifier.background(c.surface.copy(alpha = 0.94f)).border(0.5.dp, c.hairline, CircleShape)
                )
                .clickable(interaction, null, role = Role.DropdownList) { expanded = true }
                .ayantPressScale(interaction, 0.93f)
                .padding(horizontal = 15.dp, vertical = 9.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Text(
                title, fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = 1,
                color = if (isOn) Color.White else c.ink,
            )
            Icon(
                Icons.Filled.KeyboardArrowDown, null,
                tint = if (isOn) Color.White else c.ink, modifier = Modifier.size(12.dp),
            )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            items { expanded = false }
        }
    }
}

/** Быстрый чип-переключатель. Зеркалит `quickChip`. */
@Composable
private fun QuickChip(title: String, isOn: Boolean, onClick: () -> Unit) {
    val c = AyantTheme.colors
    val interaction = remember { MutableInteractionSource() }
    Box(
        Modifier
            .clip(CircleShape)
            .then(
                if (isOn) Modifier.background(c.accentGradient)
                else Modifier.background(c.surface).border(0.5.dp, c.hairline, CircleShape)
            )
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .ayantPressScale(interaction, scale = 0.93f)
            .padding(horizontal = 15.dp, vertical = 9.dp),
    ) {
        Text(
            title,
            fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = 1,
            color = if (isOn) Color.White else c.inkSoft,
        )
    }
}

/**
 * Фото-карточка выдачи. Зеркалит `VenueResultCard`: крупный снимок, лента
 * акции поверх него, затем имя и одна строка фактов — рейтинг, «открыто»,
 * расстояние. Прежняя строка (иконка 64×64 слева) вмещала больше пунктов, но по
 * ней невозможно выбрать заведение: еду и интерьер в 64 точках не видно.
 */
@Composable
fun VenueResultCard(
    venue: Venue,
    distanceKm: Double?,
    deal: Deal?,
    rating: Pair<Double, Int>,
    isSaved: Boolean,
    onSave: () -> Unit,
    onOpen: () -> Unit,
    modifier: Modifier = Modifier,
    /** Превью выбранного пина: та же карточка, но ниже — под ней ещё кнопка возврата к списку. */
    compact: Boolean = false,
) {
    val c = AyantTheme.colors
    val interaction = remember { MutableInteractionSource() }
    val shape = RoundedCornerShape(AyantRadius.card)
    Column(
        modifier
            .fillMaxWidth()
            .clickable(interaction, null, onClick = onOpen)
            .ayantPressScale(interaction, 0.98f),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(Modifier.fillMaxWidth().height(if (compact) 132.dp else 168.dp).clip(shape)) {
            VenuePhoto(venue.imageURL, venue.gradientColors, Modifier.fillMaxSize())
            // Лента акции: скидка важнее типа акции, тип — важнее «спец дня».
            val ribbon: String? = when {
                deal?.effectiveDiscountPercent != null -> "−${deal.effectiveDiscountPercent}%"
                deal != null -> deal.type.localizedTitle()
                venue.hasTodaySpecial -> stringResource(R.string.today)
                else -> null
            }
            if (ribbon != null) {
                Text(
                    ribbon,
                    fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color.White,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .padding(10.dp)
                        .clip(CircleShape)
                        .background(c.accentGradient)
                        .padding(horizontal = 10.dp, vertical = 6.dp),
                )
            }
            val saveInteraction = remember { MutableInteractionSource() }
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .padding(10.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.35f))
                    .clickable(saveInteraction, null, role = Role.Button, onClick = onSave)
                    .padding(9.dp),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (isSaved) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
                    contentDescription = stringResource(if (isSaved) R.string.action_unsave else R.string.action_save),
                    tint = Color.White, modifier = Modifier.size(14.dp),
                )
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    venue.name,
                    fontSize = 17.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.3).sp, color = c.ink,
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                if (venue.isVerified) {
                    Icon(Icons.Filled.Verified, null, tint = c.accentText, modifier = Modifier.size(13.dp))
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(Icons.Filled.Star, null, tint = Color(0xFFFF9500), modifier = Modifier.size(11.dp))
                    Text(rating.first.ratingText(), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = c.ink)
                    Text("(${rating.second})", fontSize = 12.sp, color = c.inkSoft)
                }
                Dot()
                Text(venue.category.localizedName(), fontSize = 13.sp, color = c.inkSoft, maxLines = 1)
                if (venue.isOpenNow) {
                    Dot()
                    Text(stringResource(R.string.status_open), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = c.open)
                }
                if (distanceKm != null) {
                    Dot()
                    Text(distanceKm.distanceText(), fontSize = 13.sp, color = c.inkSoft, maxLines = 1)
                }
            }
        }
    }
}

@Composable
private fun Dot() {
    Text("·", fontSize = 13.sp, color = AyantTheme.colors.inkSoft)
}

/** Полный набор фильтров — рейтинг, расстояние, категория. Зеркалит `filterSheet`. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FilterSheet(
    minRating: Int, onRating: (Int) -> Unit,
    maxDistance: Double?, onDistance: (Double?) -> Unit,
    category: VenueCategory?, onCategory: (VenueCategory?) -> Unit,
    anyFilterOn: Boolean,
    onReset: () -> Unit,
    onDone: () -> Unit,
) {
    val c = AyantTheme.colors
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = AyantMetrics.screenPadding)
            .padding(bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onReset, enabled = anyFilterOn) {
                Text(stringResource(R.string.action_reset), color = if (anyFilterOn) c.accentText else c.inkSoft)
            }
            Spacer(Modifier.weight(1f))
            Text(stringResource(R.string.filter_title), fontSize = 17.sp, fontWeight = FontWeight.Bold, color = c.ink)
            Spacer(Modifier.weight(1f))
            TextButton(onClick = onDone) { Text(stringResource(R.string.action_done), color = c.accentText) }
        }

        FilterGroup(stringResource(R.string.filter_rating)) {
            QuickChip(stringResource(R.string.filter_any_m), minRating == 0) { onRating(0) }
            QuickChip(stringResource(R.string.filter_rating_3), minRating == 3) { onRating(3) }
            QuickChip(stringResource(R.string.filter_rating_4), minRating == 4) { onRating(4) }
        }
        FilterGroup(stringResource(R.string.filter_distance)) {
            QuickChip(stringResource(R.string.filter_any_n), maxDistance == null) { onDistance(null) }
            QuickChip(stringResource(R.string.filter_dist_500), maxDistance == 0.5) { onDistance(0.5) }
            QuickChip(stringResource(R.string.filter_dist_1), maxDistance == 1.0) { onDistance(1.0) }
            QuickChip(stringResource(R.string.filter_dist_3), maxDistance == 3.0) { onDistance(3.0) }
        }
        // Категории — сеткой, а не в одну строку: их шесть плюс «Все».
        FilterGroup(stringResource(R.string.filter_category)) {
            QuickChip(stringResource(R.string.filter_all), category == null) { onCategory(null) }
            VenueCategory.all.forEach { cat ->
                QuickChip(cat.localizedName(), category == cat) { onCategory(if (category == cat) null else cat) }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FilterGroup(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            title.uppercase(),
            fontSize = 10.5.sp, fontWeight = FontWeight.Black, letterSpacing = 1.1.sp,
            color = Color(0xFF9A9188),
        )
        FlowRow(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) { content() }
    }
}

/** Оформление капсулы пина. Зеркалит `VenueAnnotation.Style`. */
private enum class PinStyle { FEATURED, DARK, PLAIN }

/** ClusterItem wrapper for a venue pin. */
private class MapVenueItem(
    val venue: Venue,
    val label: String,
    val style: PinStyle,
) : ClusterItem {
    override fun getPosition() = LatLng(venue.latitude, venue.longitude)
    override fun getTitle() = venue.name
    override fun getSnippet() = "${venue.category.localizedName(AppLanguage.context)} · ${venue.district}"
    override fun getZIndex() = 0f
}

/**
 * Подписи пинов по макету. Зеркалит `VenuesMapView.annotations(for:deals:)`:
 * лучшая скидка → `−40%`; иначе тип акции → `ПРОМО`; иначе спецпредложение дня
 * → `Новое`; иначе рейтинг. Самая большая скидка получает акцентный градиент.
 */
private fun pinItems(context: android.content.Context, venues: List<Venue>, deals: List<Deal>): List<MapVenueItem> {
    val byVenue = deals.filter { it.isActive }.groupBy { it.venueID }
    val best = venues
        .mapNotNull { v -> byVenue[v.id]?.mapNotNull { it.effectiveDiscountPercent }?.maxOrNull()?.let { v.id to it } }
        .maxByOrNull { it.second }?.first

    return venues.map { v ->
        val venueDeals = byVenue[v.id].orEmpty()
        val percent = venueDeals.mapNotNull { it.effectiveDiscountPercent }.maxOrNull()
        when {
            percent != null -> MapVenueItem(
                v, "−$percent%", if (v.id == best) PinStyle.FEATURED else PinStyle.PLAIN,
            )
            venueDeals.isNotEmpty() -> MapVenueItem(v, venueDeals.first().type.badgeLabel(context), PinStyle.PLAIN)
            v.hasTodaySpecial -> MapVenueItem(v, context.getString(R.string.map_pin_new), PinStyle.DARK)
            else -> MapVenueItem(v, "★ ${v.rating.ratingText()}", PinStyle.PLAIN)
        }
    }
}

/**
 * Капсула пина: `padding 7×12`, радиус 999, 12sp/800, тень.
 *
 * Без «парения», в отличие от iOS: маркеры Google Maps — растровые, и кадр
 * анимации означал бы перерисовку битмапа на каждый маркер. На iOS то же
 * движение уезжает в Core Animation и не стоит ни кадра, поэтому там оно есть.
 */
@Composable
private fun MapPinCapsule(label: String, style: PinStyle) {
    val c = AyantTheme.colors
    val background: Modifier = when (style) {
        PinStyle.FEATURED -> Modifier.background(c.accentGradient)
        PinStyle.DARK -> Modifier.background(c.ink)
        PinStyle.PLAIN -> Modifier.background(Color.White)
    }
    Box(
        Modifier
            .clip(CircleShape)
            .then(background)
            .padding(horizontal = 12.dp, vertical = 7.dp),
    ) {
        Text(
            label,
            fontSize = 12.sp, fontWeight = FontWeight.Black, letterSpacing = (-0.2).sp,
            maxLines = 1,
            color = if (style == PinStyle.PLAIN) c.ink else Color.White,
        )
    }
}

@Suppress("unused")
private val Dp.px: Float @Composable get() = with(LocalDensity.current) { toPx() }
