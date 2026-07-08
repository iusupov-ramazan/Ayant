package kg.ayant.app.ui.saved

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.location.LocationManager
import kg.ayant.app.ui.components.CompactDealRow
import kg.ayant.app.ui.components.VenueCompactRow
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.AppViewModel

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

    Scaffold(
        containerColor = c.canvas,
        topBar = {
            TopAppBar(
                title = { Text("Сохранённое", fontWeight = FontWeight.Bold) },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = c.canvas, titleContentColor = c.ink),
            )
        },
    ) { padding ->
        if (app.isGuest) {
            EmptyMessage(
                "Только для аккаунтов",
                "Войдите, чтобы сохранять заведения и предложения. Гостям доступен только просмотр.",
                Modifier.padding(padding),
            )
            return@Scaffold
        }
        Column(Modifier.fillMaxSize().padding(padding)) {
            TabRow(selectedTabIndex = tab, containerColor = c.canvas, contentColor = c.accent) {
                Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text("Заведения") })
                Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text("Предложения") })
            }
            if (tab == 0) {
                val saved = app.savedVenues
                if (saved.isEmpty()) {
                    EmptyMessage("Сохраняй любимые места", "Они появятся здесь — нажми закладку на любом заведении.")
                } else {
                    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        items(saved, key = { it.id }) { v ->
                            val agg = app.aggregate(v)
                            VenueCompactRow(
                                venue = v,
                                distanceKm = location.distanceKm(v.latitude, v.longitude),
                                rating = agg.first, ratingCount = agg.second,
                                onClick = { onVenue(v.id) },
                            )
                        }
                    }
                }
            } else {
                val fav = app.favoriteDeals
                if (fav.isEmpty()) {
                    EmptyMessage("Сохраняй предложения", "Нажми закладку на любом предложении, чтобы сохранить его сюда.")
                } else {
                    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        items(fav, key = { it.id }) { d ->
                            val venue = app.venue(forDeal = d)
                            CompactDealRow(
                                deal = d,
                                venueName = venue?.name,
                                venueGradient = venue?.gradient ?: listOf(c.accent, c.accentDeep),
                                isFavorite = app.isFavorite(d),
                                onClick = { onDeal(d.id) },
                                onFavoriteClick = { app.toggleFavorite(d) },
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
