package kg.ayant.app.ui.home

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import android.text.format.DateUtils
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.outlined.BookmarkBorder
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.Share
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import kg.ayant.app.ui.components.VenuePhoto
import kg.ayant.app.ui.theme.ayantPopOnSet
import kg.ayant.app.ui.theme.ayantPressScale
import kotlinx.coroutines.delay
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.BiasAlignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.geometry.isSpecified
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImagePainter
import coil.compose.rememberAsyncImagePainter
import kg.ayant.app.R
import kg.ayant.app.core.distanceText
import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.DealType
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.ui.theme.AyantMotion
import kg.ayant.app.ui.theme.AyantTiming
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantPopOnSet
import kg.ayant.app.ui.theme.ayantPressScale
import kg.ayant.app.ui.theme.ayantRisoHatch
import kg.ayant.app.ui.theme.gradientColors
import kg.ayant.app.ui.theme.rememberReduceMotion
import kotlin.math.roundToInt

/**
 * Redesigned feed card (SCREENS.md G2). Mirrors `FeedCard.swift`.
 *
 * The defining change of the redesign: full-bleed, no corner radius, 10dp of
 * canvas between cards. Photo fills the frame; the text sits on top of a
 * four-stop scrim.
 *
 * The card is NOT a fixed height: it takes the proportions of the photo itself,
 * like an Instagram feed. The ratio is clamped to a corridor — otherwise a
 * panorama collapses into a strip and a very tall frame pushes everything else
 * off screen. We clamp the RATIO, not a height in dp, so the same card reads the
 * same on any screen width.
 */
object AyantFeedCard {
    /** Width / height. Smaller means a taller card. */
    const val TALLEST_ASPECT = 0.63f
    const val WIDEST_ASPECT = 0.95f
    /** Until the photo has loaded (and when there is none) — the handoff ratio. */
    const val PLACEHOLDER_ASPECT = 0.67f

    /** Frame ratio, clamped into the corridor. */
    fun aspect(width: Float, height: Float): Float =
        if (width <= 0f || height <= 0f) PLACEHOLDER_ASPECT
        else (width / height).coerceIn(TALLEST_ASPECT, WIDEST_ASPECT)
}

/**
 * Loads the photo once and reports both the painter and its real proportions.
 *
 * [rememberAsyncImagePainter] rather than plain [AsyncImage] because the card
 * height has to be known before the photo is drawn, and only the painter exposes
 * `intrinsicSize`. Coil's own cache means nothing is fetched twice.
 */
@Composable
private fun rememberFeedPhoto(imageUrl: String?): Pair<AsyncImagePainter?, Float> {
    if (imageUrl.isNullOrEmpty()) return null to AyantFeedCard.PLACEHOLDER_ASPECT
    val painter = rememberAsyncImagePainter(model = imageUrl)
    val size = (painter.state as? AsyncImagePainter.State.Success)?.painter?.intrinsicSize
    val aspect = if (size != null && size.isSpecified) {
        AyantFeedCard.aspect(size.width, size.height)
    } else {
        AyantFeedCard.PLACEHOLDER_ASPECT
    }
    return painter to aspect
}

@Composable
private fun FeedPhoto(painter: AsyncImagePainter?, gradient: List<Color>) {
    Box(Modifier.fillMaxSize().background(Brush.linearGradient(gradient))) {
        if (painter != null) {
            // The frame is already in its own proportions, so `Crop` trims almost
            // nothing — only at the edges of the ratio corridor.
            Image(
                painter = painter,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            // Fallback: hatch + camera glyph + «ФОТО», the glyph at 44% height.
            // A bias rather than a dp offset — the card height is no longer fixed.
            Box(Modifier.fillMaxSize().ayantRisoHatch(alpha = 0.21f, stripe = 1.5.dp, period = 14.dp))
            Column(
                Modifier.fillMaxSize().wrapContentHeight(BiasAlignment.Vertical(-0.12f)),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(9.dp),
            ) {
                Icon(
                    Icons.Filled.PhotoCamera, null,
                    tint = Color.White.copy(alpha = 0.6f),
                    modifier = Modifier.size(34.dp),
                )
                Text(
                    stringResource(R.string.feed_photo_placeholder),
                    fontSize = 10.5.sp, fontWeight = FontWeight.Black,
                    letterSpacing = 2.sp, color = Color.White.copy(alpha = 0.6f),
                )
            }
        }
    }
}

/** Four-stop scrim. Never flatten it: the white text below rides on the bottom two stops. */
@Composable
private fun FeedScrim() {
    val ink = Color(0xFF17130F)
    Box(
        Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    0f to ink.copy(alpha = 0.28f),
                    0.38f to ink.copy(alpha = 0.10f),
                    0.70f to ink.copy(alpha = 0.74f),
                    1f to ink.copy(alpha = 0.94f),
                )
            )
    )
}

@Composable
private fun FeedGlassChip(text: String, dotColor: Color? = null) {
    Row(
        Modifier
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.14f))
            .padding(horizontal = 12.dp, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (dotColor != null) {
            Box(Modifier.size(6.dp).clip(CircleShape).background(dotColor))
        }
        Text(text, fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
    }
}

@Composable
private fun FeedSaveButton(isSaved: Boolean, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val shape = RoundedCornerShape(16.dp)
    Box(
        Modifier
            .size(44.dp)
            .ayantPopOnSet(isSaved)
            .clip(shape)
            .then(
                if (isSaved) Modifier.background(AyantTheme.colors.accentGradient)
                else Modifier.background(Color.White.copy(alpha = 0.18f))
            )
            .selectable(
                selected = isSaved,
                interactionSource = interaction,
                indication = null,
                role = Role.Button,
                onClick = onClick,
            )
            .ayantPressScale(interaction, scale = 0.86f),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            if (isSaved) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
            contentDescription = stringResource(
                if (isSaved) R.string.action_unsave else R.string.action_save
            ),
            tint = Color.White,
            modifier = Modifier.size(19.dp),
        )
    }
}

@Composable
private fun DiscountBadge(text: String) {
    val c = AyantTheme.colors
    Box(
        Modifier
            .rotate(-3f)
            .clip(RoundedCornerShape(12.dp))
            .background(c.accentGradient)
            .padding(horizontal = 13.dp, vertical = 8.dp),
    ) {
        Text(
            text, fontSize = 15.sp, fontWeight = FontWeight.Black,
            letterSpacing = (-0.5).sp, color = Color.White,
        )
    }
}


// MARK: - Пост ленты (SCREENS.md G2). Зеркалит `FeedCard.swift`.
//
// Лента переехала с полноэкранной карточки на пост, как в Instagram: белая
// полоса во всю ширину, фото 4:5 и ВЕСЬ текст под фотографией, на белом.
// Раньше заголовок, цена и чипы лежали поверх снимка на скриме; скрим держал
// контраст, но съедал нижнюю треть кадра и ограничивал текст двумя строками.
// На белом ограничение снимается — отсюда описание со сворачиванием и ряд
// действий. На фотографии не осталось ничего, кроме бейджа скидки.

/**
 * Каркас поста: белая полоса без рамок.
 *
 * Линий сверху и снизу нет: посты и так разделены полосой канваса, а две
 * границы на каждый пост превращали ленту в таблицу.
 */
@Composable
private fun FeedPostFrame(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.fillMaxWidth().background(AyantTheme.colors.surface),
        content = content,
    )
}

/** Аватар заведения: кольцо градиентом заведения → белый зазор → заливка. */
@Composable
private fun FeedPostAvatar(gradient: List<Color>, imageURL: String?) {
    val brush = Brush.linearGradient(gradient)
    Box(
        Modifier.size(38.dp).clip(CircleShape).background(brush),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier.size(35.dp).clip(CircleShape).background(AyantTheme.colors.surface),
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.size(32.dp).clip(CircleShape).background(brush)) {
                if (!imageURL.isNullOrEmpty()) {
                    Image(
                        painter = rememberAsyncImagePainter(imageURL),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
            }
        }
    }
}

/** Кнопка ряда действий. Цель нажатия — 44dp, глиф меньше. */
@Composable
private fun FeedActionButton(
    icon: ImageVector,
    contentDescription: String,
    size: Dp = 23.dp,
    tint: Color = AyantTheme.colors.ink,
    isOn: Boolean = false,
    onClick: () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    Box(
        Modifier
            .size(44.dp)
            .ayantPressScale(interaction, 0.86f)
            .ayantPopOnSet(isOn)
            .clickable(interaction, null, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription, tint = tint, modifier = Modifier.size(size))
    }
}

/**
 * Фото поста 4:5 с бейджем и двойным тапом.
 *
 * `aspectRatio` считает высоту от ширины, поэтому кадр любой пропорции даёт
 * плитку одного размера — посты не разъезжаются, когда подгружаются снимки.
 */
@Composable
private fun FeedPostPhoto(
    imageURL: String?,
    gradient: List<Color>,
    onOpen: () -> Unit,
    onDoubleTapLike: (() -> Unit)? = null,
    badge: @Composable () -> Unit,
) {
    var burst by remember { mutableStateOf(false) }
    val burstScale by animateFloatAsState(
        targetValue = if (burst) 1f else 0.7f,
        animationSpec = AyantMotion.pop(),
        label = "burstScale",
    )
    LaunchedEffect(burst) {
        if (burst) { delay(420); burst = false }
    }
    Box(
        Modifier
            .fillMaxWidth()
            .aspectRatio(4f / 5f)
            .pointerInput(onDoubleTapLike) {
                detectTapGestures(
                    onDoubleTap = onDoubleTapLike?.let { like -> { like(); burst = true } },
                    onTap = { onOpen() },
                )
            },
    ) {
        VenuePhoto(imageURL?.ifEmpty { null }, gradient, Modifier.fillMaxSize())
        Box(Modifier.padding(start = 14.dp, top = 14.dp)) { badge() }
        if (burst) {
            Icon(
                Icons.Filled.Favorite, null,
                tint = Color.White,
                modifier = Modifier.align(Alignment.Center).size(92.dp).scale(burstScale),
            )
        }
    }
}

@Composable
fun FeedDealCard(
    deal: Deal,
    venue: Venue?,
    distanceKm: Double?,
    isSaved: Boolean,
    isLiked: Boolean,
    onOpen: () -> Unit,
    onVenue: () -> Unit,
    onSave: () -> Unit,
    onLike: () -> Unit,
    onShare: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    val gradient = venue?.gradientColors ?: listOf(c.accent, Color(0xFFFF9500))
    var expanded by remember(deal.id) { mutableStateOf(false) }
    var isTruncated by remember(deal.id) { mutableStateOf(false) }

    FeedPostFrame(modifier) {
        FeedPostHeader(
            name = venue?.name.orEmpty(),
            verified = venue?.isVerified == true,
            subtitle = postSubtitle(venue?.district, distanceKm),
            gradient = gradient,
            imageURL = venue?.imageURL,
            onOpen = onVenue,
        )
        FeedPostPhoto(
            imageURL = deal.allImages.firstOrNull() ?: venue?.imageURL,
            gradient = gradient,
            onOpen = onOpen,
            onDoubleTapLike = onLike,
        ) {
            DiscountBadge(deal.effectiveDiscountPercent?.let { "−$it%" } ?: deal.type.badgeLabel())
        }

        // Сердечко и закладка — РАЗНЫЕ действия. Сердечко это реакция (живёт на
        // устройстве), закладка кладёт акцию в «Сохранённое».
        Row(
            Modifier.fillMaxWidth().padding(top = 4.dp, start = 8.dp, end = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            FeedActionButton(
                icon = if (isLiked) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                contentDescription = stringResource(
                    if (isLiked) R.string.action_unlike else R.string.action_like),
                size = 24.dp,
                tint = if (isLiked) Color(0xFFFF3B00) else c.ink,
                isOn = isLiked,
                onClick = onLike,
            )
            FeedActionButton(Icons.Outlined.Share,
                stringResource(R.string.action_share), onClick = onShare)
            Spacer(Modifier.weight(1f))
            FeedActionButton(
                icon = if (isSaved) Icons.Filled.Bookmark else Icons.Outlined.BookmarkBorder,
                contentDescription = stringResource(
                    if (isSaved) R.string.action_unsave else R.string.action_save),
                size = 22.dp,
                tint = if (isSaved) c.accentText else c.ink,
                isOn = isSaved,
                onClick = onSave,
            )
        }

        // Вся подпись открывает акцию. Исключение — переключатель «…ещё»: он
        // раскрывает текст на месте, и уводить с ленты по нему нельзя.
        val captionInteraction = remember { MutableInteractionSource() }
        Column(
            Modifier
                .clickable(captionInteraction, null, onClick = onOpen)
                .padding(top = 2.dp, start = 15.dp, end = 15.dp, bottom = 17.dp),
        ) {
            PriceRow(deal)
            Spacer(Modifier.height(8.dp))
            Text(
                deal.title,
                fontSize = 19.sp, fontWeight = FontWeight.Black,
                letterSpacing = (-0.7).sp, lineHeight = 23.sp, color = c.ink,
            )
            val details = deal.details.trim()
            if (details.isNotEmpty()) {
                Spacer(Modifier.height(8.dp))
                Text(
                    details,
                    // Описание — вторичный текст, а не второй заголовок. Прежний
                    // #3D362F почти совпадал с чернилами. `inkSoft` — тот же
                    // токен, что у всех подписей на белом, и проходит 4.5:1.
                    fontSize = 14.sp, lineHeight = 21.sp, color = c.inkSoft,
                    maxLines = if (expanded) Int.MAX_VALUE else 2,
                    overflow = TextOverflow.Ellipsis,
                    // Без этой проверки «…ещё» висело бы под любым описанием,
                    // в том числе под однострочным, и ничего не раскрывало.
                    onTextLayout = { if (!expanded) isTruncated = it.hasVisualOverflow },
                )
                if (isTruncated || deal.terms.isNotEmpty()) {
                    val interaction = remember { MutableInteractionSource() }
                    Text(
                        stringResource(if (expanded) R.string.feed_collapse else R.string.feed_more),
                        fontSize = 13.5.sp, fontWeight = FontWeight.Bold, color = c.inkSoft,
                        modifier = Modifier
                            .padding(top = 6.dp)
                            .ayantPressScale(interaction, 0.94f)
                            .clickable(interaction, null) { expanded = !expanded },
                    )
                }
                if (expanded) TermsPanel(deal.terms)
            }
            Spacer(Modifier.height(12.dp))
            CaptionChipRow(venue, distanceKm)
            postMeta(venue?.reviewCount, deal.startDate)?.let {
                Text(
                    it, fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold,
                    color = Color(0xFF9A9188), modifier = Modifier.padding(top = 10.dp),
                )
            }
        }
    }
}

/**
 * Условия акции — панель на канвасе под описанием.
 *
 * Показывается только в развёрнутом виде: условия отвечают на вопрос «а что
 * мелким шрифтом», который возникает уже после интереса. В свёрнутой ленте они
 * бы просто удлиняли каждый пост.
 */
@Composable
private fun TermsPanel(terms: List<String>) {
    if (terms.isEmpty()) return
    val c = AyantTheme.colors
    Column(
        Modifier
            .padding(top = 4.dp)
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(c.canvas)
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        terms.forEach { line ->
            Row(verticalAlignment = Alignment.Top) {
                Box(
                    Modifier
                        // Точка на середину первой строки текста, а не на её верх.
                        .padding(top = 6.dp)
                        .size(5.dp).clip(CircleShape).background(c.accentText),
                )
                Spacer(Modifier.width(8.dp))
                Text(line, fontSize = 12.5.sp, lineHeight = 18.sp, color = c.inkSoft)
            }
        }
    }
}

@Composable
private fun FeedPostHeader(
    name: String,
    verified: Boolean,
    subtitle: String?,
    gradient: List<Color>,
    imageURL: String?,
    onOpen: () -> Unit,
) {
    val c = AyantTheme.colors
    val interaction = remember { MutableInteractionSource() }
    Row(
        Modifier.fillMaxWidth().padding(top = 11.dp, start = 14.dp, end = 14.dp, bottom = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            Modifier.weight(1f)
                .ayantPressScale(interaction, 0.98f)
                .clickable(interaction, null, onClick = onOpen),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            FeedPostAvatar(gradient, imageURL)
            Column(Modifier.padding(start = 10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(name, fontSize = 14.sp, fontWeight = FontWeight.Bold,
                        letterSpacing = (-0.25).sp, color = c.ink, maxLines = 1,
                        overflow = TextOverflow.Ellipsis)
                    if (verified) {
                        Spacer(Modifier.width(5.dp))
                        Icon(Icons.Filled.Verified, null, tint = Color(0xFF4DA3FF),
                            modifier = Modifier.size(12.dp))
                    }
                }
                if (subtitle != null) {
                    Text(subtitle, fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold,
                        color = c.inkSoft, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

/** «Центр · 0,4 км» — район всегда, расстояние если геолокация разрешена. */
private fun postSubtitle(district: String?, distanceKm: Double?): String? {
    val d = district.orEmpty()
    val km = distanceKm?.distanceText()
    return when {
        d.isNotEmpty() && km != null -> "$d · $km"
        d.isNotEmpty() -> d
        else -> km
    }
}

@Composable
private fun PriceRow(deal: Deal) {
    val savings = deal.oldPrice?.let { old -> deal.newPrice?.let { new -> (old - new).takeIf { it > 0 } } }
    if (deal.newPrice == null && deal.oldPrice == null) return
    Row(
        verticalAlignment = Alignment.Bottom,
        horizontalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        deal.newPrice?.let {
            Text(
                stringResource(R.string.price_som, it),
                fontSize = 27.sp, fontWeight = FontWeight.Black,
                letterSpacing = (-1.1).sp, color = AyantTheme.colors.accentText,
            )
        }
        deal.oldPrice?.let {
            Text(
                stringResource(R.string.price_som, it),
                fontSize = 14.5.sp, color = Color(0xFF9A9188),
                textDecoration = TextDecoration.LineThrough,
            )
        }
        savings?.let {
            Text(
                stringResource(R.string.feed_savings, it),
                fontSize = 12.5.sp, fontWeight = FontWeight.Bold, color = Color(0xFF2FA24C),
            )
        }
    }
}

@Composable
private fun CaptionChip(fill: Color, ink: Color, text: String, dot: Color? = null) {
    Row(
        Modifier.clip(CircleShape).background(fill).padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (dot != null) {
            Box(Modifier.size(5.dp).clip(CircleShape).background(dot))
            Spacer(Modifier.width(5.dp))
        }
        Text(text, fontSize = 11.5.sp, fontWeight = FontWeight.Bold, color = ink)
    }
}

@Composable
private fun CaptionChipRow(venue: Venue?, distanceKm: Double?) {
    val c = AyantTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        if (venue?.isOpenNow == true) {
            CaptionChip(Color(0xFF2FA24C).copy(alpha = 0.12f), Color(0xFF1F7D3A),
                stringResource(R.string.status_open), dot = Color(0xFF2FA24C))
        }
        distanceKm?.let { CaptionChip(Color(0xFFF1EEE8), c.inkSoft, it.distanceText()) }
        venue?.earnRateLabel()?.let { CaptionChip(Color(0xFFFFF3EC), c.accentText, it) }
    }
}

/**
 * «12 отзывов · 2 часа назад». Обе половины — реальные данные: счётчик отзывов
 * заведения и дата старта акции. Нет ни того, ни другого — строки нет.
 */
@Composable
private fun postMeta(reviewCount: Int?, startDate: java.util.Date?): String? {
    val parts = buildList {
        if (reviewCount != null && reviewCount > 0) {
            add(stringResource(R.string.venue_reviews_count, reviewCount))
        }
        if (startDate != null) {
            add(
                DateUtils.getRelativeTimeSpanString(
                    startDate.time, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS,
                ).toString()
            )
        }
    }
    return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ")
}

/**
 * Заведение, вклеенное в ленту как реклама. Тот же пост, но помечен «РЕКЛАМА» —
 * иначе реклама неотличима от органики. Сердечка нет: лайкают предложение, а не
 * объявление.
 */
@Composable
fun FeedAdVenueCard(
    venue: Venue,
    distanceKm: Double?,
    isSaved: Boolean,
    onOpen: () -> Unit,
    onSave: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    FeedPostFrame(modifier) {
        FeedPostHeader(
            name = venue.name,
            verified = venue.isVerified,
            subtitle = postSubtitle(venue.district, distanceKm),
            gradient = venue.gradientColors,
            imageURL = venue.imageURL,
            onOpen = onOpen,
        )
        FeedPostPhoto(venue.imageURL, venue.gradientColors, onOpen) {
            Text(
                stringResource(R.string.feed_ad_label),
                fontSize = 10.5.sp, fontWeight = FontWeight.Black, letterSpacing = 1.1.sp,
                color = Color.White,
                modifier = Modifier
                    .clip(CircleShape)
                    .background(Color.Black.copy(alpha = 0.32f))
                    .padding(horizontal = 11.dp, vertical = 6.dp),
            )
        }
        Row(
            Modifier.fillMaxWidth().padding(top = 4.dp, start = 8.dp, end = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Spacer(Modifier.weight(1f))
            FeedActionButton(
                icon = if (isSaved) Icons.Filled.Bookmark else Icons.Outlined.BookmarkBorder,
                contentDescription = stringResource(
                    if (isSaved) R.string.action_unsave else R.string.action_save),
                size = 22.dp,
                tint = if (isSaved) c.accentText else c.ink,
                isOn = isSaved,
                onClick = onSave,
            )
        }
        Column(Modifier.padding(top = 2.dp, start = 15.dp, end = 15.dp, bottom = 17.dp)) {
            Text(
                venue.name,
                fontSize = 19.sp, fontWeight = FontWeight.Black,
                letterSpacing = (-0.7).sp, lineHeight = 23.sp, color = c.ink,
            )
            venue.todaySpecialText?.takeIf { it.isNotEmpty() }?.let {
                Text(
                    it, fontSize = 14.sp, lineHeight = 21.sp, color = Color(0xFF3D362F),
                    maxLines = 2, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
            Spacer(Modifier.height(12.dp))
            CaptionChipRow(venue, distanceKm)
        }
    }
}

/**
 * Скелетон загрузки. Не спиннер: он ничего не сообщает о том, что грузится.
 * Блоки повторяют РЕАЛЬНЫЕ пропорции поста — строка шапки, кадр 4:5, полосы
 * подписи, — поэтому появление контента не двигает вёрстку.
 */
@Composable
fun FeedSkeleton() {
    val reduceMotion = rememberReduceMotion()
    val transition = rememberInfiniteTransition(label = "skeleton")
    val phase by transition.animateFloat(
        initialValue = 0.45f, targetValue = 0.9f,
        animationSpec = infiniteRepeatable(
            animation = tween(AyantTiming.SKELETON_PULSE_MS, easing = AyantMotion.EnterEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "skeletonPhase",
    )
    val phase2 by transition.animateFloat(
        initialValue = 0.9f, targetValue = 0.45f,
        animationSpec = infiniteRepeatable(
            animation = tween(AyantTiming.SKELETON_PULSE_MS, easing = AyantMotion.EnterEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "skeletonPhase2",
    )
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        listOf(phase, phase2).forEach { alpha ->
            val a = if (reduceMotion) 0.7f else alpha
            FeedPostFrame {
                Row(
                    Modifier.fillMaxWidth()
                        .padding(top = 11.dp, start = 14.dp, end = 14.dp, bottom = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Bone(38.dp, 38.dp, 19.dp, a)
                    Column(Modifier.padding(start = 10.dp)) {
                        Bone(120.dp, 11.dp, alpha = a)
                        Spacer(Modifier.height(5.dp))
                        Bone(78.dp, 9.dp, alpha = a)
                    }
                }
                Box(
                    Modifier.fillMaxWidth().aspectRatio(4f / 5f)
                        .background(Color(0xFFE9E3DA).copy(alpha = a))
                )
                Column(Modifier.padding(top = 14.dp, start = 15.dp, end = 15.dp, bottom = 18.dp)) {
                    Bone(140.dp, 22.dp, alpha = a)
                    Spacer(Modifier.height(9.dp))
                    Bone(220.dp, 14.dp, alpha = a)
                    Spacer(Modifier.height(9.dp))
                    Bone(180.dp, 12.dp, alpha = a)
                }
            }
        }
    }
}

@Composable
private fun Bone(width: Dp, height: Dp, radius: Dp = 5.dp, alpha: Float) {
    Box(
        Modifier.size(width, height).clip(RoundedCornerShape(radius))
            .background(Color(0xFFE9E3DA).copy(alpha = alpha))
    )
}

// MARK: - Small derived values

/** Badge text when there is no percentage discount. Mirrors `DealType.badgeLabel`. */
fun DealType.badgeLabel(): String = when (this) {
    DealType.DISCOUNT -> "СКИДКА"
    DealType.PROMO -> "ПРОМО"
    DealType.NOVELTY -> "НОВОЕ"
    DealType.ANNOUNCEMENT -> "АНОНС"
}

/**
 * «How much you'll earn» chip: reads the points config, computes nothing.
 * Award arithmetic lives only in `PointsMath`.
 */
fun Venue.earnRateLabel(): String? {
    if (!pointsEnabled) return null
    return when (pointsMode) {
        "cashback" -> if (cashbackPercent > 0) "+${cashbackPercent.percentText()}% САН" else null
        "bands" -> "Баллы САН"
        else -> if (pointsFlat > 0) "+$pointsFlat баллов" else null
    }
}

private fun Double.percentText(): String =
    if (this == this.roundToInt().toDouble()) this.roundToInt().toString()
    else String.format("%.1f", this).replace('.', ',')
