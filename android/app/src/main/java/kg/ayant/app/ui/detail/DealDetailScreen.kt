package kg.ayant.app.ui.detail

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.core.Links
import kg.ayant.app.core.sanShort
import kg.ayant.app.core.shareText
import kg.ayant.app.ui.components.CoverImage
import kg.ayant.app.ui.components.DealTypeBadge
import kg.ayant.app.ui.components.PriceLabel
import kg.ayant.app.ui.components.QrCode
import kg.ayant.app.ui.components.VenueAvatar
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.ui.vm.SessionViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DealDetailScreen(
    dealID: String,
    app: AppViewModel,
    session: SessionViewModel,
    onBack: () -> Unit,
    onVenue: (String) -> Unit,
) {
    val c = AyantTheme.colors
    val context = LocalContext.current
    val deal = app.deals.firstOrNull { it.id == dealID } ?: run {
        Box(Modifier.fillMaxSize().background(c.canvas), contentAlignment = Alignment.Center) { Text("Предложение не найдено") }
        return
    }
    val venue = app.venue(forDeal = deal)

    Scaffold(
        containerColor = c.canvas,
        topBar = {
            TopAppBar(
                title = { Text(venue?.name ?: "Предложение", fontWeight = FontWeight.Bold, maxLines = 1) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Назад") } },
                actions = {
                    IconButton(onClick = { app.toggleFavorite(deal) }) {
                        Icon(if (app.isFavorite(deal)) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder, "Сохранить")
                    }
                    IconButton(onClick = { context.shareText("${deal.title} — ${venue?.name ?: ""}. Нашёл в Ayant! ${Links.deal(deal.id)}", deal.title) }) {
                        Icon(Icons.Filled.Share, "Поделиться")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = c.canvas, titleContentColor = c.ink),
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Box {
                CoverImage(deal.imageURL, venue?.gradient ?: listOf(c.accent, c.accentDeep), deal.emoji, Modifier.fillMaxWidth().height(300.dp), emojiSize = 100)
                deal.discountPercent?.let { pct ->
                    Text(
                        "−$pct%", fontSize = 28.sp, fontWeight = FontWeight.Black, color = Color.White,
                        modifier = Modifier.padding(16.dp).clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.35f)).padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }
            }

            Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                DealTypeBadge(deal)
                Text(deal.title, fontSize = 24.sp, fontWeight = FontWeight.Bold, color = c.ink)
                Text(deal.details, fontSize = 16.sp, color = c.inkSoft)
                PriceLabel(deal)
                deal.urgencyText?.let {
                    Text(
                        "🔥 $it", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color(0xFFD32F2F),
                        modifier = Modifier.clip(RoundedCornerShape(50)).background(Color(0xFFD32F2F).copy(alpha = 0.12f)).padding(horizontal = 10.dp, vertical = 5.dp),
                    )
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Schedule, null, tint = c.inkSoft, modifier = Modifier.size(16.dp))
                    Text(" Действует до ${deal.validUntil.sanShort()}", fontSize = 14.sp, color = c.inkSoft)
                }
            }

            // Coupon
            if (deal.isRedeemable && (venue?.couponsEnabled != false)) {
                Column(
                    Modifier.padding(horizontal = 16.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.accent.copy(alpha = 0.08f)).padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        QrCode("AYANT-${deal.id.uppercase()}", size = 92)
                        Column(Modifier.padding(start = 14.dp)) {
                            Text("Купон на предложение", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = c.ink)
                            Text("Сотрудник сканирует QR и применяет предложение перед оплатой.", fontSize = 12.sp, color = c.inkSoft)
                        }
                    }
                    if (session.isGuest) {
                        Text("Войдите в аккаунт, чтобы получить купон.", fontSize = 12.sp, color = c.inkSoft)
                    }
                }
            }

            // Venue section
            if (venue != null) {
                Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("Заведение", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink)
                    Row(
                        Modifier.fillMaxWidth().clickable { onVenue(venue.id) },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        VenueAvatar(venue.gradient, venue.imageURL, 48)
                        Column(Modifier.padding(start = 12.dp).weight(1f)) {
                            Text(venue.name, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = c.ink)
                            Text("${venue.category.rawValue} • ${venue.district}", fontSize = 12.sp, color = c.inkSoft)
                        }
                        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = c.inkSoft, modifier = Modifier.size(18.dp))
                    }
                }
            }
        }
    }
}
