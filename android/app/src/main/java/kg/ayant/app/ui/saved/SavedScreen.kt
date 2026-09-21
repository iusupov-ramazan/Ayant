package kg.ayant.app.ui.saved

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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.core.localizedName
import kg.ayant.app.location.LocationManager
import kg.ayant.app.ui.components.AyantNavBar
import kg.ayant.app.ui.components.AyantUnavailableView
import kg.ayant.app.ui.components.VenuePhoto
import kg.ayant.app.ui.home.earnRateLabel
import kg.ayant.app.ui.theme.AyantMetrics
import kg.ayant.app.ui.theme.AyantRadius
import kg.ayant.app.ui.theme.AyantShadow
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.AyantTiming
import kg.ayant.app.ui.theme.ayantCard
import kg.ayant.app.ui.theme.ayantPressScale
import kg.ayant.app.ui.theme.ayantRise
import kg.ayant.app.ui.theme.ayantShadow
import kg.ayant.app.ui.theme.gradientColors
import kg.ayant.app.ui.vm.AppViewModel

/**
 * Сохранённое: заведения и предложения. Зеркалит `SavedView.swift`.
 *
 * После редизайна это не вкладка, а экран, в который приходят из шапки ленты
 * (закладка) и из профиля — поэтому сверху «назад», а не панель вкладок.
 *
 * Сетка в две колонки с шагом 12 — по макету (SCREENS.md G7). Сохранённое —
 * поверхность ПРОСМОТРА: сюда приходят выбирать из своего, а не залипать.
 * Списком помещалось три-четыре карточки на экран, плитками вдвое больше.
 */
@Composable
fun SavedScreen(
    app: AppViewModel,
    location: LocationManager,
    onVenue: (String) -> Unit,
    onDeal: (String) -> Unit,
    /** Без явного обработчика — системный «назад» (диспетчер Activity). */
    onBack: (() -> Unit)? = null,
) {
    val c = AyantTheme.colors
    val dispatcher = LocalOnBackPressedDispatcherOwner.current?.onBackPressedDispatcher
    val back: () -> Unit = onBack ?: { dispatcher?.onBackPressed() }
    var tab by remember { mutableIntStateOf(0) }
    // Подписка на владельцев данных: адаптеры `app.*` — обычные геттеры поверх
    // `state.value` ленты и профиля, поэтому без этих строк экран не перерисуется
    // ни после загрузки каталога, ни после изменения сохранённого.
    val feedState by app.feedState.collectAsState()
    val profileState by app.profileFlow.collectAsState()

    Column(Modifier.fillMaxSize().background(c.canvas)) {
        // Экран открывается пушем, поэтому «назад» обязателен: системную панель
        // прячем ради крупного заголовка в контенте, но выход оставляем.
        AyantNavBar(onBack = back)

        if (app.isGuest) {
            AyantUnavailableView(
                icon = Icons.Outlined.AccountCircle,
                title = stringResource(R.string.saved_guest_title),
                body = stringResource(R.string.saved_guest_body),
            )
            return@Column
        }

        val saved = remember(feedState, profileState) { app.savedVenues }
        val fav = remember(feedState, profileState) { app.favoriteDeals }

        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = AyantMetrics.screenPadding, end = AyantMetrics.screenPadding,
                top = 8.dp, bottom = 28.dp,
            ),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item(key = "title", span = { GridItemSpan(maxLineSpan) }) {
                Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    Text(
                        stringResource(R.string.title_saved),
                        fontSize = 44.sp, fontWeight = FontWeight.Black,
                        letterSpacing = (-2.4).sp, lineHeight = 42.sp, color = c.ink,
                    )
                    Segmented(tab) { tab = it }
                    // Между переключателем и сеткой — 16, как между остальными
                    // блоками; 12 даёт сама сетка.
                    Spacer(Modifier.height(4.dp))
                }
            }
            if (tab == 0) {
                if (saved.isEmpty()) {
                    item(key = "emptyVenues", span = { GridItemSpan(maxLineSpan) }) {
                        EmptyNote(
                            stringResource(R.string.saved_empty_venues_title),
                            stringResource(R.string.saved_empty_venues_body),
                        )
                    }
                } else {
                    itemsIndexed(saved, key = { _, v -> v.id }) { index, v ->
                        SavedTile(
                            cover = v.imageURL,
                            gradient = v.gradientColors,
                            title = v.name,
                            subtitle = "${v.category.localizedName()} · ${v.district}",
                            pill = v.earnRateLabel(),
                            onClick = { onVenue(v.id) },
                            onRemove = { app.unsaveVenue(v) },
                            modifier = Modifier.ayantRise(
                                index = index, key = v.id,
                                staggerMs = AyantTiming.GRID_TILE_STAGGER_MS,
                                durationMs = AyantTiming.GRID_TILE_RISE_MS,
                                cap = AyantTiming.GRID_STAGGER_CAP,
                            ),
                        )
                    }
                }
            } else {
                if (fav.isEmpty()) {
                    item(key = "emptyDeals", span = { GridItemSpan(maxLineSpan) }) {
                        EmptyNote(
                            stringResource(R.string.saved_empty_deals_title),
                            stringResource(R.string.saved_empty_deals_body),
                        )
                    }
                } else {
                    itemsIndexed(fav, key = { _, d -> d.id }) { index, d ->
                        val venue = app.venue(forDeal = d)
                        SavedTile(
                            cover = d.allImages.firstOrNull(),
                            gradient = venue?.gradientColors ?: listOf(c.accent, Color(0xFFFF9500)),
                            title = d.title,
                            subtitle = venue?.name.orEmpty(),
                            pill = d.newPrice?.let { stringResource(R.string.price_som, it) },
                            onClick = { onDeal(d.id) },
                            onRemove = { app.unsaveDeal(d) },
                            modifier = Modifier.ayantRise(
                                index = index, key = d.id,
                                staggerMs = AyantTiming.GRID_TILE_STAGGER_MS,
                                durationMs = AyantTiming.GRID_TILE_RISE_MS,
                                cap = AyantTiming.GRID_STAGGER_CAP,
                            ),
                        )
                    }
                }
            }
        }
    }
}

/** Переключатель «Заведения | Предложения». Зеркалит `segmented` в `SavedView.swift`. */
@Composable
private fun Segmented(selected: Int, onSelect: (Int) -> Unit) {
    val c = AyantTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(c.surfaceMuted)
            .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        SegmentButton(stringResource(R.string.saved_venues), selected == 0, Modifier.weight(1f)) { onSelect(0) }
        SegmentButton(stringResource(R.string.saved_deals), selected == 1, Modifier.weight(1f)) { onSelect(1) }
    }
}

@Composable
private fun SegmentButton(title: String, isOn: Boolean, modifier: Modifier, onClick: () -> Unit) {
    val c = AyantTheme.colors
    val shape = RoundedCornerShape(13.dp)
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier
            .then(if (isOn) Modifier.ayantShadow(AyantShadow.Card, shape) else Modifier)
            .clip(shape)
            .then(if (isOn) Modifier.background(c.surface) else Modifier)
            .selectable(selected = isOn, interactionSource = interaction, indication = null, role = Role.Tab, onClick = onClick)
            .padding(vertical = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            title,
            fontSize = 13.5.sp,
            fontWeight = if (isOn) FontWeight.Bold else FontWeight.SemiBold,
            color = if (isOn) c.ink else c.inkSoft,
        )
    }
}

/** Пустое состояние — карточка-подсказка, а не центрированный экран. Зеркалит `emptyNote`. */
@Composable
private fun EmptyNote(title: String, body: String) {
    val c = AyantTheme.colors
    Column(
        Modifier.fillMaxWidth().ayantCard(padding = 0, radius = 22).padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(title, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = c.ink)
        Text(body, fontSize = 13.5.sp, lineHeight = 19.sp, color = c.inkSoft)
    }
}

/**
 * Плитка «Сохранённого»: обложка 104 + стеклянное сердечко · название 14/bold ·
 * подпись 11.5 · пилюля `#FFF3EC` с акцентным текстом — всё по макету G7.
 */
@Composable
private fun SavedTile(
    cover: String?,
    gradient: List<Color>,
    title: String,
    subtitle: String,
    pill: String?,
    onClick: () -> Unit,
    onRemove: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    val shape = RoundedCornerShape(AyantRadius.card)
    val interaction = remember { MutableInteractionSource() }
    Column(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(c.surface)
            .border(0.5.dp, c.hairline, shape)
            .clickable(interaction, null, onClick = onClick)
            .ayantPressScale(interaction, 0.97f),
    ) {
        Box {
            VenuePhoto(cover, gradient, Modifier.fillMaxWidth().height(104.dp))
            val removeInteraction = remember { MutableInteractionSource() }
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .padding(8.dp)
                    .size(30.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.75f))
                    .clickable(removeInteraction, null, role = Role.Button, onClick = onRemove)
                    .ayantPressScale(removeInteraction, 0.86f),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Filled.Favorite,
                    contentDescription = stringResource(R.string.saved_remove),
                    tint = c.accentText,
                    modifier = Modifier.size(15.dp),
                )
            }
        }
        Column(Modifier.padding(12.dp)) {
            Text(
                title,
                fontSize = 14.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.25).sp, color = c.ink,
                maxLines = 2, lineHeight = 17.sp, overflow = TextOverflow.Ellipsis,
            )
            if (subtitle.isNotEmpty()) {
                Text(
                    subtitle,
                    fontSize = 11.5.sp, color = c.inkSoft, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(top = 5.dp),
                )
            }
            pill?.let {
                Text(
                    it,
                    fontSize = 11.sp, fontWeight = FontWeight.Bold, color = c.accentText,
                    modifier = Modifier
                        .padding(top = 9.dp)
                        .clip(CircleShape)
                        .background(Color(0xFFFFF3EC))
                        .padding(horizontal = 9.dp, vertical = 5.dp),
                )
            }
        }
    }
}
