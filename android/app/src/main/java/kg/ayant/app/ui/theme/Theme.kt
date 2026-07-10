package kg.ayant.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.geometry.Offset
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.ui.unit.dp

/**
 * Ayant design tokens not covered by Material 3's ColorScheme
 * (Canvas / Surface / Ink / Hairline / Open). Mirrors DesignSystem.swift.
 */
@Immutable
data class AyantColors(
    val canvas: Color,
    val surface: Color,
    val surfaceMuted: Color,
    val ink: Color,
    val inkSoft: Color,
    val hairline: Color,
    val accent: Color,
    val accentDeep: Color,
    val open: Color,
    val isDark: Boolean,
) {
    /** Brand gradient (headers, primary buttons, balance card, hero cards).
     *  iOS brand gradient: orange #FF4D29 → gold #FFB300 (top-leading → bottom-trailing). */
    val accentGradient: Brush
        get() = Brush.linearGradient(
            colors = listOf(Color(0xFFFF4D29), Color(0xFFFFB300)),
            start = Offset(0f, 0f),
            end = Offset(Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY),
        )
}

private val LightAyant = AyantColors(
    canvas = CanvasLight, surface = SurfaceLight, surfaceMuted = SurfaceMutedLight,
    ink = InkLight, inkSoft = InkSoftLight, hairline = HairlineLight,
    accent = Accent, accentDeep = AccentDeep, open = Open, isDark = false,
)

private val DarkAyant = AyantColors(
    canvas = CanvasDark, surface = SurfaceDark, surfaceMuted = SurfaceMutedDark,
    ink = InkDark, inkSoft = InkSoftDark, hairline = HairlineDark,
    accent = Accent, accentDeep = AccentDeep, open = Open, isDark = true,
)

val LocalAyantColors = staticCompositionLocalOf { LightAyant }

/** Convenience accessor: `AyantTheme.colors.accent`. */
object AyantTheme {
    val colors: AyantColors
        @Composable get() = LocalAyantColors.current
}

private fun ayantMaterialScheme(a: AyantColors) = if (a.isDark) {
    darkColorScheme(
        primary = a.accent,
        onPrimary = Color.White,
        background = a.canvas,
        onBackground = a.ink,
        surface = a.surface,
        onSurface = a.ink,
        surfaceVariant = a.surfaceMuted,
        onSurfaceVariant = a.inkSoft,
        outline = a.hairline,
    )
} else {
    lightColorScheme(
        primary = a.accent,
        onPrimary = Color.White,
        background = a.canvas,
        onBackground = a.ink,
        surface = a.surface,
        onSurface = a.ink,
        surfaceVariant = a.surfaceMuted,
        onSurfaceVariant = a.inkSoft,
        outline = a.hairline,
    )
}

val AyantShapes = Shapes(
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(22.dp),
)

@Composable
fun AyantTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val ayant = if (darkTheme) DarkAyant else LightAyant
    CompositionLocalProvider(LocalAyantColors provides ayant) {
        MaterialTheme(
            colorScheme = ayantMaterialScheme(ayant),
            typography = AyantTypography,
            shapes = AyantShapes,
            content = content,
        )
    }
}
