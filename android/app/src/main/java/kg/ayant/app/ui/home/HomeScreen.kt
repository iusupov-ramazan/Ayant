package kg.ayant.app.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.core.Links
import kg.ayant.app.core.categoryIcon
import kg.ayant.app.core.shareText
import kg.ayant.app.data.model.VenueCategory
import kg.ayant.app.data.model.Venue
import kg.ayant.app.location.LocationManager
import kg.ayant.app.ui.components.CategoryTile
import kg.ayant.app.ui.components.DealCard
import kg.ayant.app.ui.components.VenueCard
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.gradientColors
import kg.ayant.app.ui.vm.AppViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    app: AppViewModel,
    location: LocationManager,
    onVenue: (String) -> Unit,
    onDeal: (String) -> Unit,
) {
    val c = AyantTheme.colors
    val context = LocalContext.current
    var category by remember { mutableStateOf<VenueCategory?>(null) }

    val feedItems = app.feedItems(category)
    val specials = app.savedTodaySpecials

    Scaffold(
        containerColor = c.canvas,
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text(stringResource(R.string.home_title, app.selectedCity.name), fontWeight = FontWeight.Bold) },
                colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = c.canvas, titleContentColor = c.ink),
            )
        },
    ) { padding ->
        LazyColumn(
            Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            // Category row
            item {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(18.dp),
                ) {
                    item {
                        CategoryTile(stringResource(R.string.category_all), Icons.Filled.GridView, category == null) { category = null }
                    }
                    items(VenueCategory.all) { cat ->
                        CategoryTile(cat.rawValue, categoryIcon(cat.icon), category == cat) {
                            category = if (category == cat) null else cat
                        }
                    }
                }
            }

            // Today's specials from saved venues
            if (specials.isNotEmpty()) {
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.Star, null, tint = c.accent, modifier = Modifier.size(16.dp))
                            Text("  " + stringResource(R.string.home_today_saved), fontSize = 14.sp, fontWeight = FontWeight.Bold, color = c.accent)
                        }
                        LazyRow(
                            contentPadding = PaddingValues(horizontal = 16.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            items(specials) { v -> SpecialCard(v) { onVenue(v.id) } }
                        }
                    }
                }
            }

            // Feed
            when {
                app.isLoading -> item {
                    Box(Modifier.fillMaxWidth().padding(top = 40.dp), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = c.accent)
                    }
                }
                app.venuesInSelectedCity().isEmpty() -> item {
                    EmptyState(stringResource(R.string.home_empty_city_title, app.selectedCity.name), stringResource(R.string.home_empty_city_body))
                }
                feedItems.isEmpty() -> item {
                    EmptyState(stringResource(R.string.feed_empty_cat_title), stringResource(R.string.feed_empty_cat_body))
                }
                else -> items(feedItems, key = { it.id }) { item ->
                    when (item) {
                        is kg.ayant.app.data.model.FeedItem.DealItem -> {
                            val deal = item.deal
                            val venue = app.venue(forDeal = deal)
                            DealCard(
                                deal = deal,
                                venue = venue,
                                rating = venue?.let { app.aggregate(it).first } ?: 0.0,
                                isFavorite = app.isFavorite(deal),
                                onTap = { onDeal(deal.id) },
                                onVenueTap = { venue?.let { onVenue(it.id) } },
                                onFavoriteClick = { app.toggleFavorite(deal) },
                                onShare = { context.shareText(context.getString(R.string.deal_share_text, deal.title, venue?.name ?: "", Links.deal(deal.id)), deal.title) },
                                modifier = Modifier.padding(horizontal = 16.dp),
                            )
                        }
                        is kg.ayant.app.data.model.FeedItem.AdVenue -> {
                            val v = item.venue
                            val agg = app.aggregate(v)
                            VenueCard(
                                venue = v,
                                distanceKm = location.distanceKm(v.latitude, v.longitude),
                                isSaved = app.isSaved(v),
                                dealCount = app.deals(forVenue = v).size,
                                rating = agg.first,
                                ratingCount = agg.second,
                                isSponsored = true,
                                onSaveClick = { app.toggleSave(v) },
                                onClick = { onVenue(v.id) },
                                modifier = Modifier.padding(horizontal = 16.dp),
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SpecialCard(venue: Venue, onClick: () -> Unit) {
    val c = AyantTheme.colors
    Column(
        Modifier
            .width(220.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(c.surface)
            .border(1.dp, c.accent.copy(alpha = 0.4f), RoundedCornerShape(14.dp))
            .clickable(onClick = onClick),
    ) {
        Box(Modifier.fillMaxWidth().height(90.dp).background(Brush.linearGradient(venue.gradientColors)), contentAlignment = Alignment.Center) {
            Text(venue.emoji, fontSize = 40.sp)
        }
        Column(Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(venue.name, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = c.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (venue.isOpenNow) Text("  " + stringResource(R.string.status_open), fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = c.open)
            }
            Text(venue.todaySpecialText ?: "", fontSize = 12.sp, color = c.inkSoft, maxLines = 2, overflow = TextOverflow.Ellipsis)
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
