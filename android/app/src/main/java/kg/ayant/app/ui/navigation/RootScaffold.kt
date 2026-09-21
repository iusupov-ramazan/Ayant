package kg.ayant.app.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import kg.ayant.app.core.ayantFactory
import kg.ayant.app.domain.HostIntent
import kg.ayant.app.domain.PointsIntent
import kg.ayant.app.location.LocationManager
import kg.ayant.app.push.Push
import kg.ayant.app.ui.auth.GuestAuthSheet
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
import kg.ayant.app.ui.games.TetrisGame
import kg.ayant.app.ui.help.AboutScreen
import kg.ayant.app.ui.help.FaqScreen
import kg.ayant.app.ui.help.SupportScreen
import kg.ayant.app.ui.home.HomeScreen
import kg.ayant.app.ui.host.HostRoot
import kg.ayant.app.ui.profile.ProfileScreen
import kg.ayant.app.ui.saved.SavedScreen
import kg.ayant.app.ui.search.SearchScreen
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.ui.vm.BonusViewModel
import kg.ayant.app.ui.vm.CouponViewModel
import kg.ayant.app.ui.vm.FeedViewModel
import kg.ayant.app.ui.vm.HostViewModel
import kg.ayant.app.ui.vm.LoyaltyViewModel
import kg.ayant.app.ui.vm.PointsViewModel
import kg.ayant.app.ui.vm.ProfileViewModel
import kg.ayant.app.ui.vm.SessionViewModel
import kg.ayant.app.ui.vm.ThemeViewModel
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch

// Вкладки живут в `GuestTab` (GuestTabBar.kt): Главная · [Поиск] · Мой QR ·
// Бонусы · Профиль. «Поиск» скрыт флагом релиза (`ReleaseFlags.SEARCH_TAB`),
// маршрут остаётся. «Сохранённое» перестало быть вкладкой — маршрут `saved`
// остался и открывается из профиля (и из закладки в шапке ленты).
private val tabRoutes = GuestTab.entries.map { it.route }

/**
 * Оболочка гостевого приложения. Зеркалит `RootView` (`GuestShell.swift`) и
 * ту часть `SANApp.swift`, что живёт под вошедшим пользователем: привязка
 * владельцев каталога/библиотеки, синк кошельков, push-токен, реферал и
 * подарок по ссылке, жизненный цикл бонус-движка.
 *
 * [onEnterHost] — «Режим заведения» из профиля: корень (`RootGate`) подменяет
 * оболочку кабинетом хоста, как `hostMode = true` на iOS.
 */
@Composable
fun RootScaffold(
    session: SessionViewModel,
    initialDeepLink: String? = null,
    theme: ThemeViewModel? = null,
    linkEpoch: Int = 0,
    onEnterHost: () -> Unit = {},
) {
    val app: AppViewModel = viewModel(factory = ayantFactory())
    val location: LocationManager = viewModel(factory = ayantFactory())
    val coupons: CouponViewModel = viewModel(factory = ayantFactory())
    val loyalty: LoyaltyViewModel = viewModel(factory = ayantFactory())
    val points: PointsViewModel = viewModel(factory = ayantFactory())
    val feed: FeedViewModel = viewModel(factory = ayantFactory())
    val profile: ProfileViewModel = viewModel(factory = ayantFactory())
    val bonus: BonusViewModel = viewModel(factory = ayantFactory())
    val host: HostViewModel = viewModel(factory = ayantFactory())
    val context = LocalContext.current
    val nav = rememberNavController()
    // Все общие ViewModel создаются ЗДЕСЬ (владелец — Activity) и передаются
    // экранам параметрами. Внутри composable(...) владельцем стал бы
    // NavBackStackEntry, и каждый маршрут получил бы свой экземпляр: лента без
    // каталога, купоны без синка, очки из «Змейки» мимо экрана бонусов.

    /** Бонус-движок работает только у настоящего аккаунта (см. `startBonusIfAllowed`). */
    fun startBonusIfAllowed() {
        if (session.isSignedIn && !session.isGuest) bonus.start() else bonus.pause()
    }

    // Выход из аккаунта: отписываем устройство от push (правило `userTokens`
    // требует авторизации — успеть надо ДО закрытия сессии) и стираем всё, что
    // принадлежало вышедшему. Кошельки лежат в SharedPreferences устройства,
    // поэтому без этой чистки их видит следующий вошедший. Зеркалит
    // `signOutCleanup()` в `SANApp.swift`.
    LaunchedEffect(Unit) {
        // Кошельки лежат в SharedPreferences УСТРОЙСТВА, а не в аккаунте.
        val wipeLocalWallets = {
            points.send(PointsIntent.Stop)
            loyalty.stopObserving()
            bonus.resetForNewUser()
            coupons.resetForNewUser()
            loyalty.resetForNewUser()
            profile.resetForNewUser()
        }
        session.willSignOut = {
            Push.unregisterDevice(app.selectedCitySlug)
            bonus.pause()
            // Кэш заведений владельца из памяти (данные остаются в Firestore
            // под ownerID и вернутся при следующем входе).
            host.send(HostIntent.Configure(null))
            wipeLocalWallets()
        }
        // Гость вошёл в ЧУЖОЙ (существующий) аккаунт — uid другой, кошельки
        // прошлого владельца стираем. При регистрации uid сохраняется, и хук
        // не срабатывает: данные остаются у того же человека.
        session.onUserSwitched = { wipeLocalWallets() }
    }

    /**
     * Отложенные переходы по ссылкам: реферал (`pendingReferrer`) и подарок
     * (`pendingGift`). Зовётся после входа и на каждый новый диплинк —
     * mirrors `grantPendingReferral` / `claimReferralBonuses` / `claimPendingGift`.
     * Ключи снимаются с диска ДО первого suspend, поэтому параллельный вызов
     * ничего не заберёт дважды.
     */
    suspend fun claimPendingLinks() {
        val uid = session.user?.id ?: return
        if (session.isGuest) return
        val prefs = context.getSharedPreferences("ayant.deeplink", 0)
        // Приглашение по ссылке → приветственный бонус приглашённому; награду
        // пригласившему раздаёт бэкенд (по событию referral_join).
        val ref = prefs.getString("pendingReferrer", null)
        if (!ref.isNullOrEmpty() && !prefs.getBoolean("referralCredited", false) && ref != uid) {
            prefs.edit().putBoolean("referralCredited", true).remove("pendingReferrer").apply()
            bonus.addFromServer(100)
            app.recordReferral(ref)
        }
        // Подарок по ссылке → купон в кошелёк (+ тост о результате).
        val giftCode = prefs.getString("pendingGift", null)
        if (!giftCode.isNullOrEmpty()) {
            prefs.edit().remove("pendingGift").apply()
            app.claimGiftWithToast(giftCode) { title, code -> coupons.addGifted(title, code) }
        }
        // Начисления сервера (награды за приглашённых).
        val granted = app.claimBonusGrantsTotal()
        if (granted > 0) bonus.addFromServer(granted)
    }

    LaunchedEffect(session.user?.id) {
        // Связываем владельцев ДО setCurrentUser/load: каталог и личная библиотека
        // живут в них, и загрузка без привязки ушла бы в никуда.
        app.bindProfile(profile)   // владелец сохранённого/избранного
        app.bindFeed(feed)         // владелец каталога
        app.setCurrentUser(session.user?.id, session.user?.name, session.isGuest)
        app.load()
        location.refresh()
        // Кабинет хоста накладывается на ленту по id (`setHostContent`).
        host.bind(app)
        host.send(HostIntent.Configure(session.user?.id))
        host.send(HostIntent.Sync)
        // Push: subscribe to city broadcasts + register this device's token
        // (токен пишем уже под авторизацией — гость тоже авторизован).
        Push.subscribeDefaults(app.selectedCitySlug)
        Push.registerToken(session.user?.id, app.selectedCitySlug)
        startBonusIfAllowed()
        // Backend sync + referral/gift claims.
        val uid = session.user?.id
        if (uid != null && !session.isGuest) {
            coupons.sync(uid)
            points.send(PointsIntent.Observe(uid))   // живой поток; опрос больше не нужен
            loyalty.observe(uid)                     // и штампы — живьём, ради экрана «Начислено»
            // Штампы пришли листенером: если карта заполнилась, сервер выдал
            // купон-награду — подтягиваем купоны сразу, не дожидаясь запуска.
            launch { loyalty.cards.drop(1).collect { coupons.sync(uid) } }
            claimPendingLinks()
        }
    }

    // Новый диплинк, пока приложение открыто: подарок/реферал забираем сразу,
    // как `onOpenURL` на iOS.
    LaunchedEffect(linkEpoch) { if (linkEpoch > 0) claimPendingLinks() }

    // Жизненный цикл: на переднем плане — свежая геолокация и бонус-движок,
    // в фоне — пауза. Mirrors `.onChange(of: scenePhase)` в `SANApp.swift`.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, session.user?.id) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> {
                    location.refresh()
                    app.setCurrentUser(session.user?.id, session.user?.name, session.isGuest)
                    startBonusIfAllowed()
                }
                Lifecycle.Event.ON_PAUSE -> bonus.pause()
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    // Follow an incoming deep link once data is loaded.
    LaunchedEffect(initialDeepLink, app.venues.size) {
        if (initialDeepLink != null && app.venues.isNotEmpty()) nav.navigate(initialDeepLink)
    }

    val authSheet = remember { mutableStateOf(false) }
    if (authSheet.value) {
        GuestAuthSheet(session) { authSheet.value = false }
    }

    val backStack by nav.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route
    val showBar = currentRoute in tabRoutes

    Scaffold(
        containerColor = AyantTheme.colors.canvas,
        // Любой тап продлевает «активность» для бонус-движка. Наблюдаем на
        // проходе Initial, ничего не потребляя — кнопки внутри работают как
        // прежде (ActivityTracker с cancelsTouchesInView=false на iOS).
        modifier = Modifier.pointerInput(Unit) {
            awaitPointerEventScope {
                while (true) {
                    awaitPointerEvent(PointerEventPass.Initial)
                    bonus.registerInteraction()
                }
            }
        },
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
                        // Вкладки нет на панели — выбрать её нельзя.
                        if (!tab.isVisible) return@AyantTabBar
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
                    GuestAuthSheet(session) { nav.popBackStack() }
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
                    GuestAuthSheet(session) { nav.popBackStack() }
                    return@composable
                }
                // Вкладка, а не пуш: возвращаться некуда, кнопки «назад» нет.
                MyQrScreen(app, points, location,
                    onBack = null,
                    onScanVenue = { nav.navigate("host") })
            }
            composable("profile") {
                ProfileScreen(
                    app, session, coupons = coupons, theme = theme, host = host,
                    onCoupons = { nav.navigate("coupons") },
                    onHost = onEnterHost,
                    onHelp = { nav.navigate(it) }, onSaved = { nav.navigate("saved") },
                )
            }
            composable("about") { AboutScreen(onBack = { nav.popBackStack() }) }
            composable("faq") { FaqScreen(onBack = { nav.popBackStack() }) }
            composable("support") { SupportScreen(onBack = { nav.popBackStack() }) }
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
                    GuestAuthSheet(session) { nav.popBackStack() }
                    return@composable
                }
                val settings by app.settings.collectAsState()
                SnakeGame(bonus, watermark = settings.adPlaceholderText, onClose = { nav.popBackStack() })
            }
            composable("tetris") {
                if (session.isGuest) {
                    // Сюда гость может попасть только прямой навигацией
                    // (deeplink): показываем тот же экран входа поверх.
                    GuestAuthSheet(session) { nav.popBackStack() }
                    return@composable
                }
                TetrisGame(bonus, onClose = { nav.popBackStack() })
            }
            // Сканер заведения с экрана «Мой QR»; сам «Режим заведения» из
            // профиля подменяет корень (`RootGate`), а не пушит маршрут.
            composable("host") { HostRoot(app, session, onExit = { nav.popBackStack() }) }
        }
    }
}
