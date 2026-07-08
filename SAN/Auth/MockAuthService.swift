import Foundation

/// Локальная реализация авторизации без бэкенда.
/// Хранит «зарегистрированных» пользователей и текущую сессию в UserDefaults.
/// Заменяется на FirebaseAuthService без изменения экранов.
final class MockAuthService: AuthService {

    private let defaults = UserDefaults.standard
    private let sessionKey = "san.session.user"
    private let dbKey = "san.mock.accounts"   // [email: password]

    // MARK: Сессия

    func currentUser() -> SANUser? {
        guard let data = defaults.data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(SANUser.self, from: data)
    }

    func idToken() async -> String? { "mock-token" }

    private func persist(_ user: SANUser) {
        if let data = try? JSONEncoder().encode(user) {
            defaults.set(data, forKey: sessionKey)
        }
    }

    func signOut() {
        defaults.removeObject(forKey: sessionKey)
    }

    // MARK: Email

    private var accounts: [String: String] {
        get { defaults.dictionary(forKey: dbKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: dbKey) }
    }

    func signInWithEmail(_ email: String, password: String) async throws -> SANUser {
        try await fakeDelay()
        let key = email.lowercased()
        guard accounts[key] == password else { throw AuthError.invalidCredentials }
        let user = SANUser(id: "email_\(key.hashValue)", name: nameFrom(email),
                           email: email, provider: .email)
        persist(user)
        return user
    }

    func registerWithEmail(name: String, email: String, password: String) async throws -> SANUser {
        try await fakeDelay()
        var db = accounts
        db[email.lowercased()] = password
        accounts = db
        let user = SANUser(id: "email_\(email.lowercased().hashValue)", name: name,
                           email: email, provider: .email)
        persist(user)
        return user
    }

    // MARK: Соцсети (имитация — в проде заменит Firebase)

    func signInWithGoogle() async throws -> SANUser {
        try await fakeDelay()
        let user = SANUser(id: "google_demo", name: "Гость Google",
                           email: "user@gmail.com", provider: .google)
        persist(user)
        return user
    }

    func signInWithApple(_ c: AppleCredential) async throws -> SANUser {
        try await fakeDelay()
        let user = SANUser(id: c.userID, name: c.name ?? "Пользователь Apple",
                           email: c.email, provider: .apple)
        persist(user)
        return user
    }

    func continueAsGuest() async throws -> SANUser {
        try await fakeDelay()
        let user = SANUser(id: "guest_\(UUID().uuidString.prefix(8))",
                           name: "Гость", email: nil, provider: .guest)
        persist(user)
        return user
    }

    // MARK: Хелперы

    private func nameFrom(_ email: String) -> String {
        email.split(separator: "@").first.map(String.init)?.capitalized ?? "Друг"
    }

    private func fakeDelay() async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }
}
