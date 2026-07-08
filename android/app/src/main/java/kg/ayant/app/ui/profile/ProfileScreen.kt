package kg.ayant.app.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Storefront
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.core.Links
import kg.ayant.app.core.shareText
import kg.ayant.app.ui.components.StarRating
import kg.ayant.app.ui.theme.AyantHairline
import kg.ayant.app.ui.theme.AyantIconTile
import kg.ayant.app.ui.theme.AyantScreenTitle
import kg.ayant.app.ui.theme.AyantSectionHeader
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantCard
import kg.ayant.app.ui.theme.ayantGroupCard
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.ui.vm.SessionViewModel
import androidx.compose.ui.platform.LocalContext

@Composable
fun ProfileScreen(app: AppViewModel, session: SessionViewModel) {
    val c = AyantTheme.colors
    val context = LocalContext.current
    val username = session.user?.name ?: "Гость"
    var showDelete by remember { mutableStateOf(false) }

    Column(
        Modifier
            .fillMaxSize()
            .background(c.canvas)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .padding(top = 16.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp),
    ) {
        AyantScreenTitle("Профиль")

        // Profile card
        Row(Modifier.fillMaxWidth().ayantCard(padding = 16), verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(64.dp).clip(RoundedCornerShape(18.dp)).background(c.accentGradient),
                contentAlignment = Alignment.Center,
            ) {
                Text(username.take(1).uppercase(), fontSize = 28.sp, fontWeight = FontWeight.Black, color = Color.White)
            }
            Column(Modifier.padding(start = 14.dp)) {
                Text(username, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = c.ink)
                session.user?.email?.let { Text(it, fontSize = 14.sp, color = c.inkSoft) }
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 2.dp)) {
                    Icon(Icons.Filled.LocationOn, null, tint = c.inkSoft, modifier = Modifier.size(12.dp))
                    Text(" ${app.selectedCity.name}", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = c.inkSoft)
                }
            }
        }

        // Settings
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            AyantSectionHeader("Настройки")
            Column(Modifier.fillMaxWidth().ayantGroupCard()) {
                SettingRow(Icons.Filled.Apartment, "Город", app.selectedCity.name)
                AyantHairline(leading = 60)
                SettingRow(Icons.Filled.Language, "Язык", "Русский")
            }
        }

        // Host mode (stub — full host side is a later pass)
        Row(
            Modifier.fillMaxWidth().ayantGroupCard().padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            AyantIconTile(Icons.Filled.Storefront, filled = true, size = 44)
            Column(Modifier.padding(start = 14.dp).weight(1f)) {
                Text("Режим заведения", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = c.accent)
                Text("Управляйте своим бизнесом (скоро)", fontSize = 13.sp, color = c.inkSoft)
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = c.accent, modifier = Modifier.size(18.dp))
        }

        // My reviews
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            AyantSectionHeader("Мои отзывы")
            val reviews = app.myReviews()
            if (reviews.isEmpty()) {
                Box(Modifier.fillMaxWidth().ayantGroupCard().padding(16.dp)) {
                    Text("Ты ещё не оставил ни одного отзыва.", fontSize = 15.sp, color = c.inkSoft)
                }
            } else {
                Column(Modifier.fillMaxWidth().ayantGroupCard()) {
                    reviews.forEachIndexed { i, r ->
                        Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 13.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(app.venue(id = r.venueID)?.name ?: "Заведение", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = c.ink)
                                Spacer(Modifier.weight(1f))
                                StarRating(rating = r.rating.toDouble(), size = 11)
                            }
                            if (r.text.isNotEmpty()) {
                                Text(r.text, fontSize = 13.sp, color = c.inkSoft, maxLines = 2)
                            }
                        }
                        if (i < reviews.size - 1) AyantHairline(leading = 14)
                    }
                }
            }
        }

        // Referral
        if (!session.isGuest) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                AyantSectionHeader("Пригласить друга")
                Row(
                    Modifier.fillMaxWidth().ayantGroupCard()
                        .clickable {
                            context.shareText(
                                "Лови скидки и акции города в Ayant. Заходи по моей ссылке — бонусы получим оба! ${Links.referral(app.currentUserID)}",
                                "Ayant",
                            )
                        }
                        .padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text("Поделиться приглашением", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = c.ink)
                    Spacer(Modifier.weight(1f))
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = c.accent, modifier = Modifier.size(18.dp))
                }
            }
        }

        // Account
        Column(Modifier.fillMaxWidth().ayantGroupCard()) {
            AccountRow(Icons.AutoMirrored.Filled.Logout, "Выйти") { session.signOut() }
            AyantHairline(leading = 14)
            AccountRow(Icons.Filled.Delete, "Удалить аккаунт") { showDelete = true }
        }

        Text("Версия 0.3 (MVP)", fontSize = 13.sp, color = c.inkSoft, modifier = Modifier.fillMaxWidth(), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    }

    if (showDelete) {
        AlertDialog(
            onDismissRequest = { showDelete = false },
            title = { Text("Удалить аккаунт?") },
            text = { Text("Это действие необратимо. Все отзывы и сохранённое будут удалены.") },
            confirmButton = { TextButton(onClick = { showDelete = false; session.signOut() }) { Text("Удалить", color = Color(0xFFD32F2F)) } },
            dismissButton = { TextButton(onClick = { showDelete = false }) { Text("Отмена") } },
        )
    }
}

@Composable
private fun SettingRow(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, value: String) {
    val c = AyantTheme.colors
    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 13.dp), verticalAlignment = Alignment.CenterVertically) {
        AyantIconTile(icon, size = 34)
        Text(title, fontSize = 16.sp, color = c.ink, modifier = Modifier.padding(start = 12.dp))
        Spacer(Modifier.weight(1f))
        Text(value, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = c.inkSoft)
    }
}

@Composable
private fun AccountRow(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = Color(0xFFD32F2F), modifier = Modifier.size(22.dp))
        Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Color(0xFFD32F2F), modifier = Modifier.padding(start = 12.dp))
    }
}
