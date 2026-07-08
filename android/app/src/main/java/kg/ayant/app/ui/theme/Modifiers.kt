package kg.ayant.app.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
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
