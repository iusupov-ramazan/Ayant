import SwiftUI

// MARK: - Tab 4 — Отзывы (инбокс по всем заведениям)

struct HostReviewsView: View {
    @EnvironmentObject private var host: HostStore
    @EnvironmentObject private var store: AppStore
    @State private var replyingTo: Review?

    private var reviews: [Review] {
        store.reviews(forVenueIDs: host.ownedVenueIDs).sorted { a, b in
            // Неотвеченные выше, затем новые.
            if (a.hostReply == nil) != (b.hostReply == nil) { return a.hostReply == nil }
            return a.createdAt > b.createdAt
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if reviews.isEmpty {
                    ContentUnavailableView("Пока нет отзывов", systemImage: "star.bubble",
                        description: Text("Поделитесь заведением, чтобы получить первые отзывы."))
                } else {
                    List {
                        ForEach(reviews) { r in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(store.venue(id: r.venueID)?.name ?? "Заведение")
                                    .font(.caption.weight(.semibold)).foregroundStyle(Color.sanAccent)
                                ReviewRow(review: r)
                                Button(r.hostReply == nil ? "Ответить" : "Изменить ответ") { replyingTo = r }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.bordered).tint(.sanAccent)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Отзывы")
            .sheet(item: $replyingTo) { r in HostReplyView(review: r) }
        }
    }
}

struct HostReplyView: View {
    let review: Review
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(review: Review) {
        self.review = review
        _text = State(initialValue: review.hostReply?.text ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Отзыв гостя") {
                    StarRatingView(rating: Double(review.rating), size: 12)
                    Text(review.text).font(.subheadline)
                }
                Section("Ваш ответ (виден всем)") {
                    TextField("Поблагодарите или ответьте на замечание…", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Ответ на отзыв")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Опубликовать") {
                        store.setHostReply(reviewID: review.id, text: text)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Tab 3 — Аналитика

struct HostAnalyticsView: View {
    @EnvironmentObject private var host: HostStore
    @EnvironmentObject private var store: AppStore
    @State private var period = 7
    @State private var stats: [String: [String: Int]] = [:]   // venueID → метрики
    @State private var loading = false

    private let days = [7, 30, 90]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("Период", selection: $period) {
                        ForEach(days, id: \.self) { Text("\($0)д").tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if host.venueDTOs.isEmpty {
                        ContentUnavailableView("Данных пока нет", systemImage: "chart.line.uptrend.xyaxis",
                            description: Text("Статистика появится после первых просмотров заведения."))
                            .padding(.top, 40)
                    } else {
                        if loading { ProgressView().frame(maxWidth: .infinity) }
                        aggregateGrid
                        perVenue
                    }
                }
                .padding(16)
            }
            .navigationTitle("Аналитика")
            .task(id: "\(period)-\(host.venueDTOs.count)") { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        loading = true
        var result: [String: [String: Int]] = [:]
        for v in host.venueDTOs {
            result[v.id] = await store.analyticsStats(venueID: v.id, days: period)
        }
        stats = result
        loading = false
    }

    private func total(_ metric: String) -> Int {
        stats.values.reduce(0) { $0 + ($1[metric] ?? 0) }
    }

    private var aggregateGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            statCard("Просмотры профиля", total(AnalyticsMetric.views), "eye.fill")
            statCard("Погашено купонов", total(AnalyticsMetric.redemptions), "checkmark.seal.fill")
            statCard("Клики по предложениям", total(AnalyticsMetric.dealTaps), "hand.tap.fill")
            statCard("Сохранения", total(AnalyticsMetric.saves), "bookmark.fill")
            statCard("Звонки", total(AnalyticsMetric.calls), "phone.fill")
            statCard("Маршруты", total(AnalyticsMetric.maps), "map.fill")
        }
    }

    private func statCard(_ title: String, _ value: Int, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(Color.sanAccent)
            Text("\(value)").font(.title2.weight(.bold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var perVenue: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("По заведениям").font(.headline)
            ForEach(host.venueDTOs) { v in
                HStack {
                    Text(v.emoji)
                    Text(v.name).font(.subheadline.weight(.medium))
                    Spacer()
                    Label("\(stats[v.id]?[AnalyticsMetric.views] ?? 0)", systemImage: "eye")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

/// Детерминированные демо-метрики (без бэкенда).
enum HostMetrics {
    static func value(_ id: String, _ metric: String, _ days: Int) -> Int {
        let seed = (id + metric).unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let base = [ "views": 40, "taps": 12, "saves": 6, "calls": 3, "maps": 4 ][metric] ?? 5
        return (seed % 7 + 1) * base * days / 7
    }
}

// MARK: - Tab 2 — Продвижение

struct HostPromoteView: View {
    @EnvironmentObject private var host: HostStore
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            Group {
                if host.campaigns.isEmpty {
                    ContentUnavailableView {
                        Label("Нет активных кампаний", systemImage: "megaphone")
                    } description: {
                        Text("Продвигайте заведение, чтобы попасть в рекламные слоты ленты.")
                    } actions: {
                        Button("Запустить буст") { showCreate = true }
                            .buttonStyle(.borderedProminent).tint(.sanAccent)
                            .disabled(host.venueDTOs.isEmpty)
                    }
                } else {
                    List {
                        ForEach(host.campaigns) { c in campaignRow(c) }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Продвижение")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                        .disabled(host.venueDTOs.isEmpty)
                }
            }
            .navigationDestination(for: HostPromoteTarget.self) { HostPromoteCreateView(venueID: $0.venueID) }
            .sheet(isPresented: $showCreate) {
                NavigationStack { HostPromoteCreateView(venueID: nil) }
            }
        }
    }

    private func campaignRow(_ c: AdCampaign) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(c.kind.title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(c.status.title).font(.caption2.weight(.semibold))
                    .foregroundStyle(c.status == .active ? .green : .secondary)
            }
            Text(host.venueDTO(id: c.venueID)?.name ?? "Заведение")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Label("\(c.impressions)", systemImage: "eye")
                Label("\(c.taps)", systemImage: "hand.tap")
                Label("\(c.spend) сом", systemImage: "creditcard")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .swipeActions {
            if c.status == .active || c.status == .scheduled {
                Button(role: .destructive) { host.cancelCampaign(id: c.id) } label: {
                    Label("Отменить", systemImage: "xmark")
                }
            }
        }
    }
}

struct HostPromoteCreateView: View {
    let venueID: String?
    @EnvironmentObject private var host: HostStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedVenue: String = ""
    @State private var selectedDeal: String = ""    // "" = вся витрина заведения
    @State private var kind: AdCampaign.Kind = .boost
    @State private var duration = 7
    @State private var pushHeadline = ""
    @State private var pushBody = ""

    private var venueDeals: [HostDealDTO] { host.deals(forVenue: selectedVenue) }

    private let durations = [7, 14, 30]
    private func price(_ d: Int) -> Int { d * 150 }

    var body: some View {
        Form {
            Section("Заведение") {
                Picker("Заведение", selection: $selectedVenue) {
                    ForEach(host.venueDTOs) { Text($0.name).tag($0.id) }
                }
            }
            Section("Тип") {
                Picker("Тип", selection: $kind) {
                    Text("Буст в ленте").tag(AdCampaign.Kind.boost)
                    Text("Push-уведомление").tag(AdCampaign.Kind.push)
                }.pickerStyle(.segmented)
            }
            if kind == .boost {
                Section("Длительность") {
                    Picker("Дней", selection: $duration) {
                        ForEach(durations, id: \.self) { Text("\($0) дней — \(price($0)) сом").tag($0) }
                    }
                }
            } else {
                Section("Что продвигаем") {
                    Picker("Предложение", selection: $selectedDeal) {
                        Text("Вся витрина заведения").tag("")
                        ForEach(venueDeals) { Text($0.title).tag($0.id) }
                    }
                    .onChange(of: selectedDeal) { _, id in
                        if let d = venueDeals.first(where: { $0.id == id }) {
                            pushHeadline = String(d.title.prefix(60))
                            pushBody = String(d.details.prefix(120))
                        }
                    }
                    if !selectedDeal.isEmpty {
                        Text("Нажав на push, пользователь откроет это предложение.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Section("Текст уведомления") {
                    TextField("Заголовок (до 60)", text: $pushHeadline)
                        .onChange(of: pushHeadline) { _, v in if v.count > 60 { pushHeadline = String(v.prefix(60)) } }
                    TextField("Текст (до 120)", text: $pushBody, axis: .vertical).lineLimit(2...4)
                        .onChange(of: pushBody) { _, v in if v.count > 120 { pushBody = String(v.prefix(120)) } }
                }
            }
            Section {
                Button("Оплатить и запустить") { launch() }
                    .frame(maxWidth: .infinity)
                    .disabled(selectedVenue.isEmpty)
            }
        }
        .navigationTitle("Новая кампания")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedVenue.isEmpty {
                selectedVenue = venueID ?? host.venueDTOs.first?.id ?? ""
            }
        }
    }

    private func launch() {
        let end = Calendar.current.date(byAdding: .day, value: kind == .boost ? duration : 1, to: .now)!
        let c = AdCampaign(id: host.campaignID(), kind: kind, venueID: selectedVenue,
                           status: .active, startAt: .now, endAt: end,
                           impressions: 0, taps: 0, spend: kind == .boost ? price(duration) : 100)
        host.addCampaign(c)
        // Буст в ленте: помечаем заведение boostedUntil — оно поднимется вверх с меткой «Реклама».
        if kind == .boost {
            host.boostVenue(id: selectedVenue, until: end)
        }
        // Push-кампания: реально ставим в очередь рассылки (Cloud Function → FCM).
        if kind == .push {
            let venueName = host.venueDTO(id: selectedVenue)?.name ?? "заведение"
            host.launchPush(headline: pushHeadline.isEmpty ? venueName : pushHeadline,
                            body: pushBody.isEmpty ? "Новое предложение в \(venueName)" : pushBody,
                            venueID: selectedVenue,
                            dealID: selectedDeal.isEmpty ? nil : selectedDeal)
        }
        dismiss()
    }
}

// MARK: - Tab 5 — Профиль хоста

struct HostProfileView: View {
    @EnvironmentObject private var host: HostStore
    @EnvironmentObject private var session: SessionStore
    @AppStorage("san.hostMode") private var hostMode = false
    @AppStorage("san.host.notify") private var notify = true
    @State private var businessName = ""
    @State private var phone = ""
    @State private var email = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Бизнес-профиль") {
                    TextField("Название бизнеса", text: $businessName)
                    TextField("Телефон", text: $phone).keyboardType(.phonePad)
                    TextField("Email", text: $email).keyboardType(.emailAddress)
                    Button("Сохранить") {
                        host.updateProfile(businessName: businessName, phone: phone, email: email)
                    }
                    .font(.subheadline.weight(.semibold))
                }

                Section("Верификация") {
                    LabeledContent("Статус", value: host.profile?.verification.title ?? "—")
                    if host.profile?.verification != .verified && host.profile?.verification != .pending {
                        Button("Запросить галочку «Проверено»") { host.requestVerification() }
                    }
                }

                Section("Уведомления") {
                    Toggle("Новые отзывы и статусы кампаний", isOn: $notify)
                }

                Section("Оплата") {
                    LabeledContent("Способ оплаты", value: "Payme / Click")
                    Text("Подключение платёжных методов появится позже.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Button { hostMode = false } label: {
                        Label("Вернуться в режим пользователя", systemImage: "person.crop.circle")
                    }
                    Button(role: .destructive) { session.signOut() } label: {
                        Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Профиль заведения")
            .onAppear {
                businessName = host.profile?.businessName ?? ""
                phone = host.profile?.phone ?? ""
                email = host.profile?.email ?? ""
            }
        }
    }
}
