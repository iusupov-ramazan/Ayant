package kg.ayant.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.ui.theme.AyantTheme

// MARK: - Category tile (rounded square). Mirrors CategoryStoryCircle.

@Composable
fun CategoryTile(
    label: String,
    icon: ImageVector,
    isOn: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier.clickable(onClick = onClick),
    ) {
        Box(
            modifier = Modifier
                .size(60.dp)
                .clip(RoundedCornerShape(18.dp))
                .then(
                    if (isOn) Modifier.background(c.accentGradient)
                    else Modifier.background(c.surfaceMuted)
                ),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, null, tint = if (isOn) Color.White else c.inkSoft, modifier = Modifier.size(24.dp))
        }
        Text(
            label,
            fontSize = 11.sp,
            fontWeight = if (isOn) FontWeight.SemiBold else FontWeight.Normal,
            color = if (isOn) c.ink else c.inkSoft,
            modifier = Modifier.padding(top = 7.dp),
        )
    }
}

// MARK: - Rating breakdown (5★…1★). Mirrors RatingBreakdownView.

@Composable
fun RatingBreakdown(breakdown: Map<Int, Int>, modifier: Modifier = Modifier) {
    val total = breakdown.values.sum()
    val c = AyantTheme.colors
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(5.dp)) {
        for (star in 5 downTo 1) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("$star", fontSize = 12.sp, color = c.ink, modifier = Modifier.width(10.dp))
                Icon(Icons.Filled.Star, null, tint = Color(0xFFF5C518), modifier = Modifier.size(9.dp).padding(start = 0.dp))
                Spacer(Modifier.width(8.dp))
                Box(
                    Modifier
                        .weight(1f)
                        .height(7.dp)
                        .clip(RoundedCornerShape(50))
                        .background(c.surfaceMuted),
                ) {
                    val frac = if (total > 0) (breakdown[star] ?: 0).toFloat() / total else 0f
                    Box(
                        Modifier
                            .fillMaxWidth(frac)
                            .height(7.dp)
                            .clip(RoundedCornerShape(50))
                            .background(c.accent),
                    )
                }
                Text(
                    "${breakdown[star] ?: 0}",
                    fontSize = 11.sp,
                    color = c.inkSoft,
                    modifier = Modifier.padding(start = 8.dp).width(24.dp),
                )
            }
        }
    }
}
