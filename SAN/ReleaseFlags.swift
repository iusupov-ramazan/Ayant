import Foundation
import Observation
import AyantDomain

/// Хранилище удалённого снимка — `@Observable`: SwiftUI запоминает, какие
/// свойства прочитало тело экрана, даже через статический `ReleaseFlags`, и
/// перерисовывает экран, когда снимок меняется. Поэтому выключатель из
/// консоли прячет функцию сразу, без правки каждого места вызова.
@Observable
final class RemoteFlagsStorage {
    var settings = RemoteSettings.defaults
}

/// Флаги первого релиза: что скрыто из интерфейса, но остаётся в коде.
///
/// Каждый флаг — один переключатель для целой поверхности. Выключено то, что
/// не подкреплено бэкендом или оплатой и лишь путало бы пользователя в первой
/// версии. Включать по одному, когда соответствующая часть готова:
/// глобальный кошелёк — когда награды и подарки будут записываться в
/// Firestore; продвижение — когда появится оплата; Apple Wallet — когда
/// настроен pass type ID; поиск — когда экран карты пройдёт тестирование.
///
/// **Удалённый выключатель.** Каждый флаг ниже — «включено в сборке» И «не
/// выключено в Firebase Remote Config» (`ios_<флаг>_enabled`, см.
/// `RemoteFeature`). Удалённо можно только выключить: спрятанное в сборке
/// (`promote`, `appleWallet`, …) галочкой в консоли не откроется. Значения
/// применяются сразу (`apply(_:)`): на старте из кэша, затем после каждой
/// загрузки и публикации в реальном времени — экраны перерисовываются сами.
enum ReleaseFlags {
    private static let storage = RemoteFlagsStorage()

    /// Текущий удалённый снимок. Чтение из тела экрана подписывает экран на
    /// изменения (Observation).
    static var remote: RemoteSettings { storage.settings }

    static func apply(_ settings: RemoteSettings) {
        if storage.settings != settings { storage.settings = settings }
    }

    /// Вкладка «Поиск» (карта + список). Скрыта: большой экран, не прошёл
    /// тестирование к релизу. Экраны деталей открывают маршрут во внешних картах.
    fileprivate static let built_searchTab = false

    /// Глобальный кошелёк бонусов: капсула «БОНУСЫ», мини-игры (Змейка, Тетрис,
    /// Diamond, 2048), каталог наград, подарки.
    ///
    /// ВКЛЮЧЁН. Баланс ведёт сервер (`bonusWallets`, `earnBonus`/`buyCoupon`),
    /// курс игр — Remote Config (`GameRates`). Прежняя дыра закрыта: награду
    /// без заведения-партнёра клиент не показывает, а `buyCoupon` не продаёт,
    /// подарки сервер создаёт с заведением (`claimGift`), так что `wrong_venue`
    /// у стойки больше не возникает.
    fileprivate static let built_globalBonusWallet = true

    /// Реферальная программа в профиле.
    ///
    /// ВКЛЮЧЕНА вместе с глобальным кошельком: бонусы теперь есть на что
    /// тратить — у наград появилось заведение-партнёр. Начисление делает
    /// Cloud Function `rewardReferral`, клиент забирает его `claimBonusGrants`.
    fileprivate static let built_referrals = true

    /// «Продвижение» у хоста: буст и push-кампании. Работает по-настоящему,
    /// но оплата не подключена, а цены в интерфейсе расходятся с расчётом.
    fileprivate static let built_promote = false

    /// Кнопка «Добавить в Apple Wallet» на карте лояльности. Pass type ID на
    /// сервере ещё шаблонный, подпись пасса не пройдёт.
    fileprivate static let built_appleWallet = false

    /// Покупка купонов заведения за бонусы («Магазин купонов» на странице
    /// заведения). Сам магазин виден всегда — гость видит, что можно получить
    /// и сколько это стоит; флаг включает только кнопку «Обменять».
    ///
    /// ВКЛЮЧЕНА: покупка серверная — `buyCoupon` списывает с кошелька
    /// `bonusWallets/{uid}`, считает остаток и выдаёт купон в одной
    /// транзакции. Условие — задеплоенные функции и правила
    /// (`firebase deploy --only functions,firestore:rules`): без них покупка
    /// честно отвечает «не получилось», ничего не списав.
    fileprivate static let built_couponShopPurchase = true

    // MARK: Эффективные значения: сборка И удалённый выключатель

    static var searchTab: Bool { built_searchTab && remote.isEnabled(.searchTab) }
    static var globalBonusWallet: Bool { built_globalBonusWallet && remote.isEnabled(.globalBonusWallet) }
    static var referrals: Bool { built_referrals && remote.isEnabled(.referrals) }
    static var promote: Bool { built_promote && remote.isEnabled(.promote) }
    static var appleWallet: Bool { built_appleWallet && remote.isEnabled(.appleWallet) }
    static var couponShopPurchase: Bool { built_couponShopPurchase && remote.isEnabled(.couponShopPurchase) }

    /// Импорт акций из Instagram и меню из файла — новые и самые хрупкие
    /// поверхности кабинета (внешний API, разбор чужих PDF): их выключатели
    /// нужны больше всего, хотя в сборке они включены.
    static var instagramImport: Bool { remote.isEnabled(.instagramImport) }
    static var menuImport: Bool { remote.isEnabled(.menuImport) }
}
