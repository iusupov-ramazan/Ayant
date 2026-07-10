package kg.ayant.app.ui.host

import kotlinx.coroutines.launch
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import androidx.compose.foundation.text.KeyboardOptions
import kg.ayant.app.data.model.HostDealDTO
import kg.ayant.app.data.model.HostVenueDTO
import kg.ayant.app.data.model.VenueCategory
import kg.ayant.app.data.model.DealType
import kg.ayant.app.ui.components.CoverImage
import kg.ayant.app.ui.components.VenuePhoto
import kg.ayant.app.ui.theme.AyantPrimaryButton
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantCard
import kg.ayant.app.ui.vm.HostViewModel
import java.util.Date

// MARK: - Venue detail (host)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HostVenueDetailScreen(venueID: String, host: HostViewModel, onBack: () -> Unit, onPromote: () -> Unit = {}) {
    val c = AyantTheme.colors
    val v = host.venue(venueID) ?: run {
        Box(Modifier.fillMaxSize().background(c.canvas), contentAlignment = Alignment.Center) { Text(stringResource(R.string.venue_not_found)) }
        return
    }
    var special by remember { mutableStateOf(v.todaySpecial ?: "") }
    var showVenueForm by remember { mutableStateOf(false) }
    var showDealForm by remember { mutableStateOf<HostDealDTO?>(null) }
    var addingDeal by remember { mutableStateOf(false) }
    var showItem by remember { mutableStateOf(false) }
    var showScanner by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = c.canvas,
        topBar = {
            TopAppBar(
                title = { Text(v.name, fontWeight = FontWeight.Bold, maxLines = 1) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.action_back)) } },
                actions = { IconButton(onClick = { showScanner = true }) { Icon(Icons.Filled.QrCodeScanner, stringResource(R.string.host_cd_scanner)) } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = c.canvas, titleContentColor = c.ink),
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            // Header
            Column {
                VenuePhoto(v.imageURL.ifEmpty { null }, listOf(c.accent, c.accentDeep), Modifier.fillMaxWidth().height(130.dp).clip(RoundedCornerShape(16.dp)))
                Row(Modifier.fillMaxWidth().padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(v.name, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink)
                        Text("${v.category.rawValue} · ${v.district}", fontSize = 12.sp, color = c.inkSoft)
                    }
                    Text(if (v.isPaused) stringResource(R.string.host_paused) else stringResource(R.string.host_active), fontSize = 12.sp, color = c.inkSoft)
                    Switch(checked = !v.isPaused, onCheckedChange = { host.togglePause(v.id) })
                }
            }

            // Moderation banner (pending/rejected)
            if (v.moderation.name != "APPROVED") {
                val col = if (v.moderation.name == "REJECTED") Color(0xFFD32F2F) else Color(0xFFF59E0B)
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(col.copy(alpha = 0.1f)).padding(12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(if (v.moderation.name == "REJECTED") stringResource(R.string.host_rejected) else stringResource(R.string.host_pending), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = col)
                    Text(
                        if (v.moderation.name == "REJECTED") stringResource(R.string.host_rejected_body)
                        else stringResource(R.string.host_pending_body),
                        fontSize = 12.sp, color = c.inkSoft,
                    )
                }
            }

            // Today special
            Column(Modifier.fillMaxWidth().ayantCard(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.host_today_special), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = c.accent)
                OutlinedTextField(special, { if (it.length <= 100) special = it }, placeholder = { Text(stringResource(R.string.host_special_placeholder)) }, modifier = Modifier.fillMaxWidth())
                PillBtn(stringResource(R.string.host_save_special), accent = true) { host.setTodaySpecial(v.id, special) }
            }

            // Loyalty overview
            Column(Modifier.fillMaxWidth().ayantCard(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.venue_loyalty_card), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = c.ink)
                    Spacer(Modifier.weight(1f))
                    Text(if (v.loyaltyEnabled) stringResource(R.string.host_enabled) else stringResource(R.string.host_disabled), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = if (v.loyaltyEnabled) c.open else c.inkSoft)
                }
                Text(if (v.loyaltyEnabled) stringResource(R.string.host_loyalty_progress, v.loyaltyGoal, v.loyaltyReward) else stringResource(R.string.host_loyalty_disabled_hint), fontSize = 13.sp, color = c.inkSoft)
            }

            // Items
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.host_items_section), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink)
                    Spacer(Modifier.weight(1f))
                    IconButton(onClick = { showItem = true }) { Icon(Icons.Filled.Add, stringResource(R.string.host_cd_add_item), tint = c.accent) }
                }
                if (v.items.isEmpty()) Text(stringResource(R.string.host_no_items), fontSize = 14.sp, color = c.inkSoft)
                else v.items.forEach { item ->
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(c.surfaceMuted).padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(item.emoji, fontSize = 22.sp)
                        Column(Modifier.padding(start = 10.dp).weight(1f)) {
                            Text(item.name, fontSize = 14.sp, color = c.ink)
                            Text(item.kindTitle, fontSize = 11.sp, color = c.inkSoft)
                        }
                        IconButton(onClick = { host.deleteItem(v.id, item.id) }) { Icon(Icons.Filled.Delete, stringResource(R.string.action_delete), tint = Color(0xFFD32F2F)) }
                    }
                }
            }

            // Deals
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.saved_deals), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink)
                    Spacer(Modifier.weight(1f))
                    IconButton(onClick = { addingDeal = true; showDealForm = null }) { Icon(Icons.Filled.Add, stringResource(R.string.host_cd_add_deal), tint = c.accent) }
                }
                val deals = host.deals(forVenue = v.id)
                if (deals.isEmpty()) Text(stringResource(R.string.host_no_deals), fontSize = 14.sp, color = c.inkSoft)
                else LazyVerticalGrid(
                    columns = GridCells.Fixed(3),
                    modifier = Modifier.fillMaxWidth().height((((deals.size + 2) / 3) * 116).dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp),
                    userScrollEnabled = false,
                ) {
                    items(deals) { d ->
                        var menu by remember { mutableStateOf(false) }
                        Box {
                            Box(Modifier.height(108.dp).clip(RoundedCornerShape(10.dp)).clickable { menu = true }) {
                                CoverImage(d.imageURL.ifEmpty { null }, listOf(c.accent, c.accentDeep), d.emoji, Modifier.fillMaxSize(), emojiSize = 30)
                                Text(d.status.title(), fontSize = 8.sp, fontWeight = FontWeight.Bold, color = Color.White, modifier = Modifier.align(Alignment.BottomStart).padding(5.dp).clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.45f)).padding(horizontal = 5.dp, vertical = 2.dp))
                            }
                            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                                DropdownMenuItem(text = { Text(stringResource(R.string.action_edit)) }, onClick = { menu = false; addingDeal = false; showDealForm = d })
                                DropdownMenuItem(text = { Text(if (d.status == kg.ayant.app.data.model.DealStatus.PAUSED) stringResource(R.string.host_resume) else stringResource(R.string.host_pause)) }, onClick = {
                                    menu = false; host.setDealStatus(d.id, if (d.status == kg.ayant.app.data.model.DealStatus.PAUSED) "active" else "paused")
                                })
                                DropdownMenuItem(text = { Text(stringResource(R.string.action_delete)) }, onClick = { menu = false; host.deleteDeal(d.id) })
                            }
                        }
                    }
                }
            }

            // Actions
            AyantPrimaryButton(stringResource(R.string.host_scan_guest_coupons), onClick = { showScanner = true })
            PillBtn(stringResource(R.string.host_edit_venue)) { showVenueForm = true }
            PillBtn(stringResource(R.string.host_promote_venue), accent = true) { onPromote() }
            Text(
                stringResource(R.string.host_delete_venue), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Color(0xFFD32F2F),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Color(0xFFD32F2F).copy(alpha = 0.1f)).clickable { confirmDelete = true }.padding(vertical = 14.dp),
            )
        }
    }

    if (showVenueForm) HostVenueForm(host, v) { showVenueForm = false }
    if (showDealForm != null || addingDeal) HostDealForm(host, v.id, showDealForm) { showDealForm = null; addingDeal = false }
    if (showItem) HostItemDialog(host, v.id) { showItem = false }
    if (showScanner) HostScannerDialog(host, v.id) { showScanner = false }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text(stringResource(R.string.host_delete_venue_confirm)) },
            text = { Text(stringResource(R.string.host_delete_venue_body, v.name)) },
            confirmButton = { TextButton(onClick = { confirmDelete = false; host.deleteVenue(v.id); onBack() }) { Text(stringResource(R.string.action_delete), color = Color(0xFFD32F2F)) } },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.action_cancel)) } },
        )
    }
}

@Composable
private fun kg.ayant.app.data.model.DealStatus.title() = when (this) {
    kg.ayant.app.data.model.DealStatus.ACTIVE -> stringResource(R.string.host_active)
    kg.ayant.app.data.model.DealStatus.PAUSED -> stringResource(R.string.host_paused)
    kg.ayant.app.data.model.DealStatus.EXPIRED -> stringResource(R.string.host_expired)
    kg.ayant.app.data.model.DealStatus.DRAFT -> stringResource(R.string.host_draft)
}

// MARK: - Venue form (create / edit)

@Composable
fun HostVenueForm(host: HostViewModel, existing: HostVenueDTO?, onDismiss: () -> Unit) {
    val c = AyantTheme.colors
    var name by remember { mutableStateOf(existing?.name ?: "") }
    var category by remember { mutableStateOf(existing?.category ?: VenueCategory.CAFE) }
    var district by remember { mutableStateOf(existing?.district ?: "") }
    var address by remember { mutableStateOf(existing?.address ?: "") }
    var phone by remember { mutableStateOf(existing?.phone ?: "") }
    var emoji by remember { mutableStateOf(existing?.emoji ?: "🍽") }
    var imageURL by remember { mutableStateOf(existing?.imageURL ?: "") }
    var lat by remember { mutableStateOf((existing?.latitude ?: 42.8746).toString()) }
    var lng by remember { mutableStateOf((existing?.longitude ?: 74.5698).toString()) }
    var whatsapp by remember { mutableStateOf(existing?.whatsapp ?: "") }
    var instagram by remember { mutableStateOf(existing?.instagram ?: "") }
    var telegram by remember { mutableStateOf(existing?.telegram ?: "") }
    var pdfMenuURL by remember { mutableStateOf(existing?.pdfMenuURL ?: "") }
    var openHour by remember { mutableStateOf((existing?.openHour ?: 9).toString()) }
    var closeHour by remember { mutableStateOf((existing?.closeHour ?: 22).toString()) }
    var couponsEnabled by remember { mutableStateOf(existing?.couponsEnabled ?: true) }
    var loyaltyEnabled by remember { mutableStateOf(existing?.loyaltyEnabled ?: false) }
    var loyaltyGoal by remember { mutableStateOf((existing?.loyaltyGoal ?: 6).toString()) }
    var loyaltyReward by remember { mutableStateOf(existing?.loyaltyReward ?: "Награда за лояльность") }
    var showMapPicker by remember { mutableStateOf(false) }
    var showBranchForm by remember { mutableStateOf(false) }
    var hoursExpanded by remember { mutableStateOf(false) }
    var week by remember {
        mutableStateOf(existing?.weekHours?.takeIf { it.size == 7 } ?: List(7) { kg.ayant.app.data.model.DayHours() })
    }
    var branches by remember { mutableStateOf(existing?.branches ?: emptyList()) }

    if (showBranchForm) {
        BranchFormDialog(onDismiss = { showBranchForm = false }) { branches = branches + it }
    }
    if (showMapPicker) {
        MapPickerDialog(
            initialLat = lat.replace(',', '.').toDoubleOrNull() ?: 42.8746,
            initialLng = lng.replace(',', '.').toDoubleOrNull() ?: 74.5698,
            onDismiss = { showMapPicker = false },
        ) { la, lo -> lat = la.toString(); lng = lo.toString() }
    }

    FormDialog(
        title = if (existing == null) stringResource(R.string.venue_form_new_title) else stringResource(R.string.venue_form_edit_title),
        onDismiss = onDismiss,
        canSave = name.isNotBlank(),
        onSave = {
            val dto = (existing ?: HostVenueDTO(
                id = host.newVenueID(), name = "", categoryRaw = category.rawValue, district = "", address = "",
                phone = "", emoji = emoji, latitude = 42.8746, longitude = 74.5698, openHour = 9, closeHour = 22,
            )).copy(
                name = name.trim(), categoryRaw = category.rawValue, district = district.trim(), address = address.trim(),
                phone = phone.trim(), emoji = emoji, imageURL = imageURL.trim(),
                latitude = lat.replace(',', '.').toDoubleOrNull() ?: 42.8746,
                longitude = lng.replace(',', '.').toDoubleOrNull() ?: 74.5698,
                openHour = openHour.toIntOrNull()?.coerceIn(0, 24) ?: 9,
                closeHour = closeHour.toIntOrNull()?.coerceIn(0, 24) ?: 22,
                whatsapp = whatsapp.trim(), instagram = instagram.trim(), telegram = telegram.trim(),
                pdfMenuURL = pdfMenuURL.trim(),
                couponsEnabled = couponsEnabled, loyaltyEnabled = loyaltyEnabled,
                loyaltyGoal = loyaltyGoal.toIntOrNull() ?: 6, loyaltyReward = loyaltyReward.trim(),
                weekHours = if (hoursExpanded) week else emptyList(),
                branches = branches,
            )
            if (existing == null) host.addVenue(dto) else host.updateVenue(dto)
            onDismiss()
        },
    ) {
        SectionLabel(stringResource(R.string.venue_form_section_main))
        Field(name, { name = it }, stringResource(R.string.venue_form_name))
        CategoryDropdown(category) { category = it }
        Field(emoji, { emoji = it }, stringResource(R.string.venue_form_emoji))
        Field(district, { district = it }, stringResource(R.string.venue_form_district))
        Field(address, { address = it }, stringResource(R.string.venue_form_address))
        Field(phone, { phone = it }, stringResource(R.string.venue_form_phone), KeyboardType.Phone)
        Field(imageURL, { imageURL = it }, stringResource(R.string.venue_form_photo_url))
        UploadButton(stringResource(R.string.host_upload_photo), "image/*", "venues") { imageURL = it }
        Field(pdfMenuURL, { pdfMenuURL = it }, stringResource(R.string.venue_form_pdf_url))
        UploadButton(stringResource(R.string.host_upload_pdf), "application/pdf", "menus") { pdfMenuURL = it }

        SectionLabel(stringResource(R.string.venue_form_section_hours))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(if (hoursExpanded) stringResource(R.string.venue_form_hours_perday) else stringResource(R.string.venue_form_hours_same), fontSize = 14.sp, color = AyantTheme.colors.ink, modifier = Modifier.weight(1f))
            Switch(checked = hoursExpanded, onCheckedChange = { hoursExpanded = it })
        }
        if (!hoursExpanded) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Field(openHour, { openHour = it }, stringResource(R.string.venue_form_open_hour), KeyboardType.Number, Modifier.weight(1f))
                Field(closeHour, { closeHour = it }, stringResource(R.string.venue_form_close_hour), KeyboardType.Number, Modifier.weight(1f))
            }
        } else {
            val days = listOf(stringResource(R.string.venue_form_day_mon), stringResource(R.string.venue_form_day_tue), stringResource(R.string.venue_form_day_wed), stringResource(R.string.venue_form_day_thu), stringResource(R.string.venue_form_day_fri), stringResource(R.string.venue_form_day_sat), stringResource(R.string.venue_form_day_sun))
            days.forEachIndexed { i, day ->
                val d = week[i]
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(day, fontSize = 14.sp, color = AyantTheme.colors.ink, modifier = Modifier.width(28.dp))
                    Switch(checked = !d.closed, onCheckedChange = { on -> week = week.toMutableList().also { it[i] = d.copy(closed = !on) } })
                    if (!d.closed) {
                        Field((d.open / 60).toString(), { v -> week = week.toMutableList().also { it[i] = d.copy(open = (v.toIntOrNull() ?: 9) * 60) } }, stringResource(R.string.venue_form_from), KeyboardType.Number, Modifier.weight(1f))
                        Field((d.close / 60).toString(), { v -> week = week.toMutableList().also { it[i] = d.copy(close = (v.toIntOrNull() ?: 22) * 60) } }, stringResource(R.string.venue_form_to), KeyboardType.Number, Modifier.weight(1f))
                    } else {
                        Text(stringResource(R.string.venue_form_dayoff), fontSize = 13.sp, color = AyantTheme.colors.inkSoft, modifier = Modifier.weight(1f))
                    }
                }
            }
            PillBtn(stringResource(R.string.venue_form_apply_monday)) { week = List(7) { week[0] } }
        }

        SectionLabel(stringResource(R.string.venue_form_section_branches))
        branches.forEach { b ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(b.address + (if (b.phone.isNotEmpty()) " · ${b.phone}" else ""), fontSize = 13.sp, color = AyantTheme.colors.ink, modifier = Modifier.weight(1f))
                Text("✕", fontSize = 16.sp, color = Color(0xFFD32F2F), modifier = Modifier.clickable { branches = branches.filterNot { it.id == b.id } }.padding(6.dp))
            }
        }
        PillBtn(stringResource(R.string.venue_form_add_branch), accent = true) { showBranchForm = true }

        SectionLabel(stringResource(R.string.venue_form_section_social))
        Field(whatsapp, { whatsapp = it }, stringResource(R.string.venue_form_whatsapp), KeyboardType.Phone)
        Field(instagram, { instagram = it }, stringResource(R.string.venue_form_instagram))
        Field(telegram, { telegram = it }, stringResource(R.string.venue_form_telegram))

        SectionLabel(stringResource(R.string.venue_form_section_location))
        PillBtn(stringResource(R.string.venue_form_pick_map), accent = true) { showMapPicker = true }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Field(lat, { lat = it }, stringResource(R.string.venue_form_lat), KeyboardType.Decimal, Modifier.weight(1f))
            Field(lng, { lng = it }, stringResource(R.string.venue_form_lng), KeyboardType.Decimal, Modifier.weight(1f))
        }

        SectionLabel(stringResource(R.string.venue_form_section_loyalty))
        ToggleRow(stringResource(R.string.venue_form_accept_coupons), couponsEnabled) { couponsEnabled = it }
        ToggleRow(stringResource(R.string.venue_loyalty_card), loyaltyEnabled) { loyaltyEnabled = it }
        if (loyaltyEnabled) {
            Field(loyaltyGoal, { loyaltyGoal = it }, stringResource(R.string.venue_form_stamps_goal), KeyboardType.Number)
            Field(loyaltyReward, { loyaltyReward = it }, stringResource(R.string.venue_form_reward))
        }
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(text.uppercase(), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = AyantTheme.colors.inkSoft, modifier = Modifier.padding(top = 6.dp))
}

@Composable
private fun BranchFormDialog(onDismiss: () -> Unit, onSave: (kg.ayant.app.data.model.Branch) -> Unit) {
    var address by remember { mutableStateOf("") }
    var phone by remember { mutableStateOf("") }
    var lat by remember { mutableStateOf("42.8746") }
    var lng by remember { mutableStateOf("74.5698") }
    var showMap by remember { mutableStateOf(false) }
    if (showMap) {
        MapPickerDialog(lat.toDoubleOrNull() ?: 42.8746, lng.toDoubleOrNull() ?: 74.5698, onDismiss = { showMap = false }) { la, lo ->
            lat = la.toString(); lng = lo.toString()
        }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.venue_form_new_branch)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Field(address, { address = it }, stringResource(R.string.venue_form_address))
                Field(phone, { phone = it }, stringResource(R.string.venue_form_phone_optional), KeyboardType.Phone)
                PillBtn(stringResource(R.string.venue_form_pick_map), accent = true) { showMap = true }
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Field(lat, { lat = it }, stringResource(R.string.venue_form_lat), KeyboardType.Decimal, Modifier.weight(1f))
                    Field(lng, { lng = it }, stringResource(R.string.venue_form_lng), KeyboardType.Decimal, Modifier.weight(1f))
                }
            }
        },
        confirmButton = {
            TextButton(enabled = address.isNotBlank(), onClick = {
                onSave(kg.ayant.app.data.model.Branch(
                    "br_${java.util.UUID.randomUUID().toString().take(6)}", address.trim(),
                    lat.replace(',', '.').toDoubleOrNull() ?: 42.8746, lng.replace(',', '.').toDoubleOrNull() ?: 74.5698, phone.trim(),
                ))
                onDismiss()
            }) { Text(stringResource(R.string.action_add)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_cancel)) } },
    )
}

// MARK: - Deal form

@Composable
fun HostDealForm(host: HostViewModel, venueID: String, existing: HostDealDTO?, onDismiss: () -> Unit) {
    var title by remember { mutableStateOf(existing?.title ?: "") }
    var details by remember { mutableStateOf(existing?.details ?: "") }
    var type by remember { mutableStateOf(existing?.type ?: DealType.DISCOUNT) }
    var emoji by remember { mutableStateOf(existing?.emoji ?: "🔥") }
    var newPrice by remember { mutableStateOf(existing?.newPrice?.toString() ?: "") }
    var discount by remember { mutableStateOf(existing?.discountPercent?.toString() ?: "") }
    var imageURL by remember { mutableStateOf(existing?.imageURL ?: "") }
    var draft by remember { mutableStateOf(existing?.status == kg.ayant.app.data.model.DealStatus.DRAFT) }
    var typeMenu by remember { mutableStateOf(false) }
    // End date expressed as days-from-now (avoids a heavy date-picker); iOS uses a DatePicker.
    val existingDays = existing?.endDate?.let { ((it.time - Date().time) / 86_400_000L).toInt().coerceAtLeast(0) }
    var hasEnd by remember { mutableStateOf(existing?.endDate != null) }
    var days by remember { mutableStateOf((existingDays ?: 14).toString()) }

    FormDialog(
        title = if (existing == null) stringResource(R.string.deal_form_new_title) else stringResource(R.string.deal_form_edit_title),
        onDismiss = onDismiss,
        canSave = title.isNotBlank(),
        onSave = {
            val end = if (hasEnd) Date(Date().time + (days.toLongOrNull() ?: 14L) * 86_400_000L) else null
            host.saveDeal(HostDealDTO(
                id = existing?.id ?: host.newDealID(), venueID = venueID, typeRaw = type.title,
                title = title.trim(), details = details.trim(), emoji = emoji,
                newPrice = newPrice.toIntOrNull(), discountPercent = discount.toIntOrNull(),
                startDate = existing?.startDate ?: Date(), endDate = end,
                statusRaw = if (draft) "draft" else "active", imageURL = imageURL.trim(),
            ))
            onDismiss()
        },
    ) {
        Field(title, { title = it }, stringResource(R.string.deal_form_title))
        Box {
            Field(type.title, {}, stringResource(R.string.deal_form_type), enabled = false, modifier = Modifier.clickable { typeMenu = true })
            DropdownMenu(expanded = typeMenu, onDismissRequest = { typeMenu = false }) {
                DealType.entries.forEach { t -> DropdownMenuItem(text = { Text(t.title) }, onClick = { type = t; typeMenu = false }) }
            }
        }
        Field(emoji, { emoji = it }, stringResource(R.string.venue_form_emoji))
        Field(details, { details = it }, stringResource(R.string.deal_form_details))
        Field(newPrice, { newPrice = it }, stringResource(R.string.deal_form_new_price), KeyboardType.Number)
        Field(discount, { discount = it }, stringResource(R.string.deal_form_discount), KeyboardType.Number)
        Field(imageURL, { imageURL = it }, stringResource(R.string.venue_form_photo_url))
        UploadButton(stringResource(R.string.host_upload_photo), "image/*", "deals") { imageURL = it }
        ToggleRow(stringResource(R.string.deal_form_has_end), hasEnd) { hasEnd = it }
        if (hasEnd) Field(days, { days = it }, stringResource(R.string.deal_form_days), KeyboardType.Number)
        ToggleRow(stringResource(R.string.deal_form_draft), draft) { draft = it }
    }
}

// MARK: - Item dialog

@Composable
fun HostItemDialog(host: HostViewModel, venueID: String, onDismiss: () -> Unit) {
    var name by remember { mutableStateOf("") }
    var emoji by remember { mutableStateOf("🍽") }
    var kind by remember { mutableStateOf("food") }
    var imageURL by remember { mutableStateOf("") }
    var kindMenu by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.host_item_new_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Field(name, { name = it }, stringResource(R.string.host_item_name))
                Field(emoji, { emoji = it }, stringResource(R.string.host_item_emoji))
                Box {
                    val kindTitle = mapOf("food" to stringResource(R.string.host_item_kind_food), "service" to stringResource(R.string.host_item_kind_service), "other" to stringResource(R.string.host_item_kind_other))[kind] ?: stringResource(R.string.host_item_kind_food)
                    Field(kindTitle, {}, stringResource(R.string.host_item_kind_label), enabled = false, modifier = Modifier.clickable { kindMenu = true })
                    DropdownMenu(expanded = kindMenu, onDismissRequest = { kindMenu = false }) {
                        listOf("food" to stringResource(R.string.host_item_kind_food), "service" to stringResource(R.string.host_item_kind_service), "other" to stringResource(R.string.host_item_kind_other)).forEach { (k, t) ->
                            DropdownMenuItem(text = { Text(t) }, onClick = { kind = k; kindMenu = false })
                        }
                    }
                }
                Field(imageURL, { imageURL = it }, stringResource(R.string.venue_form_photo_url))
                UploadButton(stringResource(R.string.host_upload_photo), "image/*", "items") { imageURL = it }
            }
        },
        confirmButton = { TextButton(enabled = name.isNotBlank(), onClick = { host.addItem(venueID, name, emoji, kind, imageURL); onDismiss() }) { Text(stringResource(R.string.action_add)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_cancel)) } },
    )
}

// MARK: - Scanner (camera QR + manual code → scanCoupon Cloud Function)

@Composable
fun HostScannerDialog(host: HostViewModel, fixedVenueID: String?, onDismiss: () -> Unit) {
    val c = AyantTheme.colors
    val context = LocalContext.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val couponService = remember { kg.ayant.app.core.AppConfig.makeCouponService() }
    val authService = remember { kg.ayant.app.core.AppConfig.makeAuthService() }
    var code by remember { mutableStateOf("") }
    var venueID by remember { mutableStateOf(fixedVenueID ?: host.venues.firstOrNull()?.id ?: "") }
    var venueMenu by remember { mutableStateOf(false) }
    var manual by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var result by remember { mutableStateOf<String?>(null) }
    var success by remember { mutableStateOf(true) }

    fun redeem(scanned: String) {
        if (scanned.isBlank() || venueID.isBlank() || busy) return
        busy = true; result = null
        scope.launch {
            val token = authService.idToken() ?: ""
            val o = couponService.scanCoupon(scanned.trim(), venueID, token)
            success = o.ok
            result = when {
                !o.ok -> context.getString(R.string.host_scan_error, o.errorCode ?: context.getString(R.string.host_scan_failed))
                o.loyalty -> context.getString(R.string.host_scan_stamp, o.stamps, o.goal) + if (o.rewardIssued) context.getString(R.string.host_scan_reward_suffix, o.rewardTitle) else ""
                else -> context.getString(R.string.host_scan_redeemed, o.title)
            }
            busy = false
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.host_scan_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (fixedVenueID == null && host.venues.size > 1) {
                    Box {
                        OutlinedField(stringResource(R.string.venue_section), host.venue(venueID)?.name ?: stringResource(R.string.action_choose)) { venueMenu = true }
                        DropdownMenu(expanded = venueMenu, onDismissRequest = { venueMenu = false }) {
                            host.venues.forEach { v -> DropdownMenuItem(text = { Text(v.name) }, onClick = { venueID = v.id; venueMenu = false }) }
                        }
                    }
                }
                if (!manual && result == null) {
                    QrScannerView(onResult = { code = it; redeem(it) }, onNoPermission = { manual = true })
                    Text(stringResource(R.string.host_scan_hint), fontSize = 13.sp, color = c.inkSoft)
                    Text(stringResource(R.string.host_scan_manual), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = c.accent, modifier = Modifier.clickable { manual = true })
                } else if (result == null) {
                    Field(code, { code = it }, stringResource(R.string.host_scan_code))
                }
                if (busy) Text(stringResource(R.string.host_scan_checking), fontSize = 13.sp, color = c.inkSoft)
                result?.let { Text(it, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = if (success) c.open else Color(0xFFD32F2F)) }
            }
        },
        confirmButton = {
            if (result == null && manual) {
                TextButton(enabled = code.isNotBlank() && !busy, onClick = { redeem(code) }) { Text(stringResource(R.string.host_scan_redeem)) }
            } else {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_done)) }
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_close)) } },
    )
}

@Composable
private fun OutlinedField(label: String, value: String, onClick: () -> Unit) {
    OutlinedTextField(
        value = value, onValueChange = {}, readOnly = true, enabled = false, label = { Text(label) },
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    )
}

// MARK: - Shared form helpers

@Composable
private fun FormDialog(
    title: String,
    onDismiss: () -> Unit,
    canSave: Boolean,
    onSave: () -> Unit,
    content: @Composable () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) { content() } },
        confirmButton = { TextButton(enabled = canSave, onClick = onSave) { Text(stringResource(R.string.action_save)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_cancel)) } },
    )
}

@Composable
private fun Field(
    value: String, onChange: (String) -> Unit, label: String,
    keyboard: KeyboardType = KeyboardType.Text, modifier: Modifier = Modifier, enabled: Boolean = true,
) {
    OutlinedTextField(
        value = value, onValueChange = onChange, label = { Text(label) }, singleLine = true, enabled = enabled,
        keyboardOptions = KeyboardOptions(keyboardType = keyboard),
        modifier = modifier.fillMaxWidth(),
    )
}

@Composable
private fun ToggleRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, fontSize = 15.sp, color = AyantTheme.colors.ink, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}
