package kg.ayant.app.ui.home

import androidx.activity.compose.LocalOnBackPressedDispatcherOwner
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.LocationOn
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.core.localizedName
import kg.ayant.app.core.storefrontIcon
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenueCategory
import kg.ayant.app.location.LocationManager
import kg.ayant.app.ui.components.AyantCategoryRail
import kg.ayant.app.ui.components.AyantNavBar
import kg.ayant.app.ui.components.AyantUnavailableView
import kg.ayant.app.ui.components.VenueCompactRow
import kg.ayant.app.ui.theme.AyantHairline
import kg.ayant.app.ui.theme.AyantMetrics
import kg.ayant.app.ui.theme.AyantShadow
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantPressScale
import kg.ayant.app.ui.theme.ayantScreenEnter
import kg.ayant.app.ui.theme.ayantShadow
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.ui.vm.FeedViewModel

/**
 * Полный список заведений города — продолжение ряда «Заведения» на главной
 * («Все · N» в шапке ряда и хвостовая плитка «Все заведения →»).
 * Зеркалит `AllVenuesView.swift`.
 *
 * Открывается на той же категории, что выбрана на главной. Сверху — локальный
 * поиск и, если есть геопозиция, сортировка «Ближе».
 */
enum class AllVenuesSort { RATING, DISTANCE }

@Composable
fun AllVenuesScreen(
    app: AppViewModel,
    feed: FeedViewModel,
    location: LocationManager,
    initialCategory: VenueCategory? = null,
    onVenue: (String) -> Unit,
    /** Без явного обработчика — системный «назад» (диспетчер Activity). */
    onBack: (() -> Unit)? = null,
) {
    val c = AyantTheme.colors
    val dispatcher = LocalOnBackPressedDispatcherOwner.current?.onBackPressedDispatcher
    val back: () -> Unit = onBack ?: { dispatcher?.onBackPressed() }

    val feedState by feed.state.collectAsState()
    var category by remember { mutableStateOf(initialCategory) }
    var query by remember { mutableStateOf("") }
    var sort by remember { mutableStateOf(AllVenuesSort.RATING) }

    val canSortByDistance = location.lastLat != null && location.lastLng != null
    // Геопозиция могла появиться позже, чем человек выбрал «Ближе».
    LaunchedEffect(canSortByDistance) {
        if (sort == AllVenuesSort.DISTANCE && !canSortByDistance) sort = AllVenuesSort.RATING
    }

    fun distance(v: Venue): Double? = location.distanceKm(v.latitude, v.longitude)

    // Каталог категории в порядке ранжирования (`FeedViewModel.venues(category)`).
    val categoryVenues = remember(feedState, category) { feed.venues(category) }
    val totalCount = categoryVenues.size
    val results = remember(categoryVenues, query, sort, location.lastLat, location.lastLng) {
        var list = categoryVenues
        val needle = query.trim()
        if (needle.isNotEmpty()) {
            list = list.filter { v ->
                listOf(v.name, v.category.rawValue, v.district, v.address)
                    .any { it.contains(needle, ignoreCase = true) }
            }
        }
        if (sort == AllVenuesSort.DISTANCE && canSortByDistance) {
            // Без координат — в хвост, а не в голову: «ближе» обещает известное расстояние.
            list = list.sortedBy { distance(it) ?: Double.POSITIVE_INFINITY }
        }
        list
    }

    Column(Modifier.fillMaxSize().background(c.canvas)) {
        // Экран открывается пушем: системную панель прячем ради крупного
        // заголовка, но «назад» оставляем — как в «Сохранённом».
        AyantNavBar(onBack = back)
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = 28.dp),
        ) {
            item(key = "title") {
                Column(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = AyantMetrics.screenPadding)
                        .padding(top = 8.dp)
                        .ayantScreenEnter(),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        stringResource(R.string.home_rail_venues),
                        fontSize = 44.sp, fontWeight = FontWeight.Black,
                        letterSpacing = (-2.4).sp, lineHeight = 42.sp, color = c.ink,
                    )
                    // «41 заведение · Бишкек» — склонение по последним цифрам;
                    // город через точку, чтобы не склонять его самого.
                    Text(
                        pluralStringResource(R.plurals.venues_count, totalCount, totalCount) +
                            " · " + app.selectedCity.name,
                        fontSize = 14.sp, lineHeight = 20.sp, color = c.inkSoft,
                    )
                }
            }
            item(key = "search") {
                SearchField(
                    query = query, onQuery = { query = it },
                    modifier = Modifier
                        .padding(horizontal = AyantMetrics.screenPadding)
                        .padding(top = 16.dp),
                )
            }
            item(key = "categories") {
                AyantCategoryRail(
                    selected = category, onSelect = { category = it },
                    modifier = Modifier.padding(top = 12.dp),
                    contentPadding = PaddingValues(horizontal = AyantMetrics.screenPadding, vertical = 8.dp),
                )
            }
            if (canSortByDistance) {
                item(key = "sort") {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .padding(horizontal = AyantMetrics.screenPadding)
                            .padding(top = 4.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        SortChip(
                            stringResource(R.string.all_venues_sort_rating),
                            Icons.Outlined.StarOutline, Icons.Filled.Star,
                            isOn = sort == AllVenuesSort.RATING,
                        ) { sort = AllVenuesSort.RATING }
                        SortChip(
                            stringResource(R.string.all_venues_sort_near),
                            Icons.Outlined.LocationOn, Icons.Filled.LocationOn,
                            isOn = sort == AllVenuesSort.DISTANCE,
                        ) { sort = AllVenuesSort.DISTANCE }
                    }
                }
            }
            item(key = "gap") { Spacer(Modifier.height(8.dp)) }

            if (results.isEmpty()) {
                item(key = "empty") {
                    if (query.isNotBlank()) {
                        AyantUnavailableView(
                            icon = Icons.Filled.Search,
                            title = stringResource(R.string.search_empty_title),
                            body = stringResource(R.string.all_venues_empty_search_body),
                            actionLabel = stringResource(R.string.all_venues_clear_search),
                            onAction = { query = "" },
                        )
                    } else {
                        AyantUnavailableView(
                            icon = storefrontIcon,
                            title = stringResource(R.string.all_venues_empty_cat_title),
                            body = stringResource(
                                R.string.all_venues_empty_cat_body,
                                category?.localizedName() ?: "", app.selectedCity.name,
                            ),
                            actionLabel = stringResource(R.string.home_reset_filter),
                            onAction = { category = null },
                        )
                    }
                }
            } else {
                itemsIndexed(results, key = { _, v -> v.id }) { index, venue ->
                    val agg = feedState.aggregate(venue)
                    val interaction = remember { MutableInteractionSource() }
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .ayantPressScale(interaction, 0.98f)
                            .padding(horizontal = AyantMetrics.screenPadding, vertical = 8.dp),
                    ) {
                        VenueCompactRow(
                            venue = venue,
                            distanceKm = distance(venue),
                            rating = agg.first,
                            ratingCount = agg.second,
                            onClick = { onVenue(venue.id) },
                        )
                    }
                    if (index < results.lastIndex) {
                        // Отступ линии = поле экрана + аватар 62 + зазор 14.
                        AyantHairline(leading = 20 + 62 + 14)
                    }
                }
            }
        }
    }
}

/** Поле локального поиска: лупа, подсказка, крестик очистки. */
@Composable
private fun SearchField(query: String, onQuery: (String) -> Unit, modifier: Modifier = Modifier) {
    val c = AyantTheme.colors
    val shape = RoundedCornerShape(18.dp)
    val placeholder = Color(0xFF9A9188)
    Row(
        modifier
            .fillMaxWidth()
            .ayantShadow(AyantShadow.Card, shape)
            .clip(shape)
            .background(c.surface)
            .border(0.5.dp, c.hairline, shape)
            .padding(horizontal = 16.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Icons.Filled.Search, null, tint = placeholder, modifier = Modifier.size(16.dp))
        Box(Modifier.weight(1f)) {
            if (query.isEmpty()) {
                Text(
                    stringResource(R.string.all_venues_search_hint),
                    fontSize = 14.5.sp, fontWeight = FontWeight.Medium, color = placeholder, maxLines = 1,
                )
            }
            BasicTextField(
                value = query,
                onValueChange = onQuery,
                singleLine = true,
                textStyle = TextStyle(fontSize = 14.5.sp, fontWeight = FontWeight.Medium, color = c.ink),
                cursorBrush = SolidColor(c.accent),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search, autoCorrectEnabled = false),
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

/** Чип сортировки: чернильная заливка у выбранного. Зеркалит `sortChip`. */
@Composable
private fun SortChip(
    title: String,
    icon: ImageVector,
    iconOn: ImageVector,
    isOn: Boolean,
    onClick: () -> Unit,
) {
    val c = AyantTheme.colors
    val interaction = remember { MutableInteractionSource() }
    Row(
        Modifier
            .clip(CircleShape)
            .background(if (isOn) c.ink else c.surfaceMuted)
            .clickable(interaction, null, role = Role.Button, onClick = onClick)
            .ayantPressScale(interaction, 0.93f)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Icon(
            if (isOn) iconOn else icon, null,
            tint = if (isOn) c.canvas else c.inkSoft, modifier = Modifier.size(11.dp),
        )
        Text(
            title,
            fontSize = 12.5.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.2).sp,
            color = if (isOn) c.canvas else c.inkSoft, maxLines = 1,
        )
    }
}
