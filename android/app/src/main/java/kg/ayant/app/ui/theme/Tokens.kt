package kg.ayant.app.ui.theme

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Easing
import androidx.compose.animation.core.FiniteAnimationSpec
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp

/**
 * Redesign 2.4 shape / spacing / shadow / motion tokens.
 * Mirrors `SanRadius`, `SanMetrics`, `SanShadow`, `SanMotion` in DesignSystem.swift —
 * same names, same numbers, so the two clients can't drift.
 */

object AyantRadius {
    /** List and result cards. */
    val card: Dp = 22.dp
    /** Large cards (points, rewards, hero). */
    val hero: Dp = 26.dp
    /** Sheets overlapping a cover image. */
    val sheet: Dp = 30.dp
    /** Host header / panel bottom corners. */
    val panel: Dp = 34.dp
    /** Buttons. */
    val button: Dp = 18.dp
    /** Icon tiles. */
    val tile: Dp = 14.dp
    /** Pills and chips. */
    val pill: Dp = 999.dp
}

object AyantMetrics {
    /** Minimum hit target (tab buttons measure 55 × 75 in the prototype). */
    val minHitTarget: Dp = 44.dp
    val screenPadding: Dp = 20.dp
    /** Never go below 11sp: smaller failed both contrast and legibility review. */
    val tabLabelSize: TextUnit = 11.sp
}

/**
 * Card / CTA shadows from the handoff.
 *
 * Compose's [androidx.compose.ui.draw.shadow] has one `elevation` where CSS has
 * blur *and* a y-offset, so we map `elevation ≈ blur / 2` and keep the tint; the
 * vertical offset is not expressible and is dropped. iOS gets both (`SanShadow`).
 */
enum class AyantShadow(val elevation: Dp, val color: Color, val alpha: Float) {
    Card(5.dp, Color.Black, 0.04f),
    Elevated(7.dp, Color.Black, 0.05f),
    AccentCTA(14.dp, Accent, 0.32f),
    Hero(17.dp, Accent, 0.28f),
    Badge(10.dp, AccentDeep, 0.40f),
    SandPanel(11.dp, Color(0xFFC4783C), 0.07f),
    QrCard(20.dp, Color.Black, 0.08f);

    val tint: Color get() = color.copy(alpha = alpha)
}

/**
 * Motion. `cubic-bezier(.22,1,.36,1)` is the house curve for anything entering;
 * the "pop" curve overshoots and is only for the save heart, the success check
 * and the loyalty stamps.
 */
object AyantMotion {
    val EnterEasing: Easing = CubicBezierEasing(0.22f, 1f, 0.36f, 1f)
    val PopEasing: Easing = CubicBezierEasing(0.2f, 1.4f, 0.4f, 1f)

    /** Screen enter: +14dp slide, 420 ms. */
    fun <T> screenEnter(): FiniteAnimationSpec<T> = tween(420, easing = EnterEasing)

    /** List item rise: +24dp, 500–720 ms, staggered by [riseDelayMs]. */
    fun <T> listRise(durationMs: Int = 560, delayMs: Int = 0): FiniteAnimationSpec<T> =
        tween(durationMs, delayMillis = delayMs, easing = EnterEasing)

    /** Pop: save heart, success check, stamps. */
    fun <T> pop(): FiniteAnimationSpec<T> =
        spring(dampingRatio = 0.55f, stiffness = 380f)

    /** Press feedback, 180 ms. */
    fun <T> press(): FiniteAnimationSpec<T> = tween(180, easing = EnterEasing)

    /** Progress-bar grow: 900–1100 ms after a 200 ms delay. */
    fun <T> progress(): FiniteAnimationSpec<T> =
        tween(1000, delayMillis = 200, easing = EnterEasing)

    /** Stagger for the i-th item of a rising list. */
    fun riseDelayMs(index: Int, stepMs: Int = 90): Int = index * stepMs
}
