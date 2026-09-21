package kg.ayant.app.ui.bonus

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.core.ReleaseFlags
import kg.ayant.app.domain.CodeGen
import kg.ayant.app.domain.Tetris
import kg.ayant.app.domain.model.Coupon
import kg.ayant.app.domain.model.LoyaltyCard
import kg.ayant.app.domain.model.Reward
import kg.ayant.app.domain.model.VenuePointsCard
import kg.ayant.app.domain.stampsActive
import kg.ayant.app.ui.theme.AyantRadius
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantCard
import kg.ayant.app.ui.theme.ayantRise
import kg.ayant.app.ui.theme.ayantScreenEnter
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.ui.vm.BonusViewModel
import kg.ayant.app.ui.vm.CouponViewModel
import kg.ayant.app.ui.vm.LoyaltyViewModel
import kg.ayant.app.ui.vm.PointsViewModel
import kotlinx.coroutines.delay

/**
 * «Бонусы» (SCREENS.md G6) — один дом для всех трёх валют лояльности:
 * карусель карт «Баллы САН» и штампов, и глобальные бонусы (нарочно
 * подчинённые: их почти невозможно накопить, и это by design).
 * Mirrors `BonusHubView.swift`.
 *
 * ВНИМАНИЕ: общие ViewModel приходят параметром из RootScaffold. Вызов
 * viewModel() здесь дал бы ЭКЗЕМПЛЯР НА МАРШРУТ (владелец — NavBackStackEntry),
 * а не общий на приложение: экран остался бы с пустым состоянием.
 *
 * @param onVenuePoints карта баллов ведёт на экран баллов заведения (iOS:
 *   `VenuePointsScreen(venue)`); по умолчанию — в общий список.
 * @param onVenueLoyalty карта штампов ведёт туда же, куда и баннер на странице
 *   заведения (iOS: `VenueLoyaltyScreen(venue)`); по умолчанию — в общий список.
 */
@Composable
fun BonusScreen(
    app: AppViewModel,
    bonus: BonusViewModel,
    coupons: CouponViewModel,
    onCoupons: () -> Unit,
    onLoyalty: () -> Unit,
    onPoints: () -> Unit,
    onSnake: () -> Unit,
    onTetris: () -> Unit = {},
    points: PointsViewModel? = null,
    loyalty: LoyaltyViewModel? = null,
    onVenuePoints: (String) -> Unit = { onPoints() },
    onVenueLoyalty: (String) -> Unit = { onLoyalty() },
) {
    val c = AyantTheme.colors
    val screenPadding = 16.dp
    // Читаем состояние, а не свойство VM: счётчик обновится сам при выдаче купона.
    val allCoupons by coupons.coupons.collectAsState()
    val activeCount = allCoupons.count { !it.used }
    val balance by bonus.balanceFlow.collectAsState()

    // Заведения по id — картам нужны градиент, категория и конфиг наград.
    val venuesByID = remember(app.venues) { app.venues.associateBy { it.id } }
    val pointsState = points?.state?.collectAsState()?.value
    val pointsCards = pointsState?.sortedCards.orEmpty()
    val loyaltyCards = loyalty?.cards?.collectAsState()?.value.orEmpty()
    // Карты штампов, которым есть что показать: со штампами или заведения,
    // где штампы — действующая механика. Пустые карты заведений, которые
    // перешли на баллы, остаются в «Все карты», но карусель не засоряют.
    val stampCards = loyaltyCards.filter { card ->
        card.stamps > 0 || (venuesByID[card.venueID]?.stampsActive ?: false)
    }
    // Порядок карусели: сначала баллы (главное), потом штампы.
    val walletPages: List<WalletPage> =
        pointsCards.map { WalletPage.Points(it) } + stampCards.map { WalletPage.Stamps(it) }

    var justClaimed by remember { mutableStateOf<Coupon?>(null) }
    var pendingReward by remember { mutableStateOf<Reward?>(null) }
    var pendingGift by remember { mutableStateOf<Reward?>(null) }
    var giftShare by remember { mutableStateOf<GiftShare?>(null) }

    LaunchedEffect(Unit) { bonus.start() }
    // Глобальный кошелёк выключен — каталог наград не нужен.
    LaunchedEffect(Unit) { if (ReleaseFlags.GLOBAL_BONUS_WALLET) coupons.loadRewards() }

    Box(Modifier.fillMaxSize().background(c.canvas)) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = screenPadding)
                .padding(top = 8.dp, bottom = 28.dp)
                .ayantScreenEnter(),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            HeaderRow(balance = balance, onCoupons = onCoupons)

            if (walletPages.isEmpty()) {
                EmptyPointsCard()
            } else {
                WalletCarousel(
                    pages = walletPages,
                    venues = venuesByID,
                    onOpenPoints = { onVenuePoints(it.venueID) },
                    onOpenStamps = { onVenueLoyalty(it.venueID) },
                    screenPadding = screenPadding,
                )
            }

            // Глобальный кошелёк (награды, подарки, игры) выключен на релиз:
            // без него хаб — карусель баллов и штампов и строка в купоны.
            if (ReleaseFlags.GLOBAL_BONUS_WALLET) {
                RewardsSection(
                    coupons = coupons, balance = balance, activeCount = activeCount,
                    onCoupons = onCoupons, onPoints = onPoints, onLoyalty = onLoyalty,
                    onRedeem = { pendingReward = it }, onGift = { pendingGift = it },
                )
                GamesSection(bonus = bonus, onSnake = onSnake, onTetris = onTetris)
            } else {
                CouponsSection(activeCount = activeCount, onCoupons = onCoupons, onPoints = onPoints, onLoyalty = onLoyalty)
            }
        }

        // Тост «+N» — только с включённым кошельком: без него не наступает.
        if (ReleaseFlags.GLOBAL_BONUS_WALLET) {
            RewardToast(bonus, Modifier.align(Alignment.TopCenter))
        }
    }

    if (!ReleaseFlags.GLOBAL_BONUS_WALLET) return

    // MARK: Алерты и листы глобального кошелька

    justClaimed?.let {
        AlertDialog(
            onDismissRequest = { justClaimed = null },
            title = { Text(stringResource(R.string.bonus_coupon_claimed_title)) },
            text = { Text(stringResource(R.string.bonus_coupon_claimed_body)) },
            confirmButton = { TextButton(onClick = { justClaimed = null }) { Text(stringResource(R.string.action_great)) } },
        )
    }
    pendingReward?.let { reward ->
        AlertDialog(
            onDismissRequest = { pendingReward = null },
            title = { Text(stringResource(R.string.bonus_redeem_confirm_title)) },
            text = { Text(stringResource(R.string.bonus_redeem_confirm_body, reward.title, reward.cost)) },
            confirmButton = {
                TextButton(onClick = {
                    pendingReward = null
                    coupons.redeem(reward, bonus)?.let { justClaimed = it }
                }) { Text(stringResource(R.string.bonus_redeem_confirm_action, reward.cost)) }
            },
            dismissButton = { TextButton(onClick = { pendingReward = null }) { Text(stringResource(R.string.action_cancel)) } },
        )
    }
    pendingGift?.let { reward ->
        AlertDialog(
            onDismissRequest = { pendingGift = null },
            title = { Text(stringResource(R.string.bonus_gift_confirm_title)) },
            text = { Text(stringResource(R.string.bonus_gift_confirm_body, reward.cost, reward.title)) },
            confirmButton = {
                TextButton(onClick = {
                    pendingGift = null
                    // Как `AppStore.createGift`: списать, записать подарок в бэкенд
                    // (иначе ссылку не заберут), отдать ссылку в лист шаринга.
                    if (bonus.spend(reward.cost)) {
                        val code = CodeGen.giftCode()
                        app.createGiftBackend(reward.title, code, app.currentUserName)
                        giftShare = GiftShare(code = code, title = reward.title)
                    }
                }) { Text(stringResource(R.string.bonus_gift_confirm_action, reward.cost)) }
            },
            dismissButton = { TextButton(onClick = { pendingGift = null }) { Text(stringResource(R.string.action_cancel)) } },
        )
    }
    giftShare?.let { GiftShareSheet(code = it.code, title = it.title, onDismiss = { giftShare = null }) }
}

/** Подарок для листа шаринга — код и название купона. */
data class GiftShare(val code: String, val title: String)

// MARK: - Шапка

@Composable
private fun HeaderRow(balance: Int, onCoupons: () -> Unit) {
    val c = AyantTheme.colors
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
        Spacer(Modifier.width(8.dp))
        // Глобальный кошелёк — визуально подчинённый: он зарабатывается почти
        // в ноль и не должен спорить с баллами САН. Скрыт вместе с кошельком.
        if (ReleaseFlags.GLOBAL_BONUS_WALLET) {
            Column(
                Modifier
                    .clip(CircleShape)
                    .background(c.surface)
                    .border(0.5.dp, c.hairline, CircleShape)
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
                    "$balance", fontSize = 16.sp, fontWeight = FontWeight.Black,
                    letterSpacing = (-0.5).sp, color = c.ink,
                )
            }
        }
    }
}

@Composable
private fun EmptyPointsCard() {
    val c = AyantTheme.colors
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

// MARK: - Купоны без глобального кошелька

/**
 * «Мои купоны» + ссылки на полные списки. Без кошелька в купоны вели бы только
 * капсула «БОНУСЫ» и заголовок наград — оба спрятаны вместе с ним, а купоны на
 * акции заведений выдаются и без него.
 */
@Composable
private fun CouponsSection(activeCount: Int, onCoupons: () -> Unit, onPoints: () -> Unit, onLoyalty: () -> Unit) {
    val c = AyantTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(
            Modifier.fillMaxWidth().ayantCard(padding = 15, radius = 22).clickable(onClick = onCoupons),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            GradientIconTile(Icons.Filled.ConfirmationNumber)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    stringResource(R.string.title_my_coupons), fontSize = 14.5.sp,
                    fontWeight = FontWeight.Bold, letterSpacing = (-0.2).sp, color = c.ink,
                )
                Text(
                    if (activeCount > 0) stringResource(R.string.bonus_coupons_row_active, activeCount)
                    else stringResource(R.string.bonus_coupons_row_sub),
                    fontSize = 12.5.sp, color = c.inkSoft,
                )
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = Color(0xFF9A9188), modifier = Modifier.size(18.dp))
        }
        ListLinks(onPoints = onPoints, onLoyalty = onLoyalty)
    }
}

/** Карусель показывает не все карты штампов — ссылки на полные списки остаются. */
@Composable
private fun ListLinks(onPoints: () -> Unit, onLoyalty: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(top = 2.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        ListLink(stringResource(R.string.bonus_all_points), Icons.Filled.Star, Modifier.weight(1f), onPoints)
        ListLink(stringResource(R.string.bonus_all_cards), Icons.Filled.CreditCard, Modifier.weight(1f), onLoyalty)
    }
}

@Composable
private fun ListLink(title: String, icon: ImageVector, modifier: Modifier, onClick: () -> Unit) {
    val c = AyantTheme.colors
    Row(
        modifier
            .clip(RoundedCornerShape(AyantRadius.tile))
            .background(c.surfaceMuted)
            .clickable(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(icon, null, tint = c.ink, modifier = Modifier.size(15.dp))
        Text(title, fontSize = 13.5.sp, fontWeight = FontWeight.Bold, color = c.ink)
    }
}

// MARK: - Потратить бонусы

@Composable
private fun RewardsSection(
    coupons: CouponViewModel, balance: Int, activeCount: Int,
    onCoupons: () -> Unit, onPoints: () -> Unit, onLoyalty: () -> Unit,
    onRedeem: (Reward) -> Unit, onGift: (Reward) -> Unit,
) {
    val c = AyantTheme.colors
    val rewards by coupons.rewards.collectAsState()
    Column(verticalArrangement = Arrangement.spacedBy(13.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.host_rewards).uppercase(),
                fontSize = 11.5.sp, fontWeight = FontWeight.Black,
                letterSpacing = 1.2.sp, color = Color(0xFF9A9188),
            )
            Spacer(Modifier.weight(1f))
            Text(
                if (activeCount > 0) stringResource(R.string.bonus_my_coupons_count, activeCount)
                else stringResource(R.string.title_my_coupons),
                fontSize = 12.5.sp, fontWeight = FontWeight.Bold,
                // Акцент мелким текстом — только контрастный вариант.
                color = c.accentText,
                modifier = Modifier.clickable(onClick = onCoupons),
            )
        }
        if (rewards.isEmpty()) {
            // Партнёров ещё нет. Показывать награды без заведения нельзя:
            // купон по такой награде сотрудник не погасит.
            Text(
                stringResource(R.string.bonus_rewards_empty),
                fontSize = 13.5.sp, color = c.inkSoft,
                modifier = Modifier.padding(vertical = 2.dp),
            )
        } else {
            rewards.forEachIndexed { index, reward ->
                RewardRow(
                    reward = reward, affordable = balance >= reward.cost,
                    onRedeem = { onRedeem(reward) }, onGift = { onGift(reward) },
                    modifier = Modifier.ayantRise(index, key = reward.id, staggerMs = 70, durationMs = 500),
                )
            }
        }
        ListLinks(onPoints = onPoints, onLoyalty = onLoyalty)
    }
}

@Composable
private fun RewardRow(
    reward: Reward, affordable: Boolean,
    onRedeem: () -> Unit, onGift: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    var menu by remember { mutableStateOf(false) }
    Row(
        modifier.fillMaxWidth().alpha(if (affordable) 1f else 0.55f).ayantCard(padding = 15, radius = 22),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        GradientIconTile(Icons.Filled.Star)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                reward.title, fontSize = 14.5.sp, fontWeight = FontWeight.Bold,
                letterSpacing = (-0.2).sp, color = c.ink,
            )
            // Где гасить — часть самой награды: без заведения купон
            // некуда предъявить, и человек должен видеть куда идти.
            Text(
                if (reward.venueName.isEmpty()) stringResource(R.string.bonus_cost, reward.cost)
                else stringResource(R.string.bonus_reward_cost_venue, reward.cost, reward.venueName),
                fontSize = 12.5.sp, color = c.inkSoft, maxLines = 1,
            )
        }
        Box {
            Text(
                if (affordable) stringResource(R.string.bonus_redeem) else stringResource(R.string.bonus_not_enough),
                fontSize = 13.sp, fontWeight = FontWeight.Bold,
                color = if (affordable) Color.White else Color(0xFF9A9188),
                modifier = Modifier
                    .clip(RoundedCornerShape(14.dp))
                    .then(
                        if (affordable) Modifier.background(c.accentGradient)
                        else Modifier.background(c.surfaceMuted)
                    )
                    .clickable(enabled = affordable) { menu = true }
                    .padding(horizontal = 15.dp, vertical = 10.dp),
            )
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.bonus_redeem_self)) },
                    leadingIcon = { Icon(Icons.Filled.ConfirmationNumber, null) },
                    onClick = { menu = false; onRedeem() },
                )
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.bonus_gift_friend)) },
                    leadingIcon = { Icon(Icons.Filled.CardGiftcard, null) },
                    onClick = { menu = false; onGift() },
                )
            }
        }
    }
}

/** Плитка 46dp на фирменном градиенте с белым глифом. */
@Composable
private fun GradientIconTile(icon: ImageVector) {
    Box(
        Modifier.size(46.dp).clip(RoundedCornerShape(15.dp)).background(AyantTheme.colors.accentGradient),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, tint = Color.White, modifier = Modifier.size(20.dp)) }
}

// MARK: - Игры (тише, ниже)

@Composable
private fun GamesSection(bonus: BonusViewModel, onSnake: () -> Unit, onTetris: () -> Unit) {
    val c = AyantTheme.colors
    // Дневной потолок меняется при начислении — читаем после каждого тоста.
    val lastReward by bonus.lastRewardFlow.collectAsState()
    val remaining = remember(lastReward) { bonus.remainingGameplayToday }
    Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                stringResource(R.string.bonus_games_header).uppercase(),
                fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp, color = c.inkSoft,
            )
            Box(Modifier.weight(1f).height(0.5.dp).background(c.hairline))
            // Дневной потолок — часть правил игры, а не сюрприз: без этой
            // строки человек доходит до лимита и думает, что игра сломалась.
            Text(
                if (remaining > 0) stringResource(R.string.bonus_games_left_today, remaining)
                else stringResource(R.string.bonus_games_done_today),
                fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold, color = c.inkSoft,
            )
        }
        GameTile(
            emoji = "🐍", title = stringResource(R.string.game_snake),
            subtitle = stringResource(R.string.game_snake_sub),
            gradient = listOf(Color(0xFF1FBF75), Color(0xFF0E9E86)), onClick = onSnake,
        )
        GameTile(
            emoji = "🧱", title = stringResource(R.string.game_tetris),
            subtitle = stringResource(R.string.game_tetris_sub_fmt, Tetris.BONUS_PER_LINE),
            gradient = listOf(Color(0xFF7C6BE8), Color(0xFFB39CF0)), onClick = onTetris,
        )
    }
}

@Composable
private fun GameTile(emoji: String, title: String, subtitle: String, gradient: List<Color>, onClick: () -> Unit) {
    val c = AyantTheme.colors
    val shape = RoundedCornerShape(18.dp)
    Row(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(c.surface)
            .border(0.5.dp, c.hairline, shape)
            .clickable(onClick = onClick)
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            Modifier.size(44.dp).clip(RoundedCornerShape(14.dp)).background(Brush.linearGradient(gradient)),
            contentAlignment = Alignment.Center,
        ) { Text(emoji, fontSize = 22.sp) }
        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = c.ink)
            Text(subtitle, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = c.inkSoft)
        }
    }
}

// MARK: - Тост «+N»

@Composable
private fun RewardToast(bonus: BonusViewModel, modifier: Modifier = Modifier) {
    val c = AyantTheme.colors
    val reward by bonus.lastRewardFlow.collectAsState()
    AnimatedVisibility(
        visible = reward != null,
        enter = slideInVertically { -it } + fadeIn(),
        exit = slideOutVertically { -it } + fadeOut(),
        modifier = modifier.padding(top = 8.dp),
    ) {
        val shown = reward ?: 0
        LaunchedEffect(reward) { delay(1800); bonus.clearRewardFlag() }
        Text(
            stringResource(R.string.bonus_reward_toast, shown),
            fontSize = 15.sp, fontWeight = FontWeight.Bold, color = Color.White,
            modifier = Modifier.clip(CircleShape).background(c.open).padding(horizontal = 18.dp, vertical = 10.dp),
        )
    }
}
