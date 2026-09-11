package kg.ayant.app.ui.saved

import androidx.compose.runtime.collectAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import kg.ayant.app.ui.theme.ayantCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.location.LocationManager
import kg.ayant.app.ui.components.CompactDealRow
import kg.ayant.app.ui.components.VenueCompactRow
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.gradientColors
import kg.ayant.app.ui.vm.AppViewModel
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.clickable
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material3.Icon
import kg.ayant.app.ui.components.VenuePhoto
import kg.ayant.app.ui.theme.AyantRadius
import kg.ayant.app.ui.home.earnRateLabel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SavedScreen(
    app: AppViewModel,
    location: LocationManager,
    onVenue: (String) -> Unit,
    onDeal: (String) -> Unit,
) {
    val c = AyantTheme.colors
    var tab by remember { mutableIntStateOf(0) }
    // Подписка на владельцев данных: адаптеры `app.*` — обычные геттеры поверх
    // `state.value` ленты и профиля, поэтому без этих строк экран не перерисуется
    // ни после загрузки каталога, ни после изменения сохранённого.
    val feedState by app.feedState.collectAsState()
    val profileState by app.profileFlow.collectAsState()


    Scaffold(
        containerColor = c.canvas,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.title_saved), fontWeight = FontWeight.Bold) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = c.canvas, titleContentColor = c.ink),
            )
        },
    ) { padding ->
        if (app.isGuest) {
            EmptyMessage(
                stringResource(R.string.saved_guest_title),
                stringResource(R.string.saved_guest_body),
                Modifier.padding(padding),
            )
            return@Scaffold
        }
        Column(Modifier.fillMaxSize().background(c.canvas).padding(padding)) {
            TabRow(selectedTabIndex = tab, containerColor = c.canvas, contentColor = c.accent) {
                Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text(stringResource(R.string.saved_venues)) })
                Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text(stringResource(R.string.saved_deals)) })
            }
            // Сетка в две колонки с шагом 12 — по макету (SCREENS.md G7).
            // Сохранённое — поверхность ПРОСМОТРА: сюда приходят выбирать из
            // своего. Списком помещалось три-четыре карточки, плитками вдвое
            // больше. Зеркалит `SavedView.swift`.
            if (tab == 0) {
                val saved = remember(feedState, profileState) { app.savedVenues }
                if (saved.isEmpty()) {
                    EmptyMessage(stringResource(R.string.saved_empty_venues_title), stringResource(R.string.saved_empty_venues_body))
                } else {
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(2),
                        contentPadding = PaddingValues(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        items(saved, key = { it.id }) { v ->
                            SavedTile(
                                cover = v.imageURL,
                                gradient = v.gradientColors,
                                title = v.name,
                                subtitle = "${v.category.rawValue} · ${v.district}",
                                pill = v.earnRateLabel(),
                                onClick = { onVenue(v.id) },
                                onRemove = { app.toggleSave(v) },
                            )
                        }
                    }
                }
            } else {
                val fav = remember(feedState, profileState) { app.favoriteDeals }
                if (fav.isEmpty()) {
                    EmptyMessage(stringResource(R.string.saved_empty_deals_title), stringResource(R.string.saved_empty_deals_body))
                } else {
                    LazyVerticalGrid(
                        columns = GridCells.Fixed(2),
                        contentPadding = PaddingValues(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        items(fav, key = { it.id }) { d ->
                            val venue = app.venue(forDeal = d)
                            SavedTile(
                                cover = d.allImages.firstOrNull(),
                                gradient = venue?.gradientColors ?: listOf(c.accent, c.accentDeep),
                                title = d.title,
                                subtitle = venue?.name.orEmpty(),
                                pill = d.newPrice?.let { stringResource(R.string.price_som, it) },
                                onClick = { onDeal(d.id) },
                                onRemove = { app.toggleFavorite(d) },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptyMessage(title: String, subtitle: String, modifier: Modifier = Modifier) {
    val c = AyantTheme.colors
    Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(32.dp)) {
            Text(title, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink, textAlign = TextAlign.Center)
            Text(subtitle, fontSize = 14.sp, color = c.inkSoft, textAlign = TextAlign.Center)
        }
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
) {
    val c = AyantTheme.colors
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AyantRadius.card))
            .background(c.surface)
            .clickable(onClick = onClick),
    ) {
        Box {
            VenuePhoto(cover, gradient, Modifier.fillMaxWidth().height(104.dp))
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .padding(8.dp)
                    .size(30.dp)
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.75f))
                    .clickable(onClick = onRemove),
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
                fontSize = 14.sp, fontWeight = FontWeight.Bold, color = c.ink,
                maxLines = 2, lineHeight = 17.sp,
            )
            if (subtitle.isNotEmpty()) {
                Text(
                    subtitle,
                    fontSize = 11.5.sp, color = c.inkSoft, maxLines = 1,
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
