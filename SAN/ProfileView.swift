import SwiftUI

/// Профиль пользователя (по спецификации): отзывы, настройки, переключение в режим хоста.
struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var host: HostStore
    @AppStorage("san.hostMode") private var hostMode = false

    @AppStorage("san.notify.deals") private var notifyDeals = true
    @AppStorage("san.notify.replies") private var notifyReplies = true
    @AppStorage("san.language") private var language = "ru"

    @State private var activeSheet: ProfileSheet?
    @State private var showDeleteConfirm = false
    @State private var showGuestPrompt = false

    private var username: String { session.user?.name ?? "Гость" }

    var body: some View {
        NavigationStack {
            List {
                profileHeader
                myReviewsSection
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
                    Label(store.selectedCity.name, systemImage: "mappin.and.ellipse")
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
                Text(store.selectedCity.name).foregroundStyle(.secondary)
            } label: {
                Label("Город", systemImage: "building.2")
            }
            // Picker(selection: Binding(get: { store.selectedCitySlug }, set: { store.selectedCitySlug = $0 })) {
            //     ForEach(MockData.cities) { city in Text(city.name).tag(city.id) }
            // } label: { Label("Город", systemImage: "building.2") }

            Picker(selection: $language) {
                Text("Русский").tag("ru")
                Text("Oʻzbekcha").tag("uz")
                Text("English").tag("en")
            } label: {
                Label("Язык", systemImage: "globe")
            }

            Toggle(isOn: $notifyDeals) {
                Label("Новые акции в избранном", systemImage: "tag")
            }
            Toggle(isOn: $notifyReplies) {
                Label("Ответы на мои отзывы", systemImage: "bubble.left")
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

    // MARK: О приложении

    private var aboutSection: some View {
        Section("О приложении") {
            LabeledContent("Версия", value: "0.2 (MVP)")
            Text("Ayta — заведения, акции и отзывы твоего города. Сначала Бишкек, дальше — вся Центральная Азия.")
                .font(.caption).foregroundStyle(.secondary)
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
        .tint(.sanAccent)
}
