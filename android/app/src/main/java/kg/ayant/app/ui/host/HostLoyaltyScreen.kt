package kg.ayant.app.ui.host

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
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
import kg.ayant.app.domain.PointsConfig
import kg.ayant.app.domain.PointsMath
import kg.ayant.app.domain.model.HostVenueDTO
import kg.ayant.app.domain.model.PointsReward
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenueCategory
import kg.ayant.app.domain.model.VenuePointsCard
import kg.ayant.app.ui.bonus.WalletPointsCard
import kg.ayant.app.ui.theme.AyantMetrics
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantSandPanel
import kg.ayant.app.ui.vm.HostViewModel
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import kotlin.math.roundToInt
import kg.ayant.app.domain.HostForms
import kg.ayant.app.domain.HostIntent
import androidx.compose.ui.focus.onFocusChanged

/**
 * «Лояльность» — the host flagship (SCREENS.md H6). Mirrors `HostLoyaltyView.swift`.
 *
 * Both the pitch that wins a venue and the configuration surface. The section
 * order is deliberate: value first, controls second.
 *
 * IMPORTANT: the points config is **read-only** on the host side — the admin
 * panel owns it and the host save path must not write it (see CLAUDE.md). Modes,
 * rewards and rules are shown, not edited; making them writable is a Firestore
 * rules + `HostForms` change, not a UI decision. The calculator previews through
 * `PointsMath`.
 */
@Composable
fun HostLoyaltyScreen(host: HostViewModel) {
    val c = AyantTheme.colors
    val hostState by host.state.collectAsState()
    var selectedVenueID by remember { mutableStateOf<String?>(null) }
    var calcPercent by remember { mutableDoubleStateOf(5.0) }
    val bill = 1_200

    val venue: HostVenueDTO? = hostState.venues.firstOrNull { it.id == selectedVenueID }
        ?: hostState.venues.firstOrNull()

    Scaffold(containerColor = c.canvas) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(bottom = padding.calculateBottomPadding())
                .verticalScroll(rememberScrollState())
                .padding(horizontal = AyantMetrics.screenPadding)
                .padding(top = 12.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            // 1. Заголовок
            Column {
                Text(
                    stringResource(R.string.host_loyalty_title), fontSize = 42.sp,
                    fontWeight = FontWeight.Black, letterSpacing = (-2.3).sp,
                    lineHeight = 40.sp, color = c.ink,
                )
                Text(
                    stringResource(R.string.host_loyalty_sub),
                    fontSize = 14.sp, lineHeight = 20.sp, color = c.inkSoft,
                    modifier = Modifier.widthIn(max = 290.dp).padding(top = 9.dp),
                )
                if (hostState.venues.size > 1) {
                    Spacer(Modifier.height(14.dp))
                    Row(
                        Modifier.horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        hostState.venues.forEach { v ->
                            val isOn = v.id == venue?.id
                            Text(
                                v.name, fontSize = 13.sp, fontWeight = FontWeight.Bold,
                                color = if (isOn) Color.White else c.inkSoft,
                                modifier = Modifier
                                    .clip(CircleShape)
                                    .then(if (isOn) Modifier.background(c.accentGradient) else Modifier.background(c.surface))
                                    .clickable {
                                        selectedVenueID = v.id
                                        if (v.cashbackPercent > 0) calcPercent = v.cashbackPercent
                                    }
                                    .padding(horizontal = 14.dp, vertical = 9.dp),
                            )
                        }
                    }
                }
            }

            // 2. ROI-герой
            Column(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(28.dp))
                    .background(c.accentGradient)
                    .padding(22.dp),
            ) {
                Text(
                    stringResource(R.string.host_loyalty_roi_headline),
                    fontSize = 27.sp, fontWeight = FontWeight.Black,
                    letterSpacing = (-1.3).sp, lineHeight = 30.sp, color = Color.White,
                )
                Spacer(Modifier.height(18.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                    RoiStat("2,4×", stringResource(R.string.host_loyalty_roi_visits), Modifier.weight(1f))
                    RoiStat("+18%", stringResource(R.string.host_loyalty_roi_check), Modifier.weight(1f))
                    RoiStat("412", stringResource(R.string.host_loyalty_roi_cards), Modifier.weight(1f))
                }
                Spacer(Modifier.height(18.dp))
                Text(
                    stringResource(R.string.host_loyalty_no_commission),
                    fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold, lineHeight = 17.sp,
                    color = Color.White.copy(alpha = 0.94f),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(15.dp))
                        .background(Color.White.copy(alpha = 0.18f))
                        .padding(14.dp),
                )
            }

            // 3. Как начисляем
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Eyebrow(stringResource(R.string.host_loyalty_how))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ModeCard(stringResource(R.string.host_mode_flat), stringResource(R.string.host_mode_flat_sub),
                        (venue?.pointsMode ?: "flat") == "flat", Modifier.weight(1f))
                    ModeCard(stringResource(R.string.host_mode_bands), stringResource(R.string.host_mode_bands_sub),
                        venue?.pointsMode == "bands", Modifier.weight(1f))
                    ModeCard(stringResource(R.string.host_mode_cashback), stringResource(R.string.host_mode_cashback_sub),
                        venue?.pointsMode == "cashback", Modifier.weight(1f))
                }
                Text(
                    stringResource(R.string.host_mode_admin_owned),
                    fontSize = 11.5.sp, color = c.inkSoft,
                )
            }

            // 4. Калькулятор. Считает домен — своей формулы здесь нет.
            val award = PointsMath.award(
                config = PointsConfig(pointsEnabled = true, pointsMode = "cashback", cashbackPercent = calcPercent),
                billAmount = bill,
                bandIndex = null,
            ).valueOrNull() ?: 0
            Column(
                Modifier.fillMaxWidth().ayantSandPanel(radius = 26.dp).padding(20.dp),
            ) {
                Text(
                    stringResource(R.string.host_calculator).uppercase(),
                    fontSize = 11.5.sp, fontWeight = FontWeight.Black, letterSpacing = 1.2.sp,
                    color = c.eyebrow,
                )
                Spacer(Modifier.height(14.dp))
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                    Column {
                        Text(stringResource(R.string.host_calc_bill), fontSize = 11.5.sp,
                            fontWeight = FontWeight.Bold, color = c.sandInk)
                        Text(thousands(bill), fontSize = 26.sp, fontWeight = FontWeight.Black, color = c.ink)
                    }
                    Icon(Icons.AutoMirrored.Filled.ArrowForward, null,
                        tint = Color(0xFFC97A3A), modifier = Modifier.size(15.dp))
                    Column {
                        Text(stringResource(R.string.host_calc_guest_gets), fontSize = 11.5.sp,
                            fontWeight = FontWeight.Bold, color = c.sandInk)
                        Text("+$award", fontSize = 26.sp, fontWeight = FontWeight.Black, color = Color(0xFFE04206))
                    }
                }
                Spacer(Modifier.height(16.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(3.0, 5.0, 8.0, 10.0).forEach { p ->
                        val isOn = calcPercent == p
                        Text(
                            "${percentText(p)}%", fontSize = 13.sp, fontWeight = FontWeight.Bold,
                            color = if (isOn) Color.White else c.sandInk,
                            modifier = Modifier
                                .clip(CircleShape)
                                .then(if (isOn) Modifier.background(c.accentGradient)
                                      else Modifier.background(Color.White.copy(alpha = 0.8f)))
                                .clickable { calcPercent = p }
                                .padding(horizontal = 14.dp, vertical = 8.dp),
                        )
                    }
                }
                Spacer(Modifier.height(12.dp))
                Text(
                    stringResource(
                        R.string.host_calc_limits,
                        PointsMath.MAX_CASHBACK_PERCENT.toInt(),
                        PointsMath.effectiveCooldownMinutes(venue?.earnCooldownMinutes ?: PointsMath.DEFAULT_EARN_COOLDOWN_MINUTES),
                    ),
                    fontSize = 11.5.sp, color = c.sandInk, lineHeight = 16.sp,
                )
            }

            // 4.5. Карта штампов — ЕДИНСТВЕННОЕ, что владелец правит сам.
            // Конфиг баллов САН принадлежит админ-панели, поэтому всё выше
            // только показывается. Зеркалит `stampCardSection` в
            // `HostLoyaltyView.swift`.
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Eyebrow(stringResource(R.string.host_stamp_card))
                val v = venue
                if (v == null) {
                    AyantNoteCard(stringResource(R.string.host_stamp_need_venue))
                } else {
                    // Сохраняем ОДНО поле, перенося остальные из DTO: `SaveVenue`
                    // принимает форму целиком.
                    fun commit(change: (HostForms.VenueFields) -> HostForms.VenueFields) {
                        host.send(HostIntent.SaveVenue(v, change(HostForms.fields(v))))
                    }
                    AyantFieldCard {
                        Box(Modifier.padding(horizontal = 16.dp, vertical = 13.dp)) {
                            AyantGradientToggle(
                                title = stringResource(R.string.host_stamp_programme),
                                subtitle = stringResource(R.string.host_stamp_programme_sub),
                                checked = v.loyaltyEnabled,
                                onCheckedChange = { on -> commit { it.copy(loyaltyEnabled = on) } },
                            )
                        }
                        if (v.loyaltyEnabled) {
                            AyantFieldDivider()
                            AyantFieldRow(stringResource(R.string.host_stamp_goal)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(
                                        "${v.loyaltyGoal}",
                                        fontSize = 15.5.sp, fontWeight = FontWeight.SemiBold,
                                        color = c.ink, modifier = Modifier.weight(1f),
                                    )
                                    StepButton("−") { commit { it.copy(loyaltyGoal = (v.loyaltyGoal - 1).coerceAtLeast(2)) } }
                                    Spacer(Modifier.width(8.dp))
                                    StepButton("+") { commit { it.copy(loyaltyGoal = (v.loyaltyGoal + 1).coerceAtMost(20)) } }
                                }
                            }
                            AyantFieldDivider()
                            AyantFieldRow(stringResource(R.string.host_stamp_reward)) {
                                var draft by remember(v.id, v.loyaltyReward) { mutableStateOf(v.loyaltyReward) }
                                AyantFieldInput(
                                    placeholder = stringResource(R.string.host_stamp_reward_hint),
                                    value = draft,
                                    onValueChange = { draft = it },
                                    modifier = Modifier.onFocusChanged { f ->
                                        if (!f.isFocused && draft != v.loyaltyReward) {
                                            commit { it.copy(loyaltyReward = draft) }
                                        }
                                    },
                                )
                            }
                        }
                    }
                    if (v.loyaltyEnabled) {
                        Text(
                            stringResource(R.string.host_stamp_explain, v.loyaltyGoal, v.loyaltyReward),
                            fontSize = 12.5.sp, color = c.inkSoft, lineHeight = 17.sp,
                        )
                    }
                }
            }

            // 5. Награды
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Eyebrow(stringResource(R.string.host_rewards))
                val rewards = venue?.pointsRewards.orEmpty()
                if (rewards.isEmpty()) {
                    Text(
                        stringResource(R.string.host_rewards_empty),
                        fontSize = 13.sp, color = c.inkSoft,
                        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp))
                            .background(c.surface).padding(16.dp),
                    )
                } else {
                    rewards.forEach { RewardRow(it) }
                }
            }

            // 6. Правила
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Eyebrow(stringResource(R.string.host_rules))
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(c.surface)) {
                    RuleRow(
                        stringResource(R.string.host_rule_cooldown), stringResource(R.string.host_rule_cooldown_hint),
                        "${PointsMath.effectiveCooldownMinutes(venue?.earnCooldownMinutes ?: PointsMath.DEFAULT_EARN_COOLDOWN_MINUTES)} мин",
                    )
                    RuleRow(
                        stringResource(R.string.host_rule_expiry), stringResource(R.string.host_rule_expiry_hint),
                        // 0 здесь не значение, а «не настроено» — пол в 1 месяц.
                        "${(venue?.pointsExpiryMonths ?: 0).takeIf { it > 0 } ?: 6} мес",
                    )
                    RuleRow(
                        stringResource(R.string.host_rule_redeem), stringResource(R.string.host_rule_redeem_hint),
                        if ((venue?.redeemMode ?: "staffScan") == "staffScan")
                            stringResource(R.string.host_rule_staff) else stringResource(R.string.host_rule_customer),
                    )
                }
            }

            // 7. Что видит гость — живая связь с калькулятором.
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Eyebrow(stringResource(R.string.host_guest_sees))
                Box(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(30.dp))
                        .background(c.surfaceMuted).padding(6.dp),
                ) {
                    WalletPointsCard(
                        card = VenuePointsCard(
                            venueID = venue?.id.orEmpty(),
                            venueName = venue?.name ?: stringResource(R.string.host_your_venue),
                            balance = 340,
                        ),
                        venue = previewVenue(venue, calcPercent),
                        isFront = true,
                    )
                }
            }
        }
    }
}

@Composable
private fun Eyebrow(text: String) {
    Text(
        text.uppercase(), fontSize = 11.5.sp, fontWeight = FontWeight.Black,
        letterSpacing = 1.2.sp, color = AyantTheme.colors.inkSoft,
    )
}

@Composable
private fun RoiStat(value: String, label: String, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(value, fontSize = 26.sp, fontWeight = FontWeight.Black, color = Color.White)
        Text(label, fontSize = 11.sp, color = Color.White.copy(alpha = 0.9f), lineHeight = 14.sp)
    }
}

@Composable
private fun ModeCard(title: String, sub: String, isOn: Boolean, modifier: Modifier = Modifier) {
    val c = AyantTheme.colors
    Column(
        modifier
            .clip(RoundedCornerShape(18.dp))
            .then(if (isOn) Modifier.background(c.accentGradient)
                  else Modifier.background(c.surface).border(0.5.dp, c.hairline, RoundedCornerShape(18.dp)))
            .padding(13.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(title, fontSize = 13.5.sp, fontWeight = FontWeight.Black,
            color = if (isOn) Color.White else c.ink)
        Text(sub, fontSize = 11.sp, lineHeight = 14.sp,
            color = if (isOn) Color.White.copy(alpha = 0.88f) else c.inkSoft)
    }
}

@Composable
private fun RewardRow(r: PointsReward) {
    val c = AyantTheme.colors
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(c.surface).padding(15.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            Modifier.size(44.dp).clip(RoundedCornerShape(15.dp)).background(c.accentGradient),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Star, null, tint = Color.White, modifier = Modifier.size(18.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(r.title, fontSize = 14.5.sp, fontWeight = FontWeight.Bold, color = c.ink)
            Text("${r.cost} баллов", fontSize = 12.sp, color = c.inkSoft)
        }
        // Read-only: только админ-панель пишет это состояние.
        val tint = if (r.active) c.open else c.inkSoft
        Text(
            if (r.active) stringResource(R.string.host_reward_on) else stringResource(R.string.host_reward_off),
            fontSize = 12.sp, fontWeight = FontWeight.Bold, color = tint,
            modifier = Modifier.clip(CircleShape).background(tint.copy(alpha = 0.12f))
                .padding(horizontal = 11.dp, vertical = 6.dp),
        )
    }
}

@Composable
private fun RuleRow(title: String, hint: String, value: String) {
    val c = AyantTheme.colors
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 14.5.sp, fontWeight = FontWeight.SemiBold, color = c.ink)
            Text(hint, fontSize = 11.5.sp, color = c.inkSoft, lineHeight = 15.sp)
        }
        Text(value, fontSize = 14.5.sp, fontWeight = FontWeight.Black,
            color = c.accentTextStrong, maxLines = 1)
    }
}

/** Доменное заведение для превью: конфиг текущего + процент из калькулятора. */
private fun previewVenue(dto: HostVenueDTO?, percent: Double): Venue? {
    if (dto == null) return null
    return Venue(
        id = dto.id, name = dto.name, category = VenueCategory("Кафе"), district = "",
        address = "", phone = "", emoji = "⭐️",
        gradient = listOf(0xFFFF5A1FL, 0xFFFF9500L),   // бренд-градиент, как в маппере
        pointsEnabled = true,
        pointsMode = dto.pointsMode,
        pointsFlat = dto.pointsFlat,
        cashbackPercent = percent,
        pointsRewards = dto.pointsRewards,
    )
}

/** Русские тысячи тонким пробелом: «1 200». */
private fun thousands(v: Int): String {
    val symbols = DecimalFormatSymbols().apply { groupingSeparator = ' ' }
    return DecimalFormat("#,###", symbols).format(v)
}

private fun percentText(v: Double): String =
    if (v == v.roundToInt().toDouble()) v.roundToInt().toString()
    else String.format("%.1f", v).replace('.', ',')

/** Кнопка «+»/«−» для шага. Отдельно, чтобы ряд читался. */
@Composable
private fun StepButton(label: String, onClick: () -> Unit) {
    val c = AyantTheme.colors
    Box(
        Modifier
            .size(32.dp)
            .clip(CircleShape)
            .background(c.surfaceMuted)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = c.ink)
    }
}
