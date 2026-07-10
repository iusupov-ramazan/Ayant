package kg.ayant.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.ui.geometry.isSpecified
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.StarHalf
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.SubcomposeAsyncImage
import kg.ayant.app.core.storefrontIcon
import kg.ayant.app.data.model.Deal
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.color

// MARK: - Responsive deal image (card height follows the photo's aspect ratio,
// clamped to the Instagram range 1.91:1 … 4:5). Mirrors DealImage.

@Composable
fun DealImage(
    urlString: String?,
    gradient: List<Color>,
    emoji: String,
    modifier: Modifier = Modifier,
    emojiSize: Int = 80,
) {
    val minAR = 0.8f   // tallest (4:5)
    val maxAR = 1.91f  // widest (1.91:1)
    if (urlString.isNullOrEmpty()) {
        Box(
            modifier.fillMaxWidth().aspectRatio(1f).background(Brush.linearGradient(gradient)),
            contentAlignment = Alignment.Center,
        ) { Text(emoji, fontSize = emojiSize.sp) }
        return
    }
    val painter = coil.compose.rememberAsyncImagePainter(urlString)
    val size = painter.intrinsicSize
    val aspect = if (size.isSpecified && size.height > 0f) (size.width / size.height).coerceIn(minAR, maxAR) else 1f
    Box(
        modifier.fillMaxWidth().aspectRatio(aspect).background(Brush.linearGradient(gradient)),
        contentAlignment = Alignment.Center,
    ) {
        androidx.compose.foundation.Image(
            painter = painter, contentDescription = null,
            contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize(),
        )
        if (painter.state !is coil.compose.AsyncImagePainter.State.Success) {
            Text(emoji, fontSize = emojiSize.sp)
        }
    }
}

// MARK: - Image carousel (swipe + dots), falls back to a single responsive image.
// Mirrors ImageCarousel.

@Composable
fun ImageCarousel(
    urls: List<String>,
    gradient: List<Color>,
    emoji: String,
    modifier: Modifier = Modifier,
    height: Int = 260,
    emojiSize: Int = 90,
) {
    val imgs = urls.filter { it.isNotEmpty() }
    if (imgs.size <= 1) {
        DealImage(imgs.firstOrNull(), gradient, emoji, modifier, emojiSize)
        return
    }
    val pager = androidx.compose.foundation.pager.rememberPagerState { imgs.size }
    Box(modifier.fillMaxWidth().height(height.dp)) {
        androidx.compose.foundation.pager.HorizontalPager(state = pager, modifier = Modifier.fillMaxSize()) { i ->
            CoverImage(imgs[i], gradient, emoji, Modifier.fillMaxSize(), emojiSize)
        }
        Row(
            Modifier.align(Alignment.BottomCenter).padding(bottom = 10.dp),
            horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(6.dp),
        ) {
            repeat(imgs.size) { i ->
                Box(
                    Modifier.size(if (i == pager.currentPage) 8.dp else 6.dp)
                        .clip(androidx.compose.foundation.shape.CircleShape)
                        .background(if (i == pager.currentPage) Color.White else Color.White.copy(alpha = 0.5f))
                )
            }
        }
    }
}

// MARK: - Cover image (photo over gradient, emoji fallback). Mirrors CoverImage.

@Composable
fun CoverImage(
    urlString: String?,
    gradient: List<Color>,
    emoji: String,
    modifier: Modifier = Modifier,
    emojiSize: Int = 64,
) {
    Box(
        modifier = modifier.background(Brush.linearGradient(gradient)),
        contentAlignment = Alignment.Center,
    ) {
        if (!urlString.isNullOrEmpty()) {
            SubcomposeAsyncImage(
                model = urlString,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
                error = { Text(emoji, fontSize = emojiSize.sp) },
                loading = { Text(emoji, fontSize = emojiSize.sp) },
            )
        } else {
            Text(emoji, fontSize = emojiSize.sp)
        }
    }
}

// MARK: - Venue photo (gradient + storefront glyph / photo). Mirrors VenuePhoto.

@Composable
fun VenuePhoto(urlString: String?, gradient: List<Color>, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier.background(Brush.linearGradient(gradient)),
        contentAlignment = Alignment.Center,
    ) {
        if (!urlString.isNullOrEmpty()) {
            SubcomposeAsyncImage(
                model = urlString,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
                error = { StoreGlyph() },
                loading = { StoreGlyph() },
            )
        } else {
            StoreGlyph()
        }
    }
}

@Composable
private fun StoreGlyph() {
    Icon(storefrontIcon, contentDescription = null, tint = Color.White.copy(alpha = 0.85f), modifier = Modifier.size(44.dp))
}

// MARK: - Venue avatar (circular gradient + glyph/photo). Mirrors VenueAvatar.

@Composable
fun VenueAvatar(gradient: List<Color>, urlString: String?, size: Int = 40, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(size.dp)
            .clip(CircleShape)
            .background(Brush.linearGradient(gradient)),
        contentAlignment = Alignment.Center,
    ) {
        if (!urlString.isNullOrEmpty()) {
            SubcomposeAsyncImage(
                model = urlString,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.size(size.dp),
                error = { Icon(storefrontIcon, null, tint = Color.White, modifier = Modifier.size((size * 0.42).dp)) },
            )
        } else {
            Icon(storefrontIcon, null, tint = Color.White, modifier = Modifier.size((size * 0.42).dp))
        }
    }
}

// MARK: - Star rating. Mirrors StarRatingView.

@Composable
fun StarRating(rating: Double, count: Int? = null, size: Int = 13, modifier: Modifier = Modifier) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = modifier) {
        for (i in 0 until 5) {
            val v = rating - i
            val icon = when {
                v >= 1 -> Icons.Filled.Star
                v >= 0.5 -> Icons.Filled.StarHalf
                else -> Icons.Filled.StarBorder
            }
            Icon(icon, null, tint = Color(0xFFF5C518), modifier = Modifier.size(size.dp))
        }
        Text(
            "%.1f".format(rating),
            fontSize = size.sp,
            fontWeight = FontWeight.SemiBold,
            color = AyantTheme.colors.ink,
            modifier = Modifier.padding(start = 4.dp),
        )
        if (count != null) {
            Text("($count)", fontSize = size.sp, color = AyantTheme.colors.inkSoft, modifier = Modifier.padding(start = 3.dp))
        }
    }
}

// MARK: - Deal type badge. Mirrors DealTypeBadge.

@Composable
fun DealTypeBadge(deal: Deal, modifier: Modifier = Modifier) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .clip(RoundedCornerShape(50))
            .background(deal.type.color)
            .padding(horizontal = 10.dp, vertical = 5.dp),
    ) {
        Icon(kg.ayant.app.core.dealTypeIcon(deal.type), null, tint = Color.White, modifier = Modifier.size(12.dp))
        Text(deal.type.title, color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 4.dp))
    }
}

// MARK: - Price. Mirrors PriceLabel.

@Composable
fun PriceLabel(deal: Deal, modifier: Modifier = Modifier) {
    Row(verticalAlignment = Alignment.Bottom, modifier = modifier) {
        deal.oldPrice?.let {
            Text(
                "$it сом",
                fontSize = 14.sp,
                color = AyantTheme.colors.inkSoft,
                textDecoration = androidx.compose.ui.text.style.TextDecoration.LineThrough,
                modifier = Modifier.padding(end = 8.dp),
            )
        }
        deal.newPrice?.let {
            Text("$it сом", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = AyantTheme.colors.accent)
        }
    }
}
