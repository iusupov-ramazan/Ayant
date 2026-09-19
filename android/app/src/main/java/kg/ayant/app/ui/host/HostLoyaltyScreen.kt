package kg.ayant.app.ui.host

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.RemoveCircle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.core.AppLanguage
import kg.ayant.app.domain.HostForms
import kg.ayant.app.domain.HostIntent
import kg.ayant.app.domain.model.HostVenueDTO
import kg.ayant.app.domain.model.PointsBand
import kg.ayant.app.domain.model.PointsReward
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenuePointsCard
import kg.ayant.app.ui.bonus.WalletPointsCard
import kg.ayant.app.ui.theme.AyantMetrics
import kg.ayant.app.ui.theme.AyantPillButton
import kg.ayant.app.ui.theme.AyantPrimaryButton
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.HostViewModel
import kotlinx.coroutines.delay
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.UUID
import kotlin.math.roundToInt

/**
 * «Лояльность» — экран настройки лояльности заведения (SCREENS.md H6).
 * Mirrors `HostLoyaltyView.swift`.
 *
 * Здесь только то, что есть на самом деле: карта штампов и конфиг баллов САН.
 * Прежние «ROI-герой» с выдуманными «2,4×» и калькулятор, который ничего не
 * сохранял, убраны — цифры, за которыми не стоит данных, подрывают доверие ко
 * всему экрану.
 *
 * Экран по умолчанию — сводка настроек; «Изменить настройки» открывает
 * редактор, где карта штампов и баллы собираются в черновики ([StampDraft],
 * [PointsDraft]) и уходят одной кнопкой «Сохранить»: штампы — через
 * [HostIntent.SaveVenue], баллы — через [HostIntent.SavePointsConfig], где
 * серверные ограничения (кэшбэк ≤ 20 %, пауза 0…1440 мин и т. д.) накладывает
 * чистый `HostForms.applyPoints`. Админ-панель правит те же поля Firestore —
 * кто сохранил последним, тот и прав.
 */
@Composable
fun HostLoyaltyScreen(host: HostViewModel) {
    val c = AyantTheme.colors
    val hostState by host.state.collectAsState()
    val focus = LocalFocusManager.current

    var selectedVenueID by rememberSaveable { mutableStateOf<String?>(null) }
    // Экран по умолчанию только показывает настройки; правка — по кнопке
    // «Изменить», сохранение — по «Сохранить». Автосохранения на каждый символ
    // нет: оно держало клавиатуру открытой и писало в Firestore на каждый тап.
    var isEditing by remember { mutableStateOf(false) }

    // Черновики и снимки, с которых они начаты: «есть правки» — это
    // `draft != baseline`, без отдельных флагов.
    var draft by remember { mutableStateOf(PointsDraft()) }
    var baseline by remember { mutableStateOf(PointsDraft()) }
    var stamps by remember { mutableStateOf(StampDraft()) }
    var stampsBaseline by remember { mutableStateOf(StampDraft()) }
    // Заведение, на которое хотят переключиться при несохранённых правках.
    var pendingSwitchID by remember { mutableStateOf<String?>(null) }
    var savedFlash by remember { mutableStateOf(false) }

    val venue: HostVenueDTO? = hostState.venues.firstOrNull { it.id == selectedVenueID }
        ?: hostState.venues.firstOrNull()
    val isDirty = draft != baseline || stamps != stampsBaseline

    fun loadDraft() {
        val d = venue?.let { PointsDraft.from(it) } ?: PointsDraft()
        draft = d; baseline = d
        val st = venue?.let { StampDraft.from(it) } ?: StampDraft()
        stamps = st; stampsBaseline = st
    }

    fun switchVenue(id: String) {
        focus.clearFocus()
        isEditing = false
        selectedVenueID = id
    }

    fun startEditing() { loadDraft(); isEditing = true }

    fun cancelEditing() { focus.clearFocus(); loadDraft(); isEditing = false }

    /**
     * Одна кнопка на обе части экрана: карта штампов уходит через `SaveVenue`
     * (форма целиком, чтобы не затереть остальные поля), баллы — через
     * `SavePointsConfig`, где чистый `HostForms.applyPoints` накладывает
     * серверные ограничения.
     */
    fun saveAll() {
        val v = venue ?: return
        focus.clearFocus()
        if (stamps != stampsBaseline) {
            val reward = stamps.reward.trim()
            host.send(HostIntent.SaveVenue(v, HostForms.fields(v).copy(
                loyaltyEnabled = stamps.enabled,
                loyaltyGoal = stamps.goal,
                loyaltyReward = reward.ifEmpty { v.loyaltyReward },
            )))
        }
        if (draft != baseline) {
            host.send(HostIntent.SavePointsConfig(v.id, draft.fields()))
        }
        // Стор уже применил ограничения — обновлённое состояние подхватит
        // LaunchedEffect(hostState.venues) ниже и покажет, что реально сохранилось.
        isEditing = false
        savedFlash = true
    }

    LaunchedEffect(venue?.id) { loadDraft() }
    // Состояние обновилось (сохранение / синк), пока никто не правит —
    // подхватываем; открытый редактор не затираем.
    LaunchedEffect(hostState.venues) { if (!isEditing) loadDraft() }
    LaunchedEffect(savedFlash) { if (savedFlash) { delay(2000); savedFlash = false } }

    Scaffold(
        containerColor = c.canvas,
        bottomBar = {
            if (venue != null) {
                Footer(
                    isEditing = isEditing, isDirty = isDirty, savedFlash = savedFlash,
                    onEdit = ::startEditing, onCancel = ::cancelEditing, onSave = ::saveAll,
                )
            }
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(bottom = padding.calculateBottomPadding())
                .verticalScroll(rememberScrollState())
                .padding(horizontal = AyantMetrics.screenPadding)
                .padding(top = 12.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            Header(
                venues = hostState.venues, selectedID = venue?.id,
                onPick = { id ->
                    // Несохранённые правки не переносим молча на другое
                    // заведение — спрашиваем.
                    if (isEditing && isDirty) pendingSwitchID = id else switchVenue(id)
                },
            )

            if (venue == null) {
                AyantNoteCard(stringResource(R.string.host_loyalty_need_venue))
            } else if (isEditing) {
                StampEditor(stamps, pointsOn = draft.enabled) { stamps = it }
                PointsMasterSection(draft.enabled) { draft = draft.copy(enabled = it) }
                if (draft.enabled) {
                    ModesSection(draft) { draft = it }
                    RewardsSection(draft) { draft = it }
                    RulesSection(draft) { draft = it }
                    GuestPreview(venue, draft, isEditing = true)
                }
            } else {
                StampSummary(stamps, pointsOn = draft.enabled)
                PointsSummary(draft)
                if (draft.enabled) GuestPreview(venue, draft, isEditing = false)
            }
        }
    }

    pendingSwitchID?.let { id ->
        AlertDialog(
            onDismissRequest = { pendingSwitchID = null },
            title = { Text(stringResource(R.string.host_unsaved_title)) },
            text = { Text(stringResource(R.string.host_unsaved_body)) },
            confirmButton = {
                TextButton(onClick = { switchVenue(id); pendingSwitchID = null }) {
                    Text(stringResource(R.string.host_unsaved_leave), color = Color(0xFFE8556B))
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingSwitchID = null }) {
                    Text(stringResource(R.string.host_unsaved_stay))
                }
            },
        )
    }
}

// MARK: - Заголовок

@Composable
private fun Header(venues: List<HostVenueDTO>, selectedID: String?, onPick: (String) -> Unit) {
    val c = AyantTheme.colors
    Column {
        Text(
            stringResource(R.string.host_loyalty_screen_title), fontSize = 42.sp,
            fontWeight = FontWeight.Black, letterSpacing = (-2.3).sp,
            lineHeight = 40.sp, color = c.ink,
        )
        Text(
            stringResource(R.string.host_loyalty_screen_sub),
            fontSize = 14.sp, lineHeight = 20.sp, color = c.inkSoft,
            modifier = Modifier.widthIn(max = 290.dp).padding(top = 9.dp),
        )
        if (venues.size > 1) {
            Spacer(Modifier.height(14.dp))
            Row(
                Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                venues.forEach { v ->
                    val isOn = v.id == selectedID
                    Text(
                        v.name, fontSize = 13.sp, fontWeight = FontWeight.Bold,
                        color = if (isOn) Color.White else c.inkSoft,
                        modifier = Modifier
                            .clip(CircleShape)
                            .then(if (isOn) Modifier.background(c.accentGradient) else Modifier.background(c.surface))
                            .clickable(enabled = !isOn) { onPick(v.id) }
                            .padding(horizontal = 14.dp, vertical = 9.dp),
                    )
                }
            }
        }
    }
}

// MARK: - Карта штампов — просмотр

@Composable
private fun StampSummary(stamps: StampDraft, pointsOn: Boolean) {
    val c = AyantTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Eyebrow(stringResource(R.string.host_stamp_card))
        AyantFieldCard {
            SummaryRow(
                stringResource(R.string.host_stamp_card),
                if (stamps.enabled) stringResource(R.string.host_enabled) else stringResource(R.string.host_disabled),
            )
            if (stamps.enabled) {
                AyantFieldDivider()
                SummaryRow(stringResource(R.string.host_stamp_goal), "${stamps.goal}")
                AyantFieldDivider()
                SummaryRow(stringResource(R.string.host_stamp_reward), stamps.reward)
            }
        }
        if (stamps.enabled && pointsOn) {
            OneMechanicNote()
        } else if (stamps.enabled) {
            Text(
                stringResource(R.string.host_stamp_summary_explain, stamps.goal, stamps.reward),
                fontSize = 12.5.sp, color = c.inkSoft, lineHeight = 17.sp,
            )
        }
    }
}

// MARK: - Карта штампов — правка

@Composable
private fun StampEditor(stamps: StampDraft, pointsOn: Boolean, onChange: (StampDraft) -> Unit) {
    val c = AyantTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Eyebrow(stringResource(R.string.host_stamp_card))
        AyantFieldCard {
            Box(Modifier.padding(horizontal = 16.dp, vertical = 13.dp)) {
                AyantGradientToggle(
                    title = stringResource(R.string.host_stamp_card),
                    subtitle = stringResource(R.string.host_stamp_toggle_sub),
                    checked = stamps.enabled,
                    onCheckedChange = { onChange(stamps.copy(enabled = it)) },
                )
            }
            if (stamps.enabled) {
                AyantFieldDivider()
                AyantFieldRow(stringResource(R.string.host_stamp_goal)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            "${stamps.goal}", fontSize = 15.5.sp, fontWeight = FontWeight.SemiBold,
                            color = c.ink, modifier = Modifier.weight(1f),
                        )
                        StepButton("−") { onChange(stamps.copy(goal = (stamps.goal - 1).coerceAtLeast(2))) }
                        Spacer(Modifier.width(8.dp))
                        StepButton("+") { onChange(stamps.copy(goal = (stamps.goal + 1).coerceAtMost(12))) }
                    }
                }
                AyantFieldDivider()
                AyantFieldRow(stringResource(R.string.host_stamp_reward)) {
                    AyantFieldInput(
                        placeholder = stringResource(R.string.host_stamp_reward_hint),
                        value = stamps.reward,
                        onValueChange = { onChange(stamps.copy(reward = it)) },
                    )
                }
            }
        }
        if (stamps.enabled && pointsOn) OneMechanicNote()
    }
}

/**
 * Механика одна на заведение: пока включены баллы САН, штампы не начисляются
 * (сервер отвечает `loyalty_is_points`).
 */
@Composable
private fun OneMechanicNote() {
    AyantNoteCard(stringResource(R.string.host_one_mechanic_note))
}

// MARK: - Баллы САН — просмотр

@Composable
private fun PointsSummary(draft: PointsDraft) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Eyebrow(stringResource(R.string.host_loyalty_title))
        AyantFieldCard {
            SummaryRow(
                stringResource(R.string.host_loyalty_title),
                if (draft.enabled) stringResource(R.string.host_points_on) else stringResource(R.string.host_points_off),
            )
            if (draft.enabled) {
                AyantFieldDivider()
                SummaryRow(stringResource(R.string.host_points_accrual), accrualSummary(draft))
                AyantFieldDivider()
                SummaryRow(
                    stringResource(R.string.host_rule_cooldown),
                    if (draft.cooldownMinutes == "0") stringResource(R.string.host_points_none)
                    else stringResource(R.string.unit_min, draft.cooldownMinutes.toIntOrNull() ?: 0),
                )
                AyantFieldDivider()
                SummaryRow(
                    stringResource(R.string.host_rule_expiry),
                    stringResource(R.string.unit_months, draft.expiryMonths.toIntOrNull() ?: 0),
                )
                AyantFieldDivider()
                SummaryRow(
                    stringResource(R.string.host_points_redeem_label),
                    if (draft.redeemMode == "customerInitiated") stringResource(R.string.host_redeem_customer_short)
                    else stringResource(R.string.host_redeem_staff_short),
                )
            }
        }
        if (draft.enabled) RewardsSummary(draft)
    }
}

@Composable
private fun accrualSummary(draft: PointsDraft): String = when (draft.mode) {
    "cashback" -> stringResource(R.string.host_accrual_cashback, draft.cashback.ifEmpty { "0" })
    "bands" ->
        if (draft.bands.isEmpty()) stringResource(R.string.host_accrual_bands_empty)
        // `map` — inline, поэтому @Composable-вызов внутри допустим; `joinToString` — нет.
        else draft.bands.map { stringResource(R.string.host_accrual_band_row, it.maxAmount, it.points) }
            .joinToString("\n")
    else -> stringResource(R.string.host_accrual_flat, draft.flat.ifEmpty { "0" })
}

@Composable
private fun RewardsSummary(draft: PointsDraft) {
    val c = AyantTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Eyebrow(stringResource(R.string.host_rewards))
        if (draft.rewards.isEmpty()) {
            Text(
                stringResource(R.string.host_rewards_none_summary),
                fontSize = 13.sp, color = c.inkSoft,
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp))
                    .background(c.surface).padding(16.dp),
            )
        } else {
            AyantFieldCard {
                draft.rewards.forEachIndexed { i, r ->
                    if (i > 0) AyantFieldDivider()
                    RewardSummaryRow(r)
                }
            }
        }
    }
}

@Composable
private fun RewardSummaryRow(r: PointsDraft.RewardRow) {
    val c = AyantTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .alpha(if (r.active) 1f else 0.55f)
            .padding(horizontal = 16.dp, vertical = 13.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                r.title.ifEmpty { stringResource(R.string.host_reward_untitled) },
                fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = c.ink,
            )
            Text(
                if (r.type == "money") stringResource(R.string.host_reward_money_sub, r.ratio)
                else stringResource(R.string.host_reward_item_sub),
                fontSize = 12.sp, color = c.inkSoft,
            )
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                if (r.type == "money") stringResource(R.string.host_reward_cost_from, r.cost)
                else stringResource(R.string.host_reward_cost_points, r.cost),
                fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = c.ink,
            )
            if (!r.active) {
                Text(stringResource(R.string.host_reward_disabled_tag), fontSize = 11.5.sp, color = c.inkSoft)
            }
        }
    }
}

@Composable
private fun SummaryRow(label: String, value: String) {
    val c = AyantTheme.colors
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 13.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(label, fontSize = 14.sp, color = c.inkSoft, modifier = Modifier.weight(1f))
        Text(
            value, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = c.ink,
            textAlign = TextAlign.End,
        )
    }
}

// MARK: - Баллы САН — главный тумблер

@Composable
private fun PointsMasterSection(enabled: Boolean, onChange: (Boolean) -> Unit) {
    val c = AyantTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Eyebrow(stringResource(R.string.host_loyalty_title))
        AyantFieldCard {
            Box(Modifier.padding(horizontal = 16.dp, vertical = 13.dp)) {
                AyantGradientToggle(
                    title = stringResource(R.string.host_points_master_title),
                    subtitle = stringResource(R.string.host_points_master_sub),
                    checked = enabled,
                    onCheckedChange = onChange,
                )
            }
        }
        Text(
            stringResource(R.string.host_points_one_mechanic_hint),
            fontSize = 11.5.sp, color = c.inkSoft, lineHeight = 15.sp,
        )
    }
}

// MARK: - Как начисляем

@Composable
private fun ModesSection(draft: PointsDraft, onChange: (PointsDraft) -> Unit) {
    val c = AyantTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Eyebrow(stringResource(R.string.host_loyalty_how))
        // Названия режимов — заранее: `title` у сегмента не @Composable.
        val modeTitles = HostForms.PointsLimits.modes.associateWith { modeTitle(it) }
        AyantSegmented(
            items = HostForms.PointsLimits.modes,
            selection = draft.mode,
            title = { modeTitles[it] ?: it },
            onSelect = { onChange(draft.copy(mode = it)) },
        )
        Text(modeHint(draft.mode), fontSize = 12.sp, color = c.inkSoft, lineHeight = 16.sp)
        AyantFieldCard {
            when (draft.mode) {
                "cashback" -> FieldRowWithHint(
                    stringResource(R.string.host_cashback_label),
                    stringResource(R.string.host_cashback_hint, HostForms.PointsLimits.maxCashbackPercent.toInt()),
                ) {
                    AyantFieldInput(
                        placeholder = "5", value = draft.cashback,
                        onValueChange = { onChange(draft.copy(cashback = it)) },
                        keyboardType = KeyboardType.Decimal,
                    )
                }
                "bands" -> BandsEditor(draft, onChange)
                else -> FieldRowWithHint(
                    stringResource(R.string.host_flat_label),
                    stringResource(R.string.host_flat_hint, thousands(HostForms.PointsLimits.maxPoints)),
                ) {
                    AyantFieldInput(
                        placeholder = "50", value = draft.flat,
                        onValueChange = { onChange(draft.copy(flat = it)) },
                        keyboardType = KeyboardType.Number,
                    )
                }
            }
        }
    }
}

@Composable
private fun modeTitle(mode: String): String = when (mode) {
    "bands" -> stringResource(R.string.host_mode_bands)
    "cashback" -> stringResource(R.string.host_mode_cashback)
    else -> stringResource(R.string.host_mode_flat)
}

@Composable
private fun modeHint(mode: String): String = when (mode) {
    "bands" -> stringResource(R.string.host_mode_hint_bands)
    "cashback" -> stringResource(R.string.host_mode_hint_cashback)
    else -> stringResource(R.string.host_mode_hint_flat)
}

// MARK: - Диапазоны

@Composable
private fun BandsEditor(draft: PointsDraft, onChange: (PointsDraft) -> Unit) {
    val c = AyantTheme.colors
    draft.bands.forEach { band ->
        BandRow(
            band,
            onChange = { updated -> onChange(draft.copy(bands = draft.bands.map { if (it.id == updated.id) updated else it })) },
            onRemove = { onChange(draft.copy(bands = draft.bands.filterNot { it.id == band.id })) },
        )
        AyantFieldDivider()
    }
    if (draft.bands.isEmpty()) {
        Text(
            stringResource(R.string.host_bands_empty_edit),
            fontSize = 12.5.sp, color = c.inkSoft,
            modifier = Modifier.padding(horizontal = 16.dp).padding(top = 13.dp),
        )
    }
    AddRowButton(stringResource(R.string.host_add_band)) {
        onChange(draft.copy(bands = draft.bands + PointsDraft.BandRow(newID("pb"), "", "")))
    }
    Text(
        stringResource(R.string.host_bands_order_hint),
        fontSize = 11.5.sp, color = c.inkSoft, lineHeight = 15.sp,
        modifier = Modifier.padding(horizontal = 16.dp).padding(bottom = 13.dp),
    )
}

@Composable
private fun BandRow(band: PointsDraft.BandRow, onChange: (PointsDraft.BandRow) -> Unit, onRemove: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Caption(stringResource(R.string.host_band_upto_caption))
        AyantFieldInput(
            placeholder = "500", value = band.maxAmount,
            onValueChange = { onChange(band.copy(maxAmount = it)) },
            keyboardType = KeyboardType.Number, modifier = Modifier.width(72.dp),
        )
        Caption(stringResource(R.string.host_band_som_arrow))
        AyantFieldInput(
            placeholder = "10", value = band.points,
            onValueChange = { onChange(band.copy(points = it)) },
            keyboardType = KeyboardType.Number, modifier = Modifier.width(64.dp),
        )
        Caption(stringResource(R.string.host_band_points))
        Spacer(Modifier.weight(1f))
        RemoveButton(onRemove)
    }
}

// MARK: - Награды

@Composable
private fun RewardsSection(draft: PointsDraft, onChange: (PointsDraft) -> Unit) {
    val c = AyantTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Eyebrow(stringResource(R.string.host_rewards))
        if (draft.rewards.isEmpty()) {
            Text(
                stringResource(R.string.host_rewards_empty_edit),
                fontSize = 13.sp, color = c.inkSoft,
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp))
                    .background(c.surface).padding(16.dp),
            )
        }
        draft.rewards.forEach { reward ->
            RewardCard(
                reward,
                onChange = { updated -> onChange(draft.copy(rewards = draft.rewards.map { if (it.id == updated.id) updated else it })) },
                onRemove = { onChange(draft.copy(rewards = draft.rewards.filterNot { it.id == reward.id })) },
            )
        }
        AyantPillButton(
            text = stringResource(R.string.host_add_reward), accent = true,
            onClick = {
                onChange(draft.copy(rewards = draft.rewards + PointsDraft.RewardRow(
                    id = newID("rw"), title = "", type = "item", cost = "", ratio = "1", active = true,
                )))
            },
        )
    }
}

@Composable
private fun RewardCard(reward: PointsDraft.RewardRow, onChange: (PointsDraft.RewardRow) -> Unit, onRemove: () -> Unit) {
    val isMoney = reward.type == "money"
    val moneyTitle = stringResource(R.string.host_reward_type_money)
    val itemTitle = stringResource(R.string.host_reward_type_item)
    AyantFieldCard {
        AyantFieldRow(stringResource(R.string.host_reward_title_label)) {
            AyantFieldInput(
                placeholder = stringResource(R.string.host_reward_title_hint),
                value = reward.title, onValueChange = { onChange(reward.copy(title = it)) },
            )
        }
        AyantFieldDivider()
        FieldRowWithHint(
            stringResource(R.string.host_reward_type_label),
            if (isMoney) stringResource(R.string.host_reward_type_money_hint)
            else stringResource(R.string.host_reward_type_item_hint),
        ) {
            AyantSegmented(
                items = listOf("item", "money"),
                selection = reward.type,
                title = { if (it == "money") moneyTitle else itemTitle },
                onSelect = { onChange(reward.copy(type = it)) },
            )
        }
        AyantFieldDivider()
        AyantFieldRow(
            if (isMoney) stringResource(R.string.host_reward_min_points)
            else stringResource(R.string.host_reward_cost_label),
        ) {
            AyantFieldInput(
                placeholder = "100", value = reward.cost,
                onValueChange = { onChange(reward.copy(cost = it)) },
                keyboardType = KeyboardType.Number,
            )
        }
        if (isMoney) {
            AyantFieldDivider()
            FieldRowWithHint(
                stringResource(R.string.host_reward_ratio_label),
                stringResource(R.string.host_reward_ratio_hint),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Caption(stringResource(R.string.host_reward_ratio_prefix))
                    AyantFieldInput(
                        placeholder = "1", value = reward.ratio,
                        onValueChange = { onChange(reward.copy(ratio = it)) },
                        keyboardType = KeyboardType.Decimal, modifier = Modifier.width(64.dp),
                    )
                    Caption(stringResource(R.string.host_som))
                }
            }
        }
        AyantFieldDivider()
        Box(Modifier.padding(horizontal = 16.dp, vertical = 13.dp)) {
            AyantGradientToggle(
                title = stringResource(R.string.host_reward_on),
                subtitle = stringResource(R.string.host_reward_active_sub),
                checked = reward.active,
                onCheckedChange = { onChange(reward.copy(active = it)) },
            )
        }
        AyantFieldDivider()
        Row(
            Modifier
                .fillMaxWidth()
                .clickable(onClick = onRemove)
                .padding(horizontal = 16.dp, vertical = 13.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(Icons.Filled.Delete, null, tint = Color(0xFFE8556B), modifier = Modifier.size(18.dp))
            Text(
                stringResource(R.string.host_delete_reward),
                fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Color(0xFFE8556B),
            )
        }
    }
}

// MARK: - Правила

@Composable
private fun RulesSection(draft: PointsDraft, onChange: (PointsDraft) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Eyebrow(stringResource(R.string.host_rules))
        AyantFieldCard {
            FieldRowWithHint(
                stringResource(R.string.host_rule_cooldown_label),
                stringResource(R.string.host_rule_cooldown_edit_hint, HostForms.PointsLimits.cooldownMinutes.last),
            ) {
                AyantFieldInput(
                    placeholder = "60", value = draft.cooldownMinutes,
                    onValueChange = { onChange(draft.copy(cooldownMinutes = it)) },
                    keyboardType = KeyboardType.Number,
                )
            }
            AyantFieldDivider()
            FieldRowWithHint(
                stringResource(R.string.host_rule_expiry_label),
                stringResource(
                    R.string.host_rule_expiry_edit_hint,
                    HostForms.PointsLimits.expiryMonths.first, HostForms.PointsLimits.expiryMonths.last,
                ),
            ) {
                AyantFieldInput(
                    placeholder = "6", value = draft.expiryMonths,
                    onValueChange = { onChange(draft.copy(expiryMonths = it)) },
                    keyboardType = KeyboardType.Number,
                )
            }
            AyantFieldDivider()
            Box(Modifier.padding(horizontal = 16.dp, vertical = 13.dp)) {
                AyantGradientToggle(
                    title = stringResource(R.string.host_rule_customer_toggle),
                    subtitle = stringResource(R.string.host_rule_customer_toggle_sub),
                    checked = draft.redeemMode == "customerInitiated",
                    onCheckedChange = { onChange(draft.copy(redeemMode = if (it) "customerInitiated" else "staffScan")) },
                )
            }
        }
    }
}

// MARK: - Что видит гость

@Composable
private fun GuestPreview(venue: HostVenueDTO, draft: PointsDraft, isEditing: Boolean) {
    val c = AyantTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Eyebrow(stringResource(R.string.host_guest_sees))
        Box(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(30.dp))
                .background(c.surfaceMuted).padding(6.dp),
        ) {
            // Баланс 0 — это макет, а не чей-то счёт: выдуманные «340 баллов»
            // здесь читались бы как реальные данные.
            WalletPointsCard(
                card = VenuePointsCard(venueID = venue.id, venueName = venue.name, balance = 0),
                venue = previewVenue(venue, draft),
                isFront = true,
            )
        }
        Text(
            if (isEditing) stringResource(R.string.host_preview_hint_editing)
            else stringResource(R.string.host_preview_hint),
            fontSize = 11.5.sp, color = c.inkSoft,
        )
    }
}

/**
 * Доменное заведение для превью — черновик, уже приведённый к серверным
 * ограничениям, чтобы гость видел то же, что сохранится.
 */
private fun previewVenue(dto: HostVenueDTO, draft: PointsDraft): Venue =
    HostForms.applyPoints(dto, draft.fields()).asVenue.copy(pointsEnabled = true)

// MARK: - Подвал

@Composable
private fun Footer(
    isEditing: Boolean, isDirty: Boolean, savedFlash: Boolean,
    onEdit: () -> Unit, onCancel: () -> Unit, onSave: () -> Unit,
) {
    val c = AyantTheme.colors
    val hintColor = Color(0xFF9A9188)
    AyantStickyFooter {
        if (isEditing) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                AyantPillButton(
                    text = stringResource(R.string.action_cancel), onClick = onCancel,
                    modifier = Modifier.weight(1f),
                )
                AyantPrimaryButton(
                    text = stringResource(R.string.action_save), onClick = onSave,
                    enabled = isDirty, modifier = Modifier.weight(1f).alpha(if (isDirty) 1f else 0.6f),
                )
            }
            Text(
                if (isDirty) stringResource(R.string.host_footer_dirty) else stringResource(R.string.host_footer_clean),
                fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold, color = hintColor,
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
            )
        } else {
            AyantPrimaryButton(text = stringResource(R.string.host_edit_settings), onClick = onEdit)
            if (savedFlash) {
                Row(
                    Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.CheckCircle, null, tint = c.open, modifier = Modifier.size(14.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(
                        stringResource(R.string.host_saved),
                        fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold, color = c.open,
                    )
                }
            } else {
                Text(
                    stringResource(R.string.host_footer_idle),
                    fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold, color = hintColor,
                    textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

// MARK: - Мелочи

@Composable
private fun Eyebrow(text: String) {
    Text(
        text.uppercase(), fontSize = 11.5.sp, fontWeight = FontWeight.Black,
        letterSpacing = 1.2.sp, color = AyantTheme.colors.inkSoft,
    )
}

@Composable
private fun Caption(text: String) {
    Text(text, fontSize = 13.sp, color = AyantTheme.colors.inkSoft, maxLines = 1)
}

/** Ряд формы с подсказкой под значением. Mirrors `SanFieldRow(label:hint:)`. */
@Composable
private fun FieldRowWithHint(label: String, hint: String, value: @Composable () -> Unit) {
    AyantFieldRow(label) {
        value()
        Text(hint, fontSize = 11.5.sp, color = AyantTheme.colors.inkSoft, lineHeight = 15.sp)
    }
}

@Composable
private fun RemoveButton(onClick: () -> Unit) {
    Icon(
        Icons.Filled.RemoveCircle,
        contentDescription = stringResource(R.string.action_delete),
        tint = Color(0xFFE8556B),
        modifier = Modifier.size(22.dp).clip(CircleShape).clickable(onClick = onClick),
    )
}

@Composable
private fun AddRowButton(title: String, onClick: () -> Unit) {
    val c = AyantTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(Icons.Filled.AddCircle, null, tint = c.accentText, modifier = Modifier.size(18.dp))
        Text(title, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = c.accentText)
    }
}

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

private fun newID(prefix: String) = "${prefix}_${UUID.randomUUID().toString().take(8)}"

/** Русские тысячи тонким пробелом: «10 000». */
private fun thousands(v: Int): String {
    val symbols = DecimalFormatSymbols().apply { groupingSeparator = ' ' }
    return DecimalFormat("#,###", symbols).format(v)
}

/** «5», «7.5» — без хвоста «.0» у целых. Десятичная запятая допустима на вводе. */
private fun percentText(v: Double): String =
    if (v == v.roundToInt().toDouble()) v.roundToInt().toString()
    else String.format(AppLanguage.locale, "%.1f", v)

// MARK: - Черновик карты штампов

/**
 * Настройки штампов в том виде, в каком их держит редактор; в `VenueFields`
 * уходят один раз, при сохранении.
 */
private data class StampDraft(
    val enabled: Boolean = false,
    val goal: Int = 6,
    val reward: String = "",
) {
    companion object {
        fun from(dto: HostVenueDTO) = StampDraft(
            enabled = dto.loyaltyEnabled,
            goal = dto.loyaltyGoal.coerceIn(2, 12),
            reward = dto.loyaltyReward,
        )
    }
}

// MARK: - Черновик конфига баллов

/**
 * Форма баллов в том виде, в каком её держат текстовые поля: числа — строками,
 * чтобы пустое поле и «в процессе набора» не превращались в 0 на каждом
 * символе. В `PointsFields` конвертируется один раз, при сохранении.
 */
private data class PointsDraft(
    val enabled: Boolean = false,
    val mode: String = "flat",
    val flat: String = "",
    val cashback: String = "",
    val bands: List<BandRow> = emptyList(),
    val rewards: List<RewardRow> = emptyList(),
    val expiryMonths: String = "",
    val cooldownMinutes: String = "",
    val redeemMode: String = "staffScan",
) {
    data class BandRow(val id: String, val maxAmount: String, val points: String)
    data class RewardRow(
        val id: String,
        val title: String,
        val type: String,      // "item" | "money"
        val cost: String,
        val ratio: String,
        val active: Boolean,
    )

    /**
     * Поля формы для стора. Пустое/нечитаемое число — 0 (или 1 для курса);
     * дальше `HostForms.applyPoints` доводит до допустимых границ.
     */
    fun fields() = HostForms.PointsFields(
        pointsEnabled = enabled,
        pointsMode = mode,
        pointsFlat = int(flat),
        pointsBands = bands.map { PointsBand(int(it.maxAmount), int(it.points)) },
        cashbackPercent = double(cashback),
        pointsRewards = rewards.map { r ->
            PointsReward(
                id = r.id, type = r.type, title = r.title,
                cost = int(r.cost), ratio = double(r.ratio, fallback = 1.0), active = r.active,
            )
        },
        pointsExpiryMonths = int(expiryMonths),
        redeemMode = redeemMode,
        earnCooldownMinutes = int(cooldownMinutes),
    )

    companion object {
        fun from(dto: HostVenueDTO): PointsDraft {
            val f = HostForms.pointsFields(dto)
            return PointsDraft(
                enabled = f.pointsEnabled,
                mode = f.pointsMode,
                flat = if (f.pointsFlat > 0) f.pointsFlat.toString() else "",
                cashback = if (f.cashbackPercent > 0) percentText(f.cashbackPercent) else "",
                bands = f.pointsBands.mapIndexed { i, b -> BandRow("pb_$i", b.maxAmount.toString(), b.points.toString()) },
                rewards = f.pointsRewards.map { r ->
                    RewardRow(r.id, r.title, r.type, r.cost.toString(), percentText(r.ratio), r.active)
                },
                expiryMonths = f.pointsExpiryMonths.toString(),
                cooldownMinutes = f.earnCooldownMinutes.toString(),
                redeemMode = f.redeemMode,
            )
        }

        private fun int(s: String): Int = s.trim().toIntOrNull() ?: 0

        /** Десятичная запятая — норма на русской клавиатуре. */
        private fun double(s: String, fallback: Double = 0.0): Double =
            s.trim().replace(',', '.').toDoubleOrNull() ?: fallback
    }
}
