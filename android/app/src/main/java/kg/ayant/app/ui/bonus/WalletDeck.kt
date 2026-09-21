package kg.ayant.app.ui.bonus

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PageSize
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.core.AppLanguage
import kg.ayant.app.core.localizedName
import kg.ayant.app.domain.model.LoyaltyCard
import kg.ayant.app.domain.model.PointsReward
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenuePointsCard
import kg.ayant.app.ui.theme.AccentGold
import kg.ayant.app.ui.theme.AyantMetrics
import kg.ayant.app.ui.theme.AyantMotion
import kg.ayant.app.ui.theme.AyantRadius
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantPressScale
import kg.ayant.app.ui.theme.ayantRisoHatch
import kg.ayant.app.ui.theme.gradientColors
import kg.ayant.app.ui.theme.rememberReduceMotion
import kg.ayant.app.ui.theme.stampBrush
import kotlin.math.roundToInt

/*
 * «Бонусы»: карусель карт «Баллы САН» и карт штампов (SCREENS.md G6).
 * Mirrors `WalletDeck.swift`.
 *
 * Три валюты в одном месте: баллы заведения (главное), карта штампов и
 * глобальные бонусы (нарочно подчинённые — они почти ничего не стоят).
 */

/** Та же высота у карты баллов и карты штампов — они соседи в карусели. */
private val CARD_HEIGHT = 198.dp

/**
 * Страница карусели: карта баллов заведения или карта штампов.
 *
 * У одного заведения действует ровно одна механика (`LoyaltyKind`), но
 * локальный кэш штампов переживает переключение на баллы, поэтому id
 * страницы несёт префикс — иначе две страницы одного заведения совпали бы.
 */
sealed class WalletPage {
    abstract val id: String

    data class Points(val card: VenuePointsCard) : WalletPage() {
        override val id: String get() = "points-${card.venueID}"
    }

    data class Stamps(val card: LoyaltyCard) : WalletPage() {
        override val id: String get() = "stamps-${card.venueID}"
    }
}

/**
 * Горизонтальная карусель с прилипанием к карте: сначала все карты баллов,
 * потом карты штампов. Следующая карта выглядывает справа — так сразу видно,
 * что есть ещё. Раньше это была стопка со смещением, и её приходилось
 * «прокручивать» тапами по выглядывающим краям — на ощупь это не читалось.
 *
 * @param screenPadding горизонтальный отступ родителя: карусель растягивается
 *   на всю ширину экрана и возвращает отступ внутри, чтобы карта выглядывала.
 */
@Composable
fun WalletCarousel(
    pages: List<WalletPage>,
    venues: Map<String, Venue>,
    onOpenPoints: (VenuePointsCard) -> Unit,
    onOpenStamps: (LoyaltyCard) -> Unit,
    modifier: Modifier = Modifier,
    screenPadding: Dp = AyantMetrics.screenPadding,
) {
    val c = AyantTheme.colors
    val context = LocalContext.current
    // Подсказка «проведите» показывается до первого реального свайпа и больше
    // не возвращается — ключ переживает переустановку экрана, но не приложения.
    val hintPrefs = remember(context) { context.getSharedPreferences("ayant.wallet", 0) }
    var swipeHintSeen by remember { mutableStateOf(hintPrefs.getBoolean("swipeHintSeen", false)) }
    val pager = rememberPagerState { pages.size }
    val showsHint = pages.size > 1 && !swipeHintSeen

    // Первое прилипание к первой карте — ещё не свайп: подсказку прячем,
    // только когда пользователь долистал до другой страницы.
    LaunchedEffect(pager, pages.size) {
        snapshotFlow { pager.currentPage }.collect { page ->
            if (page != 0 && !swipeHintSeen) {
                swipeHintSeen = true
                hintPrefs.edit().putBoolean("swipeHintSeen", true).apply()
            }
        }
    }

    BoxWithConstraints(modifier.fillMaxWidth()) {
        val fullWidth = maxWidth + screenPadding * 2
        Column(
            Modifier.requiredWidth(fullWidth),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            HorizontalPager(
                state = pager,
                // Доля ширины контейнера под карту; остаток — «подглядывание» следующей.
                pageSize = PageSize.Fixed(fullWidth * CARD_FRACTION),
                contentPadding = PaddingValues(horizontal = screenPadding),
                pageSpacing = 12.dp,
                beyondViewportPageCount = 1,
                modifier = Modifier.fillMaxWidth(),
            ) { index ->
                when (val page = pages[index]) {
                    is WalletPage.Points -> PressableCard(onClick = { onOpenPoints(page.card) }) {
                        WalletPointsCard(card = page.card, venue = venues[page.card.venueID])
                    }
                    is WalletPage.Stamps -> PressableCard(onClick = { onOpenStamps(page.card) }) {
                        WalletStampCard(card = page.card)
                    }
                }
            }

            if (pages.size > 1) {
                PageDots(count = pages.size, current = pager.currentPage)
            }
            AnimatedVisibility(visible = showsHint, exit = fadeOut()) {
                Text(
                    stringResource(R.string.wallet_swipe_hint),
                    fontSize = 12.sp, color = c.inkSoft, textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

private const val CARD_FRACTION = 0.86f

/** Нажатие на карту слегка сжимает её — как `.sanPress(0.97)`. */
@Composable
private fun PressableCard(onClick: () -> Unit, content: @Composable () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    Box(
        Modifier
            .ayantPressScale(interaction, 0.97f)
            .clip(RoundedCornerShape(28.dp))
            .clickable(interactionSource = interaction, indication = null, onClick = onClick),
    ) { content() }
}

/** Точки-страницы: текущая — вытянутая акцентная капсула. */
@Composable
private fun PageDots(count: Int, current: Int) {
    val c = AyantTheme.colors
    val label = stringResource(R.string.wallet_page_a11y, current + 1, count)
    Row(
        Modifier.fillMaxWidth().semantics { contentDescription = label },
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
    ) {
        repeat(count) { i ->
            val width by animateDpAsState(
                targetValue = if (i == current) 18.dp else 6.dp,
                animationSpec = AyantMotion.listRise(300),
                label = "walletDot",
            )
            Box(
                Modifier
                    .width(width)
                    .height(6.dp)
                    .clip(CircleShape)
                    .background(if (i == current) c.accent else c.ink.copy(alpha = 0.18f)),
            )
        }
    }
}

/** Одна карта баллов заведения. */
@Composable
fun WalletPointsCard(
    card: VenuePointsCard,
    venue: Venue?,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    val gradient = venue?.gradientColors ?: listOf(c.accent, AccentGold)
    // Ближайшая награда — она задаёт цель прогресса.
    val next: PointsReward? = venue?.pointsRewards
        ?.filter { it.active && it.cost > card.balance }
        ?.minByOrNull { it.cost }
    val fraction = next?.let { (card.balance.toFloat() / it.cost.coerceAtLeast(1)).coerceAtMost(1f) } ?: 1f

    Column(
        modifier
            .fillMaxWidth()
            .height(CARD_HEIGHT)
            .clip(RoundedCornerShape(28.dp))
            .background(Brush.linearGradient(gradient))
            .padding(22.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(
                    card.venueName, fontSize = 13.sp, fontWeight = FontWeight.Bold,
                    letterSpacing = (-0.1).sp, color = Color.White, maxLines = 1,
                )
                venue?.let {
                    Text(
                        it.category.localizedName(), fontSize = 11.5.sp,
                        color = Color.White.copy(alpha = 0.72f),
                        modifier = Modifier.padding(top = 4.dp),
                    )
                }
            }
            Spacer(Modifier.width(8.dp))
            venue?.pointsModeLabel()?.let {
                Text(
                    it, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.White,
                    maxLines = 1,
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.2f))
                        .padding(horizontal = 11.dp, vertical = 6.dp),
                )
            }
        }
        Spacer(Modifier.height(20.dp))
        Text(
            "${card.balance}", fontSize = 46.sp, fontWeight = FontWeight.Black,
            letterSpacing = (-2.4).sp, lineHeight = 46.sp, color = Color.White,
        )
        Text(
            stringResource(R.string.wallet_points_word), fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.82f),
        )
        Spacer(Modifier.height(18.dp))
        AyantProgressBar(fraction = fraction, height = 6.dp)
        Spacer(Modifier.height(9.dp))
        Text(
            next?.let { stringResource(R.string.points_until_reward, it.cost - card.balance, it.title) }
                ?: stringResource(R.string.wallet_rewards_available),
            fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold,
            color = Color.White.copy(alpha = 0.9f), maxLines = 1,
        )
    }
}

// MARK: - Карта штампов

/**
 * Карта лояльности `loyaltyCards/{userID}_{venueID}` — до редизайна у неё не
 * было своего места на экране.
 *
 * Ровно `goal` кружков (2…12) в один ряд: карта живёт в карусели рядом с
 * картой баллов и обязана быть той же высоты — сетка 5×2 делала её выше
 * и она наезжала на то, что под каруселью.
 */
@Composable
fun WalletStampCard(card: LoyaltyCard, modifier: Modifier = Modifier) {
    val reduceMotion = rememberReduceMotion()
    val goal = card.goal.coerceAtLeast(1)
    val shape = RoundedCornerShape(AyantRadius.hero)

    Column(
        modifier
            .fillMaxWidth()
            .height(CARD_HEIGHT)
            .clip(shape)
            .drawBehind { drawRect(stampBrush(size)) }
            .ayantRisoHatch(alpha = 0.10f)
            .padding(20.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(
                    card.venueName, fontSize = 14.5.sp, fontWeight = FontWeight.Black,
                    letterSpacing = (-0.3).sp, color = Color.White, maxLines = 1,
                )
                Text(
                    stringResource(R.string.wallet_stamp_per_visit), fontSize = 12.sp,
                    color = Color.White.copy(alpha = 0.82f),
                    modifier = Modifier.padding(top = 3.dp),
                )
            }
            Spacer(Modifier.width(8.dp))
            Text(
                "${card.stamps} / $goal", fontSize = 11.5.sp, fontWeight = FontWeight.Black,
                color = Color.White,
                modifier = Modifier
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.2f))
                    .padding(horizontal = 11.dp, vertical = 6.dp),
            )
        }

        Spacer(Modifier.height(16.dp))
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(if (goal > 8) 5.dp else 8.dp),
        ) {
            for (i in 0 until goal) {
                Stamp(
                    index = i, filled = i < card.stamps, dense = goal > 8,
                    reduceMotion = reduceMotion,
                    modifier = Modifier.weight(1f, fill = false).widthIn(max = 36.dp),
                )
            }
        }

        Spacer(Modifier.weight(1f))
        Text(
            stampHint(card, goal), fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
            color = Color.White.copy(alpha = 0.94f), lineHeight = 16.sp, maxLines = 2,
        )
    }
}

@Composable
private fun Stamp(
    index: Int, filled: Boolean, dense: Boolean, reduceMotion: Boolean,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    // Каждый кружок «выстреливает» с шагом 50 мс (ANIMATIONS.md §4).
    val progress = remember { Animatable(if (reduceMotion) 1f else 0f) }
    LaunchedEffect(Unit) {
        if (!reduceMotion) {
            kotlinx.coroutines.delay(index * 50L)
            progress.animateTo(1f, AyantMotion.pop())
        }
    }
    Box(
        modifier
            .fillMaxWidth()
            .aspectRatio(1f)
            .graphicsLayer {
                val s = 0.6f + 0.4f * progress.value
                scaleX = s; scaleY = s; alpha = progress.value
            }
            .clip(CircleShape)
            .then(
                if (filled) Modifier.background(c.accentGradient)
                else Modifier.background(Color.White.copy(alpha = 0.26f))
            ),
        contentAlignment = Alignment.Center,
    ) {
        if (filled) {
            Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.fillMaxSize(0.5f))
        } else {
            Text(
                "${index + 1}", fontSize = if (dense) 9.sp else 11.5.sp,
                fontWeight = FontWeight.Black, color = Color.White.copy(alpha = 0.55f),
            )
        }
    }
}

/** Коротко — карта фиксированной высоты, под подсказку две строки. */
@Composable
private fun stampHint(card: LoyaltyCard, goal: Int): String {
    val left = (goal - card.stamps).coerceAtLeast(0)
    if (left == 0) return stringResource(R.string.wallet_stamp_hint_complete, card.reward)
    return stringResource(
        R.string.wallet_stamp_hint_left,
        pluralStringResource(R.plurals.visits_count, left, left), card.reward,
    )
}

// MARK: - Прогресс-бар

/**
 * Растёт от нуля один раз при появлении (ANIMATIONS.md §5). Дальнейшие
 * изменения баланса анимируются коротко — иначе полоска перезаливалась бы
 * каждый раз, когда snapshot-листенер приносит новый баланс.
 */
@Composable
fun AyantProgressBar(
    fraction: Float,
    height: Dp = 8.dp,
    track: Color = Color.White.copy(alpha = 0.26f),
    fill: Color = Color.White,
    modifier: Modifier = Modifier,
) {
    val reduceMotion = rememberReduceMotion()
    val shown = remember { Animatable(if (reduceMotion) fraction else 0f) }
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(fraction) {
        when {
            reduceMotion -> shown.snapTo(fraction)
            !appeared -> { appeared = true; shown.animateTo(fraction, AyantMotion.progress()) }
            else -> shown.animateTo(fraction, AyantMotion.listRise(400))
        }
    }
    Box(
        modifier
            .fillMaxWidth()
            .height(height)
            .clip(CircleShape)
            .background(track),
    ) {
        Box(
            Modifier
                .fillMaxWidth(shown.value.coerceIn(0f, 1f))
                .height(height)
                .clip(CircleShape)
                .background(fill)
        )
    }
}

// MARK: - Подпись режима начисления

/** «кэшбэк 5%» / «30 за визит» — читает конфиг, ничего не считает. */
@Composable
fun Venue.pointsModeLabel(): String? {
    if (!pointsEnabled) return null
    return when (pointsMode) {
        "cashback" -> if (cashbackPercent > 0) stringResource(R.string.wallet_mode_cashback, percentText(cashbackPercent)) else null
        "bands" -> stringResource(R.string.wallet_mode_bands)
        else -> if (pointsFlat > 0) stringResource(R.string.wallet_mode_flat, pointsFlat) else null
    }
}

private fun percentText(v: Double): String =
    if (v == v.roundToInt().toDouble()) v.roundToInt().toString()
    else String.format(AppLanguage.locale, "%.1f", v)
