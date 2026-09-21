package kg.ayant.app.ui.bonus

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import kg.ayant.app.R
import kg.ayant.app.domain.contract.RedeemOutcome
import kg.ayant.app.domain.model.PointsReward
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenuePointsCard
import kg.ayant.app.ui.components.QrCode
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.domain.AppError
import kg.ayant.app.domain.LoadState
import kg.ayant.app.domain.PointsIntent
import kg.ayant.app.domain.PointsMath
import kg.ayant.app.domain.RedeemPhase
import kg.ayant.app.ui.vm.PointsViewModel
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VenuePointsScreen(vm: PointsViewModel, onBack: () -> Unit) {
    val c = AyantTheme.colors
    // Опроса нет: подписка на живой поток заводится в RootScaffold, обновления
    // приходят snapshot-листенером.
    val state by vm.state.collectAsState()
    Scaffold(
        containerColor = c.canvas,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.points_title), fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.action_back)) } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = c.canvas, titleContentColor = c.ink),
            )
        },
    ) { padding ->
        // Экран — функция от одного значения состояния: свои флаги загрузки не нужны.
        when (val cards = state.cards) {
            LoadState.Idle, LoadState.Loading ->
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = c.accent)
                }

            is LoadState.Failed ->
                PointsPlaceholder(padding, c.accent, c.ink, c.inkSoft,
                    title = stringResource(R.string.points_load_failed),
                    body = pointsErrorText(cards.error))

            is LoadState.Loaded<*> ->
                if (state.sortedCards.isEmpty()) {
                    PointsPlaceholder(padding, c.accent, c.ink, c.inkSoft,
                        title = stringResource(R.string.points_empty_title),
                        body = stringResource(R.string.points_empty_body))
                } else {
                    Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        state.sortedCards.forEach { VenuePointsCardView(it, state.userID) }
                    }
                }
        }
    }
}

@Composable
fun VenuePointsCardView(card: VenuePointsCard, userID: String) {
    val c = AyantTheme.colors
    var showQR by remember { mutableStateOf(false) }
    val canScan = userID.isNotEmpty()
    val earnCode = "AYANT-PTS:$userID"

    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(28.dp)).background(c.accentGradient).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(46.dp).clip(RoundedCornerShape(14.dp)).background(Color.White.copy(alpha = 0.92f)), contentAlignment = Alignment.Center) {
                Text(card.venueName.take(1).uppercase(), fontSize = 20.sp, fontWeight = FontWeight.Black, color = c.accentDeep)
            }
            Column(Modifier.padding(start = 12.dp).weight(1f)) {
                Text(card.venueName, fontSize = 20.sp, fontWeight = FontWeight.Black, color = Color.White, maxLines = 1)
                Text(stringResource(R.string.points_your_points), fontSize = 13.sp, color = Color.White.copy(alpha = 0.92f))
            }
            Text(
                "${card.balance}", fontSize = 22.sp, fontWeight = FontWeight.Black, color = Color.White,
                modifier = Modifier.clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.22f)).padding(horizontal = 12.dp, vertical = 6.dp),
            )
        }
        if (showQR && canScan) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                QrCode(earnCode, size = 168)
                Text(stringResource(R.string.qr_show_to_staff), fontSize = 12.sp, color = Color.White.copy(alpha = 0.92f))
            }
        }
        Text(
            if (showQR) stringResource(R.string.loyalty_hide_qr) else stringResource(R.string.points_show_qr_earn), fontSize = 15.sp, fontWeight = FontWeight.Bold, color = c.accentDeep,
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Color.White.copy(alpha = 0.92f))
                .clickable(enabled = canScan) { showQR = !showQR }.padding(vertical = 13.dp),
            textAlign = TextAlign.Center,
        )
        if (!canScan) Text(stringResource(R.string.qr_sign_in_title), fontSize = 12.sp, color = Color.White.copy(alpha = 0.92f))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VenuePointsVenueScreen(venueID: String, app: AppViewModel, vm: PointsViewModel, onBack: () -> Unit) {
    val c = AyantTheme.colors
    val state by vm.state.collectAsState()
    val venue = app.venue(id = venueID) ?: run {
        Box(Modifier.fillMaxSize().background(c.canvas), contentAlignment = Alignment.Center) { Text(stringResource(R.string.venue_not_found)) }
        return
    }
    val card = state.card(venueID) ?: VenuePointsCard(venue.id, venue.name)
    val balance = state.balance(venueID)
    val activeRewards = venue.pointsRewards.filter { it.active }
    var pendingReward by remember { mutableStateOf<PointsReward?>(null) }

    Scaffold(
        containerColor = c.canvas,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.points_title), fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.action_back)) } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = c.canvas, titleContentColor = c.ink),
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            VenuePointsCardView(card, state.userID)

            if (activeRewards.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(stringResource(R.string.host_rewards), fontSize = 17.sp, fontWeight = FontWeight.Bold, color = c.ink)
                    activeRewards.forEach { reward ->
                        val affordable = balance >= reward.cost
                        Row(
                            Modifier.fillMaxWidth().alpha(if (affordable) 1f else 0.55f)
                                .clip(RoundedCornerShape(16.dp)).background(c.surface)
                                .border(0.5.dp, c.hairline, RoundedCornerShape(16.dp))
                                .clickable(enabled = affordable) { pendingReward = reward }
                                .padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(if (reward.type == "money") "💸" else "🎁", fontSize = 22.sp)
                            Column(Modifier.padding(start = 12.dp).weight(1f)) {
                                Text(reward.title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = c.ink, maxLines = 1)
                                Text(
                                    if (reward.type == "money") stringResource(R.string.points_reward_money_from, reward.cost) else stringResource(R.string.qr_points_count, reward.cost),
                                    fontSize = 12.sp, color = c.inkSoft,
                                )
                            }
                            Icon(
                                if (affordable) Icons.Filled.ChevronRight else Icons.Filled.Lock,
                                null, tint = c.inkSoft, modifier = Modifier.size(18.dp),
                            )
                        }
                    }
                }
            }

            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(c.surface).border(0.5.dp, c.hairline, RoundedCornerShape(20.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.loyalty_how_title), fontSize = 17.sp, fontWeight = FontWeight.Bold, color = c.ink)
                Text(stringResource(R.string.points_how_body), fontSize = 15.sp, color = c.inkSoft)
            }
        }
    }

    pendingReward?.let { reward ->
        RedeemDialog(venue, reward, balance, state.userID, vm) { pendingReward = null }
    }
}

@Composable
private fun RedeemDialog(
    venue: Venue, reward: PointsReward, balance: Int, userID: String,
    vm: PointsViewModel, onDismiss: () -> Unit,
) {
    val c = AyantTheme.colors
    val phase by vm.state.collectAsState()
    val redeem = phase.redeem
    val isMoney = reward.type == "money"
    val staffScan = venue.redeemMode != "customerInitiated"
    var spend by remember { mutableStateOf(reward.cost) }
    val done = (redeem as? RedeemPhase.Done)?.receipt
    val error = (redeem as? RedeemPhase.Failed)?.error
    val working = redeem.isWorking
    val cost = if (isMoney) spend else reward.cost
    val somOff = PointsMath.somOff(reward, spend) ?: 0
    val redeemCode = if (isMoney) "AYANT-RDM:$userID:${reward.id}:$spend" else "AYANT-RDM:$userID:${reward.id}"

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(reward.title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                if (isMoney) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        TextButton(enabled = spend - 10 >= reward.cost, onClick = { spend -= 10 }) { Text("−10") }
                        Text(stringResource(R.string.points_short, spend), fontWeight = FontWeight.Bold, color = c.ink)
                        TextButton(enabled = spend + 10 <= balance, onClick = { spend += 10 }) { Text("+10") }
                    }
                    Text(stringResource(R.string.points_discount_som, somOff), fontSize = 13.sp, color = c.inkSoft)
                } else {
                    Text(stringResource(R.string.points_cost, reward.cost), fontSize = 14.sp, color = c.inkSoft)
                }
                when {
                    done != null -> Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            stringResource(R.string.points_redeemed_customer, done.redeemed, done.balance),
                            fontWeight = FontWeight.SemiBold, color = c.open,
                        )
                        if (done.replayed) {
                            // Сервер узнал повтор по ключу идемпотентности — второй раз не списали.
                            Text(stringResource(R.string.points_redeem_replayed),
                                fontSize = 12.sp, color = c.inkSoft)
                        }
                    }
                    staffScan -> Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        QrCode(redeemCode, size = 200)
                        Text(stringResource(R.string.points_redeem_show_qr), fontSize = 12.sp, color = c.inkSoft)
                    }
                }
                error?.let { Text(pointsErrorText(it), fontSize = 13.sp, color = Color(0xFFD32F2F)) }
            }
        },
        confirmButton = {
            if (done == null && !staffScan) {
                TextButton(enabled = !working && cost <= balance, onClick = {
                    vm.send(PointsIntent.Redeem(venue.id, reward.id, if (isMoney) spend else 0))
                }) { Text(if (working) stringResource(R.string.points_redeeming) else stringResource(R.string.points_redeem_button, cost)) }
            } else {
                TextButton(onClick = { vm.send(PointsIntent.DismissRedeem); onDismiss() }) { Text(stringResource(R.string.action_done)) }
            }
        },
        dismissButton = {
            if (done == null) TextButton(onClick = { vm.send(PointsIntent.DismissRedeem); onDismiss() }) { Text(stringResource(R.string.action_cancel)) }
        },
    )
}

/**
 * Один словарь кодов на всю фичу: тот же код приходит и от клиентской проверки
 * (`PointsMath`), и от сервера, поэтому текст должен быть один.
 * Зеркалит `PointsMessages` на iOS.
 */
@Composable
internal fun pointsErrorText(error: AppError): String = stringResource(
    when (error.code) {
        "insufficient" -> R.string.points_err_insufficient
        "reward_not_found" -> R.string.points_err_reward_not_found
        "redeem_not_allowed" -> R.string.points_err_redeem_not_allowed
        "below_min" -> R.string.points_err_below_min
        "key_reused" -> R.string.points_err_key_reused
        "unauthenticated", "no_token", "bad_token" -> R.string.points_err_unauthenticated
        "permission_denied" -> R.string.points_err_permission_denied
        "network" -> R.string.points_err_network
        else -> R.string.points_err_generic
    }
)

/** Пустое состояние / ошибка списка — одинаковая рамка, разный текст. */
@Composable
private fun PointsPlaceholder(
    padding: PaddingValues, accent: Color, ink: Color, inkSoft: Color,
    title: String, body: String,
) {
    Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(32.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(Icons.Filled.Star, null, tint = accent, modifier = Modifier.size(48.dp))
            Text(title, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = ink)
            Text(body, fontSize = 14.sp, color = inkSoft)
        }
    }
}
