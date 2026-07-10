package kg.ayant.app.ui.bonus

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
import kg.ayant.app.data.model.Reward
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
    onCoupons: () -> Unit,
    onLoyalty: () -> Unit,
    onSnake: () -> Unit,
    onTetris: () -> Unit,
) {
    val c = AyantTheme.colors
    val bonus: BonusViewModel = viewModel()
    val coupons: CouponViewModel = viewModel()

    LaunchedEffect(Unit) { bonus.start() }

    Box(Modifier.fillMaxSize().background(c.canvas)) {
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp).padding(top = 8.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            AyantScreenTitle(stringResource(R.string.title_bonuses))

            // Wallet card
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(26.dp)).background(c.accentGradient).padding(22.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Row(verticalAlignment = Alignment.Top) {
                    Column(Modifier.weight(1f)) {
                        Text(stringResource(R.string.bonus_balance), fontSize = 15.sp, color = Color.White.copy(alpha = 0.9f))
                        Text("${bonus.balance}", fontSize = 52.sp, fontWeight = FontWeight.Black, color = Color.White)
                        Text(plural(bonus.balance), fontSize = 15.sp, color = Color.White.copy(alpha = 0.9f))
                    }
                    Box(
                        Modifier.size(52.dp).clip(CircleShape).background(Color.White.copy(alpha = 0.18f)).clickable(onClick = onCoupons),
                        contentAlignment = Alignment.Center,
                    ) { Icon(Icons.Filled.Wallet, null, tint = Color.White, modifier = Modifier.size(22.dp)) }
                }
                // Progress
                Box(Modifier.fillMaxWidth().height(12.dp).clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.28f))) {
                    Box(Modifier.fillMaxWidth(bonus.progress.coerceIn(0f, 1f)).height(12.dp).clip(RoundedCornerShape(50)).background(Color.White))
                }
                Text(stringResource(R.string.bonus_until_reward, bonus.remaining), fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Color.White)
            }

            // Rewards
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.bonus_spend), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = c.ink)
                    Spacer(Modifier.weight(1f))
                    Text(
                        stringResource(R.string.title_my_coupons) + if (coupons.activeCount > 0) " (${coupons.activeCount})" else "",
                        fontSize = 14.sp, fontWeight = FontWeight.Bold, color = c.accent,
                        modifier = Modifier.clickable(onClick = onCoupons),
                    )
                }
                CouponViewModel.catalog.forEach { reward -> RewardRow(reward, bonus, coupons, app) }
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

            // Games
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                AyantSectionHeader(stringResource(R.string.bonus_games_header))
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    GameTile("🐍", stringResource(R.string.game_snake), stringResource(R.string.game_snake_sub), Modifier.weight(1f), onSnake)
                    GameTile("🧱", stringResource(R.string.game_tetris), stringResource(R.string.game_tetris_sub), Modifier.weight(1f), onTetris)
                }
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
                        val code = "GIFT-${java.util.UUID.randomUUID().toString().take(8).uppercase()}"
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
