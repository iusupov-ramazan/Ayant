package kg.ayant.app.ui.bonus

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.ui.theme.AyantTheme

/**
 * Bonus hub placeholder. The full bonus economy, games (Snake/Tetris), loyalty
 * cards and coupons are the next Android pass (see README roadmap).
 */
@Composable
fun BonusScreen() {
    val c = AyantTheme.colors
    Box(Modifier.fillMaxSize().background(c.canvas), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(32.dp)) {
            Icon(Icons.Filled.CardGiftcard, null, tint = c.accent, modifier = Modifier.size(56.dp))
            Text("Бонусы", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = c.ink)
            Text(
                "Игры, карты лояльности и купоны появятся в следующем обновлении Android-версии.",
                fontSize = 14.sp, color = c.inkSoft, textAlign = TextAlign.Center,
            )
        }
    }
}
