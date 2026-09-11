package kg.ayant.app.ui.theme

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Ayant Refresh card: radius 20, soft shadow, 0.5dp hairline border, minimal chrome.
 * Mirrors SanCard / .sanCard() from DesignSystem.swift.
 */
fun Modifier.ayantCard(padding: Int = 14, radius: Int = 20): Modifier = composed {
    val c = LocalAyantColors.current
    val shape = RoundedCornerShape(radius.dp)
    this
        .shadow(elevation = 6.dp, shape = shape, ambientColor = Color.Black.copy(alpha = 0.05f), spotColor = Color.Black.copy(alpha = 0.05f))
        .background(c.surface, shape)
        .border(0.5.dp, c.hairline, shape)
        .padding(padding.dp)
}

/** Group card without inner padding (rows supply their own; hairlines between). */
fun Modifier.ayantGroupCard(radius: Int = 20): Modifier = composed {
    val c = LocalAyantColors.current
    val shape = RoundedCornerShape(radius.dp)
    this
        .shadow(elevation = 6.dp, shape = shape, ambientColor = Color.Black.copy(alpha = 0.05f), spotColor = Color.Black.copy(alpha = 0.05f))
        .background(c.surface, shape)
        .border(0.5.dp, c.hairline, shape)
}

/** Warm canvas screen background. */
fun Modifier.ayantCanvas(): Modifier = composed {
    background(LocalAyantColors.current.canvas)
}

// MARK: - Redesign 2.4

/** One of the handoff shadows. Mirrors `.sanShadow(_:)`. */
fun Modifier.ayantShadow(shadow: AyantShadow, shape: Shape): Modifier =
    shadow(
        elevation = shadow.elevation,
        shape = shape,
        ambientColor = shadow.tint,
        spotColor = shadow.tint,
    )

/**
 * Riso hatch — `repeating-linear-gradient(45deg, rgba(255,255,255,.42) 0 2px,
 * transparent 2px 16px)`: 2dp white stripes at a 16dp period, 45°.
 *
 * The period is measured perpendicular to the stripes, so the step along X is
 * `16 × √2`. Mirrors `SanRisoHatch`.
 */
fun Modifier.ayantRisoHatch(
    alpha: Float = 0.42f,
    stripe: Dp = 2.dp,
    period: Dp = 16.dp,
): Modifier = drawWithContent {
    drawContent()
    val stepX = period.toPx() * 1.4142136f
    val color = Color.White.copy(alpha = alpha)
    var x = -size.height
    while (x <= size.width + size.height) {
        drawLine(
            color = color,
            start = Offset(x, 0f),
            end = Offset(x + size.height, size.height),
            strokeWidth = stripe.toPx(),
        )
        x += stepX
    }
}

/** Sand riso panel: 155° sand gradient + hatch, clipped to [radius]. */
fun Modifier.ayantSandPanel(radius: Dp = AyantRadius.panel): Modifier =
    this
        .clip(RoundedCornerShape(radius))
        .drawBehind { drawRect(sandBrush(size)) }
        .ayantRisoHatch()

/** Violet loyalty stamp-card surface: 140° gradient + hatch. */
fun Modifier.ayantStampPanel(radius: Dp = AyantRadius.hero): Modifier =
    this
        .clip(RoundedCornerShape(radius))
        .drawBehind { drawRect(stampBrush(size)) }
        .ayantRisoHatch(alpha = 0.10f)

/**
 * Press feedback: scale 0.94–0.98 over 180 ms. Pass the same
 * [MutableInteractionSource] you hand to `clickable`. Mirrors `SanPressableButtonStyle`.
 */
fun Modifier.ayantPressScale(
    interactionSource: MutableInteractionSource,
    scale: Float = 0.96f,
): Modifier = composed {
    val pressed by interactionSource.collectIsPressedAsState()
    val s by animateFloatAsState(
        targetValue = if (pressed) scale else 1f,
        animationSpec = AyantMotion.press(),
        label = "ayantPressScale",
    )
    graphicsLayer { scaleX = s; scaleY = s }
}
