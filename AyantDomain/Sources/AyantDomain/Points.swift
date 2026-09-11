import Foundation

// Фича «Баллы САН»: состояние, намерения и контракт данных.
// Имена полей совпадают с `Points.kt` в `android/domain` — это сознательно.

// MARK: - Модель карты

/// Карта баллов гостя в конкретном заведении.
///
/// Баланс — server-authoritative: его пишут только Cloud Functions
/// (`venuePoints/{userID}_{venueID}`). Клиент читает и показывает.
public struct VenuePointsCard: Identifiable, Codable, Hashable, Sendable {
    public var id: String { venueID }
    public var venueID: String
    public var venueName: String
    public var balance: Int = 0
    public var lifetimeEarned: Int = 0
    public var lifetimeRedeemed: Int = 0

    public init(venueID: String, venueName: String, balance: Int = 0,
                lifetimeEarned: Int = 0, lifetimeRedeemed: Int = 0) {
        self.venueID = venueID; self.venueName = venueName; self.balance = balance
        self.lifetimeEarned = lifetimeEarned; self.lifetimeRedeemed = lifetimeRedeemed
    }
}

/// Что произошло при списании (ответ `redeemVenuePoints`).
public struct RedeemReceipt: Equatable, Sendable {
    public let redeemed: Int
    public let balance: Int
    public let rewardTitle: String
    /// Скидка в сомах — только для награды типа `money`.
    public let somOff: Int?
    /// `true` — запрос с этим ключом уже выполнялся, баллы повторно НЕ списаны.
    public let replayed: Bool

    public init(redeemed: Int, balance: Int, rewardTitle: String,
                somOff: Int? = nil, replayed: Bool = false) {
        self.redeemed = redeemed; self.balance = balance; self.rewardTitle = rewardTitle
        self.somOff = somOff; self.replayed = replayed
    }
}

// MARK: - История баллов

/// Одна запись журнала карты (`venuePoints/{card}/ledger`): начисление за визит,
/// списание на награду или сгорание. Пишет только сервер; клиент читает.
public struct PointsLedgerEntry: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case earn, redeem, expire, unknown
    }

    public let id: String
    public let kind: Kind
    /// Со знаком: начисление положительное, списание и сгорание — отрицательные.
    public let points: Int
    public let at: Date
    /// Сумма чека при начислении (кэшбэк/диапазоны); у фикса — nil.
    public let billAmount: Int?
    /// Награда при списании; название подставляет экран по конфигу заведения.
    public let rewardID: String?

    public init(id: String, kind: Kind, points: Int, at: Date,
                billAmount: Int? = nil, rewardID: String? = nil) {
        self.id = id; self.kind = kind; self.points = points; self.at = at
        self.billAmount = billAmount; self.rewardID = rewardID
    }
}

// MARK: - Состояние

/// Всё состояние экрана баллов — одним значением.
///
/// Вьюха — чистая функция от него: никаких «а если карточки ещё nil, но ошибки
/// уже нет». `cards` держит и загрузку, и ошибку (см. `LoadState`).
public struct PointsState: Equatable, Sendable {
    /// Пусто — гость не авторизован; копить и тратить баллы нельзя.
    public var userID: String = ""
    public var cards: LoadState<[VenuePointsCard]> = .idle
    public var redeem: RedeemPhase = .idle
    /// История по заведениям, новые сверху. Грузится по запросу экрана
    /// (`loadHistory`), а не вместе с картами: журнал длиннее и нужен реже.
    public var history: [String: LoadState<[PointsLedgerEntry]>] = [:]

    public init(userID: String = "",
                cards: LoadState<[VenuePointsCard]> = .idle,
                redeem: RedeemPhase = .idle,
                history: [String: LoadState<[PointsLedgerEntry]>] = [:]) {
        self.userID = userID; self.cards = cards; self.redeem = redeem; self.history = history
    }

    public func history(for venueID: String) -> LoadState<[PointsLedgerEntry]> {
        history[venueID] ?? .idle
    }

    public var isSignedIn: Bool { !userID.isEmpty }

    public func card(for venueID: String) -> VenuePointsCard? {
        cards.value?.first { $0.venueID == venueID }
    }

    public func balance(for venueID: String) -> Int { card(for: venueID)?.balance ?? 0 }

    /// Карты в порядке показа: сначала с большим балансом.
    public var sortedCards: [VenuePointsCard] {
        (cards.value ?? []).sorted { $0.balance > $1.balance }
    }
}

/// Фаза списания. Отдельно от `cards`, потому что список остаётся видимым,
/// пока идёт списание.
public enum RedeemPhase: Equatable, Sendable {
    case idle
    case working(rewardID: String)
    case done(RedeemReceipt)
    case failed(AppError)

    public var isWorking: Bool {
        if case .working = self { return true }
        return false
    }
}

// MARK: - Намерения

/// Единственный вход в стор. Вьюха не зовёт методы по одному — она отправляет
/// намерение, а стор решает, что с ним делать.
public enum PointsIntent: Equatable, Sendable {
    /// Подписаться на живые обновления карт гостя (заменяет опрос раз в 4 с).
    case observe(userID: String)
    /// Отписаться (экран закрыт).
    case stop
    /// Списать баллы на награду. `pointsToSpend` важен только для `money`-награды.
    case redeem(venueID: String, rewardID: String, pointsToSpend: Int)
    /// Закрыть результат/ошибку списания.
    case dismissRedeem
    /// Загрузить (или обновить) историю начислений и списаний по заведению.
    case loadHistory(venueID: String)
}

// MARK: - Контракт данных

/// Источник карт баллов и операции списания.
///
/// Чтение — поток: реализация на Firestore держит snapshot-листенер, поэтому
/// баланс обновляется сам, когда сотрудник просканировал QR. Никакого опроса.
///
/// Запись идёт только через Cloud Function: `venuePoints` клиенту писать запрещено
/// правилами, и это единственная защита от накрутки баланса.
public protocol PointsRepository {
    /// Живой поток карт гостя. Поток завершается, когда задача-потребитель отменена.
    func cards(userID: String) -> AsyncStream<Result<[VenuePointsCard], AppError>>

    /// Списание баллов на награду.
    ///
    /// - Parameter idempotencyKey: генерируется клиентом ОДИН раз на попытку и
    ///   переиспользуется при повторе. Сервер вернёт тот же результат вместо
    ///   второго списания (`RedeemReceipt.replayed == true`).
    func redeem(venueID: String, userID: String, rewardID: String,
                pointsToSpend: Int, idempotencyKey: String) async -> Result<RedeemReceipt, AppError>

    /// Журнал карты гостя в заведении, новые записи сверху, не больше `limit`.
    func ledger(userID: String, venueID: String, limit: Int) async -> Result<[PointsLedgerEntry], AppError>
}

// MARK: - Одна механика лояльности на заведение

/// Что именно заведение даёт гостю за визит.
///
/// Механика ровно ОДНА. Пока `pointsEnabled` и `loyaltyEnabled` были независимы,
/// заведение могло включить обе: гость видел на странице и карточку баллов, и
/// баннер штампов, и по одному скану не мог понять, что ему начислили, — а
/// заведение платило дважды за один визит.
///
/// Приоритет у баллов: их настраивает админ-панель и они привязаны к деньгам
/// (1 балл = 1 сом), тогда как штампы — более простая надстройка заведения.
public enum LoyaltyKind: String, Sendable {
    case points, stamps, none

    /// Действующая механика заведения. Единственный источник правды для обеих
    /// платформ и для Cloud Functions.
    public static func active(pointsEnabled: Bool, loyaltyEnabled: Bool) -> LoyaltyKind {
        if pointsEnabled { return .points }
        if loyaltyEnabled { return .stamps }
        return .none
    }
}

public extension Venue {
    /// Действующая механика лояльности этого заведения.
    var loyaltyKind: LoyaltyKind {
        LoyaltyKind.active(pointsEnabled: pointsEnabled, loyaltyEnabled: loyaltyEnabled)
    }
    /// Штампы работают, только если баллы выключены.
    var stampsActive: Bool { loyaltyKind == .stamps }
    /// Баллы работают.
    var pointsActive: Bool { loyaltyKind == .points }
}
