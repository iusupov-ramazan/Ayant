import Foundation
import AyantDomain

/// Локальная реализация авторизации без бэкенда.
/// Хранит «зарегистрированных» пользователей и текущую сессию в UserDefaults.
/// Заменяется на FirebaseAuthService без изменения экранов.
public final class MockAuthService: AuthService {
    /// Пустой инициализатор нужен явно: синтезированный — internal.
    public init() {}


    private let defaults = UserDefaults.standard
    private let sessionKey = "san.session.user"
    private let dbKey = "san.mock.accounts"   // [email: password]

    // MARK: Сессия

    public func currentUser() -> SANUser? {
        guard let data = defaults.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(SANUser.self, from: data)
    }

    /// У mock-а сессия меняется только через этот же объект, поэтому поток
    /// отдаёт текущее значение и ждёт: гонки восстановления здесь нет.
    public func userChanges() -> AsyncStream<SANUser?> {
        AsyncStream { continuation in
            continuation.yield(currentUser())
        }
    }

    public func idToken() async -> String? { "mock-token" }

    private func persist(_ user: SANUser) {
        if let data = try? JSONEncoder().encode(user) {
            defaults.set(data, forKey: sessionKey)
        }
    }

    public func signOut() {
        defaults.removeObject(forKey: sessionKey)
    }

    // MARK: Email

    private var accounts: [String: String] {
        get { defaults.dictionary(forKey: dbKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: dbKey) }
    }

    public func signInWithEmail(_ email: String, password: String) async throws -> SANUser {
        try await fakeDelay()
        let key = AuthValidation.normalizedEmail(email)
        guard AuthValidation.isValidEmail(key) else { throw AuthError.invalidEmail }
        guard accounts[key] != nil else { throw AuthError.userNotFound }
        guard accounts[key] == password else { throw AuthError.invalidCredentials }
        let user = SANUser(id: Self.stableID(key), name: nameFrom(key),
                           email: key, provider: .email)
        persist(user)
        return user
    }

    public func registerWithEmail(name: String, email: String, password: String) async throws -> SANUser {
        try await fakeDelay()
        let key = AuthValidation.normalizedEmail(email)
        guard AuthValidation.isValidEmail(key) else { throw AuthError.invalidEmail }
        guard AuthValidation.isValidPassword(password) else { throw AuthError.weakPassword }
        // Повторная регистрация той же почты раньше молча ПЕРЕЗАПИСЫВАЛА пароль —
        // mock вёл себя мягче Firebase и прятал баг до самого прода.
        guard accounts[key] == nil else { throw AuthError.emailAlreadyInUse }
        var db = accounts
        db[key] = password
        accounts = db
        let user = SANUser(id: Self.stableID(key), name: AuthValidation.normalizedName(name),
                           email: key, provider: .email)
        persist(user)
        return user
    }

    // MARK: Соцсети (имитация — в проде заменит Firebase)

    public func signInWithGoogle() async throws -> SANUser {
        try await fakeDelay()
        let user = SANUser(id: "google_demo", name: "Гость Google",
                           email: "user@gmail.com", provider: .google)
        persist(user)
        return user
    }

    public func signInWithApple(_ c: AppleCredential) async throws -> SANUser {
        try await fakeDelay()
        let user = SANUser(id: c.userID, name: c.name ?? "Пользователь Apple",
                           email: c.email, provider: .apple)
        persist(user)
        return user
    }

    public func continueAsGuest() async throws -> SANUser {
        try await fakeDelay()
        let user = SANUser(id: "guest_\(UUID().uuidString.prefix(8))",
                           name: "Гость", email: nil, provider: .guest)
        persist(user)
        return user
    }

    // MARK: Удаление аккаунта

    public func deleteAccount() async throws {
        try await fakeDelay()
        if let email = currentUser()?.email {
            var db = accounts
            db.removeValue(forKey: AuthValidation.normalizedEmail(email))
            accounts = db
        }
        signOut()
    }

    public func discardGuestAccount() async {
        guard currentUser()?.provider == .guest else { return }
        signOut()
    }

    // MARK: Хелперы

    /// Детерминированный id по почте (FNV-1a).
    ///
    /// `String.hashValue` в Swift засеян случайно НА КАЖДЫЙ ЗАПУСК: id того же
    /// аккаунта менялся после перезапуска, и локальные данные «терялись»
    /// ровно в mock-режиме, где их и проверяют.
    static func stableID(_ email: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in Data(email.utf8) {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return "email_" + String(hash, radix: 16)
    }

    private func nameFrom(_ email: String) -> String {
        email.split(separator: "@").first.map(String.init)?.capitalized ?? "Друг"
    }

    private func fakeDelay() async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }
}
