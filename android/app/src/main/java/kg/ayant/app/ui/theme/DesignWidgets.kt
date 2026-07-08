package kg.ayant.app.ui.theme

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Screen title (heavy, 32sp). Mirrors SanScreenTitle. */
@Composable
fun AyantScreenTitle(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        color = AyantTheme.colors.ink,
        fontSize = 32.sp,
        fontWeight = FontWeight.Black,
        modifier = modifier.fillMaxWidth(),
    )
}

/** Muted uppercase section header. Mirrors SanSectionHeader. */
@Composable
fun AyantSectionHeader(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text.uppercase(),
        color = AyantTheme.colors.inkSoft,
        fontSize = 12.sp,
        fontWeight = FontWeight.Bold,
        letterSpacing = 1.sp,
        modifier = modifier.fillMaxWidth(),
    )
}

/** Rounded tinted icon tile (or gradient-filled). Mirrors SanIconTile. */
@Composable
fun AyantIconTile(
    icon: ImageVector,
    modifier: Modifier = Modifier,
    tint: Color = AyantTheme.colors.accent,
    filled: Boolean = false,
    size: Int = 44,
) {
    val shape = RoundedCornerShape((size * 0.34).dp)
    Box(
        modifier = modifier
            .size(size.dp)
            .clip(shape)
            .then(
                if (filled) Modifier.background(AyantTheme.colors.accentGradient)
                else Modifier.background(tint.copy(alpha = 0.14f))
            ),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = if (filled) Color.White else tint,
            modifier = Modifier.size((size * 0.5).dp),
        )
    }
}

/** Primary gradient button. Mirrors SanPrimaryButton. */
@Composable
fun AyantPrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(16.dp),
        colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent, contentColor = Color.White),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
        modifier = modifier.fillMaxWidth().height(52.dp),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(AyantTheme.colors.accentGradient),
            contentAlignment = Alignment.Center,
        ) {
            Text(text, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = Color.White)
        }
    }
}

/** Secondary pill button. Mirrors SanPillButton. */
@Composable
fun AyantPillButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    accent: Boolean = false,
) {
    val c = AyantTheme.colors
    OutlinedButton(
        onClick = onClick,
        shape = RoundedCornerShape(14.dp),
        border = BorderStroke(0.dp, Color.Transparent),
        colors = ButtonDefaults.outlinedButtonColors(
            containerColor = if (accent) c.accent.copy(alpha = 0.12f) else c.surfaceMuted,
            contentColor = if (accent) c.accent else c.ink,
        ),
        modifier = modifier.fillMaxWidth(),
    ) {
        Text(text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
    }
}

/** Thin divider line inside a group card. Mirrors SanHairline. */
@Composable
fun AyantHairline(leading: Int = 0) {
    Box(
        Modifier
            .fillMaxWidth()
            .padding(start = leading.dp)
            .height(0.5.dp)
            .background(AyantTheme.colors.hairline)
    )
}
