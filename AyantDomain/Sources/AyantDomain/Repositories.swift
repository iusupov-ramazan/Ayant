import Foundation

/// Контракт источника каталога — заведения, акции, отзывы.
///
/// Живёт в домене, реализации — в приложении (`MockDataRepository` на локальных
/// данных, `FirebaseDataRepository` на Firestore). Так зависимость направлена
/// внутрь: домен знает, ЧТО ему нужно, и ничего не знает о Firebase.
///
/// Зеркалит `DataRepository.kt` в `android/domain`.
public protocol DataRepository {
    func fetchVenues() async throws -> [Venue]
    func fetchDeals() async throws -> [Deal]

    // MARK: Отзывы — только ограниченные выборки
    //
    // Раньше здесь был `fetchReviews()` без аргументов: он выгружал ВСЮ коллекцию
    // на каждом холодном старте, и на каталоге в 1000 бизнесов это была главная
    // статья расходов Firestore (см. docs/design/system-design.md §2, B2).
    // Метода «дай все отзывы» больше нет намеренно — его отсутствие не даёт
    // случайно вернуть тот же запрос. Рейтинг для ленты приходит готовым на
    // документе заведения (его считает Cloud Function `aggregateReviewRating`),
    // а сами отзывы грузятся тремя ограниченными выборками ниже.

    /// Отзывы одного заведения, свежие сверху. Для карточки заведения.
    func fetchReviews(venueID: String, limit: Int) async throws -> [Review]
    /// Отзывы группы заведений — инбокс владельца (его заведения).
    func fetchReviews(venueIDs: [String], limit: Int) async throws -> [Review]
    /// Отзывы, написанные пользователем. Для профиля.
    func fetchReviews(authorID: String, limit: Int) async throws -> [Review]
    /// Публикация отзыва пользователя в Firestore (коллекция reviews).
    func saveReview(_ review: Review) async throws
    func deleteReview(id: String) async throws
    /// Ответ владельца — обновляет поле hostReply в документе отзыва.
    func updateReviewReply(reviewID: String, reply: HostReply?) async throws
    /// Погашение купона (серверный счётчик + анти-абуз). Детерминированный id.
    func logRedemption(userID: String, dealID: String, venueID: String) async throws
    /// Запись реферала: пригласивший → приглашённый.
    func recordReferral(inviteeID: String, referrerID: String) async throws
    /// Забирает начисленные сервером бонусы (рефералка) и помечает claimed. Возвращает сумму.
    func claimBonusGrants(userID: String) async throws -> Int
    /// Создаёт подарочный купон (giftCoupons/{code}) — можно отправить другому пользователю.
    func createGiftCoupon(title: String, code: String, fromName: String) async throws
    /// Забирает подарок по коду (один раз). nil — если уже забран или не найден.
    func claimGiftCoupon(code: String) async throws -> GiftInfo?
    /// Гибкий список категорий заведений (управляется из админки).
    /// Пустой массив → приложение остаётся на встроенных категориях.
    func fetchCategories() async throws -> [RemoteCategory]
    /// Опубликованные веса ранжирования (config/rankingWeights). nil → дефолты
    /// `RankingWeights`. Ключи — как у тренера (W_RATING, …). См. ml/README.md.
    func fetchRankingWeights() async throws -> [String: Double]?
}

/// Дефолт: веса не опубликованы (стабы/старые реализации остаются на `.default`).
/// Только `FirebaseDataRepository` реально читает config/rankingWeights.
extension DataRepository {
    public func fetchRankingWeights() async throws -> [String: Double]? { nil }
}

/// Данные забранного подарочного купона.
public struct GiftInfo: Equatable, Sendable {
    public let title: String
    public let code: String

    public init(title: String, code: String) {
        self.title = title; self.code = code
    }
}

/// Категория из бэкенда (коллекция `categories`).
public struct RemoteCategory: Equatable, Sendable {
    public let slug: String
    public let name: String
    public let icon: String
    public let emoji: String
    public let order: Int
    public let enabled: Bool

    public init(slug: String, name: String, icon: String, emoji: String, order: Int, enabled: Bool) {
        self.slug = slug; self.name = name; self.icon = icon
        self.emoji = emoji; self.order = order; self.enabled = enabled
    }
}
