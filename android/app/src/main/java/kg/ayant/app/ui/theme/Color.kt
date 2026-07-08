package kg.ayant.app.ui.theme

import androidx.compose.ui.graphics.Color

// MARK: - Ayant Refresh palette (mirrors iOS DesignSystem.swift / Models.swift)
// Warm Canvas background · Ink text · muted surfaces · bright orange accent.

// Accent
val Accent = Color(0xFFFF5A1F)       // sanAccent (Ayant Refresh bright orange)
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

// Deal-type accent colors (Models.swift DealType.color)
val DealDiscount = Accent
val DealPromo = Color(0xFF7E57C2)     // purple
val DealNovelty = Color(0xFF14B8A6)   // teal
val DealAnnouncement = Color(0xFF2F80ED) // blue
