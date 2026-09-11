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

    // Фальшивый сервис `FakeAuth` — в `Fakes.swift`, рядом с остальными
    // дублями доменных контрактов.

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

    /// Провал операции обязан и погасить спиннер, и объяснить себя — иначе
    /// экран входа «залипает» без единого слова.
    func testFailedOperationClearsWorkingAndSetsError() async throws {
        let store = SessionStore(service: FakeAuth())

        store.signInGoogle()   // фейк отвечает notConfigured

        try await waitUntil { store.errorMessage != nil }
        XCTAssertFalse(store.isWorking)
        XCTAssertFalse(store.isSignedIn)
        XCTAssertEqual(store.errorMessage, AuthError.notConfigured("Google").errorDescription)
    }

    // MARK: Сброс пароля

    /// «Забыли пароль?» доходит до сервиса и сообщает пользователю, куда ушло
    /// письмо. Почта нормализуется той же функцией, что и при входе.
    func testSendPasswordResetSetsInfoMessage() async throws {
        let service = FakeAuth()
        let store = SessionStore(service: service)

        store.sendPasswordReset(email: " User@Mail.ru ")

        try await waitUntil { store.infoMessage != nil }
        XCTAssertEqual(service.passwordResets, ["user@mail.ru"])
        XCTAssertEqual(store.infoMessage, "Письмо для сброса пароля отправлено на user@mail.ru")
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isWorking)
        XCTAssertFalse(store.isSignedIn, "Сброс пароля не меняет сессию")
    }

    // MARK: Удаление аккаунта

    /// Удаление зовёт именно `deleteAccount` сервиса (не `signOut`) и
    /// заканчивается выходом.
    func testDeleteAccountCallsServiceAndSignsOut() async throws {
        let service = FakeAuth()
        let store = SessionStore(service: service)
        store.signInEmail("user@mail.ru", "123456")
        try await waitUntil { store.isSignedIn }

        var finished = false
        var result: String? = "не вызван"
        store.deleteAccount { result = $0; finished = true }

        try await waitUntil { finished }
        XCTAssertTrue(service.deleted)
        XCTAssertFalse(store.isSignedIn)
        XCTAssertFalse(store.isWorking)
        XCTAssertNil(store.errorMessage)
        XCTAssertNil(result, "onFinish(nil) — успех")
        XCTAssertFalse(service.calls.contains("revoke"), "Почтовый аккаунт грант Apple не отзывает")
    }

    /// Вход через Apple: перед удалением отзываем грант свежим кодом, и
    /// именно в этом порядке (App Review 5.1.1(v)).
    func testDeleteAppleAccountRevokesTokenBeforeDelete() async throws {
        let service = FakeAuth()
        service.stored = SANUser(id: "a1", name: "Apple", email: nil, provider: .apple)
        let store = SessionStore(service: service)
        XCTAssertTrue(store.isSignedIn)

        store.deleteAccount(appleAuthorizationCode: "c_abc")

        try await waitUntil { !store.isSignedIn }
        XCTAssertEqual(service.revokedAppleCodes, ["c_abc"])
        XCTAssertEqual(service.calls, ["revoke", "delete"])
        XCTAssertTrue(service.deleted)
        XCTAssertFalse(store.isWorking)
    }

    /// Не удалось отозвать грант — аккаунт НЕ удаляем: остался бы живой грант
    /// в настройках iOS без аккаунта за ним. Пользователь остаётся в системе.
    func testDeleteAppleAccountStopsWhenRevokeFails() async throws {
        let service = FakeAuth()
        service.stored = SANUser(id: "a1", name: "Apple", email: nil, provider: .apple)
        service.revokeError = AuthError.network
        let store = SessionStore(service: service)

        var finished = false
        store.deleteAccount(appleAuthorizationCode: "c_abc") { _ in finished = true }

        try await waitUntil { finished }
        XCTAssertEqual(service.calls, ["revoke"])
        XCTAssertFalse(service.deleted)
        XCTAssertTrue(store.isSignedIn)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.errorMessage, AuthError.network.errorDescription)
    }

    /// Сервер отказал в удалении (например, аккаунт владеет заведениями):
    /// пользователь остаётся в аккаунте, ошибка показана, спиннер погашен.
    func testDeleteAccountFailureKeepsUserSignedIn() async throws {
        let service = FakeAuth()
        let store = SessionStore(service: service)
        store.signInEmail("user@mail.ru", "123456")
        try await waitUntil { store.isSignedIn }
        service.deleteError = AuthError.unknown("409")

        var finished = false
        var result: String?
        store.deleteAccount { result = $0; finished = true }

        try await waitUntil { finished }
        XCTAssertTrue(store.isSignedIn)
        XCTAssertFalse(store.isWorking)
        XCTAssertEqual(store.errorMessage, "409")
        XCTAssertEqual(result, "409")
    }

    /// Хук `willSignOut` (отписка от push) не должен держать выход: мёртвая
    /// сеть раньше оставляла вечный спиннер. Здесь хук не завершается никогда.
    func testSignOutProceedsWhenHookHangs() async throws {
        let service = FakeAuth()
        let store = SessionStore(service: service)
        store.signInEmail("user@mail.ru", "123456")
        try await waitUntil { store.isSignedIn }
        store.willSignOut = { _ = try? await Task.sleep(for: .seconds(60)) }

        store.signOut()

        // Предел хука — 5 с; ждём с запасом, но много меньше 60 с.
        try await waitUntil(8) { !store.isSignedIn }
        XCTAssertFalse(store.isWorking)
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
