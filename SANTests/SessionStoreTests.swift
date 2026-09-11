import XCTest
import AuthenticationServices
@testable import SAN
import AyantDomain
import AyantFeatures

/// Вход должен ЗАВЕРШАТЬСЯ. Экран входа — единственная дверь в приложение, и
/// «кнопка нажимается, но ничего не происходит» здесь стоит дороже любой другой
/// поломки: пользователь не может даже начать.
@MainActor
final class SessionStoreTests: XCTestCase {

    /// Фальшивый сервис: отвечает мгновенно и запоминает вызовы.
    /// Живёт в тестах, а не в слое данных (тот тянет за собой Firestore).
    private final class FakeAuth: AuthService {
        var stored: SANUser?
        var discardedGuest = false
        var deleted = false
        /// Продолжение потока — тест может «прислать» восстановленную сессию.
        var continuation: AsyncStream<SANUser?>.Continuation?

        func currentUser() -> SANUser? { stored }

        func userChanges() -> AsyncStream<SANUser?> {
            AsyncStream { continuation in
                self.continuation = continuation
                continuation.yield(self.stored)
            }
        }

        func idToken() async -> String? { "token" }

        func signInWithEmail(_ email: String, password: String) async throws -> SANUser {
            let user = SANUser(id: "u1", name: "Тест", email: email, provider: .email)
            stored = user
            return user
        }

        func registerWithEmail(name: String, email: String, password: String) async throws -> SANUser {
            let user = SANUser(id: "u1", name: name, email: email, provider: .email)
            stored = user
            return user
        }

        func signInWithGoogle() async throws -> SANUser {
            throw AuthError.notConfigured("Google")
        }

        func signInWithApple(_ credential: AppleCredential) async throws -> SANUser {
            throw AuthError.cancelled
        }

        func continueAsGuest() async throws -> SANUser {
            let user = SANUser(id: "guest", name: "Гость", email: nil, provider: .guest)
            stored = user
            return user
        }

        func signOut() { stored = nil }
        func deleteAccount() async throws { deleted = true; stored = nil }
        func discardGuestAccount() async { discardedGuest = true; stored = nil }
    }

    /// Ждём, пока условие станет истинным, но не дольше таймаута: операции
    /// стора асинхронные, а тест не должен зависеть от их скорости.
    private func waitUntil(_ timeout: TimeInterval = 2,
                           _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("Условие не выполнилось за \(timeout) с"); return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testGuestSignInCompletes() async throws {
        let store = SessionStore(service: FakeAuth())
        XCTAssertFalse(store.isSignedIn)

        store.continueAsGuest()

        try await waitUntil { store.isSignedIn }
        XCTAssertTrue(store.isGuest)
        XCTAssertFalse(store.isWorking, "Спиннер обязан гаснуть после входа")
        XCTAssertNil(store.errorMessage)
    }

    func testEmailSignInCompletes() async throws {
        let store = SessionStore(service: FakeAuth())

        store.signInEmail("user@mail.ru", "123456")

        try await waitUntil { store.isSignedIn }
        XCTAssertEqual(store.user?.email, "user@mail.ru")
        XCTAssertFalse(store.isGuest)
        XCTAssertFalse(store.isWorking)
    }

    /// Выход гостя удаляет анонимную запись: войти в неё повторно нельзя.
    func testSignOutDiscardsGuestAccount() async throws {
        let service = FakeAuth()
        let store = SessionStore(service: service)
        store.continueAsGuest()
        try await waitUntil { store.isSignedIn }

        store.signOut()

        try await waitUntil { !store.isSignedIn }
        XCTAssertTrue(service.discardedGuest)
    }

    /// Обычный аккаунт при выходе НЕ удаляется — в него ещё возвращаться.
    func testSignOutKeepsRealAccount() async throws {
        let service = FakeAuth()
        let store = SessionStore(service: service)
        store.signInEmail("user@mail.ru", "123456")
        try await waitUntil { store.isSignedIn }

        store.signOut()

        try await waitUntil { !store.isSignedIn }
        XCTAssertFalse(service.discardedGuest)
    }

    /// Firebase поднимает сессию асинхронно: пришедшее позже значение обязано
    /// оказаться в сторе, иначе вошедший пользователь видит экран входа.
    func testLateRestoreFromProviderLandsInStore() async throws {
        let service = FakeAuth()
        let store = SessionStore(service: service)
        XCTAssertFalse(store.isSignedIn)

        // Подписка стартует в `init` отдельной задачей — дожидаемся её, иначе
        // тест «пришлёт» значение в ещё не созданный поток.
        try await waitUntil { service.continuation != nil }
        // Провайдер сначала МЕНЯЕТ своё состояние и только потом уведомляет —
        // стор читает у него свежее значение, а не то, что принёс поток.
        let restored = SANUser(id: "u9", name: "Восстановлен", email: "a@b.kg", provider: .email)
        service.stored = restored
        service.continuation?.yield(restored)

        try await waitUntil { store.isSignedIn }
        XCTAssertEqual(store.user?.id, "u9")
    }

    // MARK: Apple

    /// Отмену в шторке Apple молчим — это не ошибка.
    func testAppleCancelIsSilent() async throws {
        let store = SessionStore(service: FakeAuth())
        store.handleApple(.failure(ASAuthorizationError(.canceled)))
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isSignedIn)
    }

    /// Остальные отказы Apple обязаны что-то СКАЗАТЬ: раньше часть веток молча
    /// возвращалась, и это читалось как «кнопка Apple не работает».
    func testAppleFailureAlwaysExplainsItself() async throws {
        let store = SessionStore(service: FakeAuth())

        store.handleApple(.failure(ASAuthorizationError(.unknown)))
        XCTAssertEqual(store.errorMessage, AuthError.appleUnavailable.errorDescription)

        store.errorMessage = nil
        store.handleApple(.failure(ASAuthorizationError(.invalidResponse)))
        XCTAssertEqual(store.errorMessage, AuthError.appleFailed.errorDescription)
    }
}
