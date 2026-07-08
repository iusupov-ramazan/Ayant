import SwiftUI
import UIKit

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
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SanScreenTitle("Отзывы")
                    if reviews.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(reviews) { r in reviewCard(r) }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 28)
            }
            .sanScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $replyingTo) { r in HostReplyView(review: r) }
        }
    }

    private func reviewCard(_ r: Review) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.venue(id: r.venueID)?.name ?? "Заведение")
                .font(.golos(13, .bold)).foregroundStyle(Color.sanAccent)
            ReviewRow(review: r)
            Button { replyingTo = r } label: {
                Text(r.hostReply == nil ? "Ответить" : "Изменить ответ")
                    .font(.golos(13, .semibold)).foregroundStyle(Color.sanAccent)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.sanAccent.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sanCard(padding: 0)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            SanIconTile(systemName: "star.bubble.fill", filled: true, size: 64)
            Text("Пока нет отзывов").font(.golos(18, .bold)).foregroundStyle(Color.sanInk)
            Text("Поделитесь заведением, чтобы получить первые отзывы.")
                .font(.golos(15, .regular)).foregroundStyle(Color.sanInkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(24).padding(.top, 40)
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
            .sanFormBackground()
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
                VStack(alignment: .leading, spacing: 18) {
                    SanScreenTitle("Аналитика")
                    periodPills
                    if host.venueDTOs.isEmpty {
                        emptyState
                    } else {
                        heroCard
                        statGrid
                        perVenueSection
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 28)
            }
            .sanScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .task(id: "\(period)-\(host.venueDTOs.count)") { await load() }
            .refreshable { await load() }
        }
    }

    // MARK: Период

    private var periodPills: some View {
        HStack(spacing: 8) {
            ForEach(days, id: \.self) { d in
                let sel = d == period
                Button { period = d } label: {
                    Text("\(d) дней")
                        .font(.golos(14, .semibold))
                        .foregroundStyle(sel ? Color.white : Color.sanInkSoft)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(sel ? AnyShapeStyle(LinearGradient.sanAccentGradient)
                                        : AnyShapeStyle(Color.sanSurface), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.sanHairline, lineWidth: sel ? 0 : 0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Герой (просмотры)

    private var heroCard: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Просмотры профиля")
                    .font(.golos(15, .medium)).foregroundStyle(.white.opacity(0.9))
                Text("\(total(AnalyticsMetric.views))")
                    .font(.golos(46, .heavy)).foregroundStyle(.white)
                Text("за \(period) дней")
                    .font(.golos(13, .medium)).foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            if loading {
                ProgressView().tint(.white)
            } else {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 54, height: 54).background(.white.opacity(0.18), in: Circle())
            }
        }
        .padding(20)
        .background(LinearGradient.sanAccentGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.sanAccent.opacity(0.28), radius: 20, y: 10)
    }

    // MARK: Сетка метрик

    private var statGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            metricCard("Погашено купонов", AnalyticsMetric.redemptions, "checkmark.seal.fill")
            metricCard("Клики по акциям", AnalyticsMetric.dealTaps, "hand.tap.fill")
            metricCard("Сохранения", AnalyticsMetric.saves, "bookmark.fill")
            metricCard("Звонки", AnalyticsMetric.calls, "phone.fill")
            metricCard("Маршруты", AnalyticsMetric.maps, "map.fill")
        }
    }

    private func metricCard(_ title: String, _ key: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SanIconTile(systemName: icon, size: 36)
            Text("\(total(key))").font(.golos(24, .bold)).foregroundStyle(Color.sanInk)
            Text(title).font(.golos(13, .medium)).foregroundStyle(Color.sanInkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .sanCard(padding: 0)
    }

    // MARK: По заведениям

    private var perVenueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("По заведениям").font(.golos(18, .bold)).foregroundStyle(Color.sanInk)
            ForEach(host.venueDTOs) { v in
                HStack(spacing: 12) {
                    VenuePhoto(urlString: v.imageURL)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.name).font(.golos(15, .semibold)).foregroundStyle(Color.sanInk)
                        Text("\(stats[v.id]?[AnalyticsMetric.redemptions] ?? 0) погашено")
                            .font(.golos(13, .medium)).foregroundStyle(Color.sanInkSoft)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "eye.fill").font(.system(size: 12))
                        Text("\(stats[v.id]?[AnalyticsMetric.views] ?? 0)").font(.golos(15, .bold))
                    }
                    .foregroundStyle(Color.sanAccent)
                }
                .padding(12)
                .sanCard(padding: 0)
            }
        }
    }

    // MARK: Пусто

    private var emptyState: some View {
        VStack(spacing: 14) {
            SanIconTile(systemName: "chart.line.uptrend.xyaxis", filled: true, size: 64)
            Text("Данных пока нет").font(.golos(18, .bold)).foregroundStyle(Color.sanInk)
            Text("Статистика появится после первых просмотров заведения.")
                .font(.golos(15, .regular)).foregroundStyle(Color.sanInkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(24).padding(.top, 40)
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
    @EnvironmentObject private var store: AppStore
    @State private var showCreate = false
    @State private var stats: [String: (views: Int, taps: Int)] = [:]   // campaignID → метрики

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SanScreenTitle("Продвижение")
                    promoHero
                    typeCards
                    if host.campaigns.isEmpty {
                        emptyHint
                    } else {
                        Text("Ваши кампании").font(.golos(18, .bold)).foregroundStyle(Color.sanInk)
                            .padding(.top, 2)
                        ForEach(host.campaigns) { c in campaignCard(c) }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 28)
            }
            .sanScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HostPromoteTarget.self) { HostPromoteCreateView(venueID: $0.venueID) }
            .sheet(isPresented: $showCreate) {
                NavigationStack { HostPromoteCreateView(venueID: nil) }
            }
            .task(id: host.campaigns.count) { await loadStats() }
        }
    }

    // MARK: Герой

    private var promoHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "megaphone.fill").font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("Больше гостей — быстрее").font(.golos(22, .bold)).foregroundStyle(.white)
                Text("Поднимите заведение в ленте или отправьте push об акции. Запуск за минуту.")
                    .font(.golos(14, .regular)).foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { showCreate = true } label: {
                Text(host.venueDTOs.isEmpty ? "Сначала добавьте заведение" : "Запустить продвижение")
                    .font(.golos(16, .bold)).foregroundStyle(Color.sanAccentDeep)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain).disabled(host.venueDTOs.isEmpty).opacity(host.venueDTOs.isEmpty ? 0.7 : 1)
        }
        .padding(20)
        .background(LinearGradient.sanAccentGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.sanAccent.opacity(0.28), radius: 20, y: 10)
    }

    // MARK: Типы

    private var typeCards: some View {
        HStack(spacing: 12) {
            typeCard("megaphone.fill", "Буст в ленте", "Заведение выше в списке, с меткой «Реклама».")
            typeCard("bell.badge.fill", "Push", "Сообщите гостям об акции уведомлением.")
        }
    }

    private func typeCard(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        Button { showCreate = true } label: {
            VStack(alignment: .leading, spacing: 10) {
                SanIconTile(systemName: icon, size: 40)
                Text(title).font(.golos(15, .bold)).foregroundStyle(Color.sanInk)
                Text(subtitle).font(.golos(12, .medium)).foregroundStyle(Color.sanInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(14).sanCard(padding: 0)
        }
        .buttonStyle(.plain).disabled(host.venueDTOs.isEmpty)
    }

    private var emptyHint: some View {
        Text("Пока нет активных кампаний. Запустите первую — и заведение начнёт получать больше просмотров.")
            .font(.golos(14, .regular)).foregroundStyle(Color.sanInkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16).sanGroupCard()
    }

    // MARK: Карточка кампании

    private func campaignCard(_ c: AdCampaign) -> some View {
        let status = c.effectiveStatus
        let m = stats[c.id]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SanIconTile(systemName: c.kind == .boost ? "megaphone.fill" : "bell.badge.fill", size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L(c.kind.title)).font(.golos(16, .bold)).foregroundStyle(Color.sanInk)
                    Text(host.venueDTO(id: c.venueID)?.name ?? "Заведение")
                        .font(.golos(13, .medium)).foregroundStyle(Color.sanInkSoft)
                }
                Spacer(minLength: 6)
                HStack(spacing: 5) {
                    Circle().fill(status.isLive ? Color.sanOpen : Color.sanInkSoft).frame(width: 6, height: 6)
                    Text(L(status.title)).font(.golos(12, .bold))
                        .foregroundStyle(status.isLive ? Color.sanOpen : Color.sanInkSoft)
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background((status.isLive ? Color.sanOpen : Color.sanInkSoft).opacity(0.14), in: Capsule())
            }
            HStack(spacing: 18) {
                metric("eye.fill", "\(m?.views ?? c.impressions)")
                metric("hand.tap.fill", "\(m?.taps ?? c.taps)")
                metric("creditcard.fill", "\(c.spend) сом")
            }
            if status == .active || status == .scheduled {
                Button { host.cancelCampaign(id: c.id) } label: { Text("Отменить кампанию") }
                    .buttonStyle(SanPillButton())
            }
        }
        .padding(14)
        .sanCard(padding: 0)
    }

    private func metric(_ icon: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
            Text(value).font(.golos(14, .semibold))
        }
        .foregroundStyle(Color.sanInkSoft)
    }

    /// Живая аналитика по каждой кампании: просмотры и клики заведения за период
    /// кампании (из AnalyticsService). Push-клики считаем по dealTaps.
    private func loadStats() async {
        for c in host.campaigns {
            let days = max(1, Calendar.current.dateComponents([.day], from: c.startAt, to: .now).day ?? 1)
            let raw = await store.analyticsStats(venueID: c.venueID, days: days)
            let views = raw[AnalyticsMetric.views] ?? 0
            let taps = (raw[AnalyticsMetric.dealTaps] ?? 0) + (raw[AnalyticsMetric.maps] ?? 0)
            stats[c.id] = (views: views, taps: taps)
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

    private let durations = [7, 14, 30, 0]        // 0 = бессрочно
    private func price(_ d: Int) -> Int { d == 0 ? 3000 : d * 150 }
    private func durationLabel(_ d: Int) -> String {
        d == 0 ? "Бессрочно — \(price(0)) сом" : "\(d) дней — \(price(d)) сом"
    }

    var body: some View {
        Form {
            Section("Заведение") {
                NavigationLink {
                    VenueSearchPicker(venues: host.venueDTOs, selected: $selectedVenue)
                } label: {
                    HStack {
                        Text("Заведение")
                        Spacer()
                        Text(host.venueDTO(id: selectedVenue)?.name ?? "Выбрать")
                            .foregroundStyle(.secondary)
                    }
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
                    Picker("Срок", selection: $duration) {
                        ForEach(durations, id: \.self) { Text(durationLabel($0)).tag($0) }
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
        .sanFormBackground()
        .navigationTitle("Новая кампания")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedVenue.isEmpty {
                selectedVenue = venueID ?? host.venueDTOs.first?.id ?? ""
            }
        }
    }

    private func launch() {
        // Бессрочно (duration == 0) → дата далеко в будущем.
        let boostDays = duration == 0 ? 365 * 50 : duration
        let end = Calendar.current.date(byAdding: .day, value: kind == .boost ? boostDays : 1, to: .now)!
        // Push — разовая отправка (сразу «Отправлено»); буст — «Активна» до конца срока.
        let c = AdCampaign(id: host.campaignID(), kind: kind, venueID: selectedVenue,
                           status: kind == .push ? .sent : .active, startAt: .now, endAt: end,
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

// MARK: - Поиск заведения (с клавиатурой)

struct VenueSearchPicker: View {
    let venues: [HostVenueDTO]
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [HostVenueDTO] {
        query.isEmpty ? venues
            : venues.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List(filtered) { v in
            Button {
                selected = v.id
                dismiss()
            } label: {
                HStack {
                    Text(v.name).foregroundStyle(.primary)
                    Spacer()
                    if v.id == selected {
                        Image(systemName: "checkmark").foregroundStyle(Color.sanAccent)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Поиск заведения")
        .autocorrectionDisabled()
        .navigationTitle("Заведение")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Tab 5 — Профиль хоста

struct HostProfileView: View {
    @EnvironmentObject private var host: HostStore
    @EnvironmentObject private var session: SessionStore
    @AppStorage("san.hostMode") private var hostMode = false
    @AppStorage("san.host.notify") private var notify = true

    private var isVerified: Bool { host.profile?.verification == .verified }
    private var isPending: Bool { host.profile?.verification == .pending }
    private var businessName: String { host.profile?.businessName ?? "" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SanScreenTitle("Профиль заведения")
                    headerCard
                    businessInfoCard
                    verificationCard
                    notificationsCard
                    paymentCard
                    actionsCard
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 32)
            }
            .sanScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: Шапка

    private var headerCard: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient.sanAccentGradient)
                .frame(width: 64, height: 64)
                .overlay(
                    Group {
                        if let f = businessName.first {
                            Text(String(f).uppercased()).font(.golos(28, .heavy)).foregroundStyle(.white)
                        } else {
                            Image(systemName: "storefront.fill").font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    })
            VStack(alignment: .leading, spacing: 4) {
                Text(businessName.isEmpty ? "Ваш бизнес" : businessName)
                    .font(.golos(20, .bold)).foregroundStyle(Color.sanInk).lineLimit(1)
                verificationBadge
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .sanCard(padding: 0)
    }

    private var verificationBadge: some View {
        let color: Color = isVerified ? .sanOpen : (isPending ? .orange : .sanInkSoft)
        let icon = isVerified ? "checkmark.seal.fill" : (isPending ? "clock.fill" : "seal")
        return HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold))
            Text(host.profile?.verification.title ?? "Не подтверждено").font(.golos(12, .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
    }

    // MARK: Информация о бизнесе (отдельный экран)

    private var businessInfoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SanSectionHeader("Информация о бизнесе")
            NavigationLink { HostBusinessInfoView() } label: {
                HStack(spacing: 12) {
                    SanIconTile(systemName: "building.2.fill", size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Реквизиты и контакты")
                            .font(.golos(16, .semibold)).foregroundStyle(Color.sanInk)
                        Text(infoSummary)
                            .font(.golos(13, .medium)).foregroundStyle(Color.sanInkSoft)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.sanInkSoft)
                }
                .padding(14)
                .sanGroupCard()
            }
            .buttonStyle(.plain)
        }
    }

    private var infoSummary: String {
        guard let p = host.profile else { return "Название, телефон, ИП, ИНН…" }
        var parts: [String] = []
        if !p.legalForm.isEmpty { parts.append(p.legalForm) }
        if !p.phone.isEmpty { parts.append(p.phone) }
        if !p.inn.isEmpty { parts.append("ИНН \(p.inn)") }
        return parts.isEmpty ? "Заполнить реквизиты и контакты" : parts.joined(separator: " · ")
    }

    // MARK: Верификация

    private var verificationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SanSectionHeader("Верификация")
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    SanIconTile(systemName: "checkmark.seal.fill",
                                tint: isVerified ? .sanOpen : .sanAccent, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isVerified ? "Заведение проверено" : (isPending ? "На проверке" : "Не подтверждено"))
                            .font(.golos(16, .semibold)).foregroundStyle(Color.sanInk)
                        Text(isVerified ? "У вас есть синяя галочка."
                             : "Галочка повышает доверие гостей.")
                            .font(.golos(13, .regular)).foregroundStyle(Color.sanInkSoft)
                    }
                    Spacer()
                }
                if !isVerified && !isPending {
                    Button { host.requestVerification() } label: { Text("Запросить «Проверено»") }
                        .buttonStyle(SanPillButton(accent: true))
                }
            }
            .padding(14)
            .sanGroupCard()
        }
    }

    // MARK: Уведомления

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SanSectionHeader("Уведомления")
            HStack(spacing: 12) {
                SanIconTile(systemName: "bell.fill", size: 34)
                Text("Новые отзывы и статусы кампаний")
                    .font(.golos(15, .medium)).foregroundStyle(Color.sanInk)
                Spacer()
                Toggle("", isOn: $notify).labelsHidden().tint(.sanAccent)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .sanGroupCard()
        }
    }

    // MARK: Оплата

    private var paymentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SanSectionHeader("Оплата")
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    SanIconTile(systemName: "creditcard.fill", size: 34)
                    Text("Способ оплаты").font(.golos(16, .medium)).foregroundStyle(Color.sanInk)
                    Spacer()
                    Text("Payme / Click").font(.golos(15, .semibold)).foregroundStyle(Color.sanInkSoft)
                }
                Text("Подключение платёжных методов появится позже.")
                    .font(.golos(13, .regular)).foregroundStyle(Color.sanInkSoft)
            }
            .padding(14)
            .sanGroupCard()
        }
    }

    // MARK: Действия

    private var actionsCard: some View {
        VStack(spacing: 10) {
            Button { hostMode = false } label: {
                Label("Вернуться в режим пользователя", systemImage: "person.crop.circle")
            }
            .buttonStyle(SanPillButton())
            Button { session.signOut() } label: {
                Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.golos(15, .semibold)).foregroundStyle(.red)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Информация о бизнесе (отдельный экран)

struct HostBusinessInfoView: View {
    @EnvironmentObject private var host: HostStore
    @ObservedObject private var catStore = CategoryStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var category: VenueCategory = .cafe
    @State private var phone = ""
    @State private var email = ""
    @State private var legalForm = ""
    @State private var legalName = ""
    @State private var inn = ""
    @State private var regAddress = ""
    @State private var website = ""
    @State private var about = ""

    private let forms = ["", "ИП", "ООО", "Самозанятый"]

    var body: some View {
        Form {
            Section("Основное") {
                TextField("Название бизнеса", text: $name)
                Picker("Категория", selection: $category) {
                    ForEach(catStore.categories) { Text($0.locKey).tag($0) }
                }
                TextField("Телефон", text: $phone).keyboardType(.phonePad)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never)
            }
            Section {
                Picker("Форма деятельности", selection: $legalForm) {
                    ForEach(forms, id: \.self) { Text($0.isEmpty ? "Не указано" : $0).tag($0) }
                }
                TextField(legalForm == "ООО" ? "Название юрлица" : "ФИО предпринимателя", text: $legalName)
                TextField("ИНН / ОГРНИП", text: $inn).keyboardType(.numbersAndPunctuation)
                TextField("Юридический адрес", text: $regAddress)
            } header: {
                Text("Форма и реквизиты")
            } footer: {
                Text("Эти данные видны только вам и модерации Ayant — они помогают быстрее пройти верификацию.")
            }
            Section("Дополнительно") {
                TextField("Сайт", text: $website)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("О бизнесе (коротко)", text: $about, axis: .vertical).lineLimit(3...6)
            }
        }
        .sanFormBackground()
        .navigationTitle("Информация о бизнесе")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { save() } }
        }
        .onAppear(perform: populate)
    }

    private func populate() {
        guard let p = host.profile else { return }
        name = p.businessName; category = p.category; phone = p.phone; email = p.email
        legalForm = p.legalForm; legalName = p.legalName; inn = p.inn
        regAddress = p.registrationAddress; website = p.website; about = p.about
    }

    private func save() {
        host.updateBusinessInfo(businessName: name, category: category, phone: phone, email: email,
                                legalForm: legalForm, legalName: legalName, inn: inn,
                                registrationAddress: regAddress, website: website, about: about)
        dismiss()
    }
}
