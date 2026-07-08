package kg.ayant.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.LocalOffer
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.core.distanceText
import kg.ayant.app.core.sanShort
import kg.ayant.app.data.model.Deal
import kg.ayant.app.data.model.Venue
import kg.ayant.app.ui.theme.AyantTheme

private val AdGradient = Brush.horizontalGradient(listOf(Color(0xFFFF4D29), Color(0xFFFFB300)))

// MARK: - Venue card (feed, search). Mirrors VenueCard.

@Composable
fun VenueCard(
    venue: Venue,
    distanceKm: Double?,
    isSaved: Boolean,
    dealCount: Int,
    rating: Double,
    ratingCount: Int,
    isSponsored: Boolean = false,
    onSaveClick: () -> Unit,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    val shape = RoundedCornerShape(22.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(if (isSponsored) c.accent.copy(alpha = 0.06f) else c.surface)
            .border(if (isSponsored) 1.5.dp else 0.5.dp, if (isSponsored) c.accent.copy(alpha = 0.6f) else c.hairline, shape)
            .clickable(onClick = onClick),
    ) {
        if (isSponsored) AdBanner("рекомендуем заведение")
        // Cover
        Box(Modifier.fillMaxWidth().height(180.dp)) {
            VenuePhoto(venue.imageURL, venue.gradient, Modifier.fillMaxWidth().height(180.dp))
            Box(
                Modifier
                    .align(Alignment.TopEnd)
                    .padding(10.dp)
                    .size(34.dp)
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.35f))
                    .clickable(onClick = onSaveClick),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (isSaved) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
                    null, tint = Color.White, modifier = Modifier.size(18.dp),
                )
            }
            if (venue.hasTodaySpecial) {
                Text(
                    "⭐️ Сегодня",
                    fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color.White,
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(10.dp)
                        .clip(RoundedCornerShape(50))
                        .background(c.accent)
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                )
            }
        }
        // Info
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(venue.name, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = c.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (venue.isVerified) {
                    Icon(Icons.Filled.Verified, null, tint = Color(0xFF2F80ED), modifier = Modifier.padding(start = 5.dp).size(16.dp))
                }
                Spacer(Modifier.weight(1f))
                Text(
                    if (venue.isOpenNow) "Открыто" else "Закрыто",
                    fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                    color = if (venue.isOpenNow) c.open else c.inkSoft,
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                StarRating(rating = rating, count = ratingCount, size = 12)
                Text(" · ${venue.category.rawValue}", fontSize = 12.sp, color = c.inkSoft)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (distanceKm != null) {
                    Icon(Icons.Filled.LocationOn, null, tint = c.inkSoft, modifier = Modifier.size(13.dp))
                    Text(" ${distanceKm.distanceText()}", fontSize = 12.sp, color = c.inkSoft, modifier = Modifier.padding(end = 10.dp))
                }
                if (dealCount > 0) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.clip(RoundedCornerShape(50)).background(c.accent.copy(alpha = 0.12f)).padding(horizontal = 8.dp, vertical = 3.dp),
                    ) {
                        Icon(Icons.Filled.LocalOffer, null, tint = c.accent, modifier = Modifier.size(11.dp))
                        Text(" $dealCount акц.", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = c.accent)
                    }
                }
            }
        }
    }
}

// MARK: - Deal card (Instagram-style feed). Mirrors DealCard.

@Composable
fun DealCard(
    deal: Deal,
    venue: Venue?,
    rating: Double,
    isFavorite: Boolean,
    onTap: () -> Unit,
    onVenueTap: () -> Unit,
    onFavoriteClick: () -> Unit,
    onShare: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    val shape = RoundedCornerShape(22.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(c.surface)
            .border(0.5.dp, c.hairline, shape),
    ) {
        // Header → venue
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().clickable(onClick = onVenueTap).padding(horizontal = 14.dp, vertical = 12.dp),
        ) {
            if (venue != null) VenueAvatar(venue.gradient, venue.imageURL, 46)
            Column(Modifier.padding(start = 12.dp).weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(venue?.name ?: "", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = c.ink)
                    if (venue?.isVerified == true) {
                        Icon(Icons.Filled.Verified, null, tint = Color(0xFF2F80ED), modifier = Modifier.padding(start = 4.dp).size(12.dp))
                    }
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = c.inkSoft, modifier = Modifier.size(14.dp))
                }
                Text("${venue?.category?.rawValue ?: ""} • ${venue?.district ?: ""}", fontSize = 12.sp, color = c.inkSoft)
            }
            DealTypeBadge(deal)
        }
        // Visual + caption → deal
        Column(Modifier.clickable(onClick = onTap)) {
            Box {
                CoverImage(deal.imageURL, venue?.gradient ?: listOf(c.accent, c.accentDeep), deal.emoji, Modifier.fillMaxWidth().height(240.dp), emojiSize = 90)
                deal.discountPercent?.let { pct ->
                    Text(
                        "−$pct%",
                        fontSize = 22.sp, fontWeight = FontWeight.Black, color = Color.White,
                        modifier = Modifier.padding(12.dp).clip(RoundedCornerShape(50)).background(Color.Black.copy(alpha = 0.35f)).padding(horizontal = 14.dp, vertical = 8.dp),
                    )
                }
            }
            Column(Modifier.padding(horizontal = 14.dp).padding(top = 16.dp, bottom = 4.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                deal.urgencyText?.let {
                    Text(
                        "🔥 $it",
                        fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color(0xFFD32F2F),
                        modifier = Modifier.clip(RoundedCornerShape(50)).background(Color(0xFFD32F2F).copy(alpha = 0.12f)).padding(horizontal = 8.dp, vertical = 3.dp),
                    )
                }
                Text(deal.title, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
                Text(deal.details, fontSize = 14.sp, color = c.inkSoft, maxLines = 2, overflow = TextOverflow.Ellipsis)
                PriceLabel(deal)
            }
        }
        // Actions
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(14.dp)) {
            Icon(Icons.Filled.Schedule, null, tint = c.inkSoft, modifier = Modifier.size(14.dp))
            Text(" до ${deal.validUntil.sanShort()}", fontSize = 12.sp, color = c.inkSoft)
            Spacer(Modifier.weight(1f))
            Icon(
                if (isFavorite) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
                null, tint = if (isFavorite) c.accent else c.ink,
                modifier = Modifier.size(22.dp).clickable(onClick = onFavoriteClick),
            )
            Icon(Icons.Filled.Share, null, tint = c.ink, modifier = Modifier.padding(start = 18.dp).size(20.dp).clickable(onClick = onShare))
        }
    }
}

@Composable
private fun AdBanner(trailing: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().background(AdGradient).padding(horizontal = 14.dp, vertical = 8.dp),
    ) {
        Icon(Icons.Filled.Campaign, null, tint = Color.White, modifier = Modifier.size(14.dp))
        Text(" Реклама", fontSize = 12.sp, fontWeight = FontWeight.Black, color = Color.White)
        Spacer(Modifier.weight(1f))
        Text(trailing, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.9f))
    }
}

// MARK: - Compact venue row (Saved, cluster). Mirrors VenueCompactRow.

@Composable
fun VenueCompactRow(
    venue: Venue,
    distanceKm: Double?,
    rating: Double,
    ratingCount: Int,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 8.dp, horizontal = 4.dp),
    ) {
        VenueAvatar(venue.gradient, venue.imageURL, 62)
        Column(Modifier.padding(start = 14.dp).weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(venue.name, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = c.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (venue.isVerified) Icon(Icons.Filled.Verified, null, tint = Color(0xFF2F80ED), modifier = Modifier.padding(start = 4.dp).size(13.dp))
            }
            StarRating(rating = rating, count = ratingCount, size = 12)
            Text(
                "${venue.category.rawValue} · ${venue.district}" + (distanceKm?.let { " · ${it.distanceText()}" } ?: ""),
                fontSize = 12.sp, color = c.inkSoft, maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = c.inkSoft, modifier = Modifier.size(18.dp))
    }
}

// MARK: - Compact deal row (Saved deals). Mirrors CompactDealRow.

@Composable
fun CompactDealRow(
    deal: Deal,
    venueName: String?,
    venueGradient: List<Color>,
    isFavorite: Boolean,
    onClick: () -> Unit,
    onFavoriteClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 8.dp, horizontal = 4.dp),
    ) {
        CoverImage(deal.imageURL, venueGradient, deal.emoji, Modifier.size(62.dp).clip(RoundedCornerShape(14.dp)), emojiSize = 28)
        Column(Modifier.padding(start = 14.dp).weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(deal.title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = c.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(
                (venueName?.let { "$it • " } ?: "") + "до ${deal.validUntil.sanShort()}",
                fontSize = 12.sp, color = c.inkSoft,
            )
        }
        Icon(
            if (isFavorite) Icons.Filled.Bookmark else Icons.Filled.BookmarkBorder,
            null, tint = if (isFavorite) c.accent else c.inkSoft,
            modifier = Modifier.padding(start = 8.dp).size(22.dp).clickable(onClick = onFavoriteClick),
        )
    }
}
