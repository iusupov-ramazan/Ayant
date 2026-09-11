package kg.ayant.app.ui.bonus

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.border
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
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.location.LocationManager
import kg.ayant.app.ui.components.QrCode
import kg.ayant.app.ui.theme.AyantRadius
import kg.ayant.app.ui.theme.AyantTiming
import kg.ayant.app.ui.theme.rememberReduceMotion
import kg.ayant.app.ui.theme.AyantShadow
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantShadow
import kg.ayant.app.ui.theme.gradientColors
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.ui.vm.PointsViewModel
import kg.ayant.app.domain.pointsActive

/**
 * «Ваш QR» — the central FAB destination. Mirrors `MyQRView.swift`.
 *
 * Renders the personal `AYANT-PTS:<userID>` code; the venue scans it and the
 * `scanCoupon` callable (branch C) awards the points. Nothing is computed or
 * written here.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MyQrScreen(
    app: AppViewModel,
    points: PointsViewModel,
    location: LocationManager,
    /// `null`, когда экран открыт вкладкой: возвращаться некуда.
    onBack: (() -> Unit)?,
    onScanVenue: () -> Unit = {},
) {
    val c = AyantTheme.colors
    val state by points.state.collectAsState()
    val userID = state.userID
    val reduceMotion = rememberReduceMotion()

    // Начисление: сотрудник сканирует код → Cloud Function пишет баланс →
    // snapshot-листенер приносит его сюда. Клиент ничего не считает, он лишь
    // замечает приход и анимирует счётчик К серверному значению.
    var baseline by remember { mutableStateOf<Map<String, Int>>(emptyMap()) }
    var earned by remember { mutableStateOf<EarnedEvent?>(null) }
    LaunchedEffect(state.cards) {
        val current = (state.cards.valueOrNull() ?: emptyList()).associate { it.venueID to it.balance }
        if (baseline.isNotEmpty()) {
            // Незнакомая карта на первом снимке — не начисление, а подгрузка.
            current.forEach { (venueID, balance) ->
                val was = baseline[venueID] ?: return@forEach
                if (balance > was && earned == null) {
                    val card = (state.cards.valueOrNull() ?: emptyList()).firstOrNull { it.venueID == venueID }
                    earned = EarnedEvent(
                        delta = balance - was,
                        venueName = card?.venueName.orEmpty(),
                        venueSubtitle = app.venue(id = venueID)?.district ?: app.selectedCity.name,
                        newBalance = balance,
                    )
                }
            }
        }
        baseline = current
    }
    val totalBalance = (state.cards.valueOrNull() ?: emptyList()).sumOf { it.balance }

    // Venues with points enabled, nearest first.
    val nearby: List<Venue> = app.venues
        .filter { it.pointsActive }
        .sortedBy { location.distanceKm(it.latitude, it.longitude) ?: Double.MAX_VALUE }
        .take(8)

    Scaffold(
        containerColor = c.canvas,
        topBar = {
            TopAppBar(
                title = {},
                navigationIcon = {
                    if (onBack != null) {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.action_back), tint = c.ink)
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = c.canvas),
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 26.dp),
        ) {
            Text(
                stringResource(R.string.title_your_qr),
                fontSize = 40.sp, fontWeight = FontWeight.Black,
                letterSpacing = (-2.2).sp, color = c.ink,
            )
            Text(
                stringResource(R.string.qr_subtitle),
                fontSize = 14.sp, color = c.inkSoft, lineHeight = 20.sp,
                modifier = Modifier.widthIn(max = 280.dp).padding(top = 9.dp),
            )

            Spacer(Modifier.height(22.dp))
            if (userID.isEmpty()) SignInPrompt() else QrCard(app, totalBalance, userID)

            if (nearby.isNotEmpty()) {
                Spacer(Modifier.height(22.dp))
                Text(
                    stringResource(R.string.qr_nearby).uppercase(),
                    fontSize = 11.5.sp, fontWeight = FontWeight.Black,
                    letterSpacing = 1.2.sp, color = c.inkSoft,
                )
                Spacer(Modifier.height(12.dp))
                Row(
                    Modifier.horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(9.dp),
                ) {
                    nearby.forEach { venue ->
                        NearbyCard(venue, state.balance(venue.id))
                    }
                }
            }

            Spacer(Modifier.height(20.dp))
            Box(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(18.dp))
                    .background(c.surfaceMuted)
                    .clickable(onClick = onScanVenue)
                    .padding(vertical = 15.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    stringResource(R.string.qr_scan_venue), fontSize = 14.5.sp,
                    fontWeight = FontWeight.Bold, color = c.ink,
                )
            }
        }
    }

    earned?.let { event ->
        PointsEarnedScreen(
            delta = event.delta,
            venueName = event.venueName,
            venueSubtitle = event.venueSubtitle,
            newBalance = event.newBalance,
        ) {
            earned = null
            onBack?.invoke()
        }
    }
}

/** Что принёс snapshot-листенер, пока экран открыт. */
private data class EarnedEvent(
    val delta: Int,
    val venueName: String,
    val venueSubtitle: String,
    val newBalance: Int,
)

@Composable
private fun QrCard(app: AppViewModel, totalBalance: Int, userID: String) {
    val c = AyantTheme.colors
    val reduceMotion = rememberReduceMotion()
    val shape = RoundedCornerShape(32.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .ayantShadow(AyantShadow.QrCard, shape)
            .background(c.surface, shape)
            .border(0.5.dp, c.hairline, shape)
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(app.currentUserName, fontSize = 14.5.sp, fontWeight = FontWeight.Bold, color = c.ink)
                Text(app.selectedCity.name, fontSize = 12.sp, color = c.inkSoft)
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(stringResource(R.string.qr_total_points), fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = c.inkSoft)
                // Small accent numeral on white → accentTextStrong, never the fill orange.
                Text(
                    "$totalBalance", fontSize = 20.sp, fontWeight = FontWeight.Black,
                    letterSpacing = (-0.7).sp, color = c.accentTextStrong,
                )
            }
        }
        Spacer(Modifier.height(20.dp))
        Box(contentAlignment = Alignment.Center) {
            QrCode(text = "AYANT-PTS:$userID", size = 196)
            if (!reduceMotion) {
                // Луч сканирования бежит сверху вниз по коду (ANIMATIONS.md §7).
                val sweep = rememberInfiniteTransition(label = "qrSweep")
                val t by sweep.animateFloat(
                    initialValue = 0f, targetValue = 1f,
                    animationSpec = infiniteRepeatable(
                        animation = tween(AyantTiming.QR_SWEEP_MS, easing = LinearEasing),
                        repeatMode = RepeatMode.Restart,
                    ),
                    label = "qrSweepPhase",
                )
                Box(
                    Modifier
                        .fillMaxWidth(0.9f)
                        .height(3.dp)
                        .graphicsLayer { translationY = (t - 0.5f) * 196.dp.toPx() }
                        .background(
                            Brush.horizontalGradient(
                                listOf(Color.Transparent, c.accent, Color.Transparent)
                            )
                        )
                )
            }
        }
        Spacer(Modifier.height(18.dp))
        Text(
            stringResource(R.string.qr_show_to_staff),
            fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold,
            color = c.inkSoft, textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun SignInPrompt() {
    val c = AyantTheme.colors
    val shape = RoundedCornerShape(32.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .background(c.surface, shape)
            .border(0.5.dp, c.hairline, shape)
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            stringResource(R.string.qr_sign_in_title),
            fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
            color = c.ink, textAlign = TextAlign.Center,
        )
        Text(
            stringResource(R.string.qr_sign_in_body),
            fontSize = 13.sp, color = c.inkSoft, textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun NearbyCard(venue: Venue, balance: Int) {
    val c = AyantTheme.colors
    val shape = RoundedCornerShape(20.dp)
    Column(
        Modifier
            .width(132.dp)
            .background(c.surface, shape)
            .border(0.5.dp, c.hairline, shape)
            .padding(13.dp),
    ) {
        Box(
            Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(12.dp))
                .background(Brush.linearGradient(venue.gradientColors))
        )
        Text(
            venue.name, fontSize = 13.5.sp, fontWeight = FontWeight.Bold,
            color = c.ink, maxLines = 2, modifier = Modifier.padding(top = 10.dp),
        )
        Text(
            stringResource(R.string.qr_points_count, balance),
            fontSize = 12.sp, color = c.inkSoft, modifier = Modifier.padding(top = 3.dp),
        )
    }
}
