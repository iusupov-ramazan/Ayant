package kg.ayant.app.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

// Mirrors iOS SF Pro hierarchy. Uses the platform default (Roboto) which is the
// Android HIG system font and supports Cyrillic + Dynamic Type out of the box.
private val System = FontFamily.Default

val AyantTypography = Typography(
    displaySmall = TextStyle(fontFamily = System, fontWeight = FontWeight.Black, fontSize = 32.sp),
    headlineMedium = TextStyle(fontFamily = System, fontWeight = FontWeight.Bold, fontSize = 24.sp),
    titleLarge = TextStyle(fontFamily = System, fontWeight = FontWeight.Bold, fontSize = 20.sp),
    titleMedium = TextStyle(fontFamily = System, fontWeight = FontWeight.SemiBold, fontSize = 17.sp),
    bodyLarge = TextStyle(fontFamily = System, fontWeight = FontWeight.Normal, fontSize = 16.sp),
    bodyMedium = TextStyle(fontFamily = System, fontWeight = FontWeight.Normal, fontSize = 14.sp),
    labelLarge = TextStyle(fontFamily = System, fontWeight = FontWeight.SemiBold, fontSize = 14.sp),
    labelMedium = TextStyle(fontFamily = System, fontWeight = FontWeight.Medium, fontSize = 12.sp),
    labelSmall = TextStyle(fontFamily = System, fontWeight = FontWeight.Medium, fontSize = 11.sp),
)
