import Foundation

// MARK: - Пользователь

public struct SANUser: Codable, Equatable {
    public let id: String
    public var name: String
    public var email: String?
    public var provider: AuthProvider

    public init(id: String, name: String, email: String?, provider: AuthProvider) {
        self.id = id
        self.name = name
        self.email = email
        self.provider = provider
    }
}

public enum AuthProvider: String, Codable {
    case apple, google, email, guest
}

// MARK: - Ошибки

/// Ошибки авторизации на языке пользователя.
///
/// Коды Firebase (`ERROR_INVALID_CREDENTIAL`, «The password is invalid…») наружу
/// не выпускаем: их переводит `FirebaseAuthService.mapError` в один из случаев
/// ниже. Строки русские, как и весь домен, — каталог `Localizable.xcstrings`
/// пакету недоступен.
public enum AuthError: LocalizedError, Equatable {
    case cancelled
    case invalidCredentials
    case invalidEmail
    case emailAlreadyInUse
    case weakPassword
    case userNotFound
    case userDisabled
    case tooManyRequests
    case network
    case requiresRecentLogin
    /// Apple не выдал устройству учётку: чаще всего на нём просто не выполнен
    /// вход в iCloud. Раньше этот случай приходил как `.unknown` с английским
    /// системным текстом — «кнопка не работает» без единой подсказки.
    case appleUnavailable
    /// Apple вернул ответ, из которого нельзя собрать credential (нет токена
    /// или потерян nonce). Показывать «неверная почта или пароль» здесь нельзя:
    /// пользователь не вводил ни того, ни другого.
    case appleFailed
    case notConfigured(String)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .cancelled: return "Вход отменён"
        case .invalidCredentials: return "Неверная почта или пароль"
        case .invalidEmail: return "Неверный формат почты"
        // «Забыли пароль?» — реальная кнопка на экране входа (`sendPasswordReset`),
        // поэтому подсказка обещает то, что есть.
        case .emailAlreadyInUse: return "Эта почта уже зарегистрирована. Войдите или нажмите «Забыли пароль?»."
        case .weakPassword: return "Слишком простой пароль — нужно минимум \(AuthValidation.minPasswordLength) символов"
        case .userNotFound: return "Аккаунт с такой почтой не найден"
        case .userDisabled: return "Аккаунт заблокирован. Напишите в поддержку."
        case .tooManyRequests: return "Слишком много попыток. Попробуйте через несколько минут."
        case .network: return "Нет связи с сервером. Проверьте интернет."
        case .requiresRecentLogin: return "Для удаления аккаунта войдите заново — так мы убеждаемся, что это вы."
        case .appleUnavailable: return "Вход через Apple недоступен: проверьте, что на устройстве выполнен вход в iCloud."
        case .appleFailed: return "Apple не подтвердил вход. Попробуйте ещё раз."
        case .notConfigured(let p): return "\(p) ещё не подключён. Нужен Firebase-проект и ключи."
        case .unknown(let m): return m
        }
    }
}

// MARK: - Протокол сервиса авторизации
// Mock-реализация работает сейчас. FirebaseAuthService подключается позже
// без изменения UI — он реализует тот же протокол.

public protocol AuthService {
    func currentUser() -> SANUser?
    /// Поток изменений сессии от провайдера.
    ///
    /// Firebase восстанавливает пользователя из связки ключей АСИНХРОННО: на
    /// холодном старте `currentUser()` может быть ещё пустым, и одного чтения
    /// при инициализации мало — экран остаётся на форме входа (или на пустом
    /// каталоге) у человека, который на самом деле вошёл. Поток закрывает эту
    /// гонку и заодно ловит выход, сделанный другим экраном.
    func userChanges() -> AsyncStream<SANUser?>
    /// Firebase ID-токен текущего пользователя (для авторизации вызовов Cloud Functions).
    func idToken() async -> String?
    func signInWithEmail(_ email: String, password: String) async throws -> SANUser
    func registerWithEmail(name: String, email: String, password: String) async throws -> SANUser
    /// Письмо для сброса пароля на указанную почту.
    ///
    /// Firebase с включённой защитой от перебора отвечает успехом и на
    /// незнакомую почту, поэтому единственный честный ответ пользователю —
    /// «письмо отправлено», а не «такого аккаунта нет».
    func sendPasswordReset(email: String) async throws
    func signInWithGoogle() async throws -> SANUser
    /// Результат нативного Sign in with Apple. idTokenString + rawNonce нужны
    /// для обмена на Firebase-credential; mock использует только id/имя/email.
    func signInWithApple(_ credential: AppleCredential) async throws -> SANUser
    /// Анонимный вход (Firebase signInAnonymously)
    func continueAsGuest() async throws -> SANUser
    func signOut()
    /// Удаляет аккаунт целиком: данные в Firestore и запись в Firebase Auth.
    ///
    /// Обычный выход оставляет и то и другое — поэтому «Удалить аккаунт» обязано
    /// звать именно этот метод, иначе пользователь исчезает только из интерфейса.
    /// Каскад по коллекциям делает Cloud Function `deleteAccount` (правила
    /// запрещают клиенту трогать чужие/денежные документы).
    func deleteAccount() async throws
    /// Отзывает грант Sign in with Apple по свежему `authorizationCode`.
    ///
    /// App Review 5.1.1(v): приложение с входом через Apple обязано при удалении
    /// аккаунта отозвать и выданный Apple токен — иначе аккаунт продолжает
    /// висеть у пользователя в «Вход с Apple» в настройках iOS. Код живёт
    /// несколько минут и берётся из повторной шторки Apple прямо перед удалением.
    func revokeAppleToken(authorizationCode: String) async throws
    /// Гостевая (анонимная) запись после выхода никому не нужна: войти в неё
    /// повторно невозможно, а в Firebase Auth она копится мусором.
    /// Тихо удаляет её, если текущий пользователь анонимный.
    func discardGuestAccount() async
}

/// Данные, полученные от Sign in with Apple.
public struct AppleCredential {
    public let userID: String
    public let idTokenString: String?
    public let rawNonce: String?
    public let name: String?
    public let email: String?

    public init(userID: String, idTokenString: String?, rawNonce: String?, name: String?, email: String?) {
        self.userID = userID
        self.idTokenString = idTokenString
        self.rawNonce = rawNonce
        self.name = name
        self.email = email
    }
}
