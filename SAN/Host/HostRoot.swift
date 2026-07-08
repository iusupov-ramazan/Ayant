import SwiftUI

// MARK: - Корневая навигация хоста (5 вкладок)

struct HostRootView: View {
    @EnvironmentObject private var host: HostStore
    @EnvironmentObject private var store: AppStore

    private var pendingReviews: Int {
        store.reviews(forVenueIDs: host.ownedVenueIDs).filter { $0.hostReply == nil }.count
    }

    var body: some View {
        TabView {
            HostVenuesView()
                .tabItem { Label("Заведения", systemImage: "storefront.fill") }
            HostPromoteView()
                .tabItem { Label("Продвижение", systemImage: "megaphone.fill") }
            HostAnalyticsView()
                .tabItem { Label("Аналитика", systemImage: "chart.line.uptrend.xyaxis") }
            HostReviewsView()
                .tabItem { Label("Отзывы", systemImage: "star.bubble.fill") }
                .badge(pendingReviews)
            HostProfileView()
                .tabItem { Label("Профиль", systemImage: "person.crop.square.fill") }
        }
        .tint(.sanAccent)
    }
}

// MARK: - Онбординг хоста

struct HostOnboardingView: View {
    @EnvironmentObject private var host: HostStore
    @Environment(\.dismiss) private var dismiss
    var onFinished: () -> Void

    @State private var step = 0
    // Шаг 1
    @State private var businessName = ""
    @State private var category: VenueCategory = .cafe
    @State private var phone = ""
    @State private var email = ""
    // Шаг 2
    @State private var showVenueForm = false

    var body: some View {
        NavigationStack {
            Group {
                if step == 0 { basics } else { firstVenue }
            }
            .navigationTitle("Режим заведения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
            .sheet(isPresented: $showVenueForm, onDismiss: finish) {
                HostVenueFormView(existing: nil)
            }
        }
    }

    // Шаг 1 — основное о бизнесе
    private var basics: some View {
        Form {
            Section {
                Text("Расскажите о вашем бизнесе. Оплата и верификация не требуются.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Бизнес") {
                TextField("Название бизнеса", text: $businessName)
                Picker("Категория", selection: $category) {
                    ForEach(VenueCategory.allCases) { Text($0.locKey).tag($0) }
                }
                TextField("Контактный телефон", text: $phone).keyboardType(.phonePad)
                TextField("Email", text: $email).keyboardType(.emailAddress)
            }
            Section {
                Button("Продолжить") {
                    host.createAccount(businessName: businessName, category: category, phone: phone, email: email)
                    step = 1
                }
                .frame(maxWidth: .infinity)
                .disabled(businessName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // Шаг 2 — первое заведение
    private var firstVenue: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "storefront").font(.system(size: 56)).foregroundStyle(Color.sanAccent)
            Text("Добавим первое заведение?").font(.title3.weight(.bold))
            Text("Можно добавить сейчас или позже — со вкладки «Заведения».")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 10) {
                Button("Добавить заведение сейчас") { showVenueForm = true }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.sanAccent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                Button("Сделаю позже") { finish() }
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
    }

    private func finish() {
        onFinished()
        dismiss()
    }
}
