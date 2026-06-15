import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

/// Управляет состоянием входа. UI смотрит только сюда, не зная про реализацию.
@MainActor
final class SessionStore: ObservableObject {

    @Published private(set) var user: SANUser?
    @Published var isWorking = false
    @Published var errorMessage: String?

    private let service: AuthService
    private var currentNonce: String?

    init(service: AuthService = AppConfig.makeAuthService()) {
        self.service = service
        self.user = service.currentUser()
    }


    var isSignedIn: Bool { user != nil }

    /// Гость = анонимный вход. Гостям недоступны: режим заведения, сохранения, отзывы.
    var isGuest: Bool { user?.provider == .guest }

    // MARK: Email

    func signInEmail(_ email: String, _ password: String) {
        run { try await self.service.signInWithEmail(email, password: password) }
    }

    func registerEmail(name: String, email: String, password: String) {
        run { try await self.service.registerWithEmail(name: name, email: email, password: password) }
    }

    // MARK: Google

    func signInGoogle() {
        run { try await self.service.signInWithGoogle() }
    }

    // MARK: Apple (нативно + nonce для Firebase)

    /// Вызывается в onRequest кнопки Apple: генерируем nonce и просим scope.
    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            // Отмену пользователем не показываем как ошибку
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            errorMessage = error.localizedDescription
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            let fullName = [cred.fullName?.givenName, cred.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            let token = cred.identityToken.flatMap { String(data: $0, encoding: .utf8) }
            let apple = AppleCredential(
                userID: cred.user,
                idTokenString: token,
                rawNonce: currentNonce,
                name: fullName.isEmpty ? nil : fullName,
                email: cred.email
            )
            run { try await self.service.signInWithApple(apple) }
        }
    }

    // MARK: Гость / выход

    func continueAsGuest() {
        run { try await self.service.continueAsGuest() }
    }

    func signOut() {
        print("🔴 signOut called, user before: \(String(describing: user))")
        service.signOut()
        user = nil
        errorMessage = nil
        print("🔴 signOut done, user after: \(String(describing: user)), isSignedIn: \(isSignedIn)")
    }

    // MARK: Общий запуск async-операции

    private func run(_ op: @escaping () async throws -> SANUser) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                let u = try await op()
                self.user = u
            } catch {
                self.errorMessage = (error as? AuthError)?.errorDescription ?? error.localizedDescription
            }
            self.isWorking = false
        }
    }

    // MARK: Nonce (для безопасного Apple-входа через Firebase)

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random = [UInt8](repeating: 0, count: 16)
            _ = SecRandomCopyBytes(kSecRandomDefault, random.count, &random)
            for byte in random where remaining > 0 {
                if Int(byte) < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
