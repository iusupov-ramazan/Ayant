package kg.ayant.app.core

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewmodel.CreationExtras
import kg.ayant.app.location.LocationManager
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
import kg.ayant.app.ui.vm.VenueDetailViewModel

/**
 * Композиционный корень: единственное место, где ViewModel встречаются со своими
 * зависимостями.
 *
 * Раньше каждая ViewModel звала `AppConfig.make*()` дефолтом параметра — удобно,
 * но это обратная зависимость: фича-слой знал про сборку приложения и не мог
 * жить в отдельном модуле. Теперь фабрика — здесь, в app-слое, а ViewModel
 * принимают готовые контракты и про `AppConfig` не знают.
 *
 * Передаётся явно: `viewModel(factory = AyantViewModels(app))`. Именно явно, а
 * не через `defaultViewModelProviderFactory`, потому что внутри `NavHost`
 * владельцем становится `NavBackStackEntry` со своей фабрикой по умолчанию —
 * экраны хоста и карточки иначе получили бы ViewModel без зависимостей.
 */
class AyantViewModels(private val app: Application) : ViewModelProvider.Factory {

    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>, extras: CreationExtras): T =
        when (modelClass) {
            AppViewModel::class.java -> AppViewModel(
                app,
                repository = AppConfig.makeDataRepository(),
                analytics = AppConfig.makeAnalyticsService(),
                rankingLog = AppConfig.makeRankingEventService(),
                push = AppConfig.makePushService(),
            )

            FeedViewModel::class.java -> FeedViewModel(
                app,
                repository = AppConfig.makeDataRepository(),
            )

            SessionViewModel::class.java -> SessionViewModel(
                app,
                service = AppConfig.makeAuthService(),
                // Оффлайн-режим помнит вход между запусками; с Firebase доверяем
                // только живой сессии (см. SessionViewModel.restoreLocalUser).
                restoreLocalUser = !AppConfig.useFirebase,
            )

            CouponViewModel::class.java -> CouponViewModel(app, backend = AppConfig.makeCouponService())
            LoyaltyViewModel::class.java -> LoyaltyViewModel(app, backend = AppConfig.makeCouponService())
            PointsViewModel::class.java -> PointsViewModel(app, repository = AppConfig.makePointsRepository())
            HostViewModel::class.java -> HostViewModel(
                app,
                analytics = AppConfig.makeAnalyticsService(),
                push = AppConfig.makePushService(),
            )

            // Без внешних зависимостей: состояние берут из хранилища устройства
            // либо проецируют чужое.
            ProfileViewModel::class.java -> ProfileViewModel(app)
            BonusViewModel::class.java -> BonusViewModel(app)
            ThemeViewModel::class.java -> ThemeViewModel(app)
            VenueDetailViewModel::class.java -> VenueDetailViewModel(app)
            LocationManager::class.java -> LocationManager(app)

            else -> throw IllegalArgumentException(
                "AyantViewModels не знает ${modelClass.name}: добавьте ветку сюда, " +
                    "иначе ViewModel останется без зависимостей.",
            )
        } as T
}

/**
 * Фабрика для `viewModel(factory = ayantFactory())`.
 *
 * Держится через `remember`, чтобы не пересоздаваться на каждую рекомпозицию.
 */
@androidx.compose.runtime.Composable
fun ayantFactory(): ViewModelProvider.Factory {
    val app = androidx.compose.ui.platform.LocalContext.current.applicationContext as Application
    return androidx.compose.runtime.remember(app) { AyantViewModels(app) }
}
