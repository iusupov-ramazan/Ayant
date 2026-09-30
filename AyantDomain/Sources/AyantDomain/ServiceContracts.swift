import Foundation

/*
 * Контракты сервисов: аналитика, купоны, push, лог ранжирования, хост-репозиторий.
 *
 * Живут в домене, а не рядом со своими Firebase-реализациями: иначе слой фич
 * зависел бы от слоя данных ради одного протокола. Реализации — пары
 * `Mock*`/`Firebase*` — лежат в `AyantData`.
 *
 * Зеркалит `android/domain/.../domain/contract/`.
 */

/// Запись/чтение контента хоста в Firestore (заведения и предложения с владельцем).
public protocol HostRepository {
    func saveVenue(_ dto: HostVenueDTO, ownerID: String) async throws
    func deleteVenue(id: String) async throws
    func saveDeal(_ dto: HostDealDTO, ownerID: String) async throws
    func deleteDeal(id: String) async throws
    func fetchOwnedVenues(ownerID: String) async throws -> [HostVenueDTO]
    func fetchOwnedDeals(ownerID: String) async throws -> [HostDealDTO]
    /// Купоны заведения на продажу за бонусы.
    func saveCouponOffer(_ offer: CouponOffer, ownerID: String) async throws
    func deleteCouponOffer(id: String) async throws
    func fetchOwnedCouponOffers(ownerID: String) async throws -> [CouponOffer]
    /// Профиль хоста в коллекции hosts/{uid} (включая статус верификации).
    func saveProfile(_ profile: HostProfile, ownerID: String) async throws
    func fetchProfile(ownerID: String) async throws -> HostProfile?
    /// Кладёт push-кампанию в очередь (Firestore). Реальную рассылку делает
    /// Cloud Function по триггеру создания документа.
    func queuePushCampaign(headline: String, body: String, city: String,
                           category: String?, venueID: String, dealID: String?, ownerID: String) async throws
}

/// Аналитика заведений: события пишутся в коллекцию `analytics/{venueID}/days/{date}`.
public protocol AnalyticsService {
    /// Лог события (просмотр/сохранение/звонок/маршрут/клик по акции). Fire-and-forget.
    func log(venueID: String, metric: String)
    /// Сумма метрик за последние `days` дней.
    func fetchStats(venueID: String, days: Int) async throws -> [String: Int]
    /// Метрики ПО ДНЯМ за последние `days` дней: ключ — "yyyy-MM-dd".
    ///
    /// Нужен графику в «Аналитике»: суммы `fetchStats` схлопывают ряд, а рисовать
    /// столбики не из настоящих данных нельзя. Firestore и так хранит метрики
    /// подокументно на день — этот метод просто не складывает их.
    func fetchDailyStats(venueID: String, days: Int) async throws -> [String: [String: Int]]
}

public enum AnalyticsMetric {
    public static let views = "views"
    public static let saves = "saves"
    public static let calls = "calls"
    public static let maps = "maps"
    public static let dealTaps = "dealTaps"
    public static let redemptions = "redemptions"   // купоны, погашенные в заведении
    // Серверные события лояльности (пишут только Cloud Functions):
    public static let stamps = "stamps"                 // выдано штампов
    public static let rewardsIssued = "rewardsIssued"   // заполненные карты + награды за баллы
    public static let pointsEarned = "pointsEarned"     // начислено баллов (сумма)
    public static let pointsRedeemed = "pointsRedeemed" // списано баллов (сумма)
    public static let all = [views, saves, calls, maps, dealTaps, redemptions,
                             stamps, rewardsIssued, pointsEarned, pointsRedeemed]
}

/// Журнал событий ранжирования (learning-to-rank): фичи на момент показа + исходы.
/// Пишет в append-only коллекцию `rankingEvents`. Fire-and-forget, ошибки глушим —
/// телеметрия не должна ломать пользовательский поток. Схема — `RankingEvent.swift`.
public protocol RankingEventService {
    func log(_ event: RankingEvent)
}

/// Результат сканирования купона заведением (ответ Cloud Function scanCoupon).
public struct ScanOutcome: Equatable {
    public let ok: Bool
    public let title: String
    public let loyalty: Bool
    public let stamps: Int
    public let goal: Int
    public let rewardIssued: Bool
    public let rewardTitle: String
    public let errorCode: String?     // nil при успехе; иначе "already_used"/"wrong_venue"/…
    // Результат начисления баллов САН (Ветка C). points=true ⇒ это баллы, не штамп.
    public var points: Bool = false
    public var awarded: Int = 0       // начислено баллов
    public var balance: Int = 0       // новый баланс баллов
    /// true — запрос с этим idempotencyKey уже выполнялся; ничего не начислено повторно.
    public var replayed: Bool = false
    /// Имя карты штампов, на которую лёг штамп (пусто — у безымянной первой).
    public var cardTitle: String = ""

    public init(ok: Bool, title: String, loyalty: Bool, stamps: Int, goal: Int, rewardIssued: Bool, rewardTitle: String, errorCode: String?, points: Bool = false, awarded: Int = 0, balance: Int = 0, replayed: Bool = false, cardTitle: String = "") {
        self.cardTitle = cardTitle
        self.ok = ok
        self.title = title
        self.loyalty = loyalty
        self.stamps = stamps
        self.goal = goal
        self.rewardIssued = rewardIssued
        self.rewardTitle = rewardTitle
        self.errorCode = errorCode
        self.points = points
        self.awarded = awarded
        self.balance = balance
        self.replayed = replayed
    }
}

/// Результат списания баллов САН (ответ Cloud Function redeemVenuePoints).
public struct RedeemOutcome: Equatable {
    public let ok: Bool
    public let redeemed: Int          // списано баллов
    public let balance: Int           // остаток
    public let rewardTitle: String
    public let somOff: Int?           // для money-награды — скидка в сомах
    public let errorCode: String?     // nil при успехе; иначе "insufficient"/…
    /// true — запрос с этим idempotencyKey уже выполнялся, баллы НЕ списаны повторно.
    public var replayed: Bool = false

    public init(ok: Bool, redeemed: Int, balance: Int, rewardTitle: String, somOff: Int?, errorCode: String?, replayed: Bool = false) {
        self.ok = ok
        self.redeemed = redeemed
        self.balance = balance
        self.rewardTitle = rewardTitle
        self.somOff = somOff
        self.errorCode = errorCode
        self.replayed = replayed
    }
}

/// Бэкенд-трекинг купонов + карт лояльности (Firestore) и сканер заведения.
public protocol CouponService {
    /// Пишет купон пользователя в Firestore (deal-купон создаёт клиент).
    func saveCoupon(_ coupon: Coupon, userID: String) async throws
    /// Каталог наград глобального кошелька (config/globalRewards).
    /// Пусто → показывать нечего: награда без партнёра не гасится.
    func fetchGlobalRewards() async throws -> [Reward]
    /// Купоны, которые заведение продаёт за бонусы (`couponOffers` этого
    /// заведения) — для «магазина купонов» на его странице. Все статусы:
    /// что из этого можно купить сейчас, решает `CouponOffer.isAvailable(at:)`.
    func fetchCouponOffers(venueID: String) async throws -> [CouponOffer]
    /// Купоны пользователя из Firestore (для синка used-статуса и наград).
    func fetchCoupons(userID: String) async throws -> [Coupon]
    /// Карты лояльности пользователя из Firestore (разовый запрос).
    func fetchLoyaltyCards(userID: String) async throws -> [LoyaltyCard]
    /// Живой поток карт лояльности: штампы меняет сканер заведения, и экран
    /// должен увидеть это сразу, без опроса. Реализация на Firestore держит
    /// snapshot-листенер; он снимается вместе с задачей-потребителем.
    func loyaltyCards(userID: String) -> AsyncStream<[LoyaltyCard]>
    /// Карты баллов САН пользователя (venuePoints/{userID}_{venueID}).
    func fetchVenuePoints(userID: String) async throws -> [VenuePointsCard]
    /// Сканирование заведением: погашение купона / штамп / начисление баллов САН.
    /// billAmount — сумма чека (mode=cashback), bandIndex — выбранный диапазон (mode=bands).
    /// `idempotencyKey` — один на распознанный QR, повторяется при ретрае:
    /// сервер вернёт исходный результат вместо второго штампа/начисления.
    /// `cardID` — какую карту штампов выбрал сотрудник (для `AYANT-CARD:`);
    /// `nil` — первая карта, как у клиентов, не знающих о нескольких картах.
    func scanCoupon(code: String, venueID: String, idToken: String,
                    billAmount: Int?, bandIndex: Int?, idempotencyKey: String,
                    cardID: String?) async throws -> ScanOutcome
    /// Списание баллов САН на награду (через Cloud Function redeemVenuePoints).
    /// `idempotencyKey` генерируется вызывающим ОДИН раз на попытку и повторяется
    /// при ретрае — сервер вернёт тот же результат вместо второго списания.
    func redeemVenuePoints(venueID: String, userID: String, rewardId: String,
                           pointsToSpend: Int, idToken: String,
                           idempotencyKey: String) async throws -> RedeemOutcome
}

/// Push-уведомления (новые акции рядом / у избранных мест).
public protocol PushService {
    func requestAuthorization() async -> Bool
    /// Подписка на темы: "deals_bishkek", "favorites_<venueID>" и т.п.
    func subscribe(topic: String)
    func unsubscribe(topic: String)
    /// Регистрирует FCM-токен устройства для адресной рассылки (с частотным лимитом).
    func registerToken(_ token: String, city: String, uid: String?)
    /// Отписывает устройство при выходе: снимает темы, удаляет документ в
    /// `userTokens` и сам FCM-токен. Без этого следующий владелец устройства
    /// (или сам вышедший) продолжает получать адресные кампании старого uid.
    func unregisterDevice(topics: [String]) async
}

/// Разбор файла меню (PDF, CSV, Excel) в блюда — на устройстве, без сети
/// и без оплаты. Ничего не сохраняет: возвращает черновик для проверки
/// хозяином. `progress` — доля 0…1 (распознавание сканов идёт постранично).
public protocol MenuParsingService: Sendable {
    func parseMenu(file: Data, kind: MenuFileKind,
                   progress: @escaping @Sendable (Double) -> Void) async throws -> [MenuDraftItem]
}

// MARK: - Кошелёк бонусов на сервере

/// Что покупается за бонусы.
public enum BonusPurchase: Equatable, Sendable {
    /// Купон заведения (`couponOffers/{id}`).
    case offer(id: String)
    /// Награда из каталога (`config/globalRewards`) — себе или подарком.
    case reward(id: String, asGift: Bool, fromName: String)

    /// Что именно покупаем — для ключа идемпотентности на клиенте: повтор той
    /// же покупки должен нести тот же ключ, другая покупка — другой.
    public var ref: String {
        switch self {
        case .offer(let id): return "offer:\(id)"
        case .reward(let id, let asGift, _): return "reward:\(id)\(asGift ? ":gift" : "")"
        }
    }
}

/// Ответ `buyCoupon`. `errorCode` — код сервера как есть (`insufficient`,
/// `sold_out`, `unavailable`, `not_found`, `no_wallet`, `key_reused`, …).
public struct BonusPurchaseOutcome: Equatable, Sendable {
    public var ok: Bool
    public var coupon: Coupon?
    public var giftCode: String?
    public var balance: Int
    public var errorCode: String?
    public var replayed: Bool

    public init(ok: Bool, coupon: Coupon? = nil, giftCode: String? = nil, balance: Int = 0,
                errorCode: String? = nil, replayed: Bool = false) {
        self.ok = ok; self.coupon = coupon; self.giftCode = giftCode
        self.balance = balance; self.errorCode = errorCode; self.replayed = replayed
    }
}

/// Ответ `earnBonus`. `granted` может быть меньше запрошенного — сервер
/// держит потолки (за вызов и за сутки).
public struct BonusEarnOutcome: Equatable, Sendable {
    public var ok: Bool
    public var granted: Int
    public var balance: Int
    public var errorCode: String?

    public init(ok: Bool, granted: Int = 0, balance: Int = 0, errorCode: String? = nil) {
        self.ok = ok; self.granted = granted; self.balance = balance; self.errorCode = errorCode
    }
}

/// Глобальный кошелёк бонусов, который ведёт сервер (`bonusWallets/{uid}`).
///
/// Баланс на устройстве с ним — только отражение: начисления уходят в
/// `earn`, покупки — в `buy`, а число на экране приходит из `balance(userID:)`.
/// Без него (мок-режим, тесты) `BonusEngine` работает по-старому, локально.
public protocol BonusWalletService {
    /// Живой баланс кошелька (снапшот-листенер; снимается с задачей-потребителем).
    func balance(userID: String) -> AsyncStream<Int>
    /// Заводит кошелёк (один раз переносит `localBalance` устройства) и
    /// зачисляет незабранные награды. Возвращает баланс.
    func sync(localBalance: Int) async throws -> Int
    /// Начисление за игры/время. `idempotencyKey` — один на начисление.
    func earn(amount: Int, source: String, idempotencyKey: String) async throws -> BonusEarnOutcome
    /// Покупка за бонусы. `idempotencyKey` — один на попытку, повторяется при ретрае.
    func buy(_ purchase: BonusPurchase, idempotencyKey: String) async throws -> BonusPurchaseOutcome
    /// Забрать подарок по коду из ссылки: сервер создаёт купон заведения.
    /// Повтор тем же получателем возвращает тот же купон.
    func claimGift(code: String) async throws -> BonusPurchaseOutcome
}
