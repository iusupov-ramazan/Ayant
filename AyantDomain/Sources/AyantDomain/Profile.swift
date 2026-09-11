import Foundation

// Фича «Профиль» — личная библиотека пользователя: сохранённые заведения,
// избранные акции, погашенные купоны, свои отзывы.
// Имена полей совпадают с `Profile.kt` в `android/domain`.

/// Состояние профиля одним значением.
///
/// Здесь лежат **только идентификаторы** — сами заведения и акции живут в
/// каталоге. Списки собираются функциями (`savedVenues(in:)`), поэтому не могут
/// разъехаться с каталогом: удалённое заведение просто перестаёт находиться.
///
/// В отличие от ленты и карточки заведения, этот стор — **владелец** своих
/// данных: он их читает из хранилища настроек и пишет обратно.
public struct ProfileState: Equatable {
    public var userID: String = ""
    public var userName: String = ""
    public var isGuest: Bool = true

    public var savedVenueIDs: Set<String> = []
    public var favoriteDealIDs: Set<String> = []
    /// Отметки «нравится» на акциях.
    ///
    /// Отдельно от `favoriteDealIDs`: закладка кладёт акцию в «Сохранённое»,
    /// сердечко — только реакция. В ленте это две разные кнопки, и склеивать их
    /// нельзя: человек лайкает много, а сохраняет то, куда собирается пойти.
    /// Живёт на устройстве — общего счётчика лайков на сервере нет.
    public var likedDealIDs: Set<String> = []
    /// Погашенные купоны — по ним считается «был в заведении» для отзыва.
    public var redeemedDealIDs: Set<String> = []

    public init(userID: String = "", userName: String = "", isGuest: Bool = true,
                savedVenueIDs: Set<String> = [], favoriteDealIDs: Set<String> = [],
                redeemedDealIDs: Set<String> = [], likedDealIDs: Set<String> = []) {
        self.userID = userID; self.userName = userName; self.isGuest = isGuest
        self.savedVenueIDs = savedVenueIDs; self.favoriteDealIDs = favoriteDealIDs
        self.redeemedDealIDs = redeemedDealIDs; self.likedDealIDs = likedDealIDs
    }

    // MARK: - Проверки

    public func isSaved(_ venueID: String) -> Bool { savedVenueIDs.contains(venueID) }
    public func isLiked(_ dealID: String) -> Bool { likedDealIDs.contains(dealID) }
    public func isFavorite(_ dealID: String) -> Bool { favoriteDealIDs.contains(dealID) }
    public func hasRedeemed(_ dealID: String) -> Bool { redeemedDealIDs.contains(dealID) }

    /// Был ли пользователь в заведении — то есть гасил ли там купон.
    /// Отзыв такого автора помечается как проверенный визит.
    public func hasVisited(venueID: String, in catalog: FeedCatalog) -> Bool {
        catalog.deals.contains { $0.venueID == venueID && redeemedDealIDs.contains($0.id) }
    }

    /// Гость не может сохранять и писать отзывы.
    public var canContribute: Bool { !isGuest && !userID.isEmpty }

    /// Реферальный код — это и есть id пользователя.
    public var referralCode: String { userID }

    // MARK: - Списки (сборка по каталогу)

    /// Сохранённые заведения в порядке каталога. Исчезнувшие из каталога
    /// пропускаются — id остаётся, но показывать нечего.
    public func savedVenues(in catalog: FeedCatalog) -> [Venue] {
        catalog.venues.filter { savedVenueIDs.contains($0.id) }
    }

    /// Избранные акции; протухшие не показываем.
    public func favoriteDeals(in catalog: FeedCatalog, now: Date) -> [Deal] {
        catalog.deals
            .filter { favoriteDealIDs.contains($0.id) && $0.isActive(at: now) }
            .sorted { $0.validUntil < $1.validUntil }
    }

    /// Отзывы, написанные этим пользователем, — новые сверху.
    public func myReviews(from reviews: [Review]) -> [Review] {
        guard !userID.isEmpty else { return [] }
        return reviews.filter { $0.authorID == userID }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

/// Единственный вход в стор профиля.
public enum ProfileIntent: Equatable {
    case setUser(id: String, name: String, isGuest: Bool)
    case toggleSave(venueID: String)
    case unsaveVenue(venueID: String)
    case toggleFavorite(dealID: String)
    case toggleLike(dealID: String)
    case unsaveDeal(dealID: String)
    /// Купон погашен — запоминаем, чтобы отзыв пометился проверенным визитом.
    case markRedeemed(dealID: String)
}

/// Хранилище личной библиотеки между запусками.
///
/// Ключи load-bearing: их читают уже установленные приложения, переименование
/// потеряет пользовательские данные.
public protocol ProfileStorage {
    func loadIDs(key: String) -> Set<String>
    func saveIDs(_ ids: Set<String>, key: String)
}

public enum ProfileStorageKey {
    // ВНИМАНИЕ: значения совпадают с тем, что уже лежит на устройствах
    // пользователей. Переименование = потеря сохранённых заведений и избранного.
    public static let savedVenues = "san.savedVenues"
    public static let favoriteDeals = "san.favorites"
    public static let redeemedDeals = "san.redeemed"
    public static let likedDeals = "san.liked"
}
