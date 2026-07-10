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
import kg.ayant.app.ui.bonus.CouponDetailScreen
import kg.ayant.app.ui.bonus.LoyaltyScreen
import kg.ayant.app.ui.bonus.MyCouponsScreen
import kg.ayant.app.ui.bonus.VenueLoyaltyScreen
import kg.ayant.app.ui.detail.DealDetailScreen
import kg.ayant.app.ui.detail.VenueDetailScreen
import kg.ayant.app.ui.games.SnakeGame
import kg.ayant.app.ui.games.TetrisGame
import kg.ayant.app.ui.home.HomeScreen
import kg.ayant.app.ui.profile.ProfileScreen
import kg.ayant.app.ui.saved.SavedScreen
import kg.ayant.app.ui.search.SearchScreen
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.ui.vm.SessionViewModel

private data class Tab(val route: String, val labelRes: Int, val icon: ImageVector)

private val tabs = listOf(
    Tab("home", kg.ayant.app.R.string.tab_home, Icons.Filled.Home),
    Tab("search", kg.ayant.app.R.string.tab_search, Icons.Filled.Search),
    Tab("bonus", kg.ayant.app.R.string.tab_bonus, Icons.Filled.CardGiftcard),
    Tab("saved", kg.ayant.app.R.string.tab_saved, Icons.Filled.Bookmark),
    Tab("profile", kg.ayant.app.R.string.tab_profile, Icons.Filled.Person),
)

@Composable
fun RootScaffold(session: SessionViewModel, initialDeepLink: String? = null, theme: kg.ayant.app.ui.vm.ThemeViewModel? = null) {
    val app: AppViewModel = viewModel()
    val location: LocationManager = viewModel()
    val coupons: kg.ayant.app.ui.vm.CouponViewModel = viewModel()
    val loyalty: kg.ayant.app.ui.vm.LoyaltyViewModel = viewModel()
    val bonus: kg.ayant.app.ui.vm.BonusViewModel = viewModel()
    val context = androidx.compose.ui.platform.LocalContext.current
    val nav = rememberNavController()

    LaunchedEffect(session.user?.id) {
        app.setCurrentUser(session.user?.id, session.user?.name, session.isGuest)
        app.load()
        location.refresh()
        // Push: subscribe to city broadcasts + register this device's token.
        kg.ayant.app.push.Push.subscribeDefaults(app.selectedCitySlug)
        if (!session.isGuest) kg.ayant.app.push.Push.registerToken(session.user?.id, app.selectedCitySlug)
        // Backend sync + referral/gift claims.
        val uid = session.user?.id
        if (uid != null && !session.isGuest) {
            coupons.sync(uid)
            loyalty.sync(uid)
            val prefs = context.getSharedPreferences("ayant.deeplink", 0)
            // Pending referral (from an invite link) → welcome bonus for the invitee.
            val ref = prefs.getString("pendingReferrer", null)
            if (!ref.isNullOrEmpty() && !prefs.getBoolean("referralCredited", false) && ref != uid) {
                prefs.edit().putBoolean("referralCredited", true).remove("pendingReferrer").apply()
                bonus.addFromServer(100)
                app.recordReferral(ref)
            }
            // Server-granted bonuses (rewards for people you invited).
            val granted = app.claimBonusGrantsTotal()
            if (granted > 0) bonus.addFromServer(granted)
            // Pending gift (from a gift link) → coupon in wallet.
            val giftCode = prefs.getString("pendingGift", null)
            if (!giftCode.isNullOrEmpty()) {
                prefs.edit().remove("pendingGift").apply()
                app.claimGift(giftCode)?.let { coupons.addGifted(it.title, it.code) }
            }
        }
    }

    // Follow an incoming deep link once data is loaded.
    LaunchedEffect(initialDeepLink, app.venues.size) {
        if (initialDeepLink != null && app.venues.isNotEmpty()) nav.navigate(initialDeepLink)
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
                        val label = androidx.compose.ui.res.stringResource(tab.labelRes)
                        NavigationBarItem(
                            selected = currentRoute == tab.route,
                            onClick = {
                                nav.navigate(tab.route) {
                                    popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = { Icon(tab.icon, contentDescription = label) },
                            label = { Text(label, maxLines = 1) },
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
            composable("bonus") {
                BonusScreen(
                    app = app,
                    onCoupons = { nav.navigate("coupons") },
                    onLoyalty = { nav.navigate("loyalty") },
                    onSnake = { nav.navigate("snake") },
                    onTetris = { nav.navigate("tetris") },
                )
            }
            composable("saved") {
                SavedScreen(app, location, onVenue = { nav.navigate("venue/$it") }, onDeal = { nav.navigate("deal/$it") })
            }
            composable("profile") {
                ProfileScreen(
                    app, session, theme = theme,
                    onCoupons = { nav.navigate("coupons") }, onHost = { nav.navigate("host") },
                    onHelp = { nav.navigate(it) },
                )
            }
            composable("about") { kg.ayant.app.ui.help.AboutScreen(onBack = { nav.popBackStack() }) }
            composable("faq") { kg.ayant.app.ui.help.FaqScreen(onBack = { nav.popBackStack() }) }
            composable("support") { kg.ayant.app.ui.help.SupportScreen(onBack = { nav.popBackStack() }) }
            composable("venue/{id}") { entry ->
                val id = entry.arguments?.getString("id") ?: return@composable
                VenueDetailScreen(id, app, session, location,
                    onBack = { nav.popBackStack() }, onDeal = { nav.navigate("deal/$it") },
                    onLoyalty = { nav.navigate("venueLoyalty/$it") })
            }
            composable("deal/{id}") { entry ->
                val id = entry.arguments?.getString("id") ?: return@composable
                DealDetailScreen(id, app, session, onBack = { nav.popBackStack() }, onVenue = { nav.navigate("venue/$it") },
                    onCoupon = { nav.navigate("couponDetail/$it") })
            }
            composable("coupons") { MyCouponsScreen(onBack = { nav.popBackStack() }, onCoupon = { nav.navigate("couponDetail/$it") }) }
            composable("couponDetail/{id}") { entry ->
                CouponDetailScreen(entry.arguments?.getString("id") ?: return@composable, onBack = { nav.popBackStack() })
            }
            composable("loyalty") { LoyaltyScreen(onBack = { nav.popBackStack() }) }
            composable("venueLoyalty/{id}") { entry ->
                VenueLoyaltyScreen(entry.arguments?.getString("id") ?: return@composable, app, onBack = { nav.popBackStack() })
            }
            composable("snake") { SnakeGame(onClose = { nav.popBackStack() }) }
            composable("tetris") { TetrisGame(onClose = { nav.popBackStack() }) }
            composable("host") { kg.ayant.app.ui.host.HostRoot(app, session, onExit = { nav.popBackStack() }) }
        }
    }
}
