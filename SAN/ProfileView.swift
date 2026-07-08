import SwiftUI

/// Профиль пользователя (по спецификации): отзывы, настройки, переключение в режим хоста.
struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var host: HostStore
    @EnvironmentObject private var coupons: CouponStore
    @AppStorage("san.hostMode") private var hostMode = false

    @AppStorage("san.language") private var language = "ru"

    @State private var activeSheet: ProfileSheet?
    @State private var showDeleteConfirm = false
    @State private var showGuestPrompt = false

    private var username: String { session.user?.name ?? "Гость" }

    var body: some View {
        NavigationStack {
            List {
                profileHeader
                couponsSection
                myReviewsSection
                referralSection
                settingsSection
                hostModeSection
                aboutSection
                accountSection
            }
            .navigationTitle("Профиль")
            .alert("Войдите в аккаунт", isPresented: $showGuestPrompt) {
                Button("Войти") { session.signOut() }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Гостям доступен только просмотр. Войдите, чтобы добавлять заведения, сохранять места и оставлять отзывы.")
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .editReview(let review):
                    if let venue = store.venue(id: review.venueID) {
                        WriteReviewView(venue: venue, existing: review)
                    }
                case .hostMode:
                    HostOnboardingView { hostMode = true }
                }
            }
        }
        .onAppear { store.setCurrentUser(id: session.user?.id, name: session.user?.name, isGuest: session.isGuest) }
    }

    // MARK: Шапка

    private var profileHeader: some View {
        Section {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [.sanAccent, .yellow],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(String(username.prefix(1))).font(.title.weight(.bold)).foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(username).font(.headline)
                    if let email = session.user?.email {
                        Text(email).font(.caption).foregroundStyle(.secondary)
                    }
                    Label(L(store.selectedCity.name), systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Мои отзывы

    private var myReviewsSection: some View {
        Section("Мои отзывы") {
            if store.myReviews.isEmpty {
                Text("Ты ещё не оставил ни одного отзыва.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(store.myReviews) { review in
                    Button { activeSheet = .editReview(review) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(store.venue(id: review.venueID)?.name ?? "Заведение")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Spacer()
                                StarRatingView(rating: Double(review.rating), size: 11)
                            }
                            if !review.text.isEmpty {
                                Text(review.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { store.deleteReview(review) } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: Настройки

    private var settingsSection: some View {
        Section("Настройки") {
            // Выбор города отключён — пока доступен только Бишкек.
            LabeledContent {
                Text(L(store.selectedCity.name)).foregroundStyle(.secondary)
            } label: {
                Label("Город", systemImage: "building.2")
            }
            // Picker(selection: Binding(get: { store.selectedCitySlug }, set: { store.selectedCitySlug = $0 })) {
            //     ForEach(MockData.cities) { city in Text(city.name).tag(city.id) }
            // } label: { Label("Город", systemImage: "building.2") }

            Picker(selection: $language) {
                Text("Русский").tag("ru")
                Text("English").tag("en")
                Text("Кыргызча").tag("ky")
            } label: {
                Label("Язык", systemImage: "globe")
            }

            Picker(selection: Binding(get: { themeStore.theme }, set: { themeStore.theme = $0 })) {
                ForEach(AppTheme.allCases) { theme in Label(theme.title, systemImage: theme.icon).tag(theme) }
            } label: {
                Label("Тема", systemImage: "circle.lefthalf.filled")
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: Режим хоста

    private var hostModeSection: some View {
        Section {
            Button {
                if session.isGuest { showGuestPrompt = true }
                else if host.hasAccount { hostMode = true }
                else { activeSheet = .hostMode }
            } label: {
                Label("Переключиться в режим заведения", systemImage: "storefront")
                    .foregroundStyle(Color.sanAccent)
            }
        } footer: {
            if session.isGuest {
                Text("Гость: только просмотр. Войдите, чтобы добавлять заведения и сохранять.")
            }
        }
    }

    // MARK: Купоны

    private var couponsSection: some View {
        Section {
            NavigationLink { MyCouponsView() } label: {
                HStack {
                    Label("Мои купоны", systemImage: "ticket.fill")
                    Spacer()
                    if coupons.activeCount > 0 {
                        Text("\(coupons.activeCount)")
                            .font(.caption.weight(.bold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Color.sanAccent, in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: Пригласить друга (рефералка)

    @ViewBuilder
    private var referralSection: some View {
        Section("Пригласить друга") {
            if session.isGuest {
                Text("Войдите в аккаунт, чтобы приглашать друзей и получать бонусы.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ShareLink(
                    item: DeepLinkRouter.referralURL(store.referralCode),
                    subject: Text("Ayant"),
                    message: Text("Лови скидки и акции города в Ayant. Заходи по моей ссылке — бонусы получим оба!")
                ) {
                    Label("Поделиться приглашением", systemImage: "person.2.fill")
                }
                .simultaneousGesture(TapGesture().onEnded {
                    AnalyticsLog.log(.referralInvite, ["user_id": store.referralCode])
                })
                Text("Друг получит приветственные бонусы, а ты — за каждого, кто присоединится.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: О приложении

    private var aboutSection: some View {
        Section("Помощь") {
            NavigationLink { AboutView() } label: { Label("О приложении", systemImage: "info.circle") }
            NavigationLink { FAQView() } label: { Label("Вопросы и ответы", systemImage: "questionmark.circle") }
            NavigationLink { SupportView() } label: { Label("Поддержка", systemImage: "bubble.left.and.bubble.right") }
            LabeledContent("Версия", value: "0.3 (MVP)")
        }
    }

    // MARK: Аккаунт

    private var accountSection: some View {
        Section {
            Button { session.signOut() } label: {
                Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right").foregroundStyle(.red)
            }
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Удалить аккаунт", systemImage: "trash").foregroundStyle(.red)
            }
        }
        .confirmationDialog("Удалить аккаунт?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Удалить аккаунт", role: .destructive) { session.signOut() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Это действие необратимо. Все отзывы и сохранённое будут удалены.")
        }
    }
}

/// Единый источник модальных листов профиля.
private enum ProfileSheet: Identifiable {
    case editReview(Review)
    case hostMode

    var id: String {
        switch self {
        case .editReview(let r): return "review_\(r.id)"
        case .hostMode: return "hostMode"
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppStore())
        .environmentObject(SessionStore())
        .environmentObject(ThemeStore())
        .environmentObject(HostStore())
        .environmentObject(CouponStore())
        .tint(.sanAccent)
}
