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

    /// Авторы, чьи отзывы пользователь скрыл («Скрыть отзывы автора»,
    /// Guidelines 1.2 — блокировка пользователей). Отзывы этих авторов не
    /// показываются нигде: `AppStore.reviews` фильтрует их на входе.
    @Published public private(set) var blockedAuthorIDs: Set<String> = []
    /// Имена скрытых авторов — только для списка «Скрытые авторы» в профиле.
    /// Живут на устройстве; в аккаунт уходят одни id.
    @Published public private(set) var blockedAuthorNames: [String: String] = [:]

    private let storage: ProfileStorage
    /// Синхронизация с `userLibraries/{uid}`. nil — мок-режим: библиотека
    /// только на устройстве, как раньше.
    private let library: UserLibrarySyncing?
    /// Пауза перед записью: серия переключений уходит одной записью.
    private let writeDelay: Duration

    /// Пользователь, с которым библиотека уже сведена (после неё правки пишутся).
    private var syncedUserID: String?
    private var syncingUserID: String?
    private var writeTask: Task<Void, Never>?
    /// Растёт на каждой правке: запись, обогнанная новой правкой, не снимает «грязь».
    private var changeGeneration = 0

    /// Ключи, которыми стор помечает своё хранилище. Load-bearing, как и
    /// `ProfileStorageKey`: их читают уже установленные приложения.
    enum LibraryKey {
        static let blockedAuthors = "san.blockedAuthors"
        /// Элементы `id␟имя` — множество строк, другого хранилище не умеет.
        static let blockedAuthorNames = "san.blockedAuthorNames"
        /// uid, которому принадлежит локальная библиотека (один элемент).
        static let owner = "san.library.owner"
        /// Непустое — есть правки, которых сервер ещё не видел.
        static let dirty = "san.library.dirty"
    }
    private static let nameSeparator: Character = "\u{1F}"

    /// Хранилище — обязательный параметр: дефолт поверх `UserDefaults` читал бы
    /// настоящие настройки устройства мимо подставленного в тесте `prefs`.
    public init(storage: ProfileStorage,
                library: UserLibrarySyncing? = nil,
                writeDelay: Duration = .milliseconds(800)) {
        self.storage = storage
        self.library = library
        self.writeDelay = writeDelay
        state.savedVenueIDs = storage.loadIDs(key: ProfileStorageKey.savedVenues)
        state.favoriteDealIDs = storage.loadIDs(key: ProfileStorageKey.favoriteDeals)
        state.redeemedDealIDs = storage.loadIDs(key: ProfileStorageKey.redeemedDeals)
        state.likedDealIDs = storage.loadIDs(key: ProfileStorageKey.likedDeals)
        blockedAuthorIDs = storage.loadIDs(key: LibraryKey.blockedAuthors)
        for entry in storage.loadIDs(key: LibraryKey.blockedAuthorNames) {
            let parts = entry.split(separator: Self.nameSeparator, maxSplits: 1).map(String.init)
            if parts.count == 2 { blockedAuthorNames[parts[0]] = parts[1] }
        }
    }

    public func send(_ intent: ProfileIntent) {
        switch intent {
        case .setUser(let id, let name, let isGuest):
            state.userID = id
            state.userName = name
            state.isGuest = isGuest
            // Вызывается часто (каждое возвращение в приложение, экран профиля) —
            // сведение с сервером идёт один раз на пользователя.
            if library != nil, state.canContribute, syncedUserID != id, syncingUserID != id {
                Task { await syncLibrary() }
            }

        case .toggleSave(let venueID):
            guard state.canContribute else { return }
            toggle(&state.savedVenueIDs, venueID, key: ProfileStorageKey.savedVenues)
            libraryChanged()

        case .unsaveVenue(let venueID):
            state.savedVenueIDs.remove(venueID)
            storage.saveIDs(state.savedVenueIDs, key: ProfileStorageKey.savedVenues)
            libraryChanged()

        case .toggleFavorite(let dealID):
            guard state.canContribute else { return }
            toggle(&state.favoriteDealIDs, dealID, key: ProfileStorageKey.favoriteDeals)
            libraryChanged()

        case .toggleLike(let dealID):
            // Лайк — тоже действие аккаунта: он кормит ранжирование и должен
            // переезжать с пользователем на другое устройство. Раньше гостю
            // разрешалось лайкать «потому что лайк локальный» — на деле лайки
            // оставались на устройстве и доставались следующему вошедшему.
            guard state.canContribute else { return }
            toggle(&state.likedDealIDs, dealID, key: ProfileStorageKey.likedDeals)
            libraryChanged()

        case .unsaveDeal(let dealID):
            state.favoriteDealIDs.remove(dealID)
            storage.saveIDs(state.favoriteDealIDs, key: ProfileStorageKey.favoriteDeals)
            libraryChanged()

        case .markRedeemed(let dealID):
            guard !state.redeemedDealIDs.contains(dealID) else { return }
            state.redeemedDealIDs.insert(dealID)
            storage.saveIDs(state.redeemedDealIDs, key: ProfileStorageKey.redeemedDeals)
        }
    }

    /// Стирает личную библиотеку при смене пользователя.
    /// Ключи хранилища общие для устройства, поэтому без этого сохранённые
    /// места и избранные акции переходят следующему вошедшему.
    ///
    /// С синхронизацией это больше не потеря: библиотека лежит в
    /// `userLibraries/{uid}` и вернётся при следующем входе.
    public func resetForNewUser() {
        writeTask?.cancel()
        writeTask = nil
        syncedUserID = nil
        syncingUserID = nil
        // Пользователя больше нет: отложенное сведение (`Task` из `.setUser`)
        // не должно скачать его библиотеку обратно на устройство.
        state.userID = ""
        state.userName = ""
        state.isGuest = true
        wipeLocalLibrary()
        storage.saveIDs([], key: LibraryKey.owner)
    }

    // MARK: - Скрытые авторы

    public func isBlocked(authorID: String) -> Bool { blockedAuthorIDs.contains(authorID) }

    /// Скрыть все отзывы автора. Доступно и гостю (локально): защита от
    /// оскорблений не должна упираться в регистрацию.
    public func blockAuthor(id: String, name: String) {
        guard !id.isEmpty, id != state.userID, !blockedAuthorIDs.contains(id) else { return }
        blockedAuthorIDs.insert(id)
        let clean = name.replacingOccurrences(of: String(Self.nameSeparator), with: " ")
        if !clean.isEmpty { blockedAuthorNames[id] = clean }
        persistBlocked()
        libraryChanged()
    }

    public func unblockAuthor(id: String) {
        guard blockedAuthorIDs.remove(id) != nil else { return }
        blockedAuthorNames[id] = nil
        persistBlocked()
        libraryChanged()
    }

    private func persistBlocked() {
        storage.saveIDs(blockedAuthorIDs, key: LibraryKey.blockedAuthors)
        storage.saveIDs(Set(blockedAuthorNames.map { "\($0.key)\(Self.nameSeparator)\($0.value)" }),
                        key: LibraryKey.blockedAuthorNames)
    }

    // MARK: - Синхронизация с аккаунтом

    private var currentLibrary: UserLibrary {
        UserLibrary(savedVenueIDs: state.savedVenueIDs, favoriteDealIDs: state.favoriteDealIDs,
                    likedDealIDs: state.likedDealIDs, blockedAuthorIDs: blockedAuthorIDs)
    }

    private var isDirty: Bool { !storage.loadIDs(key: LibraryKey.dirty).isEmpty }
    private func setDirty(_ dirty: Bool) {
        storage.saveIDs(dirty ? ["1"] : [], key: LibraryKey.dirty)
    }

    /// Сводит локальную библиотеку с аккаунтом. Зовётся сам при `.setUser`;
    /// открыт для тестов.
    ///
    /// Правила слияния:
    ///  • локальная библиотека чужого uid (вход в другой аккаунт без выхода) —
    ///    стирается, а не смешивается с новой;
    ///  • есть неотправленные правки (или библиотека с версии до синхронизации,
    ///    без владельца) — объединение локальной и серверной;
    ///  • иначе сервер — источник правды: удалённое на другом устройстве
    ///    исчезает и здесь, а не воскресает объединением.
    public func syncLibrary() async {
        guard let library, state.canContribute else { return }
        let uid = state.userID
        guard syncedUserID != uid, syncingUserID != uid else { return }
        syncingUserID = uid
        defer { if syncingUserID == uid { syncingUserID = nil } }

        let owner = storage.loadIDs(key: LibraryKey.owner).first
        if let owner, owner != uid { wipeLocalLibrary() }
        let legacyLocal = owner == nil && currentLibrary != UserLibrary()
        do {
            let remote = try await library.fetchUserLibrary(userID: uid)
            guard state.userID == uid, syncingUserID == uid else { return }
            let merged: UserLibrary
            if let remote, !(isDirty || legacyLocal) {
                merged = remote
            } else {
                merged = currentLibrary.union(remote ?? UserLibrary()).capped
            }
            apply(merged)
            storage.saveIDs([uid], key: LibraryKey.owner)
            syncedUserID = uid
            if merged != remote {
                await flush(userID: uid)
            } else {
                setDirty(false)
            }
        } catch {
            // Сеть/правила: правки остаются «грязными», повтор — при следующем
            // `.setUser` (каждое возвращение в приложение).
            setDirty(isDirty || legacyLocal)
        }
    }

    /// Немедленная запись (тесты; уход с экрана).
    public func flushLibrary() async {
        guard let uid = syncedUserID, uid == state.userID else { return }
        writeTask?.cancel()
        writeTask = nil
        await flush(userID: uid)
    }

    private func libraryChanged() {
        changeGeneration += 1
        guard library != nil else { return }
        setDirty(true)
        // До сведения с сервером не пишем: частичная локальная копия затёрла
        // бы аккаунт. Правка не теряется — `syncLibrary` объединит.
        guard let uid = syncedUserID, uid == state.userID else { return }
        writeTask?.cancel()
        let delay = writeDelay
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.flush(userID: uid)
        }
    }

    private func flush(userID uid: String) async {
        guard let library, state.userID == uid else { return }
        let generation = changeGeneration
        do {
            try await library.saveUserLibrary(currentLibrary.capped, userID: uid)
            if generation == changeGeneration, state.userID == uid { setDirty(false) }
        } catch {
            setDirty(true)
        }
    }

    private func apply(_ lib: UserLibrary) {
        state.savedVenueIDs = lib.savedVenueIDs
        state.favoriteDealIDs = lib.favoriteDealIDs
        state.likedDealIDs = lib.likedDealIDs
        storage.saveIDs(lib.savedVenueIDs, key: ProfileStorageKey.savedVenues)
        storage.saveIDs(lib.favoriteDealIDs, key: ProfileStorageKey.favoriteDeals)
        storage.saveIDs(lib.likedDealIDs, key: ProfileStorageKey.likedDeals)
        if lib.blockedAuthorIDs != blockedAuthorIDs {
            blockedAuthorIDs = lib.blockedAuthorIDs
            blockedAuthorNames = blockedAuthorNames.filter { lib.blockedAuthorIDs.contains($0.key) }
            persistBlocked()
        }
    }

    private func wipeLocalLibrary() {
        state.savedVenueIDs = []
        state.favoriteDealIDs = []
        state.redeemedDealIDs = []
        state.likedDealIDs = []
        blockedAuthorIDs = []
        blockedAuthorNames = [:]
        storage.saveIDs([], key: ProfileStorageKey.savedVenues)
        storage.saveIDs([], key: ProfileStorageKey.favoriteDeals)
        storage.saveIDs([], key: ProfileStorageKey.redeemedDeals)
        storage.saveIDs([], key: ProfileStorageKey.likedDeals)
        persistBlocked()
        setDirty(false)
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
