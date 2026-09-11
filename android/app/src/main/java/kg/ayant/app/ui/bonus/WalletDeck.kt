package kg.ayant.app.ui.bonus

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import kg.ayant.app.domain.model.LoyaltyCard
import kg.ayant.app.domain.model.PointsReward
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenuePointsCard
import kg.ayant.app.ui.theme.AyantMotion
import kg.ayant.app.ui.theme.AyantRadius
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantRisoHatch
import kg.ayant.app.ui.theme.gradientColors
import kg.ayant.app.ui.theme.rememberReduceMotion
import kg.ayant.app.ui.theme.stampBrush
import kotlin.math.roundToInt

/**
 * Wallet deck and stamp card (SCREENS.md G6). Mirrors `WalletDeck.swift`.
 *
 * Three currencies in one place: per-venue points (the product), the stamp card,
 * and the global bonus wallet — the last deliberately subordinate, because it is
 * near-impossible to accumulate by design.
 */

private val CARD_HEIGHT = 198.dp
private val DECK_STEP = 44.dp
private const val DECK_SCALE_STEP = 0.055f
/** Deeper than four is unreadable and the stage height is fixed. */
private const val DECK_MAX_VISIBLE = 4

@Composable
fun WalletDeck(
    cards: List<VenuePointsCard>,
    venues: Map<String, Venue>,
    onOpen: (VenuePointsCard) -> Unit,
    modifier: Modifier = Modifier,
) {
    var top by remember { mutableIntStateOf(0) }
    val visible = minOf(cards.size, DECK_MAX_VISIBLE)
    val stageHeight = CARD_HEIGHT + DECK_STEP * (visible - 1)

    Box(modifier.fillMaxWidth().height(stageHeight).padding(horizontal = 24.dp)) {
        cards.forEachIndexed { index, card ->
            val rel = (index - top + cards.size) % cards.size
            if (rel < DECK_MAX_VISIBLE) {
                // rel = position from the front; the whole deck re-orders in one 550 ms move.
                val offsetY by animateFloatAsState(
                    targetValue = rel.toFloat(),
                    animationSpec = tween(550, easing = AyantMotion.EnterEasing),
                    label = "deckOffset",
                )
                val scale = 1f - DECK_SCALE_STEP * offsetY
                WalletPointsCard(
                    card = card,
                    venue = venues[card.venueID],
                    isFront = rel == 0,
                    modifier = Modifier
                        .offset(y = DECK_STEP * offsetY)
                        .graphicsLayer {
                            scaleX = scale
                            scaleY = scale
                            transformOrigin = androidx.compose.ui.graphics.TransformOrigin(0.5f, 0f)
                        }
                        .zIndex((cards.size - rel).toFloat())
                        .clickable { if (rel == 0) onOpen(card) else top = index },
                )
            }
        }
    }
}

@Composable
fun WalletPointsCard(
    card: VenuePointsCard,
    venue: Venue?,
    isFront: Boolean,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    val gradient = venue?.gradientColors ?: listOf(c.accent, Color(0xFFFF9500))
    // The nearest affordable-but-unreached reward sets the progress target.
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
                        it.category.rawValue, fontSize = 11.5.sp,
                        color = Color.White.copy(alpha = 0.72f),
                        modifier = Modifier.padding(top = 4.dp),
                    )
                }
            }
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
        Text("баллов", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.82f))
        Spacer(Modifier.height(18.dp))
        AyantProgressBar(fraction = fraction, height = 6.dp)
        Spacer(Modifier.height(9.dp))
        Text(
            next?.let { "Ещё ${it.cost - card.balance} до «${it.title}»" } ?: "Награды доступны",
            fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold,
            color = Color.White.copy(alpha = 0.9f), maxLines = 1,
        )
    }
}

/**
 * The `loyaltyCards/{userID}_{venueID}` stamp product, which had no home on
 * screen before the redesign.
 */
@Composable
fun WalletStampCard(card: LoyaltyCard, modifier: Modifier = Modifier) {
    val reduceMotion = rememberReduceMotion()
    val goal = card.goal.coerceAtLeast(1)
    val shape = RoundedCornerShape(AyantRadius.hero)

    Column(
        modifier
            .fillMaxWidth()
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
                    "штамп за каждый визит", fontSize = 12.sp,
                    color = Color.White.copy(alpha = 0.82f),
                    modifier = Modifier.padding(top = 3.dp),
                )
            }
            Text(
                "${card.stamps} / $goal", fontSize = 11.5.sp, fontWeight = FontWeight.Black,
                color = Color.White,
                modifier = Modifier
                    .clip(CircleShape)
                    .background(Color.White.copy(alpha = 0.2f))
                    .padding(horizontal = 11.dp, vertical = 6.dp),
            )
        }

        Spacer(Modifier.height(18.dp))
        // Not lazy: `goal` is small (2–12) and a nested lazy grid inside a
        // scrolling column needs a fixed height anyway.
        Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
            (0 until goal).chunked(5).forEach { row ->
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(9.dp),
                ) {
                    row.forEach { i ->
                        Stamp(index = i, filled = i < card.stamps, reduceMotion = reduceMotion,
                              modifier = Modifier.weight(1f))
                    }
                    repeat(5 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }

        Spacer(Modifier.height(16.dp))
        Text(
            stampHint(card, goal), fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold,
            color = Color.White.copy(alpha = 0.94f), lineHeight = 17.sp,
        )
    }
}

@Composable
private fun Stamp(index: Int, filled: Boolean, reduceMotion: Boolean, modifier: Modifier = Modifier) {
    val c = AyantTheme.colors
    // Each circle pops in on a 50 ms stagger (ANIMATIONS.md §4).
    val progress = remember { Animatable(if (reduceMotion) 1f else 0f) }
    LaunchedEffect(Unit) {
        if (!reduceMotion) {
            kotlinx.coroutines.delay(index * 50L)
            progress.animateTo(1f, AyantMotion.pop())
        }
    }
    Box(
        modifier
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
            Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.fillMaxSize(0.55f))
        } else {
            Text(
                "${index + 1}", fontSize = 12.5.sp, fontWeight = FontWeight.Black,
                color = Color.White.copy(alpha = 0.55f),
            )
        }
    }
}

private fun stampHint(card: LoyaltyCard, goal: Int): String {
    val left = (goal - card.stamps).coerceAtLeast(0)
    if (left == 0) return "Круг собран — покажите карту сотруднику и заберите «${card.reward}»."
    return "Ещё $left ${visitsWord(left)} — и «${card.reward}» в подарок. " +
        "Штампы ставит сотрудник, сканируя ваш QR."
}

private fun visitsWord(n: Int): String {
    val n10 = n % 10
    val n100 = n % 100
    return when {
        n10 == 1 && n100 != 11 -> "визит"
        n10 in 2..4 && n100 !in 12..14 -> "визита"
        else -> "визитов"
    }
}

/**
 * Progress bar that grows from zero once on appear (ANIMATIONS.md §5). Later
 * value changes animate short, so the bar does not re-fill every time the
 * snapshot listener delivers a new balance.
 */
@Composable
fun AyantProgressBar(
    fraction: Float,
    height: androidx.compose.ui.unit.Dp = 8.dp,
    track: Color = Color.White.copy(alpha = 0.26f),
    fill: Color = Color.White,
    modifier: Modifier = Modifier,
) {
    val reduceMotion = rememberReduceMotion()
    val shown = remember { Animatable(if (reduceMotion) fraction else 0f) }
    LaunchedEffect(fraction) {
        if (reduceMotion) shown.snapTo(fraction)
        else shown.animateTo(fraction, AyantMotion.progress())
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

/** «кэшбэк 5%» / «30 за визит» — reads the config, computes nothing. */
fun Venue.pointsModeLabel(): String? {
    if (!pointsEnabled) return null
    return when (pointsMode) {
        "cashback" -> if (cashbackPercent > 0) "кэшбэк ${percentText(cashbackPercent)}%" else null
        "bands" -> "по сумме чека"
        else -> if (pointsFlat > 0) "$pointsFlat за визит" else null
    }
}

private fun percentText(v: Double): String =
    if (v == v.roundToInt().toDouble()) v.roundToInt().toString()
    else String.format("%.1f", v).replace('.', ',')
