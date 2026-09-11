package kg.ayant.app.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
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
import kg.ayant.app.ui.bonus.MyQrScreen
import kg.ayant.app.ui.bonus.VenueLoyaltyScreen
import kg.ayant.app.ui.bonus.VenuePointsScreen
import kg.ayant.app.ui.bonus.VenuePointsVenueScreen
import kg.ayant.app.ui.detail.DealDetailScreen
import kg.ayant.app.ui.detail.VenueDetailScreen
import kg.ayant.app.ui.games.SnakeGame
import kg.ayant.app.ui.home.HomeScreen
import kg.ayant.app.ui.profile.ProfileScreen
import kg.ayant.app.ui.saved.SavedScreen
import kg.ayant.app.ui.search.SearchScreen
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.ui.vm.SessionViewModel

// Вкладки живут в `GuestTab` (GuestTabBar.kt): Главная · Поиск · [QR] · Кошелёк ·
// Профиль. «Сохранённое» перестало быть вкладкой — маршрут `saved` остался и
// открывается из профиля (и из закладки в шапке ленты).
private val tabRoutes = GuestTab.entries.map { it.route }

@Composable
fun RootScaffold(session: SessionViewModel, initialDeepLink: String? = null, theme: kg.ayant.app.ui.vm.ThemeViewModel? = null) {
    val app: AppViewModel = viewModel(factory = kg.ayant.app.core.ayantFactory())
    val location: LocationManager = viewModel(factory = kg.ayant.app.core.ayantFactory())
    val coupons: kg.ayant.app.ui.vm.CouponViewModel = viewModel(factory = kg.ayant.app.core.ayantFactory())
    val loyalty: kg.ayant.app.ui.vm.LoyaltyViewModel = viewModel(factory = kg.ayant.app.core.ayantFactory())
    val points: kg.ayant.app.ui.vm.PointsViewModel = viewModel(factory = kg.ayant.app.core.ayantFactory())
    val feed: kg.ayant.app.ui.vm.FeedViewModel = viewModel(factory = kg.ayant.app.core.ayantFactory())
    val profile: kg.ayant.app.ui.vm.ProfileViewModel = viewModel(factory = kg.ayant.app.core.ayantFactory())
    val bonus: kg.ayant.app.ui.vm.BonusViewModel = viewModel(factory = kg.ayant.app.core.ayantFactory())
    val context = androidx.compose.ui.platform.LocalContext.current
    val nav = rememberNavController()
    // Все общие ViewModel создаются ЗДЕСЬ (владелец — Activity) и передаются
    // экранам параметрами. Внутри composable(...) владельцем стал бы
    // NavBackStackEntry, и каждый маршрут получил бы свой экземпляр: лента без
    // каталога, купоны без синка, очки из «Змейки» мимо экрана бонусов.

    // Выход из аккаунта: отписываем устройство от push (правило `userTokens`
    // требует авторизации — успеть надо ДО закрытия сессии) и стираем всё, что
    // принадлежало вышедшему. Кошельки лежат в SharedPreferences устройства,
    // поэтому без этой чистки их видит следующий вошедший. Зеркалит
    // `signOutCleanup()` в `SANApp.swift`.
    LaunchedEffect(Unit) {
        // Кошельки лежат в SharedPreferences УСТРОЙСТВА, а не в аккаунте.
        val wipeLocalWallets = {
            points.send(kg.ayant.app.domain.PointsIntent.Stop)
            bonus.resetForNewUser()
            coupons.resetForNewUser()
            loyalty.resetForNewUser()
            profile.resetForNewUser()
        }
        session.willSignOut = {
            kg.ayant.app.push.Push.unregisterDevice(app.selectedCitySlug)
            wipeLocalWallets()
        }
        // Гость вошёл в ЧУЖОЙ (существующий) аккаунт — uid другой, кошельки
        // прошлого владельца стираем. При регистрации uid сохраняется, и хук
        // не срабатывает: данные остаются у того же человека.
        session.onUserSwitched = { wipeLocalWallets() }
    }

    LaunchedEffect(session.user?.id) {
        // Связываем владельцев ДО setCurrentUser/load: каталог и личная библиотека
        // живут в них, и загрузка без привязки ушла бы в никуда.
        app.bindProfile(profile)   // владелец сохранённого/избранного
        app.bindFeed(feed)         // владелец каталога
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
            points.send(kg.ayant.app.domain.PointsIntent.Observe(uid))   // живой поток; опрос больше не нужен
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

    val authSheet = androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(false) }
    if (authSheet.value) {
        kg.ayant.app.ui.auth.GuestAuthSheet(session) { authSheet.value = false }
    }

    val backStack by nav.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route
    val showBar = currentRoute in tabRoutes

    Scaffold(
        containerColor = AyantTheme.colors.canvas,
        bottomBar = {
            if (showBar) {
                AyantTabBar(
                    currentRoute = currentRoute,
                    onSelect = { tab ->
                        // QR и «Бонусы» гостю не работают: код привязан к
                        // аккаунту, баллы копятся на нём же. Вместо подмены
                        // содержимого заглушкой показываем вход ПОВЕРХ
                        // приложения, а вкладка не переключается — гость
                        // остаётся там, где стоял.
                        if (session.isGuest && (tab == GuestTab.Qr || tab == GuestTab.Wallet)) {
                            authSheet.value = true
                            return@AyantTabBar
                        }
                        nav.navigate(tab.route) {
                            popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                )
            }
        },
    ) { padding ->
        NavHost(
            navController = nav,
            startDestination = "home",
            modifier = Modifier.padding(padding),
        ) {
            composable("home") {
                HomeScreen(app, location, feed, session,
                    onVenue = { nav.navigate("venue/$it") },
                    onDeal = { nav.navigate("deal/$it") },
                    onSaved = { nav.navigate("saved") })
            }
            composable("search") {
                SearchScreen(app, location, onVenue = { nav.navigate("venue/$it") })
            }
            composable("bonus") {
                // Баллы и купоны копятся в аккаунте — гостю показываем замок.
                if (session.isGuest) {
                    // Сюда гость может попасть только прямой навигацией
                    // (deeplink): показываем тот же экран входа поверх.
                    kg.ayant.app.ui.auth.GuestAuthSheet(session) { nav.popBackStack() }
                    return@composable
                }
                BonusScreen(
                    app = app,
                    bonus = bonus,
                    coupons = coupons,
                    onCoupons = { nav.navigate("coupons") },
                    onLoyalty = { nav.navigate("loyalty") },
                    onPoints = { nav.navigate("points") },
                    onSnake = { nav.navigate("snake") },
                    onTetris = { nav.navigate("tetris") },
                    points = points,
                    loyalty = loyalty,
                )
            }
            composable("saved") {
                SavedScreen(app, location, onVenue = { nav.navigate("venue/$it") }, onDeal = { nav.navigate("deal/$it") })
            }
            composable("myqr") {
                // Личный QR привязан к аккаунту: гостю начислять некуда.
                if (session.isGuest) {
                    // Сюда гость может попасть только прямой навигацией
                    // (deeplink): показываем тот же экран входа поверх.
                    kg.ayant.app.ui.auth.GuestAuthSheet(session) { nav.popBackStack() }
                    return@composable
                }
                // Вкладка, а не пуш: возвращаться некуда, кнопки «назад» нет.
                MyQrScreen(app, points, location,
                    onBack = null,
                    onScanVenue = { nav.navigate("host") })
            }
            composable("profile") {
                ProfileScreen(
                    app, session, coupons = coupons, theme = theme,
                    onCoupons = { nav.navigate("coupons") }, onHost = { nav.navigate("host") },
                    onHelp = { nav.navigate(it) }, onSaved = { nav.navigate("saved") },
                )
            }
            composable("about") { kg.ayant.app.ui.help.AboutScreen(onBack = { nav.popBackStack() }) }
            composable("faq") { kg.ayant.app.ui.help.FaqScreen(onBack = { nav.popBackStack() }) }
            composable("support") { kg.ayant.app.ui.help.SupportScreen(onBack = { nav.popBackStack() }) }
            composable("venue/{id}") { entry ->
                val id = entry.arguments?.getString("id") ?: return@composable
                VenueDetailScreen(id, app, session, location, points,
                    onBack = { nav.popBackStack() }, onDeal = { nav.navigate("deal/$it") },
                    onLoyalty = { nav.navigate("venueLoyalty/$it") },
                    onPoints = { nav.navigate("venuePoints/$it") })
            }
            composable("deal/{id}") { entry ->
                val id = entry.arguments?.getString("id") ?: return@composable
                DealDetailScreen(id, app, session, coupons, onBack = { nav.popBackStack() }, onVenue = { nav.navigate("venue/$it") },
                    onCoupon = { nav.navigate("couponDetail/$it") })
            }
            composable("coupons") { MyCouponsScreen(coupons, onBack = { nav.popBackStack() }, onCoupon = { nav.navigate("couponDetail/$it") }) }
            composable("couponDetail/{id}") { entry ->
                CouponDetailScreen(entry.arguments?.getString("id") ?: return@composable, coupons, onBack = { nav.popBackStack() })
            }
            composable("loyalty") { LoyaltyScreen(loyalty, onBack = { nav.popBackStack() }) }
            composable("venueLoyalty/{id}") { entry ->
                VenueLoyaltyScreen(entry.arguments?.getString("id") ?: return@composable, app, loyalty, onBack = { nav.popBackStack() })
            }
            composable("points") { VenuePointsScreen(points, onBack = { nav.popBackStack() }) }
            composable("venuePoints/{id}") { entry ->
                VenuePointsVenueScreen(entry.arguments?.getString("id") ?: return@composable, app, points, onBack = { nav.popBackStack() })
            }
            // Игры начисляют бонусы в кошелёк аккаунта — гостю закрыты.
            composable("snake") {
                if (session.isGuest) {
                    // Сюда гость может попасть только прямой навигацией
                    // (deeplink): показываем тот же экран входа поверх.
                    kg.ayant.app.ui.auth.GuestAuthSheet(session) { nav.popBackStack() }
                    return@composable
                }
                SnakeGame(bonus, onClose = { nav.popBackStack() })
            }
            composable("tetris") {
                if (session.isGuest) {
                    // Сюда гость может попасть только прямой навигацией
                    // (deeplink): показываем тот же экран входа поверх.
                    kg.ayant.app.ui.auth.GuestAuthSheet(session) { nav.popBackStack() }
                    return@composable
                }
                kg.ayant.app.ui.games.TetrisGame(bonus, onClose = { nav.popBackStack() })
            }
            composable("host") { kg.ayant.app.ui.host.HostRoot(app, session, onExit = { nav.popBackStack() }) }
        }
    }
}
