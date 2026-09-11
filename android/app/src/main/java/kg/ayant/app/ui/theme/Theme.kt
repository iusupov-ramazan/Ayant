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
import androidx.compose.ui.geometry.Size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.ui.unit.dp
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

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
    // Плоская шапка хоста — единственная часть «кремового мира» с тёмной парой.
    val hostHeader: Color,
    val hostCaption: Color,
    val hostEyebrow: Color,
    // Redesign 2.4 — warm-surface tokens. Single value for now: dark mode for the
    // rest of the sand/cream world is not designed yet (mirrors DesignSystem.swift).
    val sand: Color = Sand,
    val sandDeep: Color = SandDeep,
    val sandInk: Color = SandInk,
    val sandInkStrong: Color = SandInkStrong,
    val accentText: Color = AccentText,
    val accentTextStrong: Color = AccentTextStrong,
    val eyebrow: Color = Eyebrow,
    val tabIdle: Color = TabIdle,
    val cream: Color = Cream,
    val creamLine: Color = CreamLine,
) {
    /** Brand gradient (headers, primary buttons, balance card, hero cards).
     *  #FF5A1F → #FF9500, top-leading → bottom-trailing (CSS 135°). Same two stops
     *  as `Venue.defaultGradient` / `Palette.accent`+`Palette.orange` on iOS. */
    val accentGradient: Brush
        get() = Brush.linearGradient(
            colors = listOf(accent, AccentGold),
            start = Offset(0f, 0f),
            end = Offset(Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY),
        )
}

/**
 * Sand gradient for the host header and riso panels — CSS `155deg`.
 *
 * Angles other than 135° need the real box size, so these are functions rather
 * than [Brush] properties: call them from a `drawBehind`/`drawWithCache` scope
 * where `size` is known (or use [Modifier.ayantSandPanel]).
 * Direction for a CSS angle θ (y down) is `(sin θ, −cos θ)`.
 */
fun sandBrush(size: Size): Brush = angledGradient(listOf(Sand, SandDeep), 155.0, size)

/** Loyalty stamp-card gradient — CSS `140deg`, violet. */
fun stampBrush(size: Size): Brush = angledGradient(listOf(StampStart, StampEnd), 140.0, size)

/** Linear gradient at a CSS angle across a box of [size]. */
fun angledGradient(colors: List<Color>, degrees: Double, size: Size): Brush {
    val rad = Math.toRadians(degrees)
    val dx = sin(rad).toFloat()
    val dy = (-cos(rad)).toFloat()
    val cx = size.width / 2f
    val cy = size.height / 2f
    val half = (abs(dx) * size.width + abs(dy) * size.height) / 2f
    return Brush.linearGradient(
        colors = colors,
        start = Offset(cx - dx * half, cy - dy * half),
        end = Offset(cx + dx * half, cy + dy * half),
    )
}

private val LightAyant = AyantColors(
    canvas = CanvasLight, surface = SurfaceLight, surfaceMuted = SurfaceMutedLight,
    ink = InkLight, inkSoft = InkSoftLight, hairline = HairlineLight,
    accent = Accent, accentDeep = AccentDeep, open = Open, isDark = false,
    hostHeader = HostHeaderLight, hostCaption = HostCaptionLight, hostEyebrow = HostEyebrowLight,
)

private val DarkAyant = AyantColors(
    canvas = CanvasDark, surface = SurfaceDark, surfaceMuted = SurfaceMutedDark,
    ink = InkDark, inkSoft = InkSoftDark, hairline = HairlineDark,
    accent = Accent, accentDeep = AccentDeep, open = Open, isDark = true,
    hostHeader = HostHeaderDark, hostCaption = HostCaptionDark, hostEyebrow = HostEyebrowDark,
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
