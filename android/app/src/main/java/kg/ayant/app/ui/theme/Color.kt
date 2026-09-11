package kg.ayant.app.ui.theme

import androidx.compose.ui.graphics.Color

// MARK: - Ayant Refresh palette (mirrors iOS DesignSystem.swift / Models.swift)
// Warm Canvas background · Ink text · muted surfaces · bright orange accent.

// Accent
val Accent = Color(0xFFFF5A1F)       // sanAccent (Ayant Refresh bright orange)
val AccentGold = Color(0xFFFF9500)   // Palette.orange — second stop of the brand gradient
val AccentDeep = Color(0xFFFF3B00)   // sanAccentDeep (gradient end)
val Open = Color(0xFF2FA24C)         // "Открыто" green

// Light tokens
val CanvasLight = Color(0xFFF6F4F0)
val SurfaceLight = Color(0xFFFFFFFF)
val SurfaceMutedLight = Color(0xFFEFEDE7)
val InkLight = Color(0xFF17130F)
val InkSoftLight = Color(0xFF6E655C)
val HairlineLight = Color(0xFFE7E3DC)

// Dark tokens
val CanvasDark = Color(0xFF121110)
val SurfaceDark = Color(0xFF1E1C1A)
val SurfaceMutedDark = Color(0xFF2A2724)
val InkDark = Color(0xFFF3F1EC)
val InkSoftDark = Color(0xFFB4ADA3)
val HairlineDark = Color(0xFF322E2A)

// MARK: - Redesign 2.4 tokens (mirrors the "Редизайн 2.4 · новые токены" block
// in DesignSystem.swift). They exist because the redesign puts small text on warm
// surfaces where the old greys and the accent itself fell below WCAG AA;
// the stated ratios were measured on the prototype.
//
// NOTE: dark mode for the sand/cream surfaces is NOT designed yet (see the
// Accessibility section of the handoff), so these have a single value and are
// handed to both AyantColors schemes unchanged. When dark is drawn, split them
// here and in DesignSystem.swift together.

val Sand = Color(0xFFFFEEDF)            // host header / riso panel gradient start
val SandDeep = Color(0xFFFFDBC0)        // …end
val SandInk = Color(0xFF7E4520)         // captions on sand — 4.6:1
val SandInkStrong = Color(0xFF6B3A18)   // pill-button labels on sand — 6.2:1
val AccentText = Color(0xFFC43C05)      // accent as SMALL TEXT / active tab — 4.78:1 on canvas
val AccentTextStrong = Color(0xFFB03505) // accent numerals on white — 6.25:1
val Eyebrow = Color(0xFF9C3306)         // uppercase eyebrows on sand — 4.5:1
val TabIdle = Color(0xFF726251)         // inactive tab labels — 5.34:1 on canvas
val Cream = Color(0xFFFFF7F1)           // host tab-bar background
val CreamLine = Color(0xFFF0DDCB)       // host tab-bar top border

// Плоская шапка хоста — единственное место «кремового мира», у которого есть
// тёмная пара. Статический Cream оставлял шапку светлой на тёмной теме, а
// заголовок поверх (ink) становился почти белым — «Заведения» пропадали.
val HostHeaderLight = Color(0xFFFFF7F1)
val HostHeaderDark = Color(0xFF1E1C1A)
val HostCaptionLight = Color(0xFF7E4520)
val HostCaptionDark = Color(0xFFC8A48A)
val HostEyebrowLight = Color(0xFF9C3306)
val HostEyebrowDark = Color(0xFFFF9F6B)

// Loyalty stamp card gradient (140°).
val StampStart = Color(0xFF5B4CC4)
val StampEnd = Color(0xFF9B87F0)

// Deal-type accent colors (Models.swift DealType.color)
val DealDiscount = Accent
val DealPromo = Color(0xFF7E57C2)     // purple
val DealNovelty = Color(0xFF14B8A6)   // teal
val DealAnnouncement = Color(0xFF2F80ED) // blue
