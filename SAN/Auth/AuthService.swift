import Foundation

// MARK: - Пользователь

struct SANUser: Codable, Equatable {
    let id: String
    var name: String
    var email: String?
    var provider: AuthProvider
}

enum AuthProvider: String, Codable {
    case apple, google, email, guest
}

// MARK: - Ошибки

enum AuthError: LocalizedError {
    case cancelled
    case invalidCredentials
    case notConfigured(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Вход отменён"
        case .invalidCredentials: return "Неверная почта или пароль"
        case .notConfigured(let p): return "\(p) ещё не подключён. Нужен Firebase-проект и ключи."
        case .unknown(let m): return m
        }
    }
}

// MARK: - Протокол сервиса авторизации
// Mock-реализация работает сейчас. FirebaseAuthService подключается позже
// без изменения UI — он реализует тот же протокол.

protocol AuthService {
    func currentUser() -> SANUser?
    /// Firebase ID-токен текущего пользователя (для авторизации вызовов Cloud Functions).
    func idToken() async -> String?
    func signInWithEmail(_ email: String, password: String) async throws -> SANUser
    func registerWithEmail(name: String, email: String, password: String) async throws -> SANUser
    func signInWithGoogle() async throws -> SANUser
    /// Результат нативного Sign in with Apple. idTokenString + rawNonce нужны
    /// для обмена на Firebase-credential; mock использует только id/имя/email.
    func signInWithApple(_ credential: AppleCredential) async throws -> SANUser
    /// Анонимный вход (Firebase signInAnonymously)
    func continueAsGuest() async throws -> SANUser
    func signOut()
}

/// Данные, полученные от Sign in with Apple.
struct AppleCredential {
    let userID: String
    let idTokenString: String?
    let rawNonce: String?
    let name: String?
    let email: String?
}
