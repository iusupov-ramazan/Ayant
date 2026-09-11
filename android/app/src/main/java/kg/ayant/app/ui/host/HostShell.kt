package kg.ayant.app.ui.host

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CenterFocusWeak
import androidx.compose.material.icons.filled.RateReview
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Storefront
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.ui.theme.AyantMetrics
import kg.ayant.app.ui.theme.AyantMotion
import kg.ayant.app.ui.theme.AyantRadius
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.AyantTiming
import kg.ayant.app.ui.theme.ayantPressScale
import kg.ayant.app.ui.theme.ayantSandPanel
import kg.ayant.app.ui.theme.rememberReduceMotion
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Badge

/**
 * Host shell after the redesign. Mirrors `HostShell.swift`.
 *
 * The host's identity is warm sand riso panels and a cream tab bar — no dark
 * chrome anywhere; the only dark element in the whole host app is the scanner's
 * camera window.
 *
 * Tabs: Заведения · Лояльность · [Scanner FAB] · Аналитика · Отзывы.
 * «Продвижение» gave up its slot to «Лояльность» and lives in the quick actions
 * on Заведения; «Профиль» moved to the avatar in the header.
 */

enum class HostTab(val route: String, val labelRes: Int, val icon: ImageVector) {
    Venues("h_venues", R.string.htab_venues, Icons.Filled.Storefront),
    Loyalty("h_loyalty", R.string.htab_loyalty, Icons.Filled.Star),
    Scanner("h_scan", R.string.htab_scanner, Icons.Filled.QrCodeScanner),
    Analytics("h_analytics", R.string.htab_analytics, Icons.Filled.BarChart),
    Reviews("h_reviews", R.string.htab_reviews, Icons.Filled.RateReview),
}

@Composable
fun HostTabBar(
    currentRoute: String?,
    pendingReviews: Int,
    onSelect: (HostTab) -> Unit,
) {
    val c = AyantTheme.colors
    NavigationBar(containerColor = c.cream) {
        HostTab.entries.forEach { tab ->
            val label = stringResource(tab.labelRes)
            NavigationBarItem(
                selected = currentRoute == tab.route,
                onClick = { onSelect(tab) },
                icon = {
                    if (tab == HostTab.Reviews && pendingReviews > 0) {
                        BadgedBox(badge = { Badge { Text("$pendingReviews") } }) {
                            Icon(tab.icon, contentDescription = label)
                        }
                    } else {
                        Icon(tab.icon, contentDescription = label)
                    }
                },
                label = {
                    Text(
                        label,
                        fontSize = AyantMetrics.tabLabelSize,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = (-0.1).sp,
                        maxLines = 1,
                    )
                },
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = c.accentText,
                    selectedTextColor = c.accentText,
                    unselectedIconColor = c.tabIdle,
                    unselectedTextColor = c.tabIdle,
                    indicatorColor = c.surfaceMuted,
                ),
            )
        }
    }
}


// MARK: - Sand header

/** Riso panel with rounded bottom corners — the shared host header. */
@Composable
fun HostSandHeader(
    modifier: Modifier = Modifier,
    // Плоский вариант: кремовая заливка, без riso-текстуры и скруглений снизу.
    //
    // Нужен «Заведениям»: там под шапкой идёт сетка встык, во всю ширину и без
    // скруглений. Панель с текстурой и радиусом 34 обрывалась над ней ребром —
    // экран читался как карточка, положенная на сетку, а не как одна витрина.
    // Остальные хост-экраны — списки на канвасе, им панель по-прежнему нужна.
    flat: Boolean = false,
    content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit,
) {
    Column(
        modifier
            .fillMaxWidth()
            .let {
                if (flat) it.background(AyantTheme.colors.hostHeader)
                else it.clip(RoundedCornerShape(bottomStart = AyantRadius.panel, bottomEnd = AyantRadius.panel))
                    .ayantSandPanel(radius = 0.dp)
            }
            .padding(horizontal = AyantMetrics.screenPadding)
            .padding(top = 14.dp, bottom = if (flat) 18.dp else 26.dp),
        content = content,
    )
}

/** «РЕЖИМ ЗАВЕДЕНИЯ» chip with a pulsing dot. */
@Composable
fun HostModeChip() {
    val c = AyantTheme.colors
    val reduceMotion = rememberReduceMotion()
    val pulse = androidx.compose.animation.core.rememberInfiniteTransition(label = "modeDot")
    val alpha by pulse.animateFloat(
        initialValue = 1f, targetValue = if (reduceMotion) 1f else 0.35f,
        animationSpec = infiniteRepeatable(
            animation = tween(1000, easing = AyantMotion.EnterEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "modeDotAlpha",
    )
    Row(
        Modifier
            .clip(CircleShape)
            .background(c.accent.copy(alpha = 0.15f))
            .padding(horizontal = 11.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Box(Modifier.size(6.dp).clip(CircleShape).background(Color(0xFFFF9500).copy(alpha = alpha)))
        Text(
            stringResource(R.string.host_mode_chip).uppercase(),
            fontSize = 10.5.sp, fontWeight = FontWeight.Black, letterSpacing = 1.1.sp,
            color = c.hostEyebrow,
        )
    }
}

/** «Я гость» pill — back to the guest app. */
@Composable
fun HostGuestPill(onClick: () -> Unit) {
    val c = AyantTheme.colors
    val interaction = remember { MutableInteractionSource() }
    Box(
        Modifier
            .height(36.dp)
            .clip(CircleShape)
            .background(Color.White.copy(alpha = 0.82f))
            .selectable(
                selected = false,
                interactionSource = interaction,
                indication = null,
                role = Role.Button,
                onClick = onClick,
            )
            .ayantPressScale(interaction, scale = 0.94f)
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            stringResource(R.string.host_i_am_guest),
            fontSize = 12.5.sp, fontWeight = FontWeight.Bold, color = c.sandInkStrong,
        )
    }
}
