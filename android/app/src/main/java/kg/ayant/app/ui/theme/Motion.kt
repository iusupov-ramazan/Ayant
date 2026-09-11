package kg.ayant.app.ui.theme

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import android.provider.Settings

/**
 * Motion modifiers from ANIMATIONS.md. Mirrors `Motion.swift`; the curves and
 * durations themselves live in [AyantMotion] / [AyantTiming] so a number never
 * appears in two files.
 */

object AyantTiming {
    const val SCREEN_ENTER_MS = 420
    const val PRESS_MS = 180

    const val FEED_RISE_MS = 720
    const val FEED_STAGGER_MS = 90
    const val DEAL_ROW_RISE_MS = 550
    const val DEAL_ROW_STAGGER_MS = 80
    const val GRID_TILE_RISE_MS = 500
    const val GRID_TILE_STAGGER_MS = 60
    /** Витрина хоста: плитки мельче и их втрое больше в ряду, поэтому шаг короче. */
    const val HOST_GRID_RISE_MS = 500
    const val HOST_GRID_STAGGER_MS = 50

    /** Only the first screenful is staggered — otherwise the 12th card waits a second. */
    const val STAGGER_CAP = 4
    /** То же правило для сетки 3×N: первый экран — это девять плиток. */
    const val GRID_STAGGER_CAP = 9
    /**
     * Лента постов: на экран влезает один пост, но задержку получают первые
     * четыре — их видно при быстрой прокрутке сразу после входа.
     */
    const val FEED_STAGGER_CAP = 4

    const val PROGRESS_BAR_MS = 1000
    const val QR_SWEEP_MS = 2600
    const val SCANNER_SWEEP_MS = 2200
    const val SHIMMER_MS = 3400
    const val FAB_PULSE_MS = 2800
    const val SKELETON_PULSE_MS = 1200
}

/**
 * True when the user has turned animations off system-wide
 * (`Settings.Global.ANIMATOR_DURATION_SCALE == 0`). Under it we keep fades and
 * drop translation/scale, and no infinite animation runs — ANIMATIONS.md §17.
 */
@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        Settings.Global.getFloat(
            context.contentResolver,
            Settings.Global.ANIMATOR_DURATION_SCALE,
            1f,
        ) == 0f
    }
}

/** §1 Screen entrance: +14dp and a fade over 420 ms. */
fun Modifier.ayantScreenEnter(): Modifier = composed {
    val reduceMotion = rememberReduceMotion()
    val progress = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        progress.animateTo(1f, tween(AyantTiming.SCREEN_ENTER_MS, easing = AyantMotion.EnterEasing))
    }
    val slide = with(androidx.compose.ui.platform.LocalDensity.current) { 14.dp.toPx() }
    graphicsLayer {
        alpha = progress.value
        translationY = if (reduceMotion) 0f else (1f - progress.value) * slide
    }
}

/**
 * §2 Staggered list entrance: +28dp, scale 0.985, delayed by index.
 *
 * [key] keys the animation to the item id so LazyColumn recycling does not
 * re-trigger the rise when a row is scrolled back into view.
 */
fun Modifier.ayantRise(
    index: Int,
    key: Any = index,
    staggerMs: Int = AyantTiming.FEED_STAGGER_MS,
    durationMs: Int = AyantTiming.FEED_RISE_MS,
    cap: Int = AyantTiming.STAGGER_CAP,
    enabled: Boolean = true,
): Modifier = composed {
    val reduceMotion = rememberReduceMotion()
    val progress = remember(key) { Animatable(if (enabled) 0f else 1f) }
    val delay = if (index < cap) index * staggerMs else 0
    LaunchedEffect(key) {
        if (!enabled) { progress.snapTo(1f); return@LaunchedEffect }
        progress.animateTo(
            1f,
            tween(durationMs, delayMillis = delay, easing = AyantMotion.EnterEasing),
        )
    }
    val slide = with(androidx.compose.ui.platform.LocalDensity.current) { 28.dp.toPx() }
    graphicsLayer {
        alpha = progress.value
        if (!reduceMotion) {
            translationY = (1f - progress.value) * slide
            val s = 0.985f + 0.015f * progress.value
            scaleX = s
            scaleY = s
        }
    }
}

/**
 * §4 Pop when something BECOMES set (saved, checked, stamped) — deliberately
 * silent on unset, or removing a like would read as another like.
 */
fun Modifier.ayantPopOnSet(isSet: Boolean): Modifier = composed {
    val reduceMotion = rememberReduceMotion()
    val scale = remember { Animatable(1f) }
    // Skip the first pass: a card that scrolls in already-saved must not pop.
    val settled = remember { mutableStateOf(false) }
    LaunchedEffect(isSet) {
        if (!settled.value) {
            settled.value = true
            return@LaunchedEffect
        }
        if (isSet && !reduceMotion) {
            scale.snapTo(0.6f)
            scale.animateTo(1f, AyantMotion.pop())
        } else {
            scale.snapTo(1f)
        }
    }
    graphicsLayer { scaleX = scale.value; scaleY = scale.value }
}
