package kg.ayant.app.ui.host

import androidx.compose.foundation.background
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
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
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
import kg.ayant.app.data.model.HostVenueDTO
import kg.ayant.app.data.model.VenueCategory
import kg.ayant.app.ui.components.VenuePhoto
import kg.ayant.app.ui.theme.AyantIconTile
import kg.ayant.app.ui.theme.AyantPrimaryButton
import kg.ayant.app.ui.theme.AyantScreenTitle
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantCard
import kg.ayant.app.ui.theme.ayantGroupCard
import kg.ayant.app.ui.vm.AppViewModel
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
            host.createAccount(name.trim(), category, phone.trim(), email.trim())
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HostVenuesScreen(host: HostViewModel, app: AppViewModel, onVenue: (String) -> Unit, onExitHost: () -> Unit) {
    val c = AyantTheme.colors
    var showForm by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<HostVenueDTO?>(null) }
    var showScanner by remember { mutableStateOf(false) }
    var addDealVenue by remember { mutableStateOf<String?>(null) }
    var statsVenue by remember { mutableStateOf<String?>(null) }

    Scaffold(
        containerColor = c.canvas,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.host_my_venues), fontWeight = FontWeight.Bold) },
                actions = {
                    if (host.venues.isNotEmpty()) IconButton(onClick = { showScanner = true }) { Icon(Icons.Filled.QrCodeScanner, stringResource(R.string.host_cd_scanner)) }
                    IconButton(onClick = { editing = null; showForm = true }) { Icon(Icons.Filled.Add, stringResource(R.string.action_add)) }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = c.canvas, titleContentColor = c.ink),
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (host.venues.isEmpty()) {
                Column(Modifier.fillMaxWidth().padding(top = 40.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    AyantIconTile(Icons.Filled.Storefront, filled = true, size = 64)
                    Text(stringResource(R.string.host_no_venues_title), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink)
                    Text(stringResource(R.string.host_no_venues_body), fontSize = 15.sp, color = c.inkSoft)
                    AyantPrimaryButton(stringResource(R.string.host_add_venue), onClick = { editing = null; showForm = true })
                }
            } else {
                // Stats
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    StatCard("${host.venues.size}", stringResource(R.string.host_stat_venues), Modifier.weight(1f))
                    val active = host.deals.count { it.status.name == "ACTIVE" }
                    StatCard("$active", stringResource(R.string.host_stat_active_deals), Modifier.weight(1f))
                    val views = host.venues.sumOf { host.stat(it.id, "views", 30) }
                    StatCard("$views", stringResource(R.string.host_stat_views), Modifier.weight(1f), accent = true)
                }
                host.venues.forEach { v ->
                    VenueCard(v, host, onVenue,
                        onEdit = { editing = v; showForm = true },
                        onAddDeal = { addDealVenue = v.id },
                        onStats = { statsVenue = v.id })
                }
            }
        }
    }

    if (showForm) HostVenueForm(host, editing) { showForm = false }
    if (showScanner) HostScannerDialog(host, null) { showScanner = false }
    addDealVenue?.let { vid -> HostDealForm(host, vid, null) { addDealVenue = null } }
    statsVenue?.let { vid -> HostVenueStatsSheet(host, vid) { statsVenue = null } }
}

@Composable
private fun HostVenueStatsSheet(host: HostViewModel, venueID: String, onDismiss: () -> Unit) {
    val c = AyantTheme.colors
    var period by remember { mutableStateOf(30) }
    val metrics = listOf(
        stringResource(R.string.analytics_views) to "views", stringResource(R.string.analytics_redemptions) to "redemptions", stringResource(R.string.analytics_deal_taps) to "dealTaps",
        stringResource(R.string.analytics_saves) to "saves", stringResource(R.string.analytics_calls) to "calls", stringResource(R.string.analytics_maps) to "maps",
    )
    androidx.compose.material3.AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(host.venue(venueID)?.name ?: stringResource(R.string.htab_analytics)) },
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
private fun VenueCard(
    v: HostVenueDTO, host: HostViewModel, onVenue: (String) -> Unit,
    onEdit: () -> Unit, onAddDeal: () -> Unit, onStats: () -> Unit,
) {
    val c = AyantTheme.colors
    Column(Modifier.fillMaxWidth().ayantGroupCard()) {
        Row(Modifier.fillMaxWidth().clickable { onVenue(v.id) }.padding(14.dp), verticalAlignment = Alignment.Top) {
            VenuePhoto(v.imageURL.ifEmpty { null }, listOf(c.accent, c.accentDeep), Modifier.size(54.dp).clip(RoundedCornerShape(15.dp)))
            Column(Modifier.padding(start = 12.dp).weight(1f)) {
                Text(v.name, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = c.ink)
                Text("${v.category.rawValue} · ${v.district}", fontSize = 13.sp, color = c.inkSoft)
                val active = host.deals(forVenue = v.id).count { it.status.name == "ACTIVE" }
                Text(stringResource(R.string.host_active_deals_count, active), fontSize = 13.sp, color = c.inkSoft)
            }
            StatusPill(v)
        }
        Box(Modifier.fillMaxWidth().height(0.5.dp).background(c.hairline))
        Row(Modifier.padding(12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PillBtn(stringResource(R.string.host_add_deal_short), Modifier.weight(1f), accent = true) { onAddDeal() }
            PillBtn(stringResource(R.string.htab_analytics), Modifier.weight(1f)) { onStats() }
            PillBtn(stringResource(R.string.action_edit), Modifier.weight(1f)) { onEdit() }
        }
    }
}

@Composable
private fun StatusPill(v: HostVenueDTO) {
    val color = when (v.moderation.name) { "APPROVED" -> AyantTheme.colors.open; "REJECTED" -> Color(0xFFD32F2F); else -> Color(0xFFF59E0B) }
    val title = when (v.moderation.name) { "APPROVED" -> stringResource(R.string.host_approved); "REJECTED" -> stringResource(R.string.host_rejected); else -> stringResource(R.string.host_pending) }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(color.copy(alpha = 0.14f)).padding(horizontal = 9.dp, vertical = 5.dp),
    ) {
        Box(Modifier.size(6.dp).clip(CircleShape).background(color))
        Text(" $title", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = color)
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
