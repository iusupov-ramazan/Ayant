import SwiftUI
import AuthenticationServices
import AyantDomain
import AyantFeatures

/*
 * «Instagram» в кабинете: подключение аккаунта заведения и импорт постов в акции.
 *
 * Зачем экран вообще нужен: контент у заведения уже написан — он в инстаграме.
 * Перенабирать его в кабинете никто не будет, и каталог остаётся пустым.
 * Здесь хост нажимает «Синхронизировать», выбирает пост, и попадает в обычную
 * форму акции с уже заполненными заголовком, описанием и фото.
 *
 * Что важно знать при правках:
 *   — Вход открывается в `ASWebAuthenticationSession`, а не во встроенном
 *     WebView: встроенный Meta для входа блокирует, да и App Review его не
 *     пропустит. Возврат ловится по схеме приложения (`san://ig/connected`).
 *   — Импортированный пост создаёт ЧЕРНОВИК. Пост писался для инстаграма, у
 *     него нет ни срока, ни условий — публиковать такое в ленту не глядя нельзя.
 *   — Уже импортированные посты помечены и не открываются второй раз: связь
 *     держит `HostDealDTO.sourcePostID`.
 */

/// Маршрут к экрану инстаграма заведения.
struct HostInstagramTarget: Hashable {
    let venueID: String
}

struct HostInstagramView: View {
    let venueID: String
    @EnvironmentObject private var host: HostStore
    @Environment(\.dismiss) private var dismiss

    @State private var webSession: WebAuthSession?
    @State private var draft: ImportedDraft?
    @State private var errorText: String?

    /// Импорт, доехавший до формы: пост + постоянные ссылки на фото.
    private struct ImportedDraft: Identifiable {
        let value: InstagramImport
        var id: String { value.postID }
    }

    private var ig: InstagramVenueState { host.state.instagram(venueID: venueID) }
    private var venue: HostVenueDTO? { host.state.venue(id: venueID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                connectionCard
                // Ошибка показывается ВСЕГДА, а не только у подключённого: без
                // этого неудачная синхронизация выглядела как «ничего не
                // произошло» — самый дорогой вид ошибки, потому что искать
                // причину идут в код, а не в текст на экране.
                if let error = ig.sync.errorText { banner(error, isWarning: true) }
                if ig.isConnected || !ig.posts.isEmpty { postsSection }
                if let errorText { banner(errorText, isWarning: true) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .sanScreenBackground()
        .navigationTitle("Instagram")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            host.observeInstagram(venueID: venueID)
            if ig.isConnected && ig.posts.isEmpty { host.send(.syncInstagram(venueID: venueID)) }
        }
        .onDisappear { host.stopObservingInstagram(venueID: venueID) }
        // Подключение доезжает ПОСЛЕ появления экрана (слушатель асинхронный),
        // поэтому проверки в `.task` мало: на первом открытии она видит ещё
        // nil. Грузим посты, как только подключение подтвердилось.
        .onChange(of: ig.isConnected) { _, connected in
            if connected && ig.posts.isEmpty && !ig.sync.isSyncing {
                host.send(.syncInstagram(venueID: venueID))
            }
        }
        // Ссылка входа появилась — открываем системный браузер.
        .onChange(of: ig.authURL) { _, url in
            guard let url else { return }
            startLogin(url)
        }
        // Импорт закончился — открываем форму акции с заполненными полями.
        .onChange(of: host.pendingImport?.postID) { _, _ in
            if let imported = host.consumeImport() { draft = ImportedDraft(value: imported) }
        }
        .sheet(item: $draft) { d in
            HostDealFormView(venueID: venueID, existing: nil, imported: d.value)
        }
    }

    // MARK: Шапка

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(venue?.name ?? LS("Заведение"))
                .font(.golos(13, .semibold)).foregroundStyle(Color.sanInkSoft)
            Text("Посты из Instagram")
                .sanText(26, .heavy, tracking: -0.8, lineHeight: 1.05)
                .foregroundStyle(Color.sanInk)
            Text("Выберите пост — заголовок, описание и фото подставятся в акцию. Перед публикацией их можно поправить.")
                .font(.golos(13)).foregroundStyle(Color.sanInkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Подключение

    @ViewBuilder
    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let connection = ig.connection {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(connection.username)")
                            .font(.golos(15, .bold)).foregroundStyle(Color.sanInk)
                        if let last = connection.lastSyncAt {
                            Text("Обновлено \(last.formatted(date: .abbreviated, time: .shortened))")
                                .font(.golos(12)).foregroundStyle(Color.sanInkSoft)
                        }
                    }
                    Spacer()
                }
                if connection.needsReauth {
                    banner(LS("Доступ к аккаунту истёк — войдите заново, чтобы снова получать посты."),
                           isWarning: true)
                    Button("Войти заново") { host.send(.connectInstagram(venueID: venueID)) }
                        .buttonStyle(SanPrimaryButton())
                } else {
                    Button {
                        SanHaptics.selection()
                        host.send(.syncInstagram(venueID: venueID))
                    } label: {
                        Label(ig.sync.isSyncing ? "Синхронизация…" : "Синхронизировать",
                              systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(SanPrimaryButton())
                    .disabled(ig.sync.isSyncing)
                }
                Button("Отключить аккаунт", role: .destructive) {
                    host.send(.disconnectInstagram(venueID: venueID))
                }
                .font(.golos(13, .semibold))
            } else {
                Text("Подключите аккаунт заведения — посты можно будет превращать в акции в два касания.")
                    .font(.golos(14)).foregroundStyle(Color.sanInk)
                    .fixedSize(horizontal: false, vertical: true)
                // Требование Meta, а не наше: личные аккаунты подключить нельзя
                // в принципе. Честнее сказать заранее, чем на экране ошибки.
                Label("Нужен профессиональный аккаунт (Business или Creator) — переключается бесплатно в настройках Instagram.",
                      systemImage: "info.circle")
                    .font(.golos(12)).foregroundStyle(Color.sanInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    SanHaptics.selection()
                    host.send(.connectInstagram(venueID: venueID))
                } label: {
                    Label("Подключить Instagram", systemImage: "link")
                }
                .buttonStyle(SanPrimaryButton())
                .disabled(ig.sync.isSyncing)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sanCard(padding: 0)
    }

    // MARK: Посты

    private var postsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if ig.posts.isEmpty {
                Text(ig.sync.isSyncing ? "Загружаем посты…" : "Постов пока нет. Нажмите «Синхронизировать».")
                    .font(.golos(13)).foregroundStyle(Color.sanInkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    ForEach(ig.posts) { post in postTile(post) }
                }
            }
        }
    }

    private func postTile(_ post: InstagramPost) -> some View {
        let imported = host.state.importedPostIDs.contains(post.id)
        let busy = ig.importing == post.id
        return Button {
            SanHaptics.selection()
            host.send(.importInstagramPost(venueID: venueID, postID: post.id))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    VenuePhoto(urlString: post.previewURL,
                               gradient: venue?.asVenue.gradientColors ?? [.sanAccent, .orange])
                        .frame(height: 130)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if busy { ProgressView().tint(.white) }
                }
                .overlay(alignment: .topTrailing) {
                    if imported {
                        Label("Добавлено", systemImage: "checkmark")
                            .font(.golos(11, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color.black.opacity(0.62), in: Capsule())
                            .padding(8)
                    }
                }
                Text(InstagramCaption.parse(post.caption).title.isEmpty
                     ? LS("Без подписи")
                     : InstagramCaption.parse(post.caption).title)
                    .font(.golos(13, .semibold)).foregroundStyle(Color.sanInk)
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.sanPress(0.96))
        .disabled(imported || busy || ig.importing != nil)
        .opacity(imported ? 0.55 : 1)
    }

    // MARK: Мелочи

    private func banner(_ text: String, isWarning: Bool) -> some View {
        Label(text, systemImage: isWarning ? "exclamationmark.triangle.fill" : "info.circle")
            .font(.golos(12.5)).foregroundStyle(isWarning ? Color.orange : Color.sanInkSoft)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Открывает вход и держит сессию живой: отпущенная `ASWebAuthenticationSession`
    /// закрывает браузер сама, не дождавшись ответа.
    private func startLogin(_ url: URL) {
        let session = WebAuthSession(url: url) { result in
            switch result {
            case .success:
                host.send(.instagramConnected(venueID: venueID))
            case .cancelled:
                host.send(.instagramConnected(venueID: venueID))   // гасим authURL
            case .failed(let message):
                errorText = message
                host.send(.instagramConnected(venueID: venueID))
            }
            webSession = nil
        }
        webSession = session
        session.start()
    }
}

// MARK: - Обёртка над ASWebAuthenticationSession

/// Вход во внешнем браузере. Отдельный класс, потому что сессии нужен
/// презентационный контекст (`ASWebAuthenticationPresentationContextProviding`)
/// и её нельзя отпускать до колбэка.
final class WebAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum Outcome {
        case success(URL)
        case cancelled
        case failed(String)
    }

    private let url: URL
    private let completion: (Outcome) -> Void
    private var session: ASWebAuthenticationSession?

    init(url: URL, completion: @escaping (Outcome) -> Void) {
        self.url = url
        self.completion = completion
    }

    func start() {
        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "san") { callback, error in
            if let callback {
                self.completion(.success(callback))
            } else if let error = error as? ASWebAuthenticationSessionError,
                      error.code == .canceledLogin {
                self.completion(.cancelled)
            } else {
                self.completion(.failed(error?.localizedDescription ?? LS("Не удалось войти")))
            }
        }
        session.presentationContextProvider = self
        // БЕЗ общих кук с Safari. Соблазн переиспользовать сессию телефона
        // («не заставлять набирать пароль») стоит дороже, чем экономит: вход
        // тогда идёт под тем аккаунтом, который открыт в браузере, а у
        // владельца заведения это обычно его личный профиль. В лучшем случае
        // он получит «Insufficient Developer Role», в худшем — к заведению
        // молча привяжется чужой инстаграм. Чистая сессия заставляет выбрать
        // аккаунт явно; подключение делается один раз.
        session.prefersEphemeralWebBrowserSession = true
        self.session = session
        session.start()
    }

    /// Окно, поверх которого показывать браузер.
    ///
    /// Нельзя возвращать `ASPresentationAnchor()`: пустое окно не принадлежит
    /// ни одной сцене, и сессия падает с `presentationContextInvalid` (код 3) —
    /// именно так это и выглядело на устройстве. Берём окно АКТИВНОЙ сцены:
    /// `connectedScenes` отдаёт и фоновые, у которых `keyWindow` пуст, поэтому
    /// «первая попавшаяся» сцена — не то же самое, что видимая пользователю.
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
        return scene?.keyWindow
            ?? scene?.windows.first { $0.isKeyWindow }
            ?? scene?.windows.first
            ?? ASPresentationAnchor()
    }
}

private extension SyncPhase {
    /// Текст ошибки синхронизации — по коду сервера, а не «что-то пошло не так».
    var errorText: String? {
        guard case .failed(let error) = self else { return nil }
        switch error.code {
        case "not_connected":    return LS("Аккаунт не подключён.")
        case "reauth_required":  return LS("Доступ к аккаунту истёк — войдите заново.")
        case "not_configured":   return LS("Интеграция ещё не настроена на сервере.")
        case "instagram_unavailable": return LS("Instagram сейчас не отвечает. Попробуйте позже.")
        case "no_image":         return LS("У этого поста нет фотографии.")
        case "upload_failed":    return LS("Не удалось перенести фото. Попробуйте ещё раз.")
        case "network":          return LS("Нет соединения.")
        default:                 return LS("Не удалось получить посты.")
        }
    }
}
