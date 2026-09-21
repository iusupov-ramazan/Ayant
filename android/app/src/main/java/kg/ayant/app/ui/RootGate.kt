package kg.ayant.app.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.Crossfade
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import kg.ayant.app.R
import kg.ayant.app.core.ayantFactory
import kg.ayant.app.domain.HostIntent
import kg.ayant.app.domain.PointsIntent
import kg.ayant.app.ui.auth.AuthScreen
import kg.ayant.app.ui.bonus.PointsEarnedScreen
import kg.ayant.app.ui.detail.WriteReviewDialog
import kg.ayant.app.ui.host.HostRoot
import kg.ayant.app.ui.navigation.RootScaffold
import kg.ayant.app.ui.onboarding.OnboardingScreen
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.ui.vm.HostViewModel
import kg.ayant.app.ui.vm.LoyaltyViewModel
import kg.ayant.app.ui.vm.PointsViewModel
import kg.ayant.app.ui.vm.SessionViewModel
import kg.ayant.app.ui.vm.ThemeViewModel
import kotlinx.coroutines.delay

/**
 * Корневой гейт. Зеркалит `SANApp.body` + `SignedInRootView` в `SANApp.swift`:
 *
 *   не вошёл → `AuthScreen`;
 *   режим заведения и кабинет заведён → `HostRoot`;
 *   не прошёл онбординг → `OnboardingScreen`;
 *   иначе → `RootScaffold` (вкладки гостя).
 *
 * Поверх любой ветки — тост (`AppToast`) и экран «Начислено» (`EarnedOverlay`):
 * событие живёт в состоянии стора и снимается только кнопкой, на какой бы
 * вкладке гость ни был.
 *
 * `hostMode` хранится в prefs (`ayant.flags/hostMode`), как `@AppStorage
 * ("san.hostMode")` на iOS: перезапуск возвращает владельца в кабинет.
 *
 * [linkEpoch] растёт на каждый входящий диплинк (см. `MainActivity`) — по нему
 * корень забирает отложенный подарок/реферала, не дожидаясь смены пользователя.
 */
@Composable
fun RootGate(
    session: SessionViewModel,
    initialDeepLink: String? = null,
    theme: ThemeViewModel? = null,
    linkEpoch: Int = 0,
) {
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("ayant.flags", 0) }
    var onboarded by rememberSaveable { mutableStateOf(prefs.getBoolean("onboarded", false)) }
    var hostMode by rememberSaveable { mutableStateOf(prefs.getBoolean("hostMode", false)) }
    val setHostMode: (Boolean) -> Unit = { on ->
        prefs.edit().putBoolean("hostMode", on).apply()
        hostMode = on
    }
    // Именно collectAsState: `session.isSignedIn` — обычный getter по
    // `_state.value`, чтение которого НЕ подписывает композицию. Выход теперь
    // асинхронный (сначала отписка от push, потом Firebase), и без подписки
    // экран остался бы висеть на уже закрытой сессии.
    val state by session.state.collectAsState()

    // Общие ViewModel — владелец Activity (мы вне NavHost), те же экземпляры
    // получат `RootScaffold` и `HostRoot`.
    val app: AppViewModel = viewModel(factory = ayantFactory())
    val host: HostViewModel = viewModel(factory = ayantFactory())
    val points: PointsViewModel = viewModel(factory = ayantFactory())
    val loyalty: LoyaltyViewModel = viewModel(factory = ayantFactory())
    val hostState by host.state.collectAsState()

    // Кабинет хоста привязан к uid. Конфигурируем ЗДЕСЬ, до выбора ветки: иначе
    // владелец с `hostMode = true` на холодном старте мельком видел бы
    // гостевые вкладки, пока `hasAccount` не поднялся из кэша.
    LaunchedEffect(state.user?.id) { host.send(HostIntent.Configure(state.user?.id)) }

    val inHostCabinet = hostMode && hostState.hasAccount

    // Ключ пересборки корня: пользователь, его гостевой статус и режим хоста.
    // Регистрация гостя сохраняет uid (запись связывается), но приложение
    // после неё — другое, с открытыми QR и бонусами, поэтому статус входит в
    // ключ. Crossfade даёт анимированную подмену вместо мгновенной перерисовки.
    val rootKey = "${state.user?.id ?: "none"}-${state.isSignedIn}-${state.isGuest}-$inHostCabinet"

    Box(Modifier.fillMaxSize()) {
        Crossfade(targetState = rootKey, label = "root") { key ->
            // Ветку выбираем по СОСТОЯНИЮ, а не по ключу: key нужен только чтобы
            // Crossfade понял, что корень сменился.
            when {
                !state.isSignedIn -> AuthScreen(session)
                inHostCabinet -> key(key) {
                    HostRoot(app, session, onExit = { setHostMode(false) })
                }
                !onboarded -> OnboardingScreen {
                    prefs.edit().putBoolean("onboarded", true).apply()
                    onboarded = true
                }
                else -> key(key) {
                    RootScaffold(
                        session,
                        initialDeepLink = initialDeepLink,
                        theme = theme,
                        linkEpoch = linkEpoch,
                        onEnterHost = { setHostMode(true) },
                    )
                }
            }
        }
        // «Начислено» — над всем приложением, но не над кабинетом хоста
        // (там сканирует сотрудник, а не копит гость).
        if (state.isSignedIn && !inHostCabinet) {
            EarnedOverlay(app = app, points = points, loyalty = loyalty, isGuest = state.isGuest)
        }
        AppToast(app)
    }
}

// MARK: - «Начислено»

/**
 * Экран «Начислено» поверх приложения. Mirrors the `fullScreenCover` in
 * `SignedInRootView`: событие живёт в состоянии стора (`PointsState.pendingEarn`
 * / `LoyaltyViewModel.pendingStamp`) и снимается только кнопкой «Отлично» —
 * перерисовка вкладок, смена экрана, новый снимок баланса его не закрывают.
 * Одновременно приходит редко; баллы первее.
 */
@Composable
private fun EarnedOverlay(
    app: AppViewModel,
    points: PointsViewModel,
    loyalty: LoyaltyViewModel,
    isGuest: Boolean,
) {
    val pointsState by points.state.collectAsState()
    val pendingStamp by loyalty.pendingStamp.collectAsState()
    val earn = pointsState.pendingEarn

    // Отзыв предлагаем после закрытия «Начислено»: два модальных окна разом
    // не показываем (на iOS SwiftUI их и не покажет).
    var pendingReviewVenueID by remember { mutableStateOf<String?>(null) }
    var reviewVenueID by remember { mutableStateOf<String?>(null) }

    val activeID = earn?.let { "pts-" + it.id } ?: pendingStamp?.let { "stamp-" + it.id }
    LaunchedEffect(activeID) {
        if (activeID != null) return@LaunchedEffect
        val id = pendingReviewVenueID ?: return@LaunchedEffect
        pendingReviewVenueID = null
        delay(450)
        reviewVenueID = id
    }

    /** Отзыв предлагаем, когда заведение в каталоге и отзыва ещё нет. */
    fun reviewAction(venueID: String): (() -> Unit)? {
        if (isGuest) return null
        val venue = app.venue(id = venueID) ?: return null
        if (app.myReview(venue.id, null) != null) return null
        return { pendingReviewVenueID = venueID }
    }

    when {
        earn != null -> {
            val subtitle = app.venue(id = earn.venueID)?.district ?: app.selectedCity.name
            PointsEarnedScreen(
                delta = earn.delta,
                venueName = earn.venueName,
                venueSubtitle = subtitle,
                newBalance = earn.newBalance,
                onDone = { points.send(PointsIntent.DismissEarn) },
                onReview = reviewAction(earn.venueID)?.let { review ->
                    { review(); points.send(PointsIntent.DismissEarn) }
                },
            )
        }
        pendingStamp != null -> {
            val event = pendingStamp!!
            val subtitle = app.venue(id = event.venueID)?.district ?: app.selectedCity.name
            PointsEarnedScreen(
                stamps = event.stamps,
                goal = event.goal,
                rewardIssued = event.rewardIssued,
                reward = event.reward,
                venueName = event.venueName,
                venueSubtitle = subtitle,
                onDone = { loyalty.dismissStamp() },
                onReview = reviewAction(event.venueID)?.let { review ->
                    { review(); loyalty.dismissStamp() }
                },
            )
        }
    }

    reviewVenueID?.let { id ->
        val venue = app.venue(id = id)
        if (venue == null) {
            reviewVenueID = null
        } else {
            WriteReviewDialog(venue = venue, app = app, preselectItemID = null, onDismiss = { reviewVenueID = null })
        }
    }
}

// MARK: - Тост

/**
 * Всплывающее уведомление (подарки, ошибки и т. п.) поверх всего приложения.
 * Mirrors `AppToast` in `SANApp.swift`. Стор отдаёт КОД (у `:feature` нет
 * каталога строк) — текст подбирается здесь на языке приложения.
 */
@Composable
private fun BoxScope.AppToast(app: AppViewModel) {
    val code by app.toastMessage.collectAsState()
    // Текст держим и на время анимации исчезновения, когда код уже снят.
    var shown by remember { mutableStateOf<String?>(null) }
    if (code != null) shown = code
    LaunchedEffect(code) {
        if (code == null) return@LaunchedEffect
        delay(2800)
        app.clearToast()
    }
    AnimatedVisibility(
        visible = code != null,
        enter = slideInVertically { -it } + fadeIn(),
        exit = slideOutVertically { -it } + fadeOut(),
        modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding(),
    ) {
        Text(
            toastText(shown),
            fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Color.White,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .padding(horizontal = 24.dp)
                .padding(top = 8.dp)
                .shadow(6.dp, CircleShape)
                .background(Color.Black.copy(alpha = 0.85f), CircleShape)
                .padding(horizontal = 16.dp, vertical = 12.dp),
        )
    }
}

@Composable
private fun toastText(code: String?): String = when (code) {
    null -> ""
    AppViewModel.TOAST_GIFT_RECEIVED -> stringResource(R.string.toast_gift_received)
    AppViewModel.TOAST_GIFT_INVALID -> stringResource(R.string.toast_gift_invalid)
    else -> code
}
