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
import kg.ayant.app.ui.vm.HostViewModel
import kg.ayant.app.ui.vm.SessionViewModel

private data class HTab(val route: String, val labelRes: Int, val icon: ImageVector)

private val hostTabs = listOf(
    HTab("h_venues", kg.ayant.app.R.string.htab_venues, Icons.Filled.Storefront),
    HTab("h_promote", kg.ayant.app.R.string.htab_promote, Icons.Filled.Campaign),
    HTab("h_analytics", kg.ayant.app.R.string.htab_analytics, Icons.Filled.BarChart),
    HTab("h_reviews", kg.ayant.app.R.string.htab_reviews, Icons.Filled.RateReview),
    HTab("h_profile", kg.ayant.app.R.string.htab_profile, Icons.Filled.Person),
)

@Composable
fun HostRoot(app: AppViewModel, session: SessionViewModel, onExit: () -> Unit) {
    val host: HostViewModel = viewModel()
    LaunchedEffect(session.user?.id) {
        host.bind(app)
        host.configure(session.user?.id)
    }

    if (!host.hasAccount) {
        HostOnboarding(host, onCancel = onExit)
        return
    }

    val nav = rememberNavController()
    val backStack by nav.currentBackStackEntryAsState()
    val route = backStack?.destination?.route
    val showBar = route in hostTabs.map { it.route }
    val pendingReviews = app.reviews(forVenueIDs = host.ownedVenueIDs).count { it.hostReply == null }

    Scaffold(
        containerColor = AyantTheme.colors.canvas,
        bottomBar = {
            if (showBar) {
                NavigationBar(containerColor = AyantTheme.colors.surface) {
                    hostTabs.forEach { tab ->
                        val label = androidx.compose.ui.res.stringResource(tab.labelRes)
                        NavigationBarItem(
                            selected = route == tab.route,
                            onClick = {
                                nav.navigate(tab.route) {
                                    popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                                    launchSingleTop = true; restoreState = true
                                }
                            },
                            icon = {
                                if (tab.route == "h_reviews" && pendingReviews > 0) {
                                    androidx.compose.material3.BadgedBox(badge = { androidx.compose.material3.Badge { Text("$pendingReviews") } }) {
                                        Icon(tab.icon, label)
                                    }
                                } else {
                                    Icon(tab.icon, label)
                                }
                            },
                            label = { Text(label, maxLines = 1) },
                        )
                    }
                }
            }
        },
    ) { padding ->
        NavHost(nav, startDestination = "h_venues", modifier = Modifier.padding(padding)) {
            composable("h_venues") {
                HostVenuesScreen(host, app, onVenue = { nav.navigate("h_venue/$it") }, onExitHost = onExit)
            }
            composable("h_promote") { HostPromoteScreen(host) }
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
