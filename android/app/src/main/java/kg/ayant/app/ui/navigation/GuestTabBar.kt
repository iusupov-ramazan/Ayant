package kg.ayant.app.ui.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.ui.theme.AyantMetrics
import kg.ayant.app.ui.theme.AyantTheme

/**
 * Панель вкладок гостя. Зеркалит `RootView` в `GuestShell.swift`.
 *
 * Пять вкладок, «Мой QR» — по центру. Раньше по центру висел FAB с личным QR, а
 * панель была нарисована руками ради выреза под него. На iOS панель переехала на
 * системную (там она приходит со стеклом), поэтому и здесь берём штатный
 * `NavigationBar` из Material 3: FAB не нужен — QR стал обычной вкладкой на том
 * же месте и в один тап.
 */

enum class GuestTab(val route: String, val labelRes: Int, val icon: ImageVector) {
    Home("home", R.string.tab_home, Icons.Filled.Home),
    Search("search", R.string.tab_search, Icons.Filled.Search),
    Qr("myqr", R.string.title_my_qr, Icons.Filled.QrCode),
    Wallet("bonus", R.string.tab_wallet, Icons.Filled.CreditCard),
    Profile("profile", R.string.tab_profile, Icons.Filled.Person),
}

@Composable
fun AyantTabBar(
    currentRoute: String?,
    onSelect: (GuestTab) -> Unit,
) {
    val c = AyantTheme.colors
    NavigationBar(containerColor = c.canvas) {
        GuestTab.entries.forEach { tab ->
            val label = stringResource(tab.labelRes)
            NavigationBarItem(
                selected = currentRoute == tab.route,
                onClick = { onSelect(tab) },
                icon = { Icon(tab.icon, contentDescription = label) },
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
                    // Акцент как ТЕКСТ: подпись 11sp, заливочный не проходит AA.
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
