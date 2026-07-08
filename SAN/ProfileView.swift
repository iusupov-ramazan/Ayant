import SwiftUI

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
    @State private var showDeleteConfirm = false
    @State private var showGuestPrompt = false

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
                    referralSection
                    helpGroup
                    accountCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .sanScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
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

    // MARK: Мои купоны

    private var couponsCard: some View {
        NavigationLink { MyCouponsView() } label: {
            HStack(spacing: 12) {
                SanIconTile(systemName: "ticket.fill", size: 34)
                Text("Мои купоны").font(.golos(16, .medium)).foregroundStyle(Color.sanInk)
                Spacer()
                if coupons.activeCount > 0 {
                    Text("\(coupons.activeCount)")
                        .font(.golos(13, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Color.sanAccent, in: Capsule())
                }
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sanInkSoft)
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .sanGroupCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: Настройки

    private var settingsGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            SanSectionHeader("Настройки")
            VStack(spacing: 0) {
                settingRow(icon: "building.2.fill", title: "Город") {
                    Text(L(store.selectedCity.name))
                        .font(.golos(15, .semibold)).foregroundStyle(Color.sanInkSoft)
                }
                SanHairline(leading: 60)
                settingRow(icon: "globe", title: "Язык") {
                    Menu {
                        Button("Русский") { language = "ru" }
                        Button("English") { language = "en" }
                        Button("Кыргызча") { language = "ky" }
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
            Text(value).font(.golos(15, .bold)).foregroundStyle(Color.sanAccent)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.sanInkSoft)
        }
    }

    private var languageTitle: String {
        switch language { case "en": return "English"; case "ky": return "Кыргызча"; default: return "Русский" }
    }

    // MARK: Режим заведения

    private var hostModeCard: some View {
        Button {
            if session.isGuest { showGuestPrompt = true }
            else if host.hasAccount { hostMode = true }
            else { activeSheet = .hostMode }
        } label: {
            HStack(spacing: 14) {
                SanIconTile(systemName: "storefront.fill", filled: true, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Режим заведения").font(.golos(16, .bold)).foregroundStyle(Color.sanAccent)
                    Text("Управляйте своим бизнесом").font(.golos(13, .medium)).foregroundStyle(Color.sanInkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.sanAccent)
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
            if store.myReviews.isEmpty {
                Text("Ты ещё не оставил ни одного отзыва.")
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
                                .foregroundStyle(Color.sanAccent)
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
                    Text("0.3 (MVP)").font(.golos(15, .semibold)).foregroundStyle(Color.sanInkSoft)
                }
                .padding(.horizontal, 14).padding(.vertical, 14)
            }
            .sanGroupCard()
        }
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
            Button { session.signOut() } label: {
                accountRow("Выйти", icon: "rectangle.portrait.and.arrow.right")
            }.buttonStyle(.plain)
            SanHairline(leading: 14)
            Button { showDeleteConfirm = true } label: {
                accountRow("Удалить аккаунт", icon: "trash")
            }.buttonStyle(.plain)
        }
        .sanGroupCard()
        .confirmationDialog("Удалить аккаунт?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Удалить аккаунт", role: .destructive) { session.signOut() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Это действие необратимо. Все отзывы и сохранённое будут удалены.")
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
