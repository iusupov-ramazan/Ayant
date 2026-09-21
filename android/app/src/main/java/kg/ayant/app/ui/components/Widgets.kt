package kg.ayant.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.core.localizedName
import kg.ayant.app.domain.model.VenueCategory
import kg.ayant.app.ui.theme.AyantMetrics
import kg.ayant.app.ui.theme.AyantShadow
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantPressScale
import kg.ayant.app.ui.theme.ayantShadow

// MARK: - Прибитая панель навигации. Зеркалит `SanNavBar` / `.sanNavBar()`.

/**
 * Квадратная кнопка 44dp на подложке `surface` с мягкой тенью — «назад» и
 * действия в шапке пушнутых экранов. Зеркалит `SanCircleButton`.
 */
@Composable
fun AyantCircleButton(
    icon: ImageVector,
    contentDescription: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    filled: Boolean = false,
) {
    val c = AyantTheme.colors
    val shape = RoundedCornerShape(14.dp)
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier
            .size(AyantMetrics.minHitTarget)
            .ayantShadow(AyantShadow.Card, shape)
            .clip(shape)
            .then(if (filled) Modifier.background(c.accentGradient) else Modifier.background(c.surface))
            .clickable(interaction, null, role = Role.Button, onClick = onClick)
            .ayantPressScale(interaction, 0.90f),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription, tint = if (filled) Color.White else c.ink, modifier = Modifier.size(17.dp))
    }
}

/**
 * Панель навигации, которая ВСЕГДА видна: «назад» слева, заголовок по центру,
 * произвольное действие справа. Без правого действия ширина кнопки всё равно
 * резервируется, иначе заголовок уезжает от центра.
 */
@Composable
fun AyantNavBar(
    onBack: () -> Unit,
    title: String? = null,
    modifier: Modifier = Modifier,
    trailing: @Composable () -> Unit = {},
) {
    val c = AyantTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .background(c.canvas)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        AyantCircleButton(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.action_back), onBack)
        Spacer(Modifier.weight(1f))
        if (title != null) {
            Text(
                title, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = c.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
        }
        Spacer(Modifier.weight(1f))
        Box(Modifier.widthIn(min = AyantMetrics.minHitTarget), contentAlignment = Alignment.CenterEnd) { trailing() }
    }
}

// MARK: - Чипы категорий (главная, «Заведения»). Зеркалят `chip(_:isOn:)`.

@Composable
fun AyantCategoryChip(label: String, isOn: Boolean, onClick: () -> Unit) {
    val c = AyantTheme.colors
    val interaction = remember { MutableInteractionSource() }
    Box(
        Modifier
            .clip(CircleShape)
            .then(
                if (isOn) Modifier.background(c.accentGradient)
                else Modifier.background(c.surface)
            )
            .selectable(
                selected = isOn,
                interactionSource = interaction,
                indication = null,
                role = Role.Tab,
                onClick = onClick,
            )
            .ayantPressScale(interaction, scale = 0.93f)
            .padding(horizontal = 16.dp, vertical = 10.dp),
    ) {
        Text(
            label,
            fontSize = 13.5.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.2).sp,
            color = if (isOn) Color.White else c.inkSoft, maxLines = 1,
        )
    }
}

/** Ряд «Всё · категории…»; повторный тап по выбранной снимает фильтр. */
@Composable
fun AyantCategoryRail(
    selected: VenueCategory?,
    onSelect: (VenueCategory?) -> Unit,
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(horizontal = AyantMetrics.screenPadding, vertical = 2.dp),
) {
    LazyRow(
        modifier = modifier,
        contentPadding = contentPadding,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item {
            AyantCategoryChip(stringResource(R.string.category_all), selected == null) { onSelect(null) }
        }
        items(VenueCategory.all) { cat ->
            AyantCategoryChip(cat.localizedName(), selected == cat) {
                onSelect(if (selected == cat) null else cat)
            }
        }
    }
}

// MARK: - Пустое состояние. Зеркалит `ContentUnavailableView` + `.bordered`-кнопку.

@Composable
fun AyantUnavailableView(
    icon: ImageVector,
    title: String,
    body: String?,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) {
    val c = AyantTheme.colors
    Column(
        modifier.fillMaxWidth().padding(top = 40.dp, start = 32.dp, end = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, null, tint = c.inkSoft, modifier = Modifier.size(48.dp))
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(title, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink, textAlign = TextAlign.Center)
            if (body != null) {
                Text(body, fontSize = 14.sp, color = c.inkSoft, textAlign = TextAlign.Center, lineHeight = 20.sp)
            }
        }
        if (actionLabel != null && onAction != null) {
            OutlinedButton(
                onClick = onAction,
                shape = RoundedCornerShape(10.dp),
                colors = ButtonDefaults.outlinedButtonColors(
                    containerColor = c.accent.copy(alpha = 0.12f),
                    contentColor = c.accentText,
                ),
                border = null,
            ) {
                Text(actionLabel, fontWeight = FontWeight.SemiBold)
            }
        }
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
