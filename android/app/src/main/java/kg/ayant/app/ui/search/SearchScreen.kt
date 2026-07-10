package kg.ayant.app.ui.search

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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.size
import androidx.compose.ui.draw.clip
import kg.ayant.app.core.distanceText
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.clustering.ClusterItem
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapsComposeExperimentalApi
import com.google.maps.android.compose.clustering.Clustering
import com.google.maps.android.compose.rememberCameraPositionState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.data.model.Venue
import kg.ayant.app.data.model.VenueCategory
import kg.ayant.app.location.LocationManager
import kg.ayant.app.ui.components.VenueCard
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.AppViewModel

@OptIn(ExperimentalMaterial3Api::class, MapsComposeExperimentalApi::class)
@Composable
fun SearchScreen(
    app: AppViewModel,
    location: LocationManager,
    onVenue: (String) -> Unit,
) {
    val c = AyantTheme.colors
    var query by remember { mutableStateOf("") }
    var openNow by remember { mutableStateOf(false) }
    var withDeals by remember { mutableStateOf(false) }
    var minRating by remember { mutableStateOf(0) }
    var maxDistance by remember { mutableStateOf<Double?>(null) }
    var category by remember { mutableStateOf<VenueCategory?>(null) }
    var showMap by remember { mutableStateOf(false) }

    fun matchesQuery(v: Venue): Boolean {
        if (query.isBlank()) return true
        val q = query.trim()
        if (v.name.contains(q, true) || v.category.rawValue.contains(q, true) ||
            v.district.contains(q, true) || v.address.contains(q, true)
        ) return true
        if (v.items.any { it.name.contains(q, true) }) return true
        if (app.deals(forVenue = v).any { it.title.contains(q, true) || it.details.contains(q, true) }) return true
        if (app.reviews(forVenue = v).any { it.text.contains(q, true) || (it.itemName?.contains(q, true) == true) }) return true
        return false
    }

    fun matchesFilters(v: Venue): Boolean {
        if (openNow && !v.isOpenNow) return false
        if (withDeals && app.deals(forVenue = v).isEmpty()) return false
        if (category != null && v.category != category) return false
        if (minRating > 0 && app.aggregate(v).first < minRating) return false
        maxDistance?.let { md ->
            val d = location.distanceKm(v.latitude, v.longitude) ?: return false
            if (d > md) return false
        }
        return true
    }

    val results = app.rankedVenues().filter { matchesQuery(it) && matchesFilters(it) }
    val anyFilterOn = openNow || withDeals || minRating > 0 || maxDistance != null || category != null

    Scaffold(
        containerColor = c.canvas,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.title_search), fontWeight = FontWeight.Bold) },
                actions = {
                    IconButton(onClick = { showMap = !showMap }) {
                        Icon(if (showMap) Icons.AutoMirrored.Filled.List else Icons.Filled.Map, if (showMap) stringResource(R.string.search_list) else stringResource(R.string.search_map))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = c.canvas, titleContentColor = c.ink),
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            OutlinedTextField(
                value = query, onValueChange = { query = it },
                placeholder = { Text(stringResource(R.string.search_hint)) },
                leadingIcon = { Icon(Icons.Filled.Search, null) },
                singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            )

            // Filters
            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (anyFilterOn) {
                    Icon(
                        Icons.Filled.Close, stringResource(R.string.filter_reset), tint = c.inkSoft,
                        modifier = Modifier.size(22.dp).clickable {
                            openNow = false; withDeals = false; minRating = 0; maxDistance = null; category = null
                        },
                    )
                }
                FilterChip(selected = openNow, onClick = { openNow = !openNow }, label = { Text(stringResource(R.string.filter_open)) })
                FilterChip(selected = withDeals, onClick = { withDeals = !withDeals }, label = { Text(stringResource(R.string.filter_deals)) })
                RatingMenu(minRating) { minRating = it }
                DistanceMenu(maxDistance) { maxDistance = it }
                CategoryMenu(category) { category = it }
            }

            if (anyFilterOn || query.isNotBlank()) {
                Text(
                    stringResource(R.string.search_found, results.size),
                    fontSize = 12.sp, color = c.inkSoft,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
                )
            }

            if (showMap) {
                val mapVenues = app.rankedVenues().filter { matchesFilters(it) }
                var preview by remember { mutableStateOf<kg.ayant.app.data.model.Venue?>(null) }
                val cam = rememberCameraPositionState {
                    position = CameraPosition.fromLatLngZoom(LatLng(app.selectedCity.latitude, app.selectedCity.longitude), 12f)
                }
                Box(Modifier.fillMaxSize()) {
                    val items = remember(mapVenues) { mapVenues.map { MapVenueItem(it) } }
                    GoogleMap(modifier = Modifier.fillMaxSize(), cameraPositionState = cam, onMapClick = { preview = null }) {
                        Clustering(
                            items = items,
                            onClusterItemClick = { preview = it.venue; false },
                        )
                    }
                    preview?.let { v ->
                        MapPreviewCard(
                            venue = v,
                            distanceKm = location.distanceKm(v.latitude, v.longitude),
                            rating = app.aggregate(v).first,
                            ratingCount = app.aggregate(v).second,
                            onOpen = { onVenue(v.id) },
                            onClose = { preview = null },
                            modifier = Modifier.align(Alignment.BottomCenter).padding(16.dp),
                        )
                    }
                }
            } else if (results.isEmpty()) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
                    Column(
                        Modifier.padding(top = 80.dp, start = 32.dp, end = 32.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(stringResource(R.string.search_empty_title), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink)
                        Text(stringResource(R.string.search_empty_body), fontSize = 14.sp, color = c.inkSoft)
                    }
                }
            } else {
                LazyColumn(
                    Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    items(results, key = { it.id }) { v ->
                        val agg = app.aggregate(v)
                        VenueCard(
                            venue = v,
                            distanceKm = location.distanceKm(v.latitude, v.longitude),
                            isSaved = app.isSaved(v),
                            dealCount = app.deals(forVenue = v).size,
                            rating = agg.first,
                            ratingCount = agg.second,
                            onSaveClick = { app.toggleSave(v) },
                            onClick = { onVenue(v.id) },
                        )
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RatingMenu(minRating: Int, onSelect: (Int) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        FilterChip(selected = minRating > 0, onClick = { open = true },
            label = { Text(if (minRating == 0) stringResource(R.string.filter_rating) else "★ $minRating+") })
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(text = { Text(stringResource(R.string.filter_rating_any)) }, onClick = { onSelect(0); open = false })
            DropdownMenuItem(text = { Text("★ 3+") }, onClick = { onSelect(3); open = false })
            DropdownMenuItem(text = { Text("★ 4+") }, onClick = { onSelect(4); open = false })
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DistanceMenu(maxDistance: Double?, onSelect: (Double?) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        FilterChip(selected = maxDistance != null, onClick = { open = true },
            label = { Text(if (maxDistance == null) stringResource(R.string.filter_distance) else "≤ ${if (maxDistance < 1) "${(maxDistance * 1000).toInt()} м" else "%.0f км".format(maxDistance)}") })
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(text = { Text(stringResource(R.string.filter_distance_any)) }, onClick = { onSelect(null); open = false })
            DropdownMenuItem(text = { Text("500 м") }, onClick = { onSelect(0.5); open = false })
            DropdownMenuItem(text = { Text("1 км") }, onClick = { onSelect(1.0); open = false })
            DropdownMenuItem(text = { Text("3 км") }, onClick = { onSelect(3.0); open = false })
            DropdownMenuItem(text = { Text("5 км") }, onClick = { onSelect(5.0); open = false })
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CategoryMenu(category: VenueCategory?, onSelect: (VenueCategory?) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        FilterChip(selected = category != null, onClick = { open = true },
            label = { Text(category?.rawValue ?: stringResource(R.string.filter_category)) })
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(text = { Text(stringResource(R.string.filter_category_all)) }, onClick = { onSelect(null); open = false })
            VenueCategory.all.forEach { cat ->
                DropdownMenuItem(text = { Text(cat.rawValue) }, onClick = { onSelect(cat); open = false })
            }
        }
    }
}

/** ClusterItem wrapper for a venue pin. */
private class MapVenueItem(val venue: kg.ayant.app.data.model.Venue) : ClusterItem {
    override fun getPosition() = LatLng(venue.latitude, venue.longitude)
    override fun getTitle() = venue.name
    override fun getSnippet() = "${venue.category.rawValue} · ${venue.district}"
    override fun getZIndex() = 0f
}

/** Mini card shown when a map pin is tapped. Tap to open, ✕ to dismiss. Mirrors MapPreviewCard. */
@Composable
private fun MapPreviewCard(
    venue: kg.ayant.app.data.model.Venue,
    distanceKm: Double?,
    rating: Double,
    ratingCount: Int,
    onOpen: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    androidx.compose.foundation.layout.Row(
        modifier
            .fillMaxWidth()
            .clip(androidx.compose.foundation.shape.RoundedCornerShape(16.dp))
            .background(c.surface)
            .clickable(onClick = onOpen)
            .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        androidx.compose.foundation.layout.Column(Modifier.weight(1f)) {
            Text(venue.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = c.ink, maxLines = 1)
            Text(
                "${venue.category.rawValue} • ${venue.district}" + (distanceKm?.let { " • ${it.distanceText()}" } ?: ""),
                fontSize = 12.sp, color = c.inkSoft, maxLines = 1,
            )
            androidx.compose.foundation.layout.Row(verticalAlignment = Alignment.CenterVertically) {
                kg.ayant.app.ui.components.StarRating(rating = rating, count = ratingCount, size = 12)
                if (venue.isOpenNow) Text("  " + stringResource(R.string.status_open), fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = c.open)
            }
        }
        Text("✕", fontSize = 18.sp, color = c.inkSoft, modifier = Modifier.clickable(onClick = onClose).padding(6.dp))
    }
}
