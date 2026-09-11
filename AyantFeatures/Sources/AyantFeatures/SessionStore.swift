import SwiftUI
import AuthenticationServices
import CryptoKit
import Security
import AyantDomain

/// Управляет состоянием входа. UI смотрит только сюда, не зная про реализацию.
@MainActor
public final class SessionStore: ObservableObject {

    @Published public private(set) var user: SANUser?
    @Published public var isWorking = false
    @Published public var errorMessage: String?
    /// Не-ошибка, о которой всё же надо сказать («письмо отправлено»).
    /// Отдельный канал: `errorMessage` показывается с заголовком «Ошибка».
    @Published public var infoMessage: String?

    private let service: AuthService
    private var currentNonce: String?

    /// Что нужно успеть сделать, ПОКА пользователь ещё авторизован: отписать
    /// устройство от push (удаление `userTokens/<token>` требует `request.auth`).
    /// Ставит композиционный корень; стор про push ничего не знает.
    public var willSignOut: (() async -> Void)?

    private var restoreTask: Task<Void, Never>?

    deinit { restoreTask?.cancel() }

    public init(service: AuthService) {
        self.service = service
        self.user = service.currentUser()
        // Firebase поднимает сессию из связки ключей асинхронно: на холодном
        // старте `currentUser()` выше может быть ещё пустым, и без подписки
        // вошедший пользователь видел экран входа или пустой каталог.
        restoreTask = Task { [weak self] in
            guard let stream = self?.service.userChanges() else { return }
            for await _ in stream {
                guard let self else { return }
                // Пока идёт наша собственная операция (вход/выход/удаление),
                // не перетираем состояние промежуточным значением слушателя.
                guard !self.isWorking else { continue }
                // Берём СВЕЖЕЕ значение у сервиса, а не то, что принёс поток.
                // Событие могло встать в очередь до нашего входа и прийти уже
                // после него — тогда устаревший `nil` выкидывал только что
                // вошедшего пользователя обратно на экран входа.
                let current = self.service.currentUser()
                if self.user != current { self.user = current }
            }
        }
    }


    public var isSignedIn: Bool { user != nil }

    /// Гость = анонимный вход. Гостям недоступны: режим заведения, сохранения, отзывы.
    public var isGuest: Bool { user?.provider == .guest }

    // MARK: Email

    public func signInEmail(_ email: String, _ password: String) {
        run { try await self.service.signInWithEmail(email, password: password) }
    }

    public func registerEmail(name: String, email: String, password: String) {
        run { try await self.service.registerWithEmail(name: name, email: email, password: password) }
    }

    /// «Забыли пароль?». Сессию не меняет — только сообщает, что письмо ушло.
    public func sendPasswordReset(email: String) {
        let clean = AuthValidation.normalizedEmail(email)
        perform {
            try await self.service.sendPasswordReset(email: clean)
            self.infoMessage = "Письмо для сброса пароля отправлено на \(clean)"
        }
    }

    // MARK: Google

    public func signInGoogle() {
        run { try await self.service.signInWithGoogle() }
    }

    // MARK: Apple (нативно + nonce для Firebase)

    /// Вызывается в onRequest кнопки Apple: генерируем nonce и просим scope.
    public func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    /// Результат нативной кнопки Apple.
    ///
    /// Каждая ветка обязана что-то СКАЗАТЬ пользователю. Раньше половина из них
    /// молчала: неизвестный тип credential — тихий `return`, пустой nonce или
    /// отсутствующий токен уходили в сервис и возвращались как «неверная почта
    /// или пароль», а системные ошибки показывались английским текстом. Со
    /// стороны это выглядит как «кнопка Apple иногда не работает».
    public func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            guard let authError = error as? ASAuthorizationError else {
                errorMessage = AuthError.appleFailed.errorDescription
                return
            }
            switch authError.code {
            case .canceled:
                // Пользователь закрыл шторку сам — это не ошибка.
                return
            case .unknown, .notInteractive:
                // Практически всегда: на устройстве не выполнен вход в iCloud.
                errorMessage = AuthError.appleUnavailable.errorDescription
            case .failed, .invalidResponse, .notHandled:
                errorMessage = AuthError.appleFailed.errorDescription
            @unknown default:
                errorMessage = AuthError.appleFailed.errorDescription
            }

        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce
            else {
                errorMessage = AuthError.appleFailed.errorDescription
                return
            }
            let fullName = [cred.fullName?.givenName, cred.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            let apple = AppleCredential(
                userID: cred.user,
                idTokenString: token,
                rawNonce: nonce,
                name: fullName.isEmpty ? nil : fullName,
                email: cred.email
            )
            run { try await self.service.signInWithApple(apple) }
        }
    }

    // MARK: Гость / выход

    public func continueAsGuest() {
        run { try await self.service.continueAsGuest() }
    }

    /// Выход. Гостевую запись при этом УДАЛЯЕМ: войти в анонимный аккаунт
    /// повторно нельзя, поэтому после выхода он — мусор в Firebase Auth,
    /// на который к тому же завязаны его баллы и купоны.
    ///
    /// Порядок шагов важен: `willSignOut` (отписка от push) обязан отработать
    /// ДО `service.signOut()`, иначе запись в Firestore уже некому авторизовать
    /// и токен остаётся получать чужие кампании. Поэтому `user = nil`
    /// выставляем в самом конце — экран входа не должен появиться раньше.
    /// Ждём хук не дольше `signOutHookTimeout`: выход не должен зависеть от сети.
    public func signOut() {
        let wasGuest = isGuest
        isWorking = true
        errorMessage = nil
        Task {
            await runWillSignOutBounded()
            if wasGuest { await service.discardGuestAccount() }
            service.signOut()
            user = nil
            isWorking = false
        }
    }

    /// Полное удаление аккаунта: Firestore-данные и запись в Firebase Auth.
    /// `onFinish(nil)` — успех; иначе текст ошибки для алерта.
    ///
    /// Порядок: (1) отзыв гранта Apple, если пользователь входил через Apple и
    /// экран принёс свежий `authorizationCode` (App Review 5.1.1(v)); (2) само
    /// удаление; (3) `willSignOut` — уже best-effort и с пределом по времени;
    /// (4) чистка локального состояния.
    ///
    /// Раньше `willSignOut` шёл ПЕРВЫМ: если облачная функция затем отвечала
    /// 409 («владеет заведениями»), 401 или 500, пользователь оставался в
    /// аккаунте, но устройство уже было отписано от push. Push-токены удаляет
    /// та же функция каскадом по `uid`, так что после успешного удаления хук
    /// нужен только ради локальной отписки от топиков.
    ///
    /// Если отзыв Apple не удался — НЕ удаляем: остался бы Firebase-аккаунт
    /// без записи, но с живым грантом в настройках iOS у пользователя.
    public func deleteAccount(appleAuthorizationCode: String? = nil,
                              onFinish: @escaping (String?) -> Void = { _ in }) {
        let needsAppleRevoke = user?.provider == .apple
        isWorking = true
        errorMessage = nil
        Task {
            defer { publishServiceUserIfChanged() }
            do {
                if needsAppleRevoke, let code = appleAuthorizationCode {
                    try await service.revokeAppleToken(authorizationCode: code)
                }
                try await service.deleteAccount()
                await runWillSignOutBounded()
                self.user = nil
                self.isWorking = false
                onFinish(nil)
            } catch {
                let text = (error as? AuthError)?.errorDescription ?? error.localizedDescription
                self.errorMessage = text
                self.isWorking = false
                onFinish(text)
            }
        }
    }

    /// Сколько ждём хук `willSignOut` (отписка устройства от push).
    /// Без предела мёртвая сеть блокировала выход НАВСЕГДА: спиннер без
    /// ошибки, и выйти из аккаунта нельзя. По таймауту выходим всё равно —
    /// лишний токен в `userTokens` дешевле запертого пользователя.
    private static let signOutHookTimeout: Duration = .seconds(5)

    private func runWillSignOutBounded() async {
        guard let hook = willSignOut else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await hook() }
            group.addTask { _ = try? await Task.sleep(for: Self.signOutHookTimeout) }
            // Кто первый — тот и решает; второго отменяем (хук, если он
            // не смотрит на отмену, дорабатывает в фоне — нам это не мешает).
            _ = await group.next()
            group.cancelAll()
        }
    }

    // MARK: Общий запуск async-операции

    /// Сколько ждём ответ провайдера, прежде чем признать попытку неудачной.
    /// Firebase не отваливается сам: при недоступной связке ключей или залипшей
    /// сети вызов не возвращается НИКОГДА — на экране оставался вечный спиннер
    /// без ошибки и без возможности повторить.
    private static let authTimeout: Duration = .seconds(30)

    /// Операция, меняющая сессию: результат становится текущим пользователем.
    private func run(_ op: @escaping () async throws -> SANUser) {
        perform { self.user = try await op() }
    }

    /// Общая обвязка любой операции провайдера: спиннер, сторожевой таймер,
    /// перевод ошибки в текст, молчание на отмену.
    private func perform(_ op: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        let watchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.authTimeout)
            guard let self, !Task.isCancelled, self.isWorking else { return }
            self.isWorking = false
            self.errorMessage = AuthError.network.errorDescription
        }
        Task {
            defer { watchdog.cancel() }
            do {
                try await op()
            } catch AuthError.cancelled {
                // Пользователь сам закрыл шторку входа — это не ошибка.
            } catch {
                self.errorMessage = (error as? AuthError)?.errorDescription ?? error.localizedDescription
            }
            self.isWorking = false
            publishServiceUserIfChanged()
        }
    }

    /// События `userChanges()`, пришедшие ПОКА шла наша операция, слушатель
    /// пропускает (см. `init`) — и раньше ничем не добирал. Отзыв сессии или
    /// выход с другого экрана, попавшие в это окно, терялись: стор показывал
    /// вошедшего пользователя, которого у провайдера уже нет. Поэтому по
    /// окончании каждой операции сверяемся с провайдером ещё раз.
    private func publishServiceUserIfChanged() {
        let current = service.currentUser()
        if user != current { user = current }
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
