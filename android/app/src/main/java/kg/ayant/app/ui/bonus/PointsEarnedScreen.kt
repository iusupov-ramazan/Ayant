package kg.ayant.app.ui.bonus

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.ui.theme.AyantMotion
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantScreenEnter
import kg.ayant.app.ui.theme.rememberReduceMotion
import kotlin.math.roundToInt

/**
 * «Начисление» (SCREENS.md G5). Mirrors `PointsEarnedView.swift`.
 *
 * IMPORTANT: no number here is computed on the client. The screen appears when
 * the `venuePoints` snapshot listener delivers a new balance, and the counter
 * animates *to* whatever the server (`scanCoupon`) wrote.
 */
@Composable
fun PointsEarnedScreen(
    delta: Int,
    venueName: String,
    venueSubtitle: String,
    newBalance: Int,
    onDone: () -> Unit,
) {
    val c = AyantTheme.colors
    val reduceMotion = rememberReduceMotion()

    val disc = remember { Animatable(if (reduceMotion) 1f else 0f) }
    val counter = remember { Animatable(if (reduceMotion) 1f else 0f) }
    LaunchedEffect(Unit) {
        if (reduceMotion) return@LaunchedEffect
        disc.animateTo(1f, AyantMotion.pop())
    }
    LaunchedEffect(Unit) {
        if (reduceMotion) return@LaunchedEffect
        // Ease-out cubic over 1 s (ANIMATIONS.md §9).
        counter.animateTo(1f, tween(1000, easing = CubicBezierEasing(0.33f, 1f, 0.68f, 1f)))
    }
    val shownDelta = (delta * counter.value).roundToInt()
    val shownBalance = ((newBalance - delta) + delta * counter.value).roundToInt()

    Box(Modifier.fillMaxSize().background(c.canvas), contentAlignment = Alignment.Center) {
        if (!reduceMotion) Confetti()

        Column(
            Modifier.padding(30.dp).ayantScreenEnter(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Burst(discProgress = disc.value, reduceMotion = reduceMotion)

            Spacer(Modifier.height(28.dp))
            Text(
                "+$shownDelta",
                fontSize = 70.sp, fontWeight = FontWeight.Black,
                letterSpacing = (-3.6).sp, lineHeight = 70.sp,
                // Gradient-masked text: the brush paints the glyphs.
                style = androidx.compose.ui.text.TextStyle(brush = c.accentGradient),
            )
            Spacer(Modifier.height(12.dp))
            Text(
                "Баллы начислены", fontSize = 24.sp, fontWeight = FontWeight.Black,
                letterSpacing = (-1).sp, color = c.ink,
            )
            Spacer(Modifier.height(8.dp))
            Text("$venueName · $venueSubtitle", fontSize = 14.5.sp, color = c.inkSoft)

            Spacer(Modifier.height(26.dp))
            Row(
                Modifier
                    .widthIn(max = 300.dp)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(24.dp))
                    .background(c.surface)
                    .padding(horizontal = 20.dp, vertical = 18.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Новый баланс", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = c.inkSoft)
                Spacer(Modifier.weight(1f))
                Text(
                    "$shownBalance", fontSize = 24.sp, fontWeight = FontWeight.Black,
                    letterSpacing = (-0.9).sp, color = c.ink,
                )
            }

            Spacer(Modifier.height(14.dp))
            Text(
                "Баллы копятся у этого заведения и тратятся у него же.",
                fontSize = 13.sp, color = Color(0xFF9A9188),
                textAlign = TextAlign.Center, modifier = Modifier.widthIn(max = 280.dp),
            )

            Spacer(Modifier.height(26.dp))
            Box(
                Modifier
                    .widthIn(max = 300.dp)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(19.dp))
                    .background(c.accentGradient)
                    .clickable(onClick = onDone)
                    .padding(vertical = 17.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text("Отлично", fontSize = 16.5.sp, fontWeight = FontWeight.Bold, color = Color.White)
            }
        }
    }
}

@Composable
private fun Burst(discProgress: Float, reduceMotion: Boolean) {
    val c = AyantTheme.colors
    Box(Modifier.size(120.dp), contentAlignment = Alignment.Center) {
        if (!reduceMotion) {
            Ring(color = c.accent, delayMs = 0)
            Ring(color = Color(0xFFFF9500), delayMs = 600)
        }
        Box(
            Modifier
                .size(104.dp)
                .graphicsLayer {
                    val s = 0.6f + 0.4f * discProgress
                    scaleX = s; scaleY = s; alpha = discProgress
                }
                .clip(CircleShape)
                .background(c.accentGradient),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(46.dp))
        }
    }
}

@Composable
private fun Ring(color: Color, delayMs: Int) {
    val transition = rememberInfiniteTransition(label = "ring")
    val t by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1900, delayMillis = delayMs, easing = LinearOutSlowInEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "ringPhase",
    )
    Box(
        Modifier
            .size(120.dp)
            .graphicsLayer {
                val s = 0.35f + (2.6f - 0.35f) * t
                scaleX = s; scaleY = s
                alpha = 0.55f * (1f - t)
            }
            .drawBehind {
                drawCircle(color = color, style = Stroke(width = 2.dp.toPx()))
            }
    )
}

/** 14 particles, 45 ms stagger, falling 220dp while rotating 320°. */
@Composable
private fun Confetti() {
    val colors = listOf(
        Color(0xFFFF5A1F), Color(0xFFFF9500), Color(0xFFFF3B00), Color(0xFFFFD166),
    )
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val w = constraints.maxWidth.toFloat()
        val h = constraints.maxHeight.toFloat()
        repeat(14) { i ->
            val progress = remember { Animatable(0f) }
            LaunchedEffect(Unit) {
                kotlinx.coroutines.delay(i * 45L)
                progress.animateTo(
                    1f,
                    tween(1500, easing = CubicBezierEasing(0.2f, 0.7f, 0.4f, 1f)),
                )
            }
            Box(
                Modifier
                    .size(9.dp)
                    .graphicsLayer {
                        translationX = w * (i + 0.5f) / 14f - size.width / 2f
                        translationY = h * 0.34f + 220.dp.toPx() * progress.value
                        rotationZ = 320f * progress.value
                        alpha = 1f - progress.value
                    }
                    .clip(RoundedCornerShape(2.dp))
                    .background(colors[i % colors.size])
            )
        }
    }
}
