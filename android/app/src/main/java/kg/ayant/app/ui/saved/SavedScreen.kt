package kg.ayant.app.ui.saved

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
            if (tab == 0) {
                val saved = app.savedVenues
                if (saved.isEmpty()) {
                    EmptyMessage(stringResource(R.string.saved_empty_venues_title), stringResource(R.string.saved_empty_venues_body))
                } else {
                    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(saved, key = { it.id }) { v ->
                            val agg = app.aggregate(v)
                            Row(Modifier.fillMaxWidth().ayantCard(padding = 10), verticalAlignment = Alignment.CenterVertically) {
                                VenueCompactRow(
                                    venue = v,
                                    distanceKm = location.distanceKm(v.latitude, v.longitude),
                                    rating = agg.first, ratingCount = agg.second,
                                    onClick = { onVenue(v.id) },
                                    modifier = Modifier.weight(1f),
                                )
                            }
                        }
                    }
                }
            } else {
                val fav = app.favoriteDeals
                if (fav.isEmpty()) {
                    EmptyMessage(stringResource(R.string.saved_empty_deals_title), stringResource(R.string.saved_empty_deals_body))
                } else {
                    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(fav, key = { it.id }) { d ->
                            val venue = app.venue(forDeal = d)
                            Row(Modifier.fillMaxWidth().ayantCard(padding = 10)) {
                                CompactDealRow(
                                    deal = d,
                                    venueName = venue?.name,
                                    venueGradient = venue?.gradientColors ?: listOf(c.accent, c.accentDeep),
                                    isFavorite = app.isFavorite(d),
                                    onClick = { onDeal(d.id) },
                                    onFavoriteClick = { app.toggleFavorite(d) },
                                    modifier = Modifier.weight(1f),
                                )
                            }
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
