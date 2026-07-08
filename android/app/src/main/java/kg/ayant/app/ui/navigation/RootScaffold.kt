package kg.ayant.app.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
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
import kg.ayant.app.location.LocationManager
import kg.ayant.app.ui.bonus.BonusScreen
import kg.ayant.app.ui.detail.DealDetailScreen
import kg.ayant.app.ui.detail.VenueDetailScreen
import kg.ayant.app.ui.home.HomeScreen
import kg.ayant.app.ui.profile.ProfileScreen
import kg.ayant.app.ui.saved.SavedScreen
import kg.ayant.app.ui.search.SearchScreen
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.ui.vm.SessionViewModel

private data class Tab(val route: String, val label: String, val icon: ImageVector)

private val tabs = listOf(
    Tab("home", "Главная", Icons.Filled.Home),
    Tab("search", "Поиск", Icons.Filled.Search),
    Tab("bonus", "Бонусы", Icons.Filled.CardGiftcard),
    Tab("saved", "Сохранённое", Icons.Filled.Bookmark),
    Tab("profile", "Профиль", Icons.Filled.Person),
)

@Composable
fun RootScaffold(session: SessionViewModel) {
    val app: AppViewModel = viewModel()
    val location: LocationManager = viewModel()
    val nav = rememberNavController()

    LaunchedEffect(session.user?.id) {
        app.setCurrentUser(session.user?.id, session.user?.name, session.isGuest)
        app.load()
        location.refresh()
    }

    val backStack by nav.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route
    val showBar = currentRoute in tabs.map { it.route }

    Scaffold(
        containerColor = AyantTheme.colors.canvas,
        bottomBar = {
            if (showBar) {
                NavigationBar(containerColor = AyantTheme.colors.surface) {
                    tabs.forEach { tab ->
                        NavigationBarItem(
                            selected = currentRoute == tab.route,
                            onClick = {
                                nav.navigate(tab.route) {
                                    popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = { Icon(tab.icon, contentDescription = tab.label) },
                            label = { Text(tab.label, maxLines = 1) },
                        )
                    }
                }
            }
        },
    ) { padding ->
        NavHost(
            navController = nav,
            startDestination = "home",
            modifier = Modifier.padding(padding),
        ) {
            composable("home") {
                HomeScreen(app, location, onVenue = { nav.navigate("venue/$it") }, onDeal = { nav.navigate("deal/$it") })
            }
            composable("search") {
                SearchScreen(app, location, onVenue = { nav.navigate("venue/$it") })
            }
            composable("bonus") { BonusScreen() }
            composable("saved") {
                SavedScreen(app, location, onVenue = { nav.navigate("venue/$it") }, onDeal = { nav.navigate("deal/$it") })
            }
            composable("profile") { ProfileScreen(app, session) }
            composable("venue/{id}") { entry ->
                val id = entry.arguments?.getString("id") ?: return@composable
                VenueDetailScreen(id, app, session, location, onBack = { nav.popBackStack() }, onDeal = { nav.navigate("deal/$it") })
            }
            composable("deal/{id}") { entry ->
                val id = entry.arguments?.getString("id") ?: return@composable
                DealDetailScreen(id, app, session, onBack = { nav.popBackStack() }, onVenue = { nav.navigate("venue/$it") })
            }
        }
    }
}
