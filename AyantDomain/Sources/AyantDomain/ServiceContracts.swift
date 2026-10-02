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
    /// `allowCreate: false` — заведение сервер уже знает (`HostStore.knownVenueIDs`).
    /// Если документа нет, его удалили (админ, другое устройство): реализация
    /// бросает `AppError.notFound`, а не воскрешает заведение из устаревшей копии.
    func saveVenue(_ dto: HostVenueDTO, ownerID: String, allowCreate: Bool) async throws
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

public extension HostRepository {
    /// Моки и фейки не различают создание и правку.
    func saveVenue(_ dto: HostVenueDTO, ownerID: String, allowCreate: Bool) async throws {
        try await saveVenue(dto, ownerID: ownerID)
    }
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
    /// Для `cooldown`: через сколько секунд гостю снова можно начислить.
    public var retryAfterSec: Int? = nil

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
    /// Код чека и момент списания (`receiptCode`/`redeemedAt` в ответе сервера).
    public var receiptCode: String = ""
    public var redeemedAt: Date? = nil

    public init(ok: Bool, redeemed: Int, balance: Int, rewardTitle: String, somOff: Int?, errorCode: String?,
                replayed: Bool = false, receiptCode: String = "", redeemedAt: Date? = nil) {
        self.receiptCode = receiptCode
        self.redeemedAt = redeemedAt
        self.ok = ok
        self.redeemed = redeemed
        self.balance = balance
        self.rewardTitle = rewardTitle
        self.somOff = somOff
        self.errorCode = errorCode
        self.replayed = replayed
    }
}

/// Одноразовый токен списания баллов (ответ `issueRedeemToken`): QR гостя
/// `AYANT-RDT:<token>` несёт только его — без uid (см. `RedeemQR`).
public struct RedeemToken: Equatable, Sendable {
    public let token: String
    public let expiresAt: Date
    /// Сколько баллов спишется (по серверному конфигу награды).
    public let cost: Int
    public init(token: String, expiresAt: Date, cost: Int) {
        self.token = token
        self.expiresAt = expiresAt
        self.cost = cost
    }
}

/// Бэкенд-трекинг купонов + карт лояльности (Firestore) и сканер заведения.
public protocol CouponService {
    /// Токен списания для QR гостя (Cloud Function `issueRedeemToken`).
    /// Ошибки: `AppError.server(code:)` — отказ сервера (`insufficient`,
    /// `reward_not_found`, `anonymous_not_allowed`, `not_deployed` — функции
    /// ещё нет на сервере), `AppError.network` — нет связи.
    func issueRedeemToken(venueID: String, rewardId: String, pointsToSpend: Int,
                          idToken: String) async throws -> RedeemToken
    /// Списание по токену из QR гостя (`AYANT-RDT:`) — гасит сотрудник.
    /// Чья карта, какая награда и сколько баллов — сервер берёт из токена;
    /// ключ идемпотентности — `rdm_<token>`, повторный скан воспроизводит
    /// первое списание (`replayed`).
    func redeemVenuePoints(venueID: String, token: String, idToken: String) async throws -> RedeemOutcome
    /// Пишет купон пользователя в Firestore (deal-купон создаёт клиент).
    func saveCoupon(_ coupon: Coupon, userID: String) async throws
    /// Каталог наград глобального кошелька (config/globalRewards).
    /// Пусто → показывать нечего: награда без партнёра не гасится.
    func fetchGlobalRewards() async throws -> [Reward]
    /// Купоны, которые заведение продаёт за бонусы (`couponOffers` этого
    /// заведения) — для «магазина купонов» на его странице. Все статусы:
    /// что из этого можно купить сейчас, решает `CouponOffer.isAvailable(at:)`.
    func fetchCouponOffers(venueID: String) async throws -> [CouponOffer]
    /// Одобренные купоны всех заведений — витрина «Купоны заведений» во
    /// вкладке «Бонусы». Пауза, остаток и срок отсекаются на клиенте
    /// (`CouponOffer.isAvailable(at:)`) — запрос фильтрует только модерацию.
    func fetchApprovedCouponOffers() async throws -> [CouponOffer]
    /// Купоны пользователя из Firestore (для синка used-статуса и наград).
    func fetchCoupons(userID: String) async throws -> [Coupon]
    /// Живой поток купонов пользователя: сотрудник сканирует (или вводит код)
    /// — купон гасится на сервере, и экран гостя видит это сразу, без
    /// перезапуска. Снапшот-листенер снимается вместе с задачей-потребителем.
    func coupons(userID: String) -> AsyncStream<[Coupon]>
    /// Карты лояльности пользователя из Firestore (разовый запрос).
    func fetchLoyaltyCards(userID: String) async throws -> [LoyaltyCard]
    /// Живой поток карт лояльности: штампы меняет сканер заведения, и экран
    /// должен увидеть это сразу, без опроса. Реализация на Firestore держит
    /// snapshot-листенер; он снимается вместе с задачей-потребителем.
    func loyaltyCards(userID: String) -> AsyncStream<[LoyaltyCard]>
    /// Тот же поток с пометкой «снимок из кэша» (см. `PointsRepository.liveCards`):
    /// детектор штампа берёт точку отсчёта только с серверного снимка.
    func liveLoyaltyCards(userID: String) -> AsyncStream<LiveSnapshot<[LoyaltyCard]>>
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
    /// `nonce` — из QR гостя (`RedeemQR`): при скане сотрудником сервер
    /// берёт ключом `rdm_<nonce>`, и повторный скан того же QR воспроизводит
    /// первое списание. `nil` — старый QR без nonce или списание гостем.
    func redeemVenuePoints(venueID: String, userID: String, rewardId: String,
                           pointsToSpend: Int, idToken: String,
                           idempotencyKey: String, nonce: String?) async throws -> RedeemOutcome
}

public extension CouponService {
    /// Мок-режим и тестовые фейки: токен локальный (сервера нет), чтобы экран
    /// списания работал офлайн. Firebase-реализация переопределяет.
    func issueRedeemToken(venueID: String, rewardId: String, pointsToSpend: Int,
                          idToken: String) async throws -> RedeemToken {
        let raw = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "")
        return RedeemToken(token: String(raw.prefix(32)),
                           expiresAt: SystemClock().now.addingTimeInterval(RedeemQR.tokenTTL),
                           cost: pointsToSpend)
    }

    /// Мок-режим: списания по токену нет — честный отказ, а не тихий успех.
    func redeemVenuePoints(venueID: String, token: String, idToken: String) async throws -> RedeemOutcome {
        RedeemOutcome(ok: false, redeemed: 0, balance: 0, rewardTitle: "", somOff: nil,
                      errorCode: "not_supported")
    }

    /// Источники без кэша (моки, фейки): каждый снимок — серверный.
    func liveLoyaltyCards(userID: String) -> AsyncStream<LiveSnapshot<[LoyaltyCard]>> {
        loyaltyCards(userID: userID).mapped { LiveSnapshot(value: $0, isFromCache: false) }
    }

    /// Прежняя сигнатура — без nonce (списание гостем, старые QR).
    func redeemVenuePoints(venueID: String, userID: String, rewardId: String,
                           pointsToSpend: Int, idToken: String,
                           idempotencyKey: String) async throws -> RedeemOutcome {
        try await redeemVenuePoints(venueID: venueID, userID: userID, rewardId: rewardId,
                                    pointsToSpend: pointsToSpend, idToken: idToken,
                                    idempotencyKey: idempotencyKey, nonce: nil)
    }
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

/// Чей потолок урезал начисление `earnBonus` (поле ответа `capReason`).
public enum BonusEarnCapReason: String, Equatable, Sendable {
    /// Общий дневной потолок кошелька: сегодня не платит ни один источник.
    case daily
    /// Потолок этого источника (Diamond, время): остальные игры платят.
    case source
    /// Слишком крупный вызов — не потолок дня; остаток можно прислать снова.
    case perCall = "per_call"
}

/// Ответ `earnBonus`. `granted` может быть меньше запрошенного — сервер
/// держит потолки (за вызов и за сутки), а `capReason` говорит, какой именно:
/// клиент больше не угадывает «общий или источника» по имени источника.
public struct BonusEarnOutcome: Equatable, Sendable {
    public var ok: Bool
    public var granted: Int
    public var balance: Int
    public var errorCode: String?
    /// `nil` — не урезано или сервер старый (поля нет).
    public var capReason: BonusEarnCapReason?
    /// Сколько ещё можно заработать сегодня по всем источникам; `nil` — сервер старый.
    public var dailyLeft: Int?
    /// Сколько ещё может принести этот источник; `nil` — у него нет своего потолка.
    public var sourceLeft: Int?

    public init(ok: Bool, granted: Int = 0, balance: Int = 0, errorCode: String? = nil,
                capReason: BonusEarnCapReason? = nil, dailyLeft: Int? = nil, sourceLeft: Int? = nil) {
        self.ok = ok; self.granted = granted; self.balance = balance; self.errorCode = errorCode
        self.capReason = capReason; self.dailyLeft = dailyLeft; self.sourceLeft = sourceLeft
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

// MARK: - Личная библиотека в аккаунте (`userLibraries/{uid}`)

/// Сохранённые места, избранные акции, отметки «нравится» и скрытые авторы
/// отзывов — то, что раньше жило только на устройстве и стиралось при выходе,
/// хотя диалог выхода обещал «данные останутся в аккаунте».
public struct UserLibrary: Equatable, Sendable {
    public var savedVenueIDs: Set<String>
    public var favoriteDealIDs: Set<String>
    public var likedDealIDs: Set<String>
    public var blockedAuthorIDs: Set<String>

    /// Потолок длины каждого списка — тот же, что в `firestore.rules`.
    public static let maxItems = 500

    public init(savedVenueIDs: Set<String> = [], favoriteDealIDs: Set<String> = [],
                likedDealIDs: Set<String> = [], blockedAuthorIDs: Set<String> = []) {
        self.savedVenueIDs = savedVenueIDs; self.favoriteDealIDs = favoriteDealIDs
        self.likedDealIDs = likedDealIDs; self.blockedAuthorIDs = blockedAuthorIDs
    }

    /// Объединение двух копий (вход на устройстве с несинхронизированными правками).
    public func union(_ other: UserLibrary) -> UserLibrary {
        UserLibrary(savedVenueIDs: savedVenueIDs.union(other.savedVenueIDs),
                    favoriteDealIDs: favoriteDealIDs.union(other.favoriteDealIDs),
                    likedDealIDs: likedDealIDs.union(other.likedDealIDs),
                    blockedAuthorIDs: blockedAuthorIDs.union(other.blockedAuthorIDs))
    }

    /// Каждый список обрезан до `maxItems` (детерминированно — по сортировке),
    /// иначе правила отвергли бы запись целиком.
    public var capped: UserLibrary {
        func cap(_ s: Set<String>) -> Set<String> {
            s.count <= Self.maxItems ? s : Set(s.sorted().prefix(Self.maxItems))
        }
        return UserLibrary(savedVenueIDs: cap(savedVenueIDs), favoriteDealIDs: cap(favoriteDealIDs),
                           likedDealIDs: cap(likedDealIDs), blockedAuthorIDs: cap(blockedAuthorIDs))
    }
}

/// Жалобы на фото (`reviewReports`, reason "photo"). Реализует `FirebaseDataRepository`;
/// без реализации (мок) жалоба не уходит никуда, как и жалоба на отзыв в моке.
public protocol PhotoReporting {
    func reportPhoto(_ report: PhotoReport) async throws
}

/// Синхронизация личной библиотеки с аккаунтом. Реализует `FirebaseDataRepository`;
/// мок-репозиторий — нет, и тогда библиотека остаётся только на устройстве.
public protocol UserLibrarySyncing {
    /// nil — документа ещё нет.
    func fetchUserLibrary(userID: String) async throws -> UserLibrary?
    func saveUserLibrary(_ library: UserLibrary, userID: String) async throws
}
