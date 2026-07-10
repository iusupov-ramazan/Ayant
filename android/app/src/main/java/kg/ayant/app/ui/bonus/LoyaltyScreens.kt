package kg.ayant.app.ui.bonus

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clip
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import kg.ayant.app.R
import kg.ayant.app.data.model.LoyaltyCard
import kg.ayant.app.ui.components.QrCode
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.ui.vm.LoyaltyViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoyaltyScreen(onBack: () -> Unit) {
    val c = AyantTheme.colors
    val vm: LoyaltyViewModel = viewModel()
    Scaffold(
        containerColor = c.canvas,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.title_loyalty), fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.action_back)) } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = c.canvas, titleContentColor = c.ink),
            )
        },
    ) { padding ->
        if (vm.cards.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(32.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.CardGiftcard, null, tint = c.accent, modifier = Modifier.size(48.dp))
                    Text(stringResource(R.string.loyalty_empty_title), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink)
                    Text(stringResource(R.string.loyalty_empty_body), fontSize = 14.sp, color = c.inkSoft)
                }
            }
        } else {
            Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                vm.cards.forEach { LoyaltyCardView(it, vm.userID) }
            }
        }
    }
}

@Composable
fun LoyaltyCardView(card: LoyaltyCard, userID: String) {
    val c = AyantTheme.colors
    var showQR by remember { mutableStateOf(false) }
    val canScan = userID.isNotEmpty()
    val loyaltyCode = "AYANT-CARD:$userID:${card.venueID}"

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
                Text(stringResource(R.string.loyalty_reward, card.reward), fontSize = 13.sp, color = Color.White.copy(alpha = 0.92f), maxLines = 1)
            }
            Text(
                "${card.stamps}/${card.goal}", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color.White,
                modifier = Modifier.clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.22f)).padding(horizontal = 11.dp, vertical = 5.dp),
            )
        }
        // Stamp grid
        LazyVerticalGrid(
            columns = GridCells.Fixed(minOf(maxOf(card.goal, 1), 6)),
            modifier = Modifier.fillMaxWidth().height((((card.goal + 5) / 6) * 56).dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
            userScrollEnabled = false,
        ) {
            items(card.goal) { i ->
                val filled = i < card.stamps
                Box(
                    Modifier.aspectRatio(1f).clip(RoundedCornerShape(12.dp))
                        .background(if (filled) Color.White else Color.White.copy(alpha = 0.12f))
                        .then(if (!filled) Modifier.border(1.5.dp, Color.White.copy(alpha = 0.6f), RoundedCornerShape(12.dp)) else Modifier),
                    contentAlignment = Alignment.Center,
                ) {
                    if (filled) Icon(Icons.Filled.Check, null, tint = c.accentDeep, modifier = Modifier.size(18.dp))
                    else if (i == card.goal - 1) Icon(Icons.Filled.CardGiftcard, null, tint = Color.White.copy(alpha = 0.85f), modifier = Modifier.size(16.dp))
                }
            }
        }
        if (card.completedRounds > 0) {
            Text(stringResource(R.string.loyalty_rewards_earned, card.completedRounds), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
        }
        if (showQR && canScan) {
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                QrCode(loyaltyCode, size = 168)
                Text(stringResource(R.string.loyalty_show_hint), fontSize = 12.sp, color = Color.White.copy(alpha = 0.92f))
            }
        }
        Text(
            if (showQR) stringResource(R.string.loyalty_hide_qr) else stringResource(R.string.loyalty_show_qr), fontSize = 15.sp, fontWeight = FontWeight.Bold, color = c.accentDeep,
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Color.White.copy(alpha = 0.92f))
                .clickable(enabled = canScan) { showQR = !showQR }.padding(vertical = 13.dp),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
        if (!canScan) Text(stringResource(R.string.loyalty_signin_hint), fontSize = 12.sp, color = Color.White.copy(alpha = 0.92f))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VenueLoyaltyScreen(venueID: String, app: AppViewModel, onBack: () -> Unit) {
    val c = AyantTheme.colors
    val vm: LoyaltyViewModel = viewModel()
    val venue = app.venue(id = venueID) ?: run {
        Box(Modifier.fillMaxSize().background(c.canvas), contentAlignment = Alignment.Center) { Text(stringResource(R.string.venue_not_found)) }
        return
    }
    val card = vm.cardOrNew(venue.id, venue.name, venue.loyaltyGoal, venue.loyaltyReward)

    Scaffold(
        containerColor = c.canvas,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.venue_loyalty_card), fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.action_back)) } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = c.canvas, titleContentColor = c.ink),
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            LoyaltyCardView(card, vm.userID)
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(c.surface).border(0.5.dp, c.hairline, RoundedCornerShape(20.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.loyalty_how_title), fontSize = 17.sp, fontWeight = FontWeight.Bold, color = c.ink)
                Text(stringResource(R.string.loyalty_how_body, venue.loyaltyGoal, venue.loyaltyReward), fontSize = 15.sp, color = c.inkSoft)
            }
        }
    }
}
