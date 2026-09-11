import SwiftUI
import AuthenticationServices
import AyantDomain
import AyantFeatures

/// Профиль пользователя (рефреш): карточка профиля, сгруппированные настройки,
/// режим заведения, отзывы, приглашение, помощь и аккаунт. Функции сохранены.
struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var host: HostStore
    @EnvironmentObject private var coupons: CouponStore
    @AppStorage("san.hostMode") private var hostMode = false
    @AppStorage("san.language") private var language = "ru"

    @State private var activeSheet: ProfileSheet?
    /// Один диалог на карточку аккаунта вместо двух.
    ///
    /// Два `.confirmationDialog` на ОДНОЙ вьюхе SwiftUI не показывает: работает
    /// только внешний, а «Выйти?» молча не открывался. То же правило действует
    /// для `.alert`, поэтому алерт ошибки удаления висит на внутреннем стеке.
    @State private var accountConfirm: AccountConfirm?
    @State private var deleteError: String?
    @State private var showGuestPrompt = false

    private enum AccountConfirm: Identifiable {
        case signOut, delete
        var id: Self { self }
    }

    private var username: String { session.user?.name ?? "Гость" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SanScreenTitle("Профиль")
                    profileCard
                    couponsCard
                    settingsGroup
                    hostModeCard
                    reviewsSection
                    // Реферальная программа платит бонусами глобального кошелька,
                    // которые в первом релизе некуда тратить — скрыта флагом.
                    if ReleaseFlags.referrals { referralSection }
                    helpGroup
                    accountCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .sanScreenBackground()
            .sanStatusBarCap()
            .toolbar(.hidden, for: .navigationBar)
            .guestAlert(isPresented: $showGuestPrompt,
                        message: "Гостям доступен только просмотр. Войдите, чтобы добавлять заведения, сохранять места и оставлять отзывы.")
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .editReview(let review):
                    if let venue = store.venue(id: review.venueID) {
                        WriteReviewView(venue: venue, existing: review)
                    }
                case .hostMode:
                    HostOnboardingView { hostMode = true }
                case .appleDelete:
                    AppleDeleteConfirmSheet { code in
                        session.deleteAccount(appleAuthorizationCode: code) { error in
                            deleteError = error
                        }
                    } onFailure: { text in
                        deleteError = text
                    }
                    .presentationDetents([.medium])
                }
            }
        }
        .onAppear { store.setCurrentUser(id: session.user?.id, name: session.user?.name, isGuest: session.isGuest) }
    }

    // MARK: Карточка профиля

    private var profileCard: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient.sanAccentGradient)
                .frame(width: 64, height: 64)
                .overlay(
                    Text(String(username.prefix(1)).uppercased())
                        .font(.golos(28, .heavy)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text(username).font(.golos(20, .bold)).foregroundStyle(Color.sanInk)
                if let email = session.user?.email {
                    Text(email).font(.golos(14, .medium)).foregroundStyle(Color.sanInkSoft)
                }
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 12, weight: .semibold))
                    Text(L(store.selectedCity.name)).font(.golos(14, .semibold))
                }
                .foregroundStyle(Color.sanInkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .sanCard(padding: 0)
    }

    // MARK: Мои купоны · Сохранённое
    //
    // «Сохранённое» перестало быть вкладкой в редизайне (4 вкладки + FAB),
    // поэтому у него теперь два входа: закладка в шапке ленты и эта строка.

    private var couponsCard: some View {
        VStack(spacing: 0) {
            NavigationLink { MyCouponsView() } label: {
                libraryRow(icon: "ticket.fill", title: "Мои купоны",
                           badge: coupons.activeCount > 0 ? "\(coupons.activeCount)" : nil)
            }
            .buttonStyle(.plain)
            SanHairline(leading: 60)
            NavigationLink { SavedView() } label: {
                libraryRow(icon: "bookmark.fill", title: "Сохранённое", badge: nil)
            }
            .buttonStyle(.plain)
        }
        .sanGroupCard()
    }

    private func libraryRow(icon: String, title: LocalizedStringKey, badge: String?) -> some View {
        HStack(spacing: 12) {
            SanIconTile(systemName: icon, size: 34)
            Text(title).font(.golos(16, .medium)).foregroundStyle(Color.sanInk)
            Spacer()
            if let badge {
                Text(badge)
                    .font(.golos(13, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Color.sanAccent, in: Capsule())
            }
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.sanInkSoft)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    // MARK: Настройки

    private var settingsGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            SanSectionHeader("Настройки")
            VStack(spacing: 0) {
                // Город — справочная строка, не выбор: пока каталог только на
                // Бишкек, и намёков на тап (шеврон, акцентный цвет, `Menu`)
                // здесь быть не должно. Вернуть `Menu`, когда появится второй город.
                settingRow(icon: "building.2.fill", title: "Город") {
                    Text(L(store.selectedCity.name))
                        .font(.golos(15, .medium)).foregroundStyle(Color.sanInkSoft)
                }
                .accessibilityElement(children: .combine)
                SanHairline(leading: 60)
                settingRow(icon: "globe", title: "Язык") {
                    Menu {
                        // Кыргызского здесь нет намеренно: строковый каталог iOS
                        // переведён на кыргызский лишь частично, и выбор языка
                        // давал бы экран-винегрет из двух языков. На Android
                        // ресурсы переведены полностью — там кыргызский есть.
                        // Вернуть сюда, когда `Localizable.xcstrings` дозаполнят.
                        Button("Русский") { language = "ru" }
                        Button("English") { language = "en" }
                    } label: { menuValue(languageTitle) }
                }
                SanHairline(leading: 60)
                settingRow(icon: "circle.lefthalf.filled", title: "Тема") {
                    Menu {
                        ForEach(AppTheme.allCases) { theme in
                            Button { themeStore.theme = theme } label: { Label(theme.title, systemImage: theme.icon) }
                        }
                    } label: { menuValue(themeStore.theme.title) }
                }
            }
            .sanGroupCard()
        }
    }

    private func settingRow<Trailing: View>(icon: String, title: String,
                                             @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            SanIconTile(systemName: icon, size: 34)
            Text(title).font(.golos(16, .medium)).foregroundStyle(Color.sanInk)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
    }

    private func menuValue(_ value: String) -> some View {
        HStack(spacing: 6) {
            Text(value).font(.golos(15, .bold)).foregroundStyle(Color.sanAccentText)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.sanInkSoft)
        }
    }

    private var languageTitle: String {
        // «ky» больше не предлагается (каталог iOS переведён не полностью) —
        // старую настройку показываем как русский, как и трактует её `SANApp`.
        switch language { case "en": return "English"; default: return "Русский" }
    }

    // MARK: Режим заведения

    private var hostModeCard: some View {
        Button {
            if session.isGuest { showGuestPrompt = true }
            else if host.state.hasAccount { hostMode = true }
            else { activeSheet = .hostMode }
        } label: {
            HStack(spacing: 14) {
                SanIconTile(systemName: "storefront.fill", filled: true, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Режим заведения").font(.golos(16, .bold)).foregroundStyle(Color.sanAccentText)
                    Text("Управляйте своим бизнесом").font(.golos(13, .medium)).foregroundStyle(Color.sanInkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.sanAccentText)
            }
            .padding(14)
            .sanGroupCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: Мои отзывы

    @ViewBuilder private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SanSectionHeader("Мои отзывы")
                // Свои отзывы тоже больше не приезжают со стартом приложения:
                // раньше они приходили в общей выгрузке всей коллекции.
                .task(id: store.currentUserID) { await store.loadMyReviews() }
            if session.isGuest {
                Text("Отзывы привязаны к аккаунту. Войдите или создайте аккаунт, чтобы оценивать блюда и услуги.")
                    .font(.golos(15, .regular)).foregroundStyle(Color.sanInkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16).sanGroupCard()
            } else if store.myReviews.isEmpty {
                Text("Вы ещё не оставили ни одного отзыва.")
                    .font(.golos(15, .regular)).foregroundStyle(Color.sanInkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16).sanGroupCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.myReviews.enumerated()), id: \.element.id) { idx, review in
                        Button { activeSheet = .editReview(review) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(store.venue(id: review.venueID)?.name ?? "Заведение")
                                        .font(.golos(15, .bold)).foregroundStyle(Color.sanInk)
                                    Spacer()
                                    StarRatingView(rating: Double(review.rating), size: 11)
                                }
                                if !review.text.isEmpty {
                                    Text(review.text).font(.golos(13, .regular))
                                        .foregroundStyle(Color.sanInkSoft).lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 13)
                        }
                        .buttonStyle(.plain)
                        if idx < store.myReviews.count - 1 { SanHairline(leading: 14) }
                    }
                }
                .sanGroupCard()
            }
        }
    }

    // MARK: Пригласить друга

    @ViewBuilder private var referralSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SanSectionHeader("Пригласить друга")
            if session.isGuest {
                Text("Войдите в аккаунт, чтобы приглашать друзей и получать бонусы.")
                    .font(.golos(14, .regular)).foregroundStyle(Color.sanInkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16).sanGroupCard()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ShareLink(
                        item: DeepLinkRouter.referralURL(store.referralCode),
                        subject: Text("Ayant"),
                        message: Text("Лови скидки и акции города в Ayant. Заходи по моей ссылке — бонусы получим оба!")
                    ) {
                        HStack(spacing: 12) {
                            SanIconTile(systemName: "person.2.fill", size: 34)
                            Text("Поделиться приглашением").font(.golos(16, .semibold)).foregroundStyle(Color.sanInk)
                            Spacer()
                            Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.sanAccentText)
                        }
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        AnalyticsLog.log(.referralInvite, ["user_id": store.referralCode])
                    })
                    Text("Друг получит приветственные бонусы, а ты — за каждого, кто присоединится.")
                        .font(.golos(13, .regular)).foregroundStyle(Color.sanInkSoft)
                }
                .padding(14).sanGroupCard()
            }
        }
    }

    // MARK: Помощь

    private var helpGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            SanSectionHeader("Помощь")
            VStack(spacing: 0) {
                NavigationLink { AboutView() } label: { linkRow("О приложении") }.buttonStyle(.plain)
                SanHairline(leading: 14)
                NavigationLink { FAQView() } label: { linkRow("Вопросы и ответы") }.buttonStyle(.plain)
                SanHairline(leading: 14)
                NavigationLink { SupportView() } label: { linkRow("Поддержка") }.buttonStyle(.plain)
                SanHairline(leading: 14)
                HStack {
                    Text("Версия").font(.golos(16, .medium)).foregroundStyle(Color.sanInk)
                    Spacer()
                    Text(Self.bundleVersion).font(.golos(15, .semibold)).foregroundStyle(Color.sanInkSoft)
                }
                .padding(.horizontal, 14).padding(.vertical, 14)
            }
            .sanGroupCard()
        }
    }

    /// «X (Y)» из Info.plist — маркетинговая версия и номер сборки. Раньше
    /// строка была захардкожена и отставала от релизов.
    private static var bundleVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    private func linkRow(_ title: String) -> some View {
        HStack {
            Text(title).font(.golos(16, .medium)).foregroundStyle(Color.sanInk)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.sanInkSoft)
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
    }

    // MARK: Аккаунт

    private var accountCard: some View {
        VStack(spacing: 0) {
            Button { accountConfirm = .signOut } label: {
                accountRow("Выйти", icon: "rectangle.portrait.and.arrow.right")
            }.buttonStyle(.plain)
            SanHairline(leading: 14)
            Button { accountConfirm = .delete } label: {
                accountRow("Удалить аккаунт", icon: "trash")
            }.buttonStyle(.plain)
        }
        // Выход и удаление ждут сеть (отписка от push, облачная функция):
        // пока идут — спиннер и заблокированные строки, иначе второй тап
        // запускал операцию повторно, а экран ничем не показывал, что занят.
        .disabled(session.isWorking)
        .opacity(session.isWorking ? 0.5 : 1)
        .overlay { if session.isWorking { ProgressView() } }
        // Алерт ошибки — на внутреннем стеке: на одной вьюхе SwiftUI покажет
        // только одну презентацию, а ниже уже висит диалог подтверждения.
        .alert("Не удалось удалить аккаунт", isPresented: Binding(
            get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("Ок") { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .sanGroupCard()
        // Выход тоже спрашиваем: у гостя он безвозвратный — анонимная запись
        // вместе с её баллами удаляется, вернуться в неё нельзя.
        .confirmationDialog(
            accountConfirm == .delete ? "Удалить аккаунт?" : "Выйти из аккаунта?",
            isPresented: Binding(get: { accountConfirm != nil },
                                 set: { if !$0 { accountConfirm = nil } }),
            titleVisibility: .visible,
            presenting: accountConfirm
        ) { action in
            switch action {
            case .signOut:
                Button("Выйти", role: .destructive) { session.signOut() }
            case .delete:
                Button("Удалить аккаунт", role: .destructive) {
                    // Раньше здесь стоял signOut(): пользователь «удалялся»
                    // только с экрана, а запись и данные оставались в Firebase.
                    //
                    // Вход через Apple: сначала повторная шторка Apple — она даёт
                    // `authorizationCode`, которым отзываем грант (App Review
                    // 5.1.1(v)); удаление запускает уже лист. Остальные
                    // провайдеры удаляются сразу.
                    if session.user?.provider == .apple {
                        activeSheet = .appleDelete
                    } else {
                        session.deleteAccount { error in deleteError = error }
                    }
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: { action in
            switch action {
            case .signOut:
                Text(session.isGuest
                     ? "Гостевой аккаунт нельзя восстановить: бонусы и купоны этой сессии будут удалены."
                     : "Вы вернётесь на экран входа. Данные аккаунта сохранятся.")
            case .delete:
                Text("Это действие необратимо. Все отзывы, сохранённое, баллы и купоны будут удалены.")
            }
        }
    }

    private func accountRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold)).frame(width: 34)
            Text(title).font(.golos(16, .semibold))
            Spacer()
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 14).padding(.vertical, 14)
    }
}

/// Единый источник модальных листов профиля.
private enum ProfileSheet: Identifiable {
    case editReview(Review)
    case hostMode
    /// Повторная шторка Apple перед удалением аккаунта — за `authorizationCode`.
    case appleDelete

    var id: String {
        switch self {
        case .editReview(let r): return "review_\(r.id)"
        case .hostMode: return "hostMode"
        case .appleDelete: return "appleDelete"
        }
    }
}

// MARK: - Подтверждение удаления через Apple

/// Лист «Подтвердите удаление через Apple».
///
/// Apple требует отозвать грант Sign in with Apple при удалении аккаунта
/// (App Review 5.1.1(v)), а для отзыва нужен СВЕЖИЙ `authorizationCode` — его
/// даёт только повторная шторка. Scope не запрашиваем: имя и почта уже есть,
/// а лишний запрос показал бы пользователю «поделиться почтой?» на удалении.
///
/// Отмена шторки закрывает лист молча; прочие отказы Apple уходят в алерт
/// профиля через `onFailure`. Кнопка — отдельная вьюха по той же причине, что
/// `AppleSignInButton` на экране входа: её нельзя пересобирать под открытой
/// шторкой.
private struct AppleDeleteConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCode: (String) -> Void
    let onFailure: (String) -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "trash.circle.fill")
                .font(.system(size: 44)).foregroundStyle(.red)
                .padding(.top, 12)
            Text("Подтвердите удаление через Apple")
                .font(.golos(20, .bold)).foregroundStyle(Color.sanInk)
                .multilineTextAlignment(.center)
            Text("Вы входили через Apple. Чтобы отвязать аккаунт от Apple ID и удалить его, подтвердите действие ещё раз.")
                .font(.golos(15, .regular)).foregroundStyle(Color.sanInkSoft)
                .multilineTextAlignment(.center)
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = []
            } onCompletion: { result in
                handle(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Button("Отмена") { dismiss() }
                .font(.golos(15, .medium)).foregroundStyle(Color.sanInkSoft)
            Spacer(minLength: 0)
        }
        .padding(24)
        .sanScreenBackground()
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            dismiss()
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return   // пользователь сам закрыл шторку — это не ошибка
            }
            onFailure(AuthError.appleFailed.errorDescription ?? "")
        case .success(let auth):
            dismiss()
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let data = cred.authorizationCode,
                  let code = String(data: data, encoding: .utf8)
            else {
                onFailure(AuthError.appleFailed.errorDescription ?? "")
                return
            }
            onCode(code)
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AyantStores.app())
        .environmentObject(AyantStores.session())
        .environmentObject(AyantStores.theme())
        .environmentObject(AyantStores.host())
        .environmentObject(AyantStores.coupons())
        .tint(.sanAccent)
}
