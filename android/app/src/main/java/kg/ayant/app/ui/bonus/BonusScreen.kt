package kg.ayant.app.ui.bonus

import androidx.compose.runtime.collectAsState
import androidx.compose.animation.AnimatedVisibility
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
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Wallet
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import kg.ayant.app.R
import kg.ayant.app.core.shareText
import kg.ayant.app.domain.model.Reward
import kg.ayant.app.ui.theme.AyantIconTile
import kg.ayant.app.ui.theme.AyantScreenTitle
import kg.ayant.app.ui.theme.AyantSectionHeader
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantCard
import kg.ayant.app.ui.vm.BonusViewModel
import kg.ayant.app.ui.vm.CouponViewModel
import kotlinx.coroutines.delay

@Composable
fun BonusScreen(
    app: kg.ayant.app.ui.vm.AppViewModel,
    bonus: BonusViewModel,
    coupons: CouponViewModel,
    onCoupons: () -> Unit,
    onLoyalty: () -> Unit,
    onPoints: () -> Unit,
    onSnake: () -> Unit,
    onTetris: () -> Unit = {},
    points: kg.ayant.app.ui.vm.PointsViewModel? = null,
    loyalty: kg.ayant.app.ui.vm.LoyaltyViewModel? = null,
) {
    val c = AyantTheme.colors
    // ВНИМАНИЕ: общие ViewModel приходят параметром из RootScaffold.
    // Вызов viewModel() здесь дал бы ЭКЗЕМПЛЯР НА МАРШРУТ (владелец —
    // NavBackStackEntry), а не общий на приложение: экран остался бы
    // с пустым/несинхронизированным состоянием.
    // Читаем состояние, а не свойство VM: счётчик обновится сам при выдаче купона.
    val activeCoupons by coupons.coupons.collectAsState()
    val activeCount = activeCoupons.count { !it.used }

    LaunchedEffect(Unit) { bonus.start() }

    Box(Modifier.fillMaxSize().background(c.canvas)) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp).padding(top = 8.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            // Header row: editorial title + the subordinate global-bonus pill.
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                Column(Modifier.weight(1f)) {
                    Text(
                        stringResource(R.string.tab_wallet),
                        fontSize = 44.sp, fontWeight = FontWeight.Black,
                        letterSpacing = (-2.5).sp, lineHeight = 41.sp, color = c.ink,
                    )
                    Text(
                        stringResource(R.string.wallet_subtitle),
                        fontSize = 14.sp, color = c.inkSoft,
                        modifier = Modifier.padding(top = 9.dp),
                    )
                }
                Column(
                    Modifier
                        .clip(CircleShape)
                        .background(c.surface)
                        .clickable(onClick = onCoupons)
                        .padding(horizontal = 14.dp, vertical = 9.dp),
                    horizontalAlignment = Alignment.End,
                ) {
                    Text(
                        stringResource(R.string.wallet_global_bonus), fontSize = 10.5.sp,
                        fontWeight = FontWeight.Black, letterSpacing = 0.4.sp,
                        color = Color(0xFF9A9188),
                    )
                    Text(
                        "${bonus.balance}", fontSize = 16.sp, fontWeight = FontWeight.Black,
                        letterSpacing = (-0.5).sp, color = c.ink,
                    )
                }
            }

            // Per-venue points deck.
            val pointsState = points?.state?.collectAsState()?.value
            val pointsCards = pointsState?.sortedCards.orEmpty()
            val venuesByID = remember(app.venues) { app.venues.associateBy { it.id } }
            if (pointsCards.isNotEmpty()) {
                WalletDeck(
                    cards = pointsCards,
                    venues = venuesByID,
                    onOpen = { onPoints() },
                    modifier = Modifier.padding(horizontal = (-16).dp),
                )
            } else {
                Column(Modifier.fillMaxWidth().ayantCard(padding = 20, radius = 26)) {
                    Text(
                        stringResource(R.string.wallet_empty_title),
                        fontSize = 16.sp, fontWeight = FontWeight.Bold, color = c.ink,
                    )
                    Text(
                        stringResource(R.string.wallet_empty_body),
                        fontSize = 13.sp, color = c.inkSoft,
                        modifier = Modifier.padding(top = 8.dp),
                    )
                }
            }

            // Stamp card — the liveliest loyalty card.
            val loyaltyCards = loyalty?.cards?.collectAsState()?.value.orEmpty()
            val stampCard = loyaltyCards.filter { it.stamps > 0 }.maxByOrNull { it.stamps }
                ?: loyaltyCards.firstOrNull()
            stampCard?.let {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        stringResource(R.string.wallet_stamp_card).uppercase(),
                        fontSize = 11.5.sp, fontWeight = FontWeight.Black,
                        letterSpacing = 1.2.sp, color = Color(0xFF9A9188),
                    )
                    WalletStampCard(it)
                }
            }

            // Rewards
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.bonus_spend), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = c.ink)
                    Spacer(Modifier.weight(1f))
                    Text(
                        stringResource(R.string.title_my_coupons) + if (activeCount > 0) " ($activeCount)" else "",
                        fontSize = 14.sp, fontWeight = FontWeight.Bold, color = c.accentText,
                        modifier = Modifier.clickable(onClick = onCoupons),
                    )
                }
                CouponViewModel.catalog.forEach { reward -> RewardRow(reward, bonus, coupons, app) }
            }

            // Points link (баллы САН)
            Row(
                Modifier.fillMaxWidth().ayantCard(padding = 12).clickable(onClick = onPoints),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                AyantIconTile(Icons.Filled.Star, size = 44)
                Text("Баллы САН", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = c.ink, modifier = Modifier.padding(start = 14.dp))
                Spacer(Modifier.weight(1f))
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = c.inkSoft, modifier = Modifier.size(18.dp))
            }

            // Loyalty link
            Row(
                Modifier.fillMaxWidth().ayantCard(padding = 12).clickable(onClick = onLoyalty),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                AyantIconTile(Icons.Filled.CardGiftcard, size = 44)
                Text(stringResource(R.string.title_loyalty), fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = c.ink, modifier = Modifier.padding(start = 14.dp))
                Spacer(Modifier.weight(1f))
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = c.inkSoft, modifier = Modifier.size(18.dp))
            }

            // Мини-игры. Обе начисляют через общий дневной лимит, поэтому
            // добавление игры не меняет экономику бонусов.
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                AyantSectionHeader(stringResource(R.string.bonus_games_header))
                GameTile("🐍", stringResource(R.string.game_snake), stringResource(R.string.game_snake_sub), Modifier.fillMaxWidth(), onSnake)
                GameTile("🧱", stringResource(R.string.game_tetris), stringResource(R.string.game_tetris_sub), Modifier.fillMaxWidth(), onTetris)
            }
        }

        // Reward toast
        val reward = bonus.lastReward
        AnimatedVisibility(visible = reward != null, modifier = Modifier.align(Alignment.TopCenter).padding(top = 8.dp)) {
            if (reward != null) {
                LaunchedEffect(reward) { delay(1800); bonus.clearRewardFlag() }
                Text(
                    stringResource(R.string.bonus_reward_toast, reward), fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Color.White,
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(c.open).padding(horizontal = 18.dp, vertical = 10.dp),
                )
            }
        }
    }
}

@Composable
private fun RewardRow(reward: Reward, bonus: BonusViewModel, coupons: CouponViewModel, app: kg.ayant.app.ui.vm.AppViewModel) {
    val c = AyantTheme.colors
    val context = androidx.compose.ui.platform.LocalContext.current
    var menu by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().ayantCard(padding = 12), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(54.dp).clip(RoundedCornerShape(16.dp)).background(c.accent.copy(alpha = 0.10f)), contentAlignment = Alignment.Center) {
            Text(reward.emoji, fontSize = 24.sp)
        }
        Column(Modifier.padding(start = 14.dp).weight(1f)) {
            Text(reward.title, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = c.ink)
            Text(stringResource(R.string.bonus_cost, reward.cost), fontSize = 13.sp, color = c.inkSoft)
        }
        Box {
            val enabled = bonus.balance >= reward.cost
            Text(
                "${reward.cost}", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Color.White,
                modifier = Modifier
                    .clip(RoundedCornerShape(50))
                    .background(if (enabled) c.accent else c.inkSoft.copy(alpha = 0.5f))
                    .clickable(enabled = enabled) { menu = true }
                    .padding(horizontal = 16.dp, vertical = 9.dp),
            )
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(text = { Text(stringResource(R.string.bonus_redeem_self)) }, onClick = { menu = false; coupons.redeem(reward, bonus) })
                DropdownMenuItem(text = { Text(stringResource(R.string.bonus_gift_friend)) }, onClick = {
                    menu = false
                    if (bonus.spend(reward.cost)) {
                        val code = kg.ayant.app.domain.CodeGen.giftCode()
                        app.createGiftBackend(reward.title, code, app.currentUserName)   // so the link can be claimed
                        context.shareText(context.getString(R.string.bonus_gift_share, reward.title, code), "Ayant")
                    }
                })
            }
        }
    }
}

@Composable
private fun GameTile(emoji: String, title: String, subtitle: String, modifier: Modifier, onClick: () -> Unit) {
    val c = AyantTheme.colors
    Row(
        modifier.ayantCard(padding = 12).clickable(onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(c.accent.copy(alpha = 0.12f)), contentAlignment = Alignment.Center) {
            Text(emoji, fontSize = 22.sp)
        }
        Column(Modifier.padding(start = 12.dp)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = c.ink)
            Text(subtitle, fontSize = 12.sp, color = c.inkSoft)
        }
    }
}

private fun plural(n: Int): String {
    val n10 = n % 10; val n100 = n % 100
    if (n10 == 1 && n100 != 11) return "бонус"
    if (n10 in 2..4 && n100 !in 12..14) return "бонуса"
    return "бонусов"
}
