package kg.ayant.app.ui.host

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.RateReview
import androidx.compose.material.icons.filled.Storefront
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.domain.HostIntent
import kg.ayant.app.ui.vm.HostViewModel
import kg.ayant.app.ui.vm.SessionViewModel

// Вкладки живут в `HostTab` (HostShell.kt): Заведения · Лояльность · [Сканер] ·
// Аналитика · Отзывы. «Продвижение» отдало слот и открывается из быстрых
// действий на «Заведениях»; «Профиль» — с аватара в шапке.
private val hostTabRoutes = HostTab.entries.map { it.route }

@Composable
fun HostRoot(app: AppViewModel, session: SessionViewModel, onExit: () -> Unit) {
    val host: HostViewModel = viewModel(factory = kg.ayant.app.core.ayantFactory())
    val hostState by host.state.collectAsState()
    // Отзывы принадлежат ленте — подписываемся, иначе счётчик неотвеченных застынет.
    val feedState by app.feedState.collectAsState()
    LaunchedEffect(session.user?.id) {
        host.bind(app)
        host.send(HostIntent.Configure(session.user?.id))
    }

    if (!hostState.hasAccount) {
        HostOnboarding(host, onCancel = onExit)
        return
    }

    val nav = rememberNavController()
    val backStack by nav.currentBackStackEntryAsState()
    val route = backStack?.destination?.route
    val showBar = route in hostTabRoutes
    val pendingReviews = feedState.reviews(forVenueIDs = hostState.ownedVenueIDs).count { it.hostReply == null }

    // Отзывы по заведениям владельца грузятся здесь — и бейдж, и инбокс читают
    // один кэш. Ключ перезапускает загрузку, когда список заведений приедет
    // (при первом рендере он ещё пуст).
    androidx.compose.runtime.LaunchedEffect(hostState.ownedVenueIDs) {
        app.loadReviews(forVenueIDs = hostState.ownedVenueIDs)
    }

    Scaffold(
        containerColor = AyantTheme.colors.canvas,
        bottomBar = {
            if (showBar) {
                HostTabBar(
                    currentRoute = route,
                    pendingReviews = pendingReviews,
                    onSelect = { tab ->
                        nav.navigate(tab.route) {
                            popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                            launchSingleTop = true; restoreState = true
                        }
                    },
                )
            }
        },
    ) { padding ->
        NavHost(nav, startDestination = "h_venues", modifier = Modifier.padding(padding)) {
            composable("h_venues") {
                // «Лояльность» и «Продвижение» больше не колбэки этого экрана:
                // первая — соседняя вкладка, второе живёт в действиях заведения.
                HostVenuesScreen(host, app,
                    onVenue = { nav.navigate("h_venue/$it") },
                    onExitHost = onExit,
                    onProfile = { nav.navigate("h_profile") })
            }
            composable("h_loyalty") { HostLoyaltyScreen(host) }
            composable("h_promote") { HostPromoteScreen(host) }
            // Сканер — вкладка, а не пуш: возвращаться некуда.
            composable("h_scan") { HostScannerScreen(host, onBack = null) }
            composable("h_analytics") { HostAnalyticsScreen(host) }
            composable("h_reviews") { HostReviewsScreen(host, app) }
            composable("h_profile") { HostProfileScreen(host, session, onExitHost = onExit) }
            composable("h_venue/{id}") { entry ->
                HostVenueDetailScreen(
                    entry.arguments?.getString("id") ?: return@composable, host,
                    onBack = { nav.popBackStack() },
                    onPromote = { nav.navigate("h_promote") },
                )
            }
        }
    }
}
