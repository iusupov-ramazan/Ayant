package kg.ayant.app.ui.host

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Backspace
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.core.AppConfig
import kg.ayant.app.domain.PointsConfig
import kg.ayant.app.domain.PointsMath
import kg.ayant.app.domain.model.HostVenueDTO
import kg.ayant.app.ui.theme.AyantMetrics
import kg.ayant.app.ui.theme.AyantMotion
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.AyantTiming
import kg.ayant.app.ui.theme.ayantRisoHatch
import kg.ayant.app.ui.theme.rememberReduceMotion
import kg.ayant.app.ui.vm.HostViewModel
import kotlinx.coroutines.launch
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.util.UUID
import kotlin.math.roundToInt
import kg.ayant.app.domain.pointsActive
import kg.ayant.app.domain.stampsActive

/**
 * Scanner flow (SCREENS.md H13–H15). Mirrors `HostScannerView.swift` +
 * `HostScannerSurfaces.swift`.
 *
 * The defining move: the scanner screen is an **accent-gradient** surface, not a
 * dark one. The only dark element in the whole host app is the camera window.
 * The QR prefix picks the branch, exactly as the backend does.
 */
@Composable
fun HostScannerScreen(
    host: HostViewModel,
    fixedVenueID: String? = null,
    /** `null`, когда сканер открыт вкладкой: возвращаться некуда. */
    onBack: (() -> Unit)?,
) {
    val c = AyantTheme.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val hostState by host.state.collectAsState()
    val couponService = remember { AppConfig.makeCouponService() }
    val authService = remember { AppConfig.makeAuthService() }

    var venueID by remember { mutableStateOf(fixedVenueID ?: hostState.venues.firstOrNull()?.id ?: "") }
    var venueMenu by remember { mutableStateOf(false) }
    var manualCode by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    var success by remember { mutableStateOf(true) }
    var pending by remember { mutableStateOf<PendingEarn?>(null) }
    var receipt by remember { mutableStateOf<EarnReceipt?>(null) }
    var lastCode by remember { mutableStateOf("") }
    // Ключ минтится ОДИН раз на распознанный QR и переживает переход на экран
    // суммы и повторные тапы: иначе ретрай ушёл бы с новым ключом и сервер
    // начислил бы второй раз (CLAUDE.md, «Key reuse is a collision»).
    var scanKey by remember { mutableStateOf("") }

    val venue: HostVenueDTO? = hostState.venues.firstOrNull { it.id == venueID }

    fun errorText(code: String?): String = when (code) {
        "coupon_not_found" -> "Купон не найден."
        "wrong_venue" -> "Этот код — для другого заведения."
        "loyalty_off" -> "Карта лояльности у заведения выключена."
        "already_used" -> "Купон уже был использован."
        "not_owner" -> "У вас нет прав на это заведение."
        "venue_not_found" -> "Заведение не найдено."
        "no_token", "bad_token" -> "Требуется вход в аккаунт заведения."
        "missing_params" -> "Пустой код купона."
        "points_off" -> "Баллы САН у заведения выключены."
        "cooldown" -> "Баллы этому гостю уже начислены недавно."
        "missing_amount" -> "Введите сумму чека."
        "bad_band" -> "Выберите диапазон суммы."
        "no_points" -> "Начислять нечего (0 баллов)."
        "bad_code" -> "Неверный QR-код."
        "insufficient" -> "У гостя недостаточно баллов."
        "reward_not_found" -> "Награда не найдена или отключена."
        "redeem_not_allowed" -> "Списание баллов недоступно для этого заведения."
        "below_min" -> "Слишком мало баллов для этой награды."
        "missing_user" -> "Не удалось определить гостя."
        else -> context.getString(R.string.host_scan_failed)
    }

    fun resetScan() {
        message = null; lastCode = ""; manualCode = ""; scanKey = ""
    }

    fun submitScan(code: String, billAmount: Int?, bandIndex: Int?, billForReceipt: Int?) {
        busy = true; message = null
        val key = scanKey.ifEmpty { UUID.randomUUID().toString() }
        val modeLabel = venue?.let { modeLabel(it) }
        scope.launch {
            val token = authService.idToken() ?: ""
            val o = couponService.scanCoupon(code.trim(), venueID, token, billAmount, bandIndex, key)
            busy = false
            success = o.ok
            when {
                o.ok && o.points -> receipt = EarnReceipt(
                    awarded = o.awarded, balance = o.balance,
                    billAmount = billForReceipt, modeLabel = modeLabel, replayed = o.replayed,
                )
                !o.ok -> message = errorText(o.errorCode)
                o.loyalty -> message = context.getString(R.string.host_scan_stamp, o.stamps, o.goal) +
                    if (o.rewardIssued) context.getString(R.string.host_scan_reward_suffix, o.rewardTitle) else ""
                else -> message = context.getString(R.string.host_scan_redeemed, o.title)
            }
        }
    }

    fun submitRedeem(code: String) {
        val parts = code.trim().split(":")
        if (parts.size < 3) { success = false; message = "Неверный код награды."; return }
        val u = parts[1]; val rid = parts[2]; val pts = parts.getOrNull(3)?.toIntOrNull() ?: 0
        busy = true; message = null
        // Ключ обязателен и здесь: без него повтор списал бы баллы дважды.
        val key = scanKey.ifEmpty { UUID.randomUUID().toString() }
        scope.launch {
            val token = authService.idToken() ?: ""
            val o = couponService.redeemVenuePoints(venueID, u, rid, pts, token, key)
            busy = false
            success = o.ok
            message = when {
                !o.ok -> errorText(o.errorCode)
                o.somOff != null -> "Списано ${o.redeemed} баллов (−${o.somOff} сом). Остаток: ${o.balance}."
                else -> "Списано ${o.redeemed} баллов. Остаток: ${o.balance}. Выдайте награду гостю."
            }
        }
    }

    fun handle(raw: String) {
        val code = raw.trim()
        if (busy || message != null || pending != null || code.isEmpty() || code == lastCode) return
        if (venueID.isBlank()) { success = false; message = "Выберите заведение"; return }
        lastCode = code
        scanKey = UUID.randomUUID().toString()
        when {
            code.startsWith("AYANT-PTS:") -> {
                val mode = venue?.pointsMode ?: "flat"
                if (mode == "cashback" || mode == "bands") {
                    pending = PendingEarn(code, mode, code.split(":").getOrNull(1).orEmpty())
                } else submitScan(code, null, null, null)
            }
            code.startsWith("AYANT-RDM:") -> submitRedeem(code)
            else -> submitScan(code, null, null, null)
        }
    }

    // H15 — квитанция поверх всего.
    receipt?.let { r ->
        HostScanReceipt(
            awarded = r.awarded, balance = r.balance, billAmount = r.billAmount,
            modeLabel = r.modeLabel, replayed = r.replayed,
            onScanMore = { receipt = null; resetScan() },
            // Вкладкой «Готово» просто возвращает к камере, закрывать нечего.
            onDone = { receipt = null; if (onBack != null) onBack() else resetScan() },
        )
        return
    }

    // H14 — сумма чека.
    pending?.let { p ->
        HostBillAmountScreen(
            pending = p,
            venue = venue,
            onBack = { pending = null; resetScan() },
            onSubmit = { amount, bandIndex ->
                pending = null
                submitScan(p.code, amount, bandIndex, amount)
            },
        )
        return
    }

    // H13 — сканер.
    Box(Modifier.fillMaxSize()) {
        HostScanSurface()
        Column(Modifier.fillMaxSize()) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (onBack != null) {
                    HostScanIconButton(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.action_back), onBack)
                } else {
                    Spacer(Modifier.size(40.dp))
                }
                Spacer(Modifier.weight(1f))
                Text(stringResource(R.string.host_scan_title), fontSize = 16.sp,
                    fontWeight = FontWeight.Bold, color = Color.White)
                Spacer(Modifier.weight(1f))
                Spacer(Modifier.size(40.dp))
            }

            if (fixedVenueID == null && hostState.venues.size > 1) {
                Box(Modifier.padding(horizontal = 20.dp, vertical = 6.dp)) {
                    Row(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp))
                            .background(Color.White.copy(alpha = 0.2f))
                            .clickable { venueMenu = true }
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(venue?.name ?: stringResource(R.string.action_choose),
                            fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                    }
                    DropdownMenu(expanded = venueMenu, onDismissRequest = { venueMenu = false }) {
                        hostState.venues.forEach { v ->
                            DropdownMenuItem(text = { Text(v.name) },
                                onClick = { venueID = v.id; venueMenu = false })
                        }
                    }
                }
            }

            Spacer(Modifier.weight(1f))
            Box(Modifier.align(Alignment.CenterHorizontally)) {
                HostScanReticle { QrScannerView(onResult = { handle(it) }, onNoPermission = {}) }
            }

            // Информационные чипы: тип определяет префикс QR, это не переключатели.
            Row(
                Modifier.align(Alignment.CenterHorizontally).padding(top = 22.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                HostScanKindChip(stringResource(R.string.host_kind_points), venue?.asVenue?.pointsActive == true)
                HostScanKindChip(stringResource(R.string.host_kind_stamp), venue?.asVenue?.stampsActive == true)
                HostScanKindChip(stringResource(R.string.host_kind_coupon), true)
            }

            Text(
                stringResource(R.string.host_scan_hint_auto),
                fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                color = Color.White.copy(alpha = 0.8f), textAlign = TextAlign.Center, lineHeight = 19.sp,
                modifier = Modifier.padding(horizontal = 34.dp, vertical = 16.dp),
            )
            Spacer(Modifier.weight(1f))

            // Ручной ввод
            Column(
                Modifier.padding(horizontal = 20.dp).padding(bottom = 18.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    stringResource(R.string.host_scan_manual_label).uppercase(),
                    fontSize = 11.5.sp, fontWeight = FontWeight.Black, letterSpacing = 1.2.sp,
                    color = Color.White.copy(alpha = 0.75f),
                )
                BasicTextField(
                    value = manualCode,
                    onValueChange = { manualCode = it.uppercase() },
                    singleLine = true,
                    textStyle = TextStyle(
                        color = Color.White, fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold, letterSpacing = 3.sp,
                        textAlign = TextAlign.Center,
                    ),
                    cursorBrush = androidx.compose.ui.graphics.SolidColor(Color.White),
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color.White.copy(alpha = 0.2f))
                        .padding(vertical = 14.dp),
                )
                val canSubmit = manualCode.isNotBlank() && !busy
                Box(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(18.dp))
                        .background(Color.White.copy(alpha = if (canSubmit) 1f else 0.6f))
                        .clickable(enabled = canSubmit) { handle(manualCode) }
                        .padding(vertical = 16.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(stringResource(R.string.host_scan_check_code), fontSize = 16.sp,
                        fontWeight = FontWeight.Bold, color = c.accentDeep)
                }
            }
        }

        // Busy / ошибка — карточкой поверх.
        if (busy || message != null) {
            Box(
                Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.35f)),
                contentAlignment = Alignment.Center,
            ) {
                Column(
                    Modifier
                        .widthIn(max = 340.dp)
                        .padding(horizontal = 28.dp)
                        .clip(RoundedCornerShape(24.dp))
                        .background(c.surface)
                        .padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    if (busy) {
                        CircularProgressIndicator(color = c.accent)
                        Text(stringResource(R.string.host_scan_checking), fontSize = 16.sp,
                            fontWeight = FontWeight.SemiBold, color = c.ink)
                    } else {
                        Text(
                            message.orEmpty(), fontSize = 16.sp, fontWeight = FontWeight.Bold,
                            color = if (success) c.open else Color(0xFFE8556B),
                            textAlign = TextAlign.Center,
                        )
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(16.dp))
                                .background(c.accentGradient)
                                .clickable { resetScan() }
                                .padding(vertical = 14.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(stringResource(R.string.host_scan_more), fontSize = 16.sp,
                                fontWeight = FontWeight.Bold, color = Color.White)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - H14 Сумма чека

@Composable
private fun HostBillAmountScreen(
    pending: PendingEarn,
    venue: HostVenueDTO?,
    onBack: () -> Unit,
    onSubmit: (amount: Int?, bandIndex: Int?) -> Unit,
) {
    val c = AyantTheme.colors
    var billText by remember { mutableStateOf("") }
    val amount = billText.toIntOrNull() ?: 0
    // Предпросмотр считает домен — своей формулы здесь нет.
    val preview = PointsMath.award(
        config = PointsConfig(
            pointsEnabled = true,
            pointsMode = venue?.pointsMode ?: "flat",
            pointsFlat = venue?.pointsFlat ?: 0,
            pointsBands = venue?.pointsBands.orEmpty(),
            cashbackPercent = venue?.cashbackPercent ?: 0.0,
        ),
        billAmount = amount,
        bandIndex = null,
    ).valueOrNull() ?: 0

    Box(Modifier.fillMaxSize()) {
        HostScanSurface()
        Column(Modifier.fillMaxSize()) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                HostScanIconButton(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.action_back), onBack)
                Spacer(Modifier.weight(1f))
                Text(stringResource(R.string.host_bill_title), fontSize = 16.sp,
                    fontWeight = FontWeight.Bold, color = Color.White, maxLines = 1)
                Spacer(Modifier.weight(1f))
                Spacer(Modifier.size(40.dp))
            }

            // Гость
            Row(
                Modifier.padding(horizontal = 20.dp, vertical = 8.dp).fillMaxWidth()
                    .clip(RoundedCornerShape(18.dp))
                    .background(Color.White.copy(alpha = 0.2f)).padding(14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(
                    Modifier.size(38.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.28f)),
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.Filled.Person, null, tint = Color.White, modifier = Modifier.size(16.dp)) }
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.host_guest), fontSize = 14.sp,
                        fontWeight = FontWeight.Bold, color = Color.White)
                    Text(
                        if (pending.userID.isEmpty()) stringResource(R.string.host_qr_recognised)
                        else "ID ${pending.userID.take(8)}",
                        fontSize = 11.5.sp, color = Color.White.copy(alpha = 0.8f),
                    )
                }
                Text(
                    stringResource(R.string.host_qr_valid), fontSize = 12.sp,
                    fontWeight = FontWeight.Bold, color = c.open, maxLines = 1,
                    modifier = Modifier.clip(CircleShape).background(Color.White)
                        .padding(horizontal = 11.dp, vertical = 6.dp),
                )
            }

            if (pending.mode == "cashback") {
                Spacer(Modifier.weight(1f))
                Column(
                    Modifier.align(Alignment.CenterHorizontally),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        if (amount > 0) thousands(amount) else "0",
                        fontSize = 64.sp, fontWeight = FontWeight.Black,
                        letterSpacing = (-3.2).sp, lineHeight = 64.sp, color = Color.White,
                    )
                    Text(stringResource(R.string.som), fontSize = 14.sp,
                        color = Color.White.copy(alpha = 0.8f))
                }
                Row(
                    Modifier.align(Alignment.CenterHorizontally).padding(top = 16.dp)
                        .clip(CircleShape).background(Color.White)
                        .padding(horizontal = 14.dp, vertical = 9.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Box(Modifier.size(7.dp).clip(CircleShape).background(Color(0xFFFF9500)))
                    Text(
                        stringResource(R.string.host_earn_preview, preview),
                        fontSize = 13.5.sp, fontWeight = FontWeight.Black, color = c.accentDeep,
                    )
                }
                Spacer(Modifier.weight(1f))
                HostAmountKeypad(billText, { billText = it }, Modifier.padding(horizontal = 20.dp))
                Box(
                    Modifier
                        .padding(horizontal = 20.dp).padding(top = 16.dp, bottom = 18.dp)
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(18.dp))
                        .background(Color.White.copy(alpha = if (amount > 0) 1f else 0.6f))
                        .clickable(enabled = amount > 0) { onSubmit(amount, null) }
                        .padding(vertical = 16.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(stringResource(R.string.host_award_points), fontSize = 16.sp,
                        fontWeight = FontWeight.Bold, color = c.accentDeep)
                }
            } else {
                val bands = venue?.pointsBands.orEmpty()
                Column(
                    Modifier.verticalScroll(rememberScrollState()).padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    bands.forEachIndexed { idx, band ->
                        Row(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(17.dp))
                                .background(Color.White.copy(alpha = 0.2f))
                                .clickable { onSubmit(null, idx) }
                                .padding(horizontal = 18.dp, vertical = 16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                if (idx == bands.size - 1) "${band.maxAmount}+ сом" else "до ${band.maxAmount} сом",
                                fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Color.White,
                            )
                            Spacer(Modifier.weight(1f))
                            Text("+${band.points}", fontSize = 17.sp,
                                fontWeight = FontWeight.Black, color = Color.White)
                        }
                    }
                    if (bands.isEmpty()) {
                        Text(
                            stringResource(R.string.host_bands_not_set),
                            fontSize = 14.sp, color = Color.White.copy(alpha = 0.85f),
                            textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Shared surfaces

/** Accent surface: 160° gradient, white radial highlight, riso hatch. */
@Composable
fun HostScanSurface() {
    Box(
        Modifier
            .fillMaxSize()
            .drawBehind {
                drawRect(
                    Brush.linearGradient(
                        listOf(Color(0xFFFF5A1F), Color(0xFFFF9500)),
                        start = androidx.compose.ui.geometry.Offset(size.width * 0.329f, size.height * 0.030f),
                        end = androidx.compose.ui.geometry.Offset(size.width * 0.671f, size.height * 0.970f),
                    )
                )
                drawRect(
                    Brush.radialGradient(
                        listOf(Color.White.copy(alpha = 0.22f), Color.Transparent),
                        center = androidx.compose.ui.geometry.Offset(size.width * 0.5f, size.height * 0.38f),
                        radius = size.minDimension * 0.8f,
                    )
                )
            }
            .ayantRisoHatch(alpha = 0.10f)
    )
}

@Composable
fun HostScanIconButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    onClick: () -> Unit,
) {
    Box(
        Modifier.size(40.dp).clip(CircleShape)
            .background(Color.White.copy(alpha = 0.24f)).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, contentDescription = label, tint = Color.White, modifier = Modifier.size(16.dp)) }
}

/** Reticle: the dark camera window + white corner brackets + sweep line. */
@Composable
fun HostScanReticle(camera: @Composable () -> Unit) {
    val reduceMotion = rememberReduceMotion()
    val side = 238.dp
    val transition = androidx.compose.animation.core.rememberInfiniteTransition(label = "reticle")
    val t by transition.animateFloat(
        initialValue = 0f, targetValue = if (reduceMotion) 0f else 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(AyantTiming.SCANNER_SWEEP_MS, easing = AyantMotion.EnterEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "reticleSweep",
    )
    Box(Modifier.size(side), contentAlignment = Alignment.Center) {
        Box(
            Modifier.fillMaxSize().clip(RoundedCornerShape(34.dp)).background(Color(0xFF241C16)),
        ) { camera() }
        // Внутренняя тень — «глубина» окна.
        Box(
            Modifier.fillMaxSize().clip(RoundedCornerShape(34.dp)).drawBehind {
                drawRoundRect(
                    color = Color.Black.copy(alpha = 0.55f),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(34.dp.toPx()),
                    style = Stroke(width = 30.dp.toPx()),
                )
            }.blur(18.dp)
        )
        HostCornerBrackets(Modifier.fillMaxSize().padding(10.dp))
        if (!reduceMotion) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 14.dp)
                    .height(2.dp)
                    .graphicsLayer { translationY = (t - 0.5f) * (side.toPx() - 40.dp.toPx()) }
                    .background(Color.White)
            )
        }
    }
}

@Composable
private fun HostCornerBrackets(modifier: Modifier = Modifier) {
    Box(
        modifier.drawBehind {
            val len = 50.dp.toPx()
            val w = 4.dp.toPx()
            val strong = Color.White
            val soft = Color.White.copy(alpha = 0.6f)
            // Верхний-левый и нижний-правый — яркие; остальные приглушены.
            drawLine(strong, androidx.compose.ui.geometry.Offset(0f, len), androidx.compose.ui.geometry.Offset(0f, 0f), w)
            drawLine(strong, androidx.compose.ui.geometry.Offset(0f, 0f), androidx.compose.ui.geometry.Offset(len, 0f), w)
            drawLine(soft, androidx.compose.ui.geometry.Offset(size.width - len, 0f), androidx.compose.ui.geometry.Offset(size.width, 0f), w)
            drawLine(soft, androidx.compose.ui.geometry.Offset(size.width, 0f), androidx.compose.ui.geometry.Offset(size.width, len), w)
            drawLine(strong, androidx.compose.ui.geometry.Offset(size.width, size.height - len), androidx.compose.ui.geometry.Offset(size.width, size.height), w)
            drawLine(strong, androidx.compose.ui.geometry.Offset(size.width, size.height), androidx.compose.ui.geometry.Offset(size.width - len, size.height), w)
            drawLine(soft, androidx.compose.ui.geometry.Offset(len, size.height), androidx.compose.ui.geometry.Offset(0f, size.height), w)
            drawLine(soft, androidx.compose.ui.geometry.Offset(0f, size.height), androidx.compose.ui.geometry.Offset(0f, size.height - len), w)
        }
    )
}

/** Informational chip: the QR prefix picks the branch, so these are not switches. */
@Composable
fun HostScanKindChip(title: String, enabled: Boolean) {
    val c = AyantTheme.colors
    Text(
        title, fontSize = 13.sp, fontWeight = FontWeight.Bold,
        color = if (enabled) c.accentDeep else Color.White,
        modifier = Modifier
            .clip(CircleShape)
            .background(if (enabled) Color.White else Color.White.copy(alpha = 0.24f))
            .padding(horizontal = 15.dp, vertical = 9.dp),
    )
}

/** 3×4 keypad. Amount capped at 7 digits. */
@Composable
fun HostAmountKeypad(text: String, onChange: (String) -> Unit, modifier: Modifier = Modifier) {
    val rows = listOf(listOf("1", "2", "3"), listOf("4", "5", "6"), listOf("7", "8", "9"), listOf("00", "0", "⌫"))
    Column(modifier, verticalArrangement = Arrangement.spacedBy(9.dp)) {
        rows.forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                row.forEach { key ->
                    Box(
                        Modifier
                            .weight(1f)
                            .height(56.dp)
                            .clip(RoundedCornerShape(17.dp))
                            .background(Color.White.copy(alpha = 0.2f))
                            .clickable {
                                if (key == "⌫") {
                                    onChange(text.dropLast(1))
                                } else {
                                    val next = (text + key).trimStart('0')
                                    if (next.length <= 7) onChange(next)
                                }
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        if (key == "⌫") {
                            Icon(Icons.AutoMirrored.Filled.Backspace, null, tint = Color.White,
                                modifier = Modifier.size(21.dp))
                        } else {
                            Text(key, fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - H15 Начислено

/**
 * Receipt after an award. The host is working, not celebrating — rings and a
 * check, no confetti. Every value comes from the `scanCoupon` response.
 */
@Composable
fun HostScanReceipt(
    awarded: Int,
    balance: Int,
    billAmount: Int?,
    modeLabel: String?,
    replayed: Boolean,
    onScanMore: () -> Unit,
    onDone: () -> Unit,
) {
    val c = AyantTheme.colors
    val reduceMotion = rememberReduceMotion()
    val disc = remember { Animatable(if (reduceMotion) 1f else 0f) }
    val counter = remember { Animatable(if (reduceMotion) 1f else 0f) }
    LaunchedEffect(Unit) { if (!reduceMotion) disc.animateTo(1f, AyantMotion.pop()) }
    LaunchedEffect(Unit) {
        if (!reduceMotion) counter.animateTo(
            1f, tween(1000, easing = androidx.compose.animation.core.CubicBezierEasing(0.33f, 1f, 0.68f, 1f)),
        )
    }
    val shown = (awarded * counter.value).roundToInt()

    Box(Modifier.fillMaxSize().background(c.canvas), contentAlignment = Alignment.Center) {
        Column(Modifier.padding(30.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.size(116.dp), contentAlignment = Alignment.Center) {
                Box(
                    Modifier
                        .size(100.dp)
                        .graphicsLayer {
                            val s = 0.6f + 0.4f * disc.value
                            scaleX = s; scaleY = s; alpha = disc.value
                        }
                        .clip(CircleShape)
                        .background(c.accentGradient),
                    contentAlignment = Alignment.Center,
                ) { Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(44.dp)) }
            }
            Spacer(Modifier.height(24.dp))
            Text(
                "+$shown", fontSize = 58.sp, fontWeight = FontWeight.Black,
                letterSpacing = (-3).sp, lineHeight = 58.sp,
                style = TextStyle(brush = c.accentGradient),
            )
            Spacer(Modifier.height(10.dp))
            Text(stringResource(R.string.host_points_awarded), fontSize = 22.sp,
                fontWeight = FontWeight.Black, letterSpacing = (-0.9).sp, color = c.ink)
            if (replayed) {
                Spacer(Modifier.height(8.dp))
                Text(
                    stringResource(R.string.host_replayed), fontSize = 12.5.sp,
                    fontWeight = FontWeight.SemiBold, color = c.inkSoft, textAlign = TextAlign.Center,
                )
            }

            Spacer(Modifier.height(24.dp))
            Column(
                Modifier.widthIn(max = 300.dp).fillMaxWidth()
                    .clip(RoundedCornerShape(24.dp)).background(c.surface)
                    .padding(horizontal = 18.dp),
            ) {
                ReceiptRow(stringResource(R.string.host_guest), stringResource(R.string.host_guest))
                billAmount?.let { ReceiptRow(stringResource(R.string.host_bill_title), "${thousands(it)} ${stringResource(R.string.som)}") }
                modeLabel?.let { ReceiptRow(stringResource(R.string.host_award_row), it) }
                ReceiptRow(stringResource(R.string.host_new_balance), "$balance", accent = true)
            }

            Spacer(Modifier.height(24.dp))
            Box(
                Modifier.widthIn(max = 300.dp).fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp)).background(c.accentGradient)
                    .clickable(onClick = onScanMore).padding(vertical = 16.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(stringResource(R.string.host_scan_more), fontSize = 16.sp,
                    fontWeight = FontWeight.Bold, color = Color.White)
            }
            Spacer(Modifier.height(14.dp))
            Text(
                stringResource(R.string.action_done), fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold, color = c.inkSoft,
                modifier = Modifier.clickable(onClick = onDone),
            )
        }
    }
}

@Composable
private fun ReceiptRow(title: String, value: String, accent: Boolean = false) {
    val c = AyantTheme.colors
    Row(
        Modifier.fillMaxWidth().padding(vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, fontSize = 13.5.sp, color = c.inkSoft)
        Spacer(Modifier.weight(1f))
        Text(value, fontSize = 14.5.sp, fontWeight = FontWeight.Bold,
            color = if (accent) c.accentText else c.ink, maxLines = 1)
    }
}

// MARK: - Models & helpers

data class PendingEarn(val code: String, val mode: String, val userID: String)

data class EarnReceipt(
    val awarded: Int,
    val balance: Int,
    val billAmount: Int?,
    val modeLabel: String?,
    val replayed: Boolean,
)

/** «Кэшбэк 5%» / «30 за визит» — строка квитанции. */
private fun modeLabel(v: HostVenueDTO): String? = when (v.pointsMode) {
    "cashback" -> if (v.cashbackPercent > 0) "Кэшбэк ${percent(v.cashbackPercent)}%" else null
    "bands" -> "По сумме чека"
    else -> if (v.pointsFlat > 0) "${v.pointsFlat} за визит" else null
}

private fun percent(v: Double): String =
    if (v == v.roundToInt().toDouble()) v.roundToInt().toString()
    else String.format("%.1f", v).replace('.', ',')

private fun thousands(v: Int): String {
    val symbols = DecimalFormatSymbols().apply { groupingSeparator = ' ' }
    return DecimalFormat("#,###", symbols).format(v)
}

/**
 * Полноэкранная обёртка сканера для мест без доступа к навигации (карточка
 * заведения, список). Раньше здесь был `HostScannerDialog` — маленький
 * AlertDialog; редизайн требует ту же поверхность, что и с FAB.
 */
@Composable
fun HostScannerOverlay(host: HostViewModel, fixedVenueID: String?, onDismiss: () -> Unit) {
    androidx.compose.ui.window.Dialog(
        onDismissRequest = onDismiss,
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false),
    ) {
        HostScannerScreen(host, fixedVenueID = fixedVenueID, onBack = onDismiss)
    }
}
