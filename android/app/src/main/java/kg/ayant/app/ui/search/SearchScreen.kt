package kg.ayant.app.ui.search

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.layout.layout
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.clustering.ClusterItem
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapsComposeExperimentalApi
import com.google.maps.android.compose.clustering.Clustering
import com.google.maps.android.compose.rememberCameraPositionState
import kg.ayant.app.R
import kg.ayant.app.core.distanceText
import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenueCategory
import kg.ayant.app.location.LocationManager
import kg.ayant.app.ui.components.StarRating
import kg.ayant.app.ui.home.badgeLabel
import kg.ayant.app.ui.components.VenuePhoto
import kg.ayant.app.ui.theme.AyantMetrics
import kg.ayant.app.ui.theme.AyantMotion
import kg.ayant.app.ui.theme.AyantRadius
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.AyantTiming
import kg.ayant.app.ui.theme.ayantPressScale
import kg.ayant.app.ui.theme.ayantRise
import kg.ayant.app.ui.theme.gradientColors
import kg.ayant.app.ui.vm.AppViewModel
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.roundToInt
import kg.ayant.app.domain.pointsActive

/**
 * Поиск после редизайна (SCREENS.md G8). Зеркалит `SearchView.swift`.
 *
 * Карта больше не прячется за переключателем «список / карта»: она всегда
 * сверху, а лист результатов ездит по ней между тремя положениями.
 *
 * ВАЖНО про производительность и попадание по «ручке»: карта НИКОГДА не меняет
 * свой размер. `GoogleMap` всегда высотой [MAP_FIXED], а видимую часть задаёт
 * подрезающий контейнер. Если менять высоту самой карты, `MapView`
 * переразмечается на каждый кадр жеста — и перетаскивание заметно лагает.
 */

private val MAP_FIXED = 520.dp        // реальная высота карты, не меняется
private val STOP_COLLAPSED = 520.dp   // карта крупно, лист снизу
private val STOP_MEDIUM = 270.dp      // по умолчанию, как в макете
private val STOP_EXPANDED = 0.dp      // лист на весь экран

@OptIn(ExperimentalMaterial3Api::class, MapsComposeExperimentalApi::class)
@Composable
fun SearchScreen(
    app: AppViewModel,
    location: LocationManager,
    onVenue: (String) -> Unit,
) {
    val c = AyantTheme.colors
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()

    var query by remember { mutableStateOf("") }
    // Подписка на владельцев данных: адаптеры `app.*` — обычные геттеры поверх
    // `state.value` ленты и профиля, поэтому без этой строки экран не
    // перерисуется ни после загрузки каталога, ни после изменения сохранённого.
    val feedState by app.feedState.collectAsState()

    var openNow by remember { mutableStateOf(false) }
    var withDeals by remember { mutableStateOf(false) }
    var pointsOnly by remember { mutableStateOf(false) }
    var minRating by remember { mutableStateOf(0) }
    var maxDistance by remember { mutableStateOf<Double?>(null) }
    var category by remember { mutableStateOf<VenueCategory?>(null) }
    var showFilters by remember { mutableStateOf(false) }
    var preview by remember { mutableStateOf<Venue?>(null) }

    fun matchesQuery(v: Venue): Boolean {
        if (query.isBlank()) return true
        val q = query.trim()
        if (v.name.contains(q, true) || v.category.rawValue.contains(q, true) ||
            v.district.contains(q, true) || v.address.contains(q, true)
        ) return true
        if (v.items.any { it.name.contains(q, true) }) return true
        if (app.deals(forVenue = v).any { it.title.contains(q, true) || it.details.contains(q, true) }) return true
        if (feedState.reviews(forVenue = v).any { it.text.contains(q, true) || (it.itemName?.contains(q, true) == true) }) return true
        return false
    }

    fun matchesFilters(v: Venue): Boolean {
        if (openNow && !v.isOpenNow) return false
        if (withDeals && app.deals(forVenue = v).isEmpty()) return false
        if (pointsOnly && !v.pointsActive) return false
        if (category != null && v.category != category) return false
        if (minRating > 0 && feedState.aggregate(v).first < minRating) return false
        maxDistance?.let { md ->
            val d = location.distanceKm(v.latitude, v.longitude) ?: return false
            if (d > md) return false
        }
        return true
    }

    val anyFilterOn = openNow || withDeals || pointsOnly || minRating > 0 || maxDistance != null || category != null

    // Выдача КЭШИРУЕТСЯ, а не считается на каждую рекомпозицию.
    //
    // `rankedVenues()` на каждый вызов пересобирает снимок каталога с агрегатами
    // по всем отзывам, а `matchesQuery` дёргает `deals(forVenue)`/`reviews` на
    // каждое заведение. Во время перетаскивания листа экран рекомпозится каждый
    // кадр — и весь этот перебор шёл 60 раз в секунду. Отсюда и лаг.
    val filterKey = listOf(
        query, openNow, withDeals, pointsOnly, minRating, maxDistance, category,
        feedState.loadedCatalog.venues.size, feedState.loadedCatalog.deals.size,
        feedState.reviews.size, location.lastLat, location.lastLng,
    )
    // `rankedVenues()` зовём ОДИН раз: список для карты — это те же заведения
    // без текстового фильтра, а выдача — его подмножество.
    val mapVenues = remember(filterKey) { app.rankedVenues().filter { matchesFilters(it) } }
    val results = remember(filterKey) { mapVenues.filter { matchesQuery(it) } }

    // Положение листа в пикселях. Animatable, а не обычный state: снапинг после
    // отпускания — это анимация, а сам жест должен идти без неё.
    val collapsedPx = with(density) { STOP_COLLAPSED.toPx() }
    val mediumPx = with(density) { STOP_MEDIUM.toPx() }
    val expandedPx = with(density) { STOP_EXPANDED.toPx() }
    val overlapPx = with(density) { 24.dp.toPx() }
    val sheetTop = remember { Animatable(mediumPx) }
    val statusBar = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    // Отступы считаем от ОСЕВШЕГО положения, а не от живого: живое значение,
    // прочитанное в композиции, рекомпозит весь экран на каждый кадр жеста.
    // Само положение применяется в фазе разметки (`layout`/`offset`-лямбды).
    var settledTop by remember { mutableStateOf(mediumPx) }
    val settledTopDp = with(density) { settledTop.toDp() }
    val dragState = rememberDraggableState { delta ->
        scope.launch { sheetTop.snapTo((sheetTop.value + delta).coerceIn(expandedPx, collapsedPx)) }
    }
    fun snapToNearest(velocity: Float) {
        // Проекция броска — как `predictedEndTranslation` на iOS.
        val target = (sheetTop.value + velocity * 0.15f).coerceIn(expandedPx, collapsedPx)
        val nearest = listOf(expandedPx, mediumPx, collapsedPx).minByOrNull { abs(it - target) } ?: mediumPx
        settledTop = nearest
        scope.launch {
            sheetTop.animateTo(nearest, tween(350, easing = AyantMotion.EnterEasing))
        }
    }

    Box(Modifier.fillMaxSize().background(c.canvas)) {
        // ── Карта. Контейнер ростом с видимую часть, карта внутри — фиксированная.
        // Карта ФИКСИРОВАННОЙ высоты и НИКОГДА не переразмечается: ниже её
        // просто накрывает непрозрачный лист. Пока высоту контейнера меняли на
        // каждый кадр жеста, вместе с ней переразмечался `MapView` — отсюда лаг.
        Box(Modifier.fillMaxWidth().height(MAP_FIXED)) {
            val cam = rememberCameraPositionState {
                position = CameraPosition.fromLatLngZoom(
                    LatLng(app.selectedCity.latitude, app.selectedCity.longitude), 12f,
                )
            }
            // Подписи пинов — как на iOS: капсула с выгодой, а не иконка.
            val items = remember(mapVenues, feedState) {
                pinItems(mapVenues, feedState.loadedCatalog.deals)
            }
            GoogleMap(
                modifier = Modifier.fillMaxWidth().height(MAP_FIXED),
                cameraPositionState = cam,
                onMapClick = { preview = null },
            ) {
                Clustering(
                    items = items,
                    onClusterItemClick = { preview = it.venue; false },
                    clusterItemContent = { item -> MapPinCapsule(item.label, item.style) },
                )
            }
        }

        // Канвас-скрим по макету — один градиент на всю ВИДИМУЮ часть карты
        // (0.55 сверху → прозрачно на 26% → 0.9 снизу). Высота берётся в фазе
        // разметки: это дешёвый градиент, а не AndroidView.
        Box(
            Modifier
                .fillMaxWidth()
                .layout { measurable, constraints ->
                    val h = sheetTop.value.roundToInt().coerceAtLeast(0)
                    // Именно min И max: у пустого Box нет собственной высоты, и
                    // с одним лишь maxHeight градиент рисовался бы в нулевой
                    // полосе, то есть никак.
                    val placeable = measurable.measure(constraints.copy(minHeight = h, maxHeight = h))
                    layout(placeable.width, h) { placeable.place(0, 0) }
                }
                .background(
                    Brush.verticalGradient(
                        0f to c.canvas.copy(alpha = 0.55f),
                        0.26f to Color.Transparent,
                        1f to c.canvas.copy(alpha = 0.9f),
                    ),
                ),
        )

        // ── Мини-карточка пина: едет над верхней кромкой листа.
        preview?.let { v ->
            MapPreviewCard(
                venue = v,
                distanceKm = location.distanceKm(v.latitude, v.longitude),
                rating = feedState.aggregate(v).first,
                ratingCount = feedState.aggregate(v).second,
                onOpen = { onVenue(v.id) },
                onClose = { preview = null },
                modifier = Modifier
                    .padding(horizontal = 16.dp)
                    .offset { IntOffset(0, (sheetTop.value - with(density) { 116.dp.toPx() }).roundToInt().coerceAtLeast(0)) },
            )
        }

        // ── Лист результатов. Всегда во всю высоту экрана и просто съезжает
        // вниз: анимируется только смещение, поэтому жест остаётся плавным.
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
                // полоску 4dp пальцем не попасть.
                Box(
                    Modifier
                        .fillMaxWidth()
                        .draggable(
                            state = dragState,
                            orientation = Orientation.Vertical,
                            onDragStopped = { velocity -> snapToNearest(velocity) },
                        )
                        // На весь экран лист подъезжает под самый верх экрана,
                        // поэтому освобождаем место под статус-бар И под
                        // плавающую строку поиска (отступ 14 + поле 48 + зазор).
                        // По макету: 18 сверху и 16 под полоской. На весь экран
                        // лист подъезжает под самый верх — тогда освобождаем
                        // место под статус-бар и плавающую строку поиска.
                        .padding(
                            top = if (settledTopDp < 130.dp) statusBar + 74.dp else 18.dp,
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

                QuickChips(
                    openNow = openNow, onOpenNow = { openNow = !openNow },
                    nearby = maxDistance != null, onNearby = { maxDistance = if (maxDistance == null) 1.0 else null },
                    pointsOnly = pointsOnly, onPointsOnly = { pointsOnly = !pointsOnly },
                    rating4 = minRating >= 4, onRating4 = { minRating = if (minRating >= 4) 0 else 4 },
                    withDeals = withDeals, onWithDeals = { withDeals = !withDeals },
                )
                Spacer(Modifier.height(16.dp))

                Text(
                    pluralStringResource(R.plurals.search_found_venues, results.size, results.size),
                    fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold, color = c.inkSoft,
                    modifier = Modifier.padding(horizontal = AyantMetrics.screenPadding),
                )

                if (results.isEmpty()) {
                    Column(
                        Modifier.fillMaxWidth().padding(top = 40.dp, start = 32.dp, end = 32.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(stringResource(R.string.search_empty_title), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink)
                        Text(stringResource(R.string.search_empty_body), fontSize = 14.sp, color = c.inkSoft)
                    }
                } else {
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
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        itemsIndexed(results, key = { _, v -> v.id }) { index, v ->
                            val agg = feedState.aggregate(v)
                            ResultRow(
                                venue = v,
                                rating = agg.first,
                                ratingCount = agg.second,
                                distanceKm = location.distanceKm(v.latitude, v.longitude),
                                onClick = { onVenue(v.id) },
                                modifier = Modifier.ayantRise(
                                    index = index,
                                    durationMs = AyantTiming.DEAL_ROW_RISE_MS,
                                    staggerMs = AyantTiming.DEAL_ROW_STAGGER_MS,
                                ),
                            )
                        }
                    }
                }
            }
        }

        // ── Плавающая строка поиска поверх всего.
        SearchBar(
            query = query,
            onQuery = { query = it },
            anyFilterOn = anyFilterOn,
            onFilters = { showFilters = true },
            modifier = Modifier.statusBarsPadding().padding(horizontal = 18.dp, vertical = 14.dp),
        )
    }

    if (showFilters) {
        val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)
        ModalBottomSheet(
            onDismissRequest = { showFilters = false },
            sheetState = sheetState,
            containerColor = c.canvas,
        ) {
            FilterSheet(
                minRating = minRating, onRating = { minRating = it },
                maxDistance = maxDistance, onDistance = { maxDistance = it },
                category = category, onCategory = { category = it },
                anyFilterOn = anyFilterOn,
                onReset = {
                    openNow = false; withDeals = false; pointsOnly = false
                    minRating = 0; maxDistance = null; category = null
                },
                onDone = { showFilters = false },
            )
        }
    }
}

@Composable
private fun SearchBar(
    query: String,
    onQuery: (String) -> Unit,
    anyFilterOn: Boolean,
    onFilters: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    val interaction = remember { MutableInteractionSource() }
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Row(
            Modifier
                .weight(1f)
                .clip(RoundedCornerShape(18.dp))
                .background(c.surface.copy(alpha = 0.94f))
                .padding(horizontal = 16.dp, vertical = 13.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.Search, null, tint = Color(0xFF9A9188), modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(10.dp))
            Box(Modifier.weight(1f)) {
                if (query.isEmpty()) {
                    Text(
                        stringResource(R.string.search_hint),
                        fontSize = 14.5.sp, color = Color(0xFF9A9188), maxLines = 1,
                    )
                }
                BasicTextField(
                    value = query,
                    onValueChange = onQuery,
                    singleLine = true,
                    textStyle = TextStyle(fontSize = 14.5.sp, fontWeight = FontWeight.Medium, color = c.ink),
                    cursorBrush = SolidColor(c.accent),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            if (query.isNotEmpty()) {
                Icon(
                    Icons.Filled.Close, stringResource(R.string.filter_reset),
                    tint = Color(0xFF9A9188),
                    modifier = Modifier.size(18.dp).clickable { onQuery("") },
                )
            }
        }
        Spacer(Modifier.width(9.dp))
        Box(
            Modifier
                .size(48.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(c.accentGradient)
                .clickable(interactionSource = interaction, indication = null, onClick = onFilters)
                .ayantPressScale(interaction, scale = 0.93f),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Tune, stringResource(R.string.filter_title), tint = Color.White, modifier = Modifier.size(20.dp))
            if (anyFilterOn) {
                Box(
                    Modifier
                        .align(Alignment.TopEnd)
                        .padding(6.dp)
                        .size(8.dp)
                        .clip(CircleShape)
                        .background(Color.White),
                )
            }
        }
    }
}

/** Быстрые чипы из макета, привязанные к реальным фильтрам. */
@Composable
private fun QuickChips(
    openNow: Boolean, onOpenNow: () -> Unit,
    nearby: Boolean, onNearby: () -> Unit,
    pointsOnly: Boolean, onPointsOnly: () -> Unit,
    rating4: Boolean, onRating4: () -> Unit,
    withDeals: Boolean, onWithDeals: () -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .padding(horizontal = AyantMetrics.screenPadding),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        QuickChip(stringResource(R.string.filter_open), openNow, onOpenNow)
        QuickChip(stringResource(R.string.search_chip_nearby), nearby, onNearby)
        QuickChip(stringResource(R.string.search_chip_points), pointsOnly, onPointsOnly)
        QuickChip(stringResource(R.string.search_chip_rating4), rating4, onRating4)
        QuickChip(stringResource(R.string.search_chip_deals), withDeals, onWithDeals)
    }
}

@Composable
private fun QuickChip(title: String, isOn: Boolean, onClick: () -> Unit) {
    val c = AyantTheme.colors
    val interaction = remember { MutableInteractionSource() }
    Box(
        Modifier
            .clip(CircleShape)
            .then(if (isOn) Modifier.background(c.accentGradient) else Modifier.background(c.surface))
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

@Composable
private fun ResultRow(
    venue: Venue,
    rating: Double,
    ratingCount: Int,
    distanceKm: Double?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    val interaction = remember { MutableInteractionSource() }
    Row(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AyantRadius.card))
            .background(c.surface)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .ayantPressScale(interaction, scale = 0.98f)
            .padding(13.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier
                .size(64.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(Brush.linearGradient(venue.gradientColors)),
            contentAlignment = Alignment.Center,
        ) {
            if (!venue.imageURL.isNullOrEmpty()) {
                VenuePhoto(venue.imageURL, venue.gradientColors, Modifier.fillMaxSize())
            } else {
                Text(venue.emoji, fontSize = 26.sp)
            }
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    venue.name,
                    fontSize = 15.sp, fontWeight = FontWeight.Bold, color = c.ink,
                    maxLines = 1,
                )
                if (venue.isOpenNow) {
                    Spacer(Modifier.width(6.dp))
                    Text(
                        stringResource(R.string.status_open),
                        fontSize = 12.sp, fontWeight = FontWeight.Bold, color = c.open,
                    )
                }
            }
            Spacer(Modifier.height(4.dp))
            Text(
                "${venue.category.rawValue} · ${venue.district}",
                fontSize = 12.5.sp, color = c.inkSoft, maxLines = 1,
            )
            Spacer(Modifier.height(7.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                StarRating(rating = rating, count = ratingCount, size = 12)
                distanceKm?.let {
                    Spacer(Modifier.width(9.dp))
                    Text(it.distanceText(), fontSize = 12.sp, color = Color(0xFF9A9188))
                }
            }
        }
    }
}

/** Полный набор фильтров — рейтинг, расстояние, категория. */
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
        FilterGroup(stringResource(R.string.filter_category)) {
            QuickChip(stringResource(R.string.filter_all), category == null) { onCategory(null) }
            VenueCategory.all.forEach { cat ->
                QuickChip(cat.rawValue, category == cat) { onCategory(if (category == cat) null else cat) }
            }
        }
    }
}

@Composable
private fun FilterGroup(title: String, content: @Composable () -> Unit) {
    val c = AyantTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            title.uppercase(),
            fontSize = 10.5.sp, fontWeight = FontWeight.Black, letterSpacing = 1.1.sp,
            color = Color(0xFF9A9188),
        )
        Row(
            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
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
    override fun getSnippet() = "${venue.category.rawValue} · ${venue.district}"
    override fun getZIndex() = 0f
}

/**
 * Подписи пинов по макету. Зеркалит `VenuesMapView.annotations(for:deals:)`:
 * лучшая скидка → `−40%`; иначе тип акции → `ПРОМО`; иначе спецпредложение дня
 * → `Новое`; иначе рейтинг. Самая большая скидка получает акцентный градиент.
 */
private fun pinItems(venues: List<Venue>, deals: List<Deal>): List<MapVenueItem> {
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
            venueDeals.isNotEmpty() -> MapVenueItem(v, venueDeals.first().type.badgeLabel(), PinStyle.PLAIN)
            v.hasTodaySpecial -> MapVenueItem(v, "Новое", PinStyle.DARK)
            else -> MapVenueItem(v, "★ %.1f".format(v.rating), PinStyle.PLAIN)
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

/** Mini card shown when a map pin is tapped. Tap to open, ✕ to dismiss. */
@Composable
private fun MapPreviewCard(
    venue: Venue,
    distanceKm: Double?,
    rating: Double,
    ratingCount: Int,
    onOpen: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(c.surface)
            .clickable(onClick = onOpen)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(venue.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = c.ink, maxLines = 1)
            Text(
                "${venue.category.rawValue} • ${venue.district}" + (distanceKm?.let { " • ${it.distanceText()}" } ?: ""),
                fontSize = 12.sp, color = c.inkSoft, maxLines = 1,
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                StarRating(rating = rating, count = ratingCount, size = 12)
                if (venue.isOpenNow) {
                    Text(
                        "  " + stringResource(R.string.status_open),
                        fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = c.open,
                    )
                }
            }
        }
        Text(
            "✕", fontSize = 18.sp, color = c.inkSoft,
            modifier = Modifier.clickable(onClick = onClose).padding(6.dp),
        )
    }
}
