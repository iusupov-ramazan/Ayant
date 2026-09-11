import SwiftUI
import AyantDomain

/// Стор профиля — четвёртая фича на новой форме и первая, которая **владеет**
/// своими данными, а не проецирует чужие.
///
/// Личная библиотека (сохранённые заведения, избранные акции, погашенные купоны)
/// живёт здесь и пишется в настройки отсюда. `AppStore` больше не хранит эти
/// множества — он делегирует сюда, поэтому старые вызовы (`isSaved(_:)`,
/// `toggleFavorite(_:)`, `hasVisited(_:)`) продолжают работать без правок вызывающих.
///
/// Ключи хранилища load-bearing: их читают уже установленные приложения
/// (см. `ProfileStorageKey`).
///
/// Зеркалит `ProfileViewModel.kt` на Android.
@MainActor
public final class ProfileStore: ObservableObject {
    @Published public private(set) var state = ProfileState()

    private let storage: ProfileStorage

    /// Хранилище — обязательный параметр: дефолт поверх `UserDefaults` читал бы
    /// настоящие настройки устройства мимо подставленного в тесте `prefs`.
    public init(storage: ProfileStorage) {
        self.storage = storage
        state.savedVenueIDs = storage.loadIDs(key: ProfileStorageKey.savedVenues)
        state.favoriteDealIDs = storage.loadIDs(key: ProfileStorageKey.favoriteDeals)
        state.redeemedDealIDs = storage.loadIDs(key: ProfileStorageKey.redeemedDeals)
        state.likedDealIDs = storage.loadIDs(key: ProfileStorageKey.likedDeals)
    }

    public func send(_ intent: ProfileIntent) {
        switch intent {
        case .setUser(let id, let name, let isGuest):
            state.userID = id
            state.userName = name
            state.isGuest = isGuest

        case .toggleSave(let venueID):
            guard state.canContribute else { return }
            toggle(&state.savedVenueIDs, venueID, key: ProfileStorageKey.savedVenues)

        case .unsaveVenue(let venueID):
            state.savedVenueIDs.remove(venueID)
            storage.saveIDs(state.savedVenueIDs, key: ProfileStorageKey.savedVenues)

        case .toggleFavorite(let dealID):
            guard state.canContribute else { return }
            toggle(&state.favoriteDealIDs, dealID, key: ProfileStorageKey.favoriteDeals)

        case .toggleLike(let dealID):
            // Лайк — тоже действие аккаунта: он кормит ранжирование и должен
            // переезжать с пользователем на другое устройство. Раньше гостю
            // разрешалось лайкать «потому что лайк локальный» — на деле лайки
            // оставались на устройстве и доставались следующему вошедшему.
            guard state.canContribute else { return }
            toggle(&state.likedDealIDs, dealID, key: ProfileStorageKey.likedDeals)

        case .unsaveDeal(let dealID):
            state.favoriteDealIDs.remove(dealID)
            storage.saveIDs(state.favoriteDealIDs, key: ProfileStorageKey.favoriteDeals)

        case .markRedeemed(let dealID):
            guard !state.redeemedDealIDs.contains(dealID) else { return }
            state.redeemedDealIDs.insert(dealID)
            storage.saveIDs(state.redeemedDealIDs, key: ProfileStorageKey.redeemedDeals)
        }
    }

    /// Стирает личную библиотеку при смене пользователя.
    /// Ключи хранилища общие для устройства, поэтому без этого сохранённые
    /// места и избранные акции переходят следующему вошедшему.
    public func resetForNewUser() {
        state.savedVenueIDs = []
        state.favoriteDealIDs = []
        state.redeemedDealIDs = []
        state.likedDealIDs = []
        storage.saveIDs([], key: ProfileStorageKey.savedVenues)
        storage.saveIDs([], key: ProfileStorageKey.favoriteDeals)
        storage.saveIDs([], key: ProfileStorageKey.redeemedDeals)
        storage.saveIDs([], key: ProfileStorageKey.likedDeals)
    }

    private func toggle(_ set: inout Set<String>, _ id: String, key: String) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        storage.saveIDs(set, key: key)
    }
}

/// Хранилище личной библиотеки поверх `UserDefaults` (через общий
/// `LocalPreferencesStore`, чтобы тест мог подставить in-memory реализацию).
public struct UserDefaultsProfileStorage: ProfileStorage {
    private let prefs: LocalPreferencesStore

    public init(prefs: LocalPreferencesStore) {
        self.prefs = prefs
    }

    public func loadIDs(key: String) -> Set<String> { prefs.stringSet(forKey: key) }
    public func saveIDs(_ ids: Set<String>, key: String) { prefs.setStringSet(ids, forKey: key) }
}
