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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.domain.model.AdCampaign
import kg.ayant.app.domain.model.Review
import kg.ayant.app.ui.components.StarRating
import kg.ayant.app.ui.theme.AyantScreenTitle
import kg.ayant.app.ui.theme.AyantSectionHeader
import kg.ayant.app.ui.theme.AyantHairline
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantCard
import kg.ayant.app.ui.theme.ayantGroupCard
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.domain.HostIntent
import kg.ayant.app.ui.vm.HostViewModel
import kg.ayant.app.ui.vm.SessionViewModel
import java.util.Date

// MARK: - Promote

@Composable
fun HostPromoteScreen(host: HostViewModel) {
    val hostState by host.state.collectAsState()
    val c = AyantTheme.colors
    var showCreate by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().background(c.canvas).verticalScroll(rememberScrollState()).padding(16.dp).padding(bottom = 28.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Text(
            stringResource(R.string.htab_promote), fontSize = 42.sp, fontWeight = FontWeight.Black,
            letterSpacing = (-2.3).sp, lineHeight = 40.sp, color = c.ink,
        )
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(24.dp)).background(c.accentGradient).padding(20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(stringResource(R.string.promote_hero_title), fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Color.White)
            Text(stringResource(R.string.promote_hero_body), fontSize = 14.sp, color = Color.White.copy(alpha = 0.9f))
            Text(
                if (hostState.venues.isEmpty()) stringResource(R.string.promote_add_venue_first) else stringResource(R.string.promote_launch),
                fontSize = 16.sp, fontWeight = FontWeight.Bold, color = c.accentDeep,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Color.White).clickable(enabled = hostState.venues.isNotEmpty()) { showCreate = true }.padding(vertical = 14.dp),
            )
        }
        // Type cards (like iOS: Буст / Push)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            PromoTypeCard(stringResource(R.string.promote_type_boost), stringResource(R.string.promote_type_boost_sub), Modifier.weight(1f)) { if (hostState.venues.isNotEmpty()) showCreate = true }
            PromoTypeCard(stringResource(R.string.promote_type_push), stringResource(R.string.promote_type_push_sub), Modifier.weight(1f)) { if (hostState.venues.isNotEmpty()) showCreate = true }
        }
        if (hostState.campaigns.isEmpty()) {
            Text(stringResource(R.string.promote_empty), fontSize = 14.sp, color = c.inkSoft, modifier = Modifier.fillMaxWidth().ayantGroupCard().padding(16.dp))
        } else {
            Text(stringResource(R.string.promote_your_campaigns), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink)
            hostState.campaigns.forEach { CampaignCard(it, host) }
        }
    }
    if (showCreate) HostPromoteCreateDialog(host) { showCreate = false }
}

@Composable
private fun PromoTypeCard(title: String, subtitle: String, modifier: Modifier, onClick: () -> Unit) {
    val c = AyantTheme.colors
    Column(modifier.ayantCard().clickable(onClick = onClick), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(Icons.Filled.Campaign, null, tint = c.accent, modifier = Modifier.size(28.dp))
        Text(title, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = c.ink)
        Text(subtitle, fontSize = 12.sp, color = c.inkSoft)
    }
}

@Composable
private fun CampaignCard(c0: AdCampaign, host: HostViewModel) {
    val hostState by host.state.collectAsState()
    val c = AyantTheme.colors
    val status = c0.effectiveStatus
    Column(Modifier.fillMaxWidth().ayantCard(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(c0.kind.title, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = c.ink)
                Text(hostState.venue(c0.venueID)?.name ?: stringResource(R.string.venue_section), fontSize = 13.sp, color = c.inkSoft)
            }
            val col = if (status.isLive) c.open else c.inkSoft
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.clip(RoundedCornerShape(50)).background(col.copy(alpha = 0.14f)).padding(horizontal = 9.dp, vertical = 5.dp)) {
                Box(Modifier.size(6.dp).clip(CircleShape).background(col))
                Text(" ${status.title}", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = col)
            }
        }
        val days = maxOf(1, ((Date().time - c0.startAt.time) / 86_400_000L).toInt())
        Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
            Text("👁 ${host.stat(c0.venueID, "views", days)}", fontSize = 14.sp, color = c.inkSoft)
            Text("👆 ${host.stat(c0.venueID, "dealTaps", days)}", fontSize = 14.sp, color = c.inkSoft)
            Text(stringResource(R.string.promote_spend, c0.spend), fontSize = 14.sp, color = c.inkSoft)
        }
        if (status == AdCampaign.Status.ACTIVE || status == AdCampaign.Status.SCHEDULED) {
            PillBtn(stringResource(R.string.promote_cancel_campaign)) { host.send(HostIntent.CancelCampaign(c0.id)) }
        }
    }
}

@Composable
private fun HostPromoteCreateDialog(host: HostViewModel, onDismiss: () -> Unit) {
    val hostState by host.state.collectAsState()
    val c = AyantTheme.colors
    val context = LocalContext.current
    var venueID by remember { mutableStateOf(hostState.venues.firstOrNull()?.id ?: "") }
    var venueMenu by remember { mutableStateOf(false) }
    var boost by remember { mutableStateOf(true) }
    var duration by remember { mutableIntStateOf(7) }
    var dealID by remember { mutableStateOf("") }
    var dealMenu by remember { mutableStateOf(false) }
    var headline by remember { mutableStateOf("") }
    var body by remember { mutableStateOf("") }
    fun price(d: Int) = if (d == 0) 3000 else d * 150
    val venueDeals = hostState.deals(forVenue = venueID)

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.promote_new_campaign)) },
        text = {
            Column(Modifier.verticalScroll(androidx.compose.foundation.rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                // Venue picker
                Box {
                    OutlinedField(stringResource(R.string.venue_section), hostState.venue(venueID)?.name ?: stringResource(R.string.action_choose)) { venueMenu = true }
                    DropdownMenu(expanded = venueMenu, onDismissRequest = { venueMenu = false }) {
                        hostState.venues.forEach { v -> DropdownMenuItem(text = { Text(v.name) }, onClick = { venueID = v.id; venueMenu = false }) }
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    PillBtn(if (boost) "● " + stringResource(R.string.promote_type_boost) else stringResource(R.string.promote_type_boost), Modifier.weight(1f), accent = boost) { boost = true }
                    PillBtn(if (!boost) "● " + stringResource(R.string.promote_type_push) else stringResource(R.string.promote_type_push), Modifier.weight(1f), accent = !boost) { boost = false }
                }
                if (boost) {
                    Text(stringResource(R.string.promote_duration), fontSize = 13.sp, color = c.inkSoft)
                    listOf(7, 14, 30).forEach { d ->
                        PillBtn(stringResource(R.string.promote_days_price, d, price(d)), accent = duration == d) { duration = d }
                    }
                } else {
                    Box {
                        val dealTitle = venueDeals.firstOrNull { it.id == dealID }?.title ?: stringResource(R.string.promote_all_venue)
                        OutlinedField(stringResource(R.string.promote_what), dealTitle) { dealMenu = true }
                        DropdownMenu(expanded = dealMenu, onDismissRequest = { dealMenu = false }) {
                            DropdownMenuItem(text = { Text(stringResource(R.string.promote_all_venue)) }, onClick = { dealID = ""; dealMenu = false })
                            venueDeals.forEach { d ->
                                DropdownMenuItem(text = { Text(d.title) }, onClick = {
                                    dealID = d.id; headline = d.title.take(60); body = d.details.take(120); dealMenu = false
                                })
                            }
                        }
                    }
                    OutlinedTextField(headline, { if (it.length <= 60) headline = it }, label = { Text(stringResource(R.string.promote_headline)) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(body, { if (it.length <= 120) body = it }, label = { Text(stringResource(R.string.promote_text)) }, minLines = 2, modifier = Modifier.fillMaxWidth())
                }
            }
        },
        confirmButton = {
            TextButton(enabled = venueID.isNotEmpty(), onClick = {
                val end = Date(System.currentTimeMillis() + (if (boost) duration else 1) * 86_400_000L)
                host.send(HostIntent.AddCampaign(AdCampaign(
                    id = host.campaignID(),
                    kind = if (boost) AdCampaign.Kind.BOOST else AdCampaign.Kind.PUSH,
                    venueID = venueID,
                    status = if (boost) AdCampaign.Status.ACTIVE else AdCampaign.Status.SENT,
                    startAt = Date(), endAt = end, impressions = 0, taps = 0,
                    spend = if (boost) price(duration) else 100,
                )))
                if (boost) host.send(HostIntent.BoostVenue(venueID, end)) else {
                    val vname = hostState.venue(venueID)?.name ?: "заведение"
                    host.send(HostIntent.LaunchPush(
                        headline = headline.ifBlank { vname },
                        body = body.ifBlank { context.getString(R.string.promote_push_default_body, vname) },
                        venueID = venueID,
                        dealID = dealID.ifBlank { null },
                    ))
                }
                onDismiss()
            }) { Text(if (boost) stringResource(R.string.promote_pay_launch) else stringResource(R.string.promote_send_push)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_cancel)) } },
    )
}

@Composable
private fun OutlinedField(label: String, value: String, onClick: () -> Unit) {
    OutlinedTextField(
        value = value, onValueChange = {}, readOnly = true, enabled = false, label = { Text(label) },
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    )
}

// MARK: - Analytics

@Composable
fun HostAnalyticsScreen(host: HostViewModel) {
    val hostState by host.state.collectAsState()
    val c = AyantTheme.colors
    var period by remember { mutableIntStateOf(30) }
    var loading by remember { mutableStateOf(false) }
    var series by remember { mutableStateOf<List<Int>>(emptyList()) }
    val statsByVenue = remember { androidx.compose.runtime.mutableStateMapOf<String, Map<String, Int>>() }

    androidx.compose.runtime.LaunchedEffect(period, hostState.venues.size) {
        loading = true
        val daily = mutableMapOf<String, Int>()
        hostState.venues.forEach { v ->
            val remote = host.statsRemote(v.id, period)
            statsByVenue[v.id] = remote.ifEmpty {
                listOf("views", "redemptions", "dealTaps", "saves", "calls", "maps")
                    .associateWith { host.stat(v.id, it, period) }
            }
            host.dailyRemote(v.id, period).forEach { (day, metrics) ->
                daily[day] = (daily[day] ?: 0) + (metrics["views"] ?: 0)
            }
        }
        series = analyticsBuckets(daily, period)
        loading = false
    }

    fun total(metric: String) = hostState.venues.sumOf { statsByVenue[it.id]?.get(metric) ?: 0 }

    Column(
        Modifier.fillMaxSize().background(c.canvas).verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Text(
            stringResource(R.string.htab_analytics), fontSize = 42.sp,
            fontWeight = FontWeight.Black, letterSpacing = (-2.3).sp, lineHeight = 40.sp, color = c.ink,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(7, 30, 90).forEach { d ->
                PillBtn(stringResource(R.string.analytics_days, d), Modifier.weight(1f), accent = period == d) { period = d }
            }
        }
        if (hostState.venues.isEmpty()) {
            Text(stringResource(R.string.analytics_empty), fontSize = 14.sp, color = c.inkSoft,
                modifier = Modifier.fillMaxWidth().ayantGroupCard().padding(16.dp))
        } else {
            // Герой + график
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(28.dp))
                    .background(c.accentGradient).padding(22.dp),
            ) {
                Text(stringResource(R.string.analytics_profile_views), fontSize = 13.5.sp,
                    fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.9f))
                Text(
                    "${total("views")}", fontSize = 48.sp, fontWeight = FontWeight.Black,
                    letterSpacing = (-2.6).sp, lineHeight = 48.sp, color = Color.White,
                )
                Text(
                    if (loading) stringResource(R.string.analytics_loading)
                    else stringResource(R.string.analytics_for_days, period),
                    fontSize = 12.5.sp, color = Color.White.copy(alpha = 0.85f),
                )
                if (series.isNotEmpty()) {
                    Spacer(Modifier.height(20.dp))
                    AnalyticsBarChart(series, period)
                }
            }
            val metrics = listOf(
                stringResource(R.string.analytics_redemptions) to "redemptions",
                stringResource(R.string.analytics_deal_taps) to "dealTaps",
                stringResource(R.string.analytics_saves) to "saves",
                stringResource(R.string.analytics_calls) to "calls",
                stringResource(R.string.analytics_maps) to "maps",
            )
            LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                modifier = Modifier.fillMaxWidth().height(330.dp),
                horizontalArrangement = Arrangement.spacedBy(11.dp),
                verticalArrangement = Arrangement.spacedBy(11.dp),
                userScrollEnabled = false,
            ) {
                items(metrics) { (title, key) ->
                    Column(Modifier.fillMaxWidth().ayantCard(padding = 14, radius = 22)) {
                        Text(
                            "${total(key)}", fontSize = 26.sp, fontWeight = FontWeight.Black,
                            letterSpacing = (-1.1).sp, color = c.ink,
                        )
                        Text(title, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = c.inkSoft)
                    }
                }
            }
            Text(
                stringResource(R.string.analytics_by_venue).uppercase(), fontSize = 11.5.sp,
                fontWeight = FontWeight.Black, letterSpacing = 1.2.sp, color = Color(0xFF9A9188),
            )
            Column(Modifier.fillMaxWidth().ayantGroupCard(radius = 22)) {
                hostState.venues.forEachIndexed { index, v ->
                    if (index > 0) AyantHairline(leading = 16)
                    val st = statsByVenue[v.id]
                    Row(
                        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(v.name, fontSize = 14.5.sp, fontWeight = FontWeight.Bold, color = c.ink)
                            Text(
                                stringResource(R.string.analytics_redeemed_count, st?.get("redemptions") ?: 0),
                                fontSize = 12.sp, color = c.inkSoft,
                            )
                        }
                        Column(horizontalAlignment = Alignment.End) {
                            Text("${st?.get("views") ?: 0}", fontSize = 17.sp,
                                fontWeight = FontWeight.Black, color = c.ink)
                            Text(stringResource(R.string.analytics_views_word), fontSize = 11.sp, color = c.inkSoft)
                        }
                    }
                }
            }
        }
    }
}

/**
 * Ряд по дням → столбики: 7 дней = 7 столбиков, иначе 12 равных корзин.
 * Пустой ряд → пустой список, и график не рисуется вовсе. Зеркалит
 * `HostAnalyticsView.buckets` на iOS.
 */
fun analyticsBuckets(daily: Map<String, Int>, period: Int): List<Int> {
    if (daily.isEmpty()) return emptyList()
    val ordered = daily.keys.sorted().map { daily[it] ?: 0 }
    val count = if (period <= 7) minOf(7, ordered.size) else 12
    if (ordered.size <= count) return ordered
    val size = ordered.size.toDouble() / count
    return (0 until count).map { i ->
        val lo = (i * size).toInt()
        val hi = minOf(ordered.size, ((i + 1) * size).toInt())
        ordered.subList(lo, maxOf(hi, lo + 1)).sum()
    }
}

/** 12 (или 7) столбиков с шагом 45 мс (ANIMATIONS.md §6). */
@Composable
private fun AnalyticsBarChart(values: List<Int>, period: Int) {
    val reduceMotion = kg.ayant.app.ui.theme.rememberReduceMotion()
    val maxValue = (values.maxOrNull() ?: 1).coerceAtLeast(1)
    val grown = remember(period) { androidx.compose.animation.core.Animatable(if (reduceMotion) 1f else 0f) }
    androidx.compose.runtime.LaunchedEffect(period) {
        if (!reduceMotion) grown.animateTo(1f, androidx.compose.animation.core.tween(700, easing = kg.ayant.app.ui.theme.AyantMotion.EnterEasing))
    }
    Row(
        Modifier.fillMaxWidth().height(74.dp),
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        values.forEachIndexed { i, v ->
            // Шаг 45 мс отражён сдвигом фазы: столбик i стартует чуть позже.
            val phase = ((grown.value * values.size) - i).coerceIn(0f, 1f)
            val h = (74f * (v.toFloat() / maxValue) * phase).coerceAtLeast(4f)
            Box(
                Modifier.weight(1f).height(h.dp)
                    .clip(RoundedCornerShape(topStart = 5.dp, topEnd = 5.dp, bottomStart = 2.dp, bottomEnd = 2.dp))
                    .background(Color.White.copy(alpha = 0.55f))
            )
        }
    }
}

// MARK: - Reviews inbox

@Composable
fun HostReviewsScreen(host: HostViewModel, app: AppViewModel) {
    val hostState by host.state.collectAsState()
    val feedState by app.feedState.collectAsState()
    val c = AyantTheme.colors
    var replyTo by remember { mutableStateOf<Review?>(null) }
    var filter by remember { mutableStateOf(0) }   // 0 все · 1 без ответа · 2 низкие

    val all = feedState.reviews(forVenueIDs = hostState.ownedVenueIDs).sortedWith(
        compareByDescending<Review> { it.hostReply == null }.thenByDescending { it.createdAt }
    )
    val pending = all.count { it.hostReply == null }
    val reviews = when (filter) {
        1 -> all.filter { it.hostReply == null }
        2 -> all.filter { it.rating <= 2 }
        else -> all
    }

    Column(
        Modifier.fillMaxSize().background(c.canvas).verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp).padding(top = 12.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                stringResource(R.string.reviews), fontSize = 42.sp, fontWeight = FontWeight.Black,
                letterSpacing = (-2.3).sp, lineHeight = 40.sp, color = c.ink,
            )
            if (pending > 0) {
                Text(
                    stringResource(R.string.host_pending_replies, pending),
                    fontSize = 12.sp, fontWeight = FontWeight.Black, color = Color.White, maxLines = 1,
                    modifier = Modifier.clip(CircleShape).background(c.accentDeep)
                        .padding(horizontal = 11.dp, vertical = 6.dp),
                )
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(
                stringResource(R.string.filter_all) to 0,
                stringResource(R.string.filter_unanswered) to 1,
                stringResource(R.string.filter_low_rating) to 2,
            ).forEach { (label, value) ->
                val isOn = filter == value
                Text(
                    label, fontSize = 13.sp, fontWeight = FontWeight.Bold,
                    color = if (isOn) Color.White else c.inkSoft,
                    modifier = Modifier
                        .clip(CircleShape)
                        .then(if (isOn) Modifier.background(c.accentGradient) else Modifier.background(c.surface))
                        .clickable { filter = value }
                        .padding(horizontal = 15.dp, vertical = 9.dp),
                )
            }
        }

        if (reviews.isEmpty()) {
            Text(stringResource(R.string.host_reviews_empty), fontSize = 14.sp, color = c.inkSoft,
                modifier = Modifier.fillMaxWidth().ayantGroupCard(radius = 22).padding(16.dp))
        } else {
            reviews.forEach { r ->
                Column(
                    Modifier.fillMaxWidth().ayantCard(padding = 15, radius = 22),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Box(
                            Modifier.size(38.dp).clip(CircleShape).background(c.accentGradient),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(r.authorName.take(1).uppercase(), fontSize = 15.sp,
                                fontWeight = FontWeight.Black, color = Color.White)
                        }
                        Column(Modifier.weight(1f)) {
                            Text(r.authorName, fontSize = 14.5.sp, fontWeight = FontWeight.Bold, color = c.ink)
                            Text(
                                "${app.venue(id = r.venueID)?.name ?: stringResource(R.string.venue_section)}",
                                fontSize = 11.5.sp, color = Color(0xFF9A9188),
                            )
                        }
                        // Низкие оценки красим иначе — их видно в списке сразу.
                        Text(
                            "★".repeat(r.rating.coerceIn(1, 5)),
                            fontSize = 13.5.sp, fontWeight = FontWeight.Black,
                            color = if (r.rating <= 2) Color(0xFFE8556B) else Color(0xFFFF9500),
                        )
                    }
                    if (r.text.isNotEmpty()) {
                        Text(r.text, fontSize = 14.sp, lineHeight = 21.sp, color = Color(0xFF3D362F))
                    }
                    val reply = r.hostReply
                    if (reply != null && reply.text.isNotEmpty()) {
                        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(c.canvas)) {
                            Box(Modifier.width(3.dp).height(56.dp).background(c.accent))
                            Column(Modifier.padding(14.dp)) {
                                Text(
                                    stringResource(R.string.host_your_reply).uppercase(), fontSize = 11.sp,
                                    fontWeight = FontWeight.Black, letterSpacing = 0.9.sp, color = c.accentText,
                                )
                                Text(reply.text, fontSize = 13.5.sp, color = c.inkSoft,
                                    modifier = Modifier.padding(top = 5.dp))
                            }
                        }
                    } else {
                        Text(
                            stringResource(R.string.host_reply), fontSize = 13.sp,
                            fontWeight = FontWeight.Bold, color = c.accentText,
                            modifier = Modifier.clip(CircleShape)
                                .background(c.accent.copy(alpha = 0.12f))
                                .clickable { replyTo = r }
                                .padding(horizontal = 15.dp, vertical = 9.dp),
                        )
                    }
                }
            }
        }
    }

    replyTo?.let { review -> HostReplySheet(review, app) { replyTo = null } }
}

/** Ответ на отзыв (SCREENS.md H11). */
@Composable
private fun HostReplySheet(review: Review, app: AppViewModel, onDismiss: () -> Unit) {
    val c = AyantTheme.colors
    var text by remember { mutableStateOf(review.hostReply?.text ?: "") }
    val quick = listOf(
        stringResource(R.string.quick_thanks),
        stringResource(R.string.quick_sorry_wait),
        stringResource(R.string.quick_come_again),
        stringResource(R.string.quick_dm_us),
    )
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.host_reply_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                // Цитата отзыва
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp))
                    .background(c.surfaceMuted).padding(14.dp)) {
                    Text(review.authorName, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = c.ink)
                    if (review.text.isNotEmpty()) {
                        Text(review.text, fontSize = 13.5.sp, lineHeight = 20.sp, color = c.inkSoft,
                            modifier = Modifier.padding(top = 6.dp))
                    }
                }
                OutlinedTextField(
                    text, { text = it },
                    label = { Text(stringResource(R.string.host_reply_hint)) },
                    minLines = 3, modifier = Modifier.fillMaxWidth(),
                )
                // Быстрые ответы дополняют поле, а не заменяют его.
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    quick.chunked(2).forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            row.forEach { phrase ->
                                Text(
                                    phrase, fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold,
                                    color = c.ink, maxLines = 1,
                                    modifier = Modifier.weight(1f).clip(CircleShape)
                                        .background(c.surface)
                                        .clickable { text = if (text.isBlank()) phrase else "$text $phrase" }
                                        .padding(horizontal = 12.dp, vertical = 10.dp),
                                )
                            }
                            repeat(2 - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(enabled = text.isNotBlank(), onClick = { app.setHostReply(review.id, text); onDismiss() }) {
                Text(stringResource(R.string.host_send_reply))
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_cancel)) } },
    )
}

// MARK: - Host profile

@Composable
fun HostProfileScreen(host: HostViewModel, session: SessionViewModel, onExitHost: () -> Unit) {
    val hostState by host.state.collectAsState()
    val c = AyantTheme.colors
    val p = hostState.profile
    var showInfo by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxSize().background(c.canvas).verticalScroll(rememberScrollState()).padding(16.dp).padding(bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(22.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                stringResource(R.string.hprofile_title), fontSize = 42.sp, fontWeight = FontWeight.Black,
                letterSpacing = (-2.3).sp, lineHeight = 40.sp, color = c.ink,
            )
            if (hostState.profile?.verification == kg.ayant.app.domain.model.VerificationStatus.VERIFIED) {
                Text(
                    stringResource(R.string.host_verified), fontSize = 12.sp,
                    fontWeight = FontWeight.Bold, color = c.open, maxLines = 1,
                    modifier = Modifier.clip(CircleShape).background(c.open.copy(alpha = 0.12f))
                        .padding(horizontal = 11.dp, vertical = 6.dp),
                )
            }
        }
        Row(Modifier.fillMaxWidth().ayantCard(padding = 16), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(64.dp).clip(RoundedCornerShape(18.dp)).background(c.accentGradient), contentAlignment = Alignment.Center) {
                Text((p?.businessName ?: "Б").take(1).uppercase(), fontSize = 28.sp, fontWeight = FontWeight.Black, color = Color.White)
            }
            Column(Modifier.padding(start = 14.dp)) {
                Text(p?.businessName?.ifEmpty { stringResource(R.string.hprofile_your_business) } ?: stringResource(R.string.hprofile_your_business), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = c.ink)
                Text(p?.verification?.title ?: stringResource(R.string.hprofile_unverified), fontSize = 13.sp, color = c.inkSoft)
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            AyantSectionHeader(stringResource(R.string.hprofile_business_info))
            Row(Modifier.fillMaxWidth().ayantGroupCard().clickable { showInfo = true }.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.hprofile_details_contacts), fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = c.ink)
                    Text(if (p?.inn?.isNotEmpty() == true) stringResource(R.string.hprofile_inn, p.inn) else stringResource(R.string.hprofile_fill_details), fontSize = 13.sp, color = c.inkSoft)
                }
                Text("›", fontSize = 22.sp, color = c.inkSoft)
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            AyantSectionHeader(stringResource(R.string.hprofile_verification))
            Column(Modifier.fillMaxWidth().ayantGroupCard().padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(if (p?.verification == kg.ayant.app.domain.model.VerificationStatus.VERIFIED) stringResource(R.string.hprofile_verified) else stringResource(R.string.hprofile_unverified), fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = c.ink)
                Text(stringResource(R.string.hprofile_verify_hint), fontSize = 13.sp, color = c.inkSoft)
                if (p?.verification == kg.ayant.app.domain.model.VerificationStatus.NONE) {
                    PillBtn(stringResource(R.string.hprofile_request_verify), accent = true) { host.send(HostIntent.RequestVerification) }
                }
            }
        }

        // Notifications
        var notify by remember { mutableStateOf(true) }
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            AyantSectionHeader(stringResource(R.string.hprofile_notifications))
            Row(Modifier.fillMaxWidth().ayantGroupCard().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.hprofile_notif_desc), fontSize = 15.sp, color = c.ink, modifier = Modifier.weight(1f))
                androidx.compose.material3.Switch(checked = notify, onCheckedChange = { notify = it })
            }
        }

        // Payment
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            AyantSectionHeader(stringResource(R.string.hprofile_payment))
            Column(Modifier.fillMaxWidth().ayantGroupCard().padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.hprofile_payment_method), fontSize = 16.sp, color = c.ink, modifier = Modifier.weight(1f))
                    Text("Payme / Click", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = c.inkSoft)
                }
                Text(stringResource(R.string.hprofile_payment_hint), fontSize = 13.sp, color = c.inkSoft)
            }
        }

        PillBtn(stringResource(R.string.hprofile_exit_host), Modifier.fillMaxWidth()) { onExitHost() }
        Text(
            stringResource(R.string.account_sign_out), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Color(0xFFD32F2F),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Color(0xFFD32F2F).copy(alpha = 0.1f)).clickable { session.signOut() }.padding(vertical = 14.dp),
        )
    }
    if (showInfo) HostBusinessInfoDialog(host) { showInfo = false }
}

@Composable
private fun HostBusinessInfoDialog(host: HostViewModel, onDismiss: () -> Unit) {
    val hostState by host.state.collectAsState()
    val p = hostState.profile
    var name by remember { mutableStateOf(p?.businessName ?: "") }
    var phone by remember { mutableStateOf(p?.phone ?: "") }
    var email by remember { mutableStateOf(p?.email ?: "") }
    var inn by remember { mutableStateOf(p?.inn ?: "") }
    var about by remember { mutableStateOf(p?.about ?: "") }
    var category by remember { mutableStateOf(p?.category ?: kg.ayant.app.domain.model.VenueCategory.CAFE) }
    var legalForm by remember { mutableStateOf(p?.legalForm ?: "") }
    var legalName by remember { mutableStateOf(p?.legalName ?: "") }
    var regAddress by remember { mutableStateOf(p?.registrationAddress ?: "") }
    var website by remember { mutableStateOf(p?.website ?: "") }
    var formMenu by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.hprofile_business_info)) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(name, { name = it }, label = { Text(stringResource(R.string.venue_form_name)) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                CategoryDropdown(category) { category = it }
                OutlinedTextField(phone, { phone = it }, label = { Text(stringResource(R.string.venue_form_phone)) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(email, { email = it }, label = { Text(stringResource(R.string.hprofile_email)) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                Box {
                    OutlinedField(stringResource(R.string.hprofile_legal_form), legalForm.ifEmpty { stringResource(R.string.hprofile_not_specified) }) { formMenu = true }
                    androidx.compose.material3.DropdownMenu(expanded = formMenu, onDismissRequest = { formMenu = false }) {
                        listOf("", "ИП", "ООО", "Самозанятый").forEach { f ->
                            androidx.compose.material3.DropdownMenuItem(text = { Text(f.ifEmpty { stringResource(R.string.hprofile_not_specified) }) }, onClick = { legalForm = f; formMenu = false })
                        }
                    }
                }
                OutlinedTextField(legalName, { legalName = it }, label = { Text(if (legalForm == "ООО") stringResource(R.string.hprofile_legal_name) else stringResource(R.string.hprofile_entrepreneur_name)) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(inn, { inn = it }, label = { Text(stringResource(R.string.hprofile_inn_label)) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(regAddress, { regAddress = it }, label = { Text(stringResource(R.string.hprofile_legal_address)) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(website, { website = it }, label = { Text(stringResource(R.string.hprofile_website)) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(about, { about = it }, label = { Text(stringResource(R.string.hprofile_about)) }, minLines = 2, modifier = Modifier.fillMaxWidth())
            }
        },
        confirmButton = { TextButton(onClick = {
            host.updateBusinessInfo(name, category, phone, email, legalForm, legalName, inn, regAddress, website, about)
            onDismiss()
        }) { Text(stringResource(R.string.action_save)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_cancel)) } },
    )
}
