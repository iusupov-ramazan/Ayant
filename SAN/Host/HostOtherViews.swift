import SwiftUI
import UIKit
import AyantDomain
import AyantFeatures

// MARK: - Tab 4 — Отзывы (инбокс по всем заведениям)

/// Отзывы (SCREENS.md H10) — инбокс по всем заведениям владельца.
struct HostReviewsView: View {
    @EnvironmentObject private var host: HostStore
    @EnvironmentObject private var store: AppStore
    @State private var replyingTo: Review?
    @State private var filter: ReviewFilter = .all

    enum ReviewFilter: Hashable { case all, unanswered, low }

    private var allReviews: [Review] {
        store.reviews(forVenueIDs: host.state.ownedVenueIDs).sorted { a, b in
            // Неотвеченные выше, затем новые.
            if (a.hostReply == nil) != (b.hostReply == nil) { return a.hostReply == nil }
            return a.createdAt > b.createdAt
        }
    }

    private var reviews: [Review] {
        switch filter {
        case .all: return allReviews
        case .unanswered: return allReviews.filter { $0.hostReply == nil }
        case .low: return allReviews.filter { $0.rating <= 2 }
        }
    }

    private var pending: Int { allReviews.filter { $0.hostReply == nil }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 10) {
                        Text("Отзывы")
                            .sanEditorialTitle(42)
                            .foregroundStyle(Color.sanInk)
                        if pending > 0 {
                            Text("\(pending) без ответа")
                                .font(.golos(12, .heavy)).foregroundStyle(.white)
                                .lineLimit(1).fixedSize()
                                .padding(.horizontal, 11).padding(.vertical, 6)
                                .background(Color.sanAccentDeep, in: Capsule())
                        }
                        Spacer(minLength: 0)
                    }
                    filterChips
                    if reviews.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 11) {
                            ForEach(Array(reviews.enumerated()), id: \.element.id) { index, r in
                                reviewCard(r)
                                    .sanRise(index, stagger: 0.08, duration: 0.5)
                            }
                        }
                    }
                }
                .padding(.horizontal, SanMetrics.screenPadding)
                .padding(.top, 12).padding(.bottom, 28)
                .sanScreenEnter()
            }
            .sanScreenBackground()
            .sanStatusBarCap()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $replyingTo) { r in HostReplyView(review: r) }
        }
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            chip("Все", .all)
            chip("Без ответа", .unanswered)
            chip("1–2 ★", .low)
            Spacer(minLength: 0)
        }
    }

    private func chip(_ title: LocalizedStringKey, _ value: ReviewFilter) -> some View {
        let isOn = filter == value
        return Button {
            SanHaptics.selection()
            withAnimation(.sanStandard) { filter = value }
        } label: {
            Text(title)
                .font(.golos(13, .bold))
                .foregroundStyle(isOn ? Color.white : Color.sanInkSoft)
                .padding(.horizontal, 15).padding(.vertical, 9)
                .background {
                    if isOn { Capsule().fill(LinearGradient.sanAccentGradient) }
                    else { Capsule().fill(Color.sanSurface)
                        .overlay(Capsule().strokeBorder(Color.sanHairline, lineWidth: 0.5)) }
                }
        }
        .buttonStyle(.sanPress(0.93))
    }

    private func reviewCard(_ r: Review) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Circle()
                    .fill(LinearGradient.sanAccentGradient)
                    .frame(width: 38, height: 38)
                    .overlay(Text(r.initial).font(.golos(15, .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.authorName).font(.golos(14.5, .bold)).foregroundStyle(Color.sanInk)
                    Text("\(store.venue(id: r.venueID)?.name ?? "Заведение") · \(r.dateText)")
                        .font(.golos(11.5)).foregroundStyle(Color(hex: 0x9A9188))
                }
                Spacer(minLength: 8)
                // Низкие оценки красим иначе — их видно в списке сразу.
                Text(String(repeating: "★", count: max(1, min(5, r.rating))))
                    .font(.golos(13.5, .heavy))
                    .foregroundStyle(r.rating <= 2 ? Color(hex: 0xE8556B) : Color(hex: Palette.orange))
            }

            if !r.text.isEmpty {
                Text(r.text)
                    .sanText(14, .regular, lineHeight: 1.5)
                    .foregroundStyle(Color(hex: 0x3D362F))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }

            if let reply = r.hostReply, !reply.text.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Ваш ответ")
                        .textCase(.uppercase)
                        .font(.golos(11, .heavy)).tracking(0.9)
                        .foregroundStyle(Color.sanAccentText)
                    Text(reply.text)
                        .font(.golos(13.5)).foregroundStyle(Color.sanInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.sanCanvas, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.sanAccent).frame(width: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                .padding(.top, 12)
                .onTapGesture { replyingTo = r }
            } else {
                Button { replyingTo = r } label: {
                    Text("Ответить")
                        .font(.golos(13, .bold)).foregroundStyle(Color.sanAccentText)
                        .padding(.horizontal, 15).padding(.vertical, 9)
                        .background(Color.sanAccent.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.sanPress(0.94))
                .padding(.top, 12)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sanCard(padding: 0, radius: SanRadius.card)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            SanIconTile(systemName: "star.bubble.fill", filled: true, size: 64)
            Text("Пока нет отзывов").font(.golos(18, .bold)).foregroundStyle(Color.sanInk)
            Text("Поделитесь заведением, чтобы получить первые отзывы.")
                .font(.golos(15)).foregroundStyle(Color.sanInkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(24).padding(.top, 40)
    }
}

/// Ответ на отзыв (SCREENS.md H11).
struct HostReplyView: View {
    let review: Review
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var host: HostStore
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var focused: Bool

    private static let quickReplies: [String] = [
        "Спасибо за отзыв!",
        "Извините за ожидание",
        "Приходите ещё — исправимся",
        "Напишите нам в директ",
    ]

    init(review: Review) {
        self.review = review
        _text = State(initialValue: review.hostReply?.text ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    quoted
                    replyField
                    quickChips
                }
                .padding(.horizontal, SanMetrics.screenPadding)
                .padding(.top, 12).padding(.bottom, 24)
            }
            .sanScreenBackground()
            .safeAreaInset(edge: .bottom) { sendBar }
            .navigationTitle("Ответ на отзыв")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            }
        }
    }

    private var quoted: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Circle()
                    .fill(LinearGradient.sanAccentGradient)
                    .frame(width: 34, height: 34)
                    .overlay(Text(review.initial).font(.golos(14, .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.authorName).font(.golos(14, .bold)).foregroundStyle(Color.sanInk)
                    Text(review.dateText).font(.golos(11.5)).foregroundStyle(Color(hex: 0x9A9188))
                }
                Spacer(minLength: 8)
                Text(String(repeating: "★", count: max(1, min(5, review.rating))))
                    .font(.golos(13, .heavy))
                    .foregroundStyle(review.rating <= 2 ? Color(hex: 0xE8556B) : Color(hex: Palette.orange))
            }
            if !review.text.isEmpty {
                Text(review.text)
                    .sanText(13.5, .regular, lineHeight: 1.5)
                    .foregroundStyle(Color.sanInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sanSurfaceMuted,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var replyField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ваш ответ")
                .textCase(.uppercase)
                .sanEyebrowText()
                .foregroundStyle(Color(hex: 0x9A9188))
            TextField("", text: $text, axis: .vertical)
                .focused($focused)
                .lineLimit(4...10)
                .font(.golos(14.5))
                .tint(Color.sanAccent)      // акцентная каретка
                .foregroundStyle(Color.sanInk)
                .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                .padding(16)
                .sanCard(padding: 0, radius: SanRadius.card)
        }
    }

    private var quickChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Быстрые ответы")
                .textCase(.uppercase)
                .sanEyebrowText()
                .foregroundStyle(Color(hex: 0x9A9188))
            FlowChips(items: Self.quickReplies) { phrase in
                SanHaptics.selection()
                text = text.isEmpty ? phrase : text + " " + phrase
                focused = true
            }
        }
    }

    private var sendBar: some View {
        Button {
            store.setHostReply(reviewID: review.id, text: text)
            dismiss()
        } label: {
            Text("Отправить ответ")
        }
        .buttonStyle(SanPrimaryButton())
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 14)
        .background {
            ZStack(alignment: .top) {
                Color.sanCanvas.opacity(0.92).background(.ultraThinMaterial)
                Rectangle().fill(Color.sanHairline).frame(height: 0.5)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Переносящийся ряд чипов (быстрые ответы, теги).
struct FlowChips: View {
    let items: [String]
    var onTap: (String) -> Void

    var body: some View {
        // Простая раскладка в две колонки: чипы длинные, в строку не помещаются.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    Text(item)
                        .font(.golos(13, .semibold))
                        .foregroundStyle(Color.sanInk)
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Color.sanSurface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.sanHairline, lineWidth: 0.5))
                }
                .buttonStyle(.sanPress(0.95))
            }
        }
    }
}

// MARK: - Tab 3 — Аналитика

/// Аналитика (SCREENS.md H9). График строится из настоящего ряда по дням
/// (`fetchDailyStats`) — рисовать столбики из выдуманных чисел нельзя.
struct HostAnalyticsView: View {
    @EnvironmentObject private var host: HostStore
    @EnvironmentObject private var store: AppStore
    @State private var period = 30
    @State private var stats: [String: [String: Int]] = [:]       // venueID → метрики
    @State private var series: [Int] = []                          // столбики графика
    @State private var loading = false

    private let days = [7, 30, 90]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Аналитика")
                        .sanEditorialTitle(42)
                        .foregroundStyle(Color.sanInk)
                    periodPills
                    if host.state.venues.isEmpty {
                        emptyState
                    } else {
                        heroCard
                        statGrid
                        perVenueSection
                    }
                }
                .padding(.horizontal, SanMetrics.screenPadding)
                .padding(.top, 12).padding(.bottom, 28)
                .sanScreenEnter()
            }
            .sanScreenBackground()
            .sanStatusBarCap()
            .toolbar(.hidden, for: .navigationBar)
            .task(id: "\(period)-\(host.state.venues.count)") { await load() }
            .refreshable { await load() }
        }
    }

    // MARK: Период

    private var periodPills: some View {
        HStack(spacing: 8) {
            ForEach(days, id: \.self) { d in
                let sel = d == period
                Button {
                    SanHaptics.selection()
                    period = d
                } label: {
                    Text("\(d) дней")
                        .font(.golos(13.5, .bold))
                        .foregroundStyle(sel ? Color.white : Color.sanInkSoft)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(sel ? AnyShapeStyle(LinearGradient.sanAccentGradient)
                                        : AnyShapeStyle(Color.sanSurface), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.sanHairline, lineWidth: sel ? 0 : 0.5))
                }
                .buttonStyle(.sanPress(0.94))
            }
        }
    }

    // MARK: Герой + график

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Просмотры профиля")
                        .font(.golos(13.5, .semibold)).foregroundStyle(.white.opacity(0.9))
                    Text("\(total(AnalyticsMetric.views))")
                        .sanText(48, .heavy, tracking: -2.6, lineHeight: 1)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: total(AnalyticsMetric.views))
                    Text("за \(period) дней")
                        .font(.golos(12.5)).foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 8)
                if loading { ProgressView().tint(.white) }
            }
            if !series.isEmpty {
                AnalyticsBarChart(values: series, period: period).padding(.top, 20)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.sanAccentGradient,
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .sanShadow(.hero)
    }

    // MARK: Сетка метрик

    private var statGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 11), count: 2), spacing: 11) {
            metricCard("Погашено купонов", AnalyticsMetric.redemptions, "checkmark.seal.fill")
            metricCard("Клики по акциям", AnalyticsMetric.dealTaps, "hand.tap.fill")
            metricCard("Сохранения", AnalyticsMetric.saves, "bookmark.fill")
            metricCard("Звонки", AnalyticsMetric.calls, "phone.fill")
            metricCard("Маршруты", AnalyticsMetric.maps, "map.fill")
        }
    }

    private func metricCard(_ title: LocalizedStringKey, _ key: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SanIconTile(systemName: icon, size: 34)
            Text("\(total(key))")
                .sanText(26, .heavy, tracking: -1.1)
                .foregroundStyle(Color.sanInk)
            Text(title).font(.golos(12, .semibold)).foregroundStyle(Color.sanInkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .sanCard(padding: 0, radius: SanRadius.card)
    }

    // MARK: По заведениям

    private var perVenueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("По заведениям")
                .textCase(.uppercase)
                .sanEyebrowText()
                .foregroundStyle(Color(hex: 0x9A9188))
            VStack(spacing: 0) {
                ForEach(Array(host.state.venues.enumerated()), id: \.element.id) { index, v in
                    if index > 0 { SanHairline(leading: 72) }
                    HStack(spacing: 14) {
                        VenuePhoto(urlString: v.imageURL)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.name).font(.golos(14.5, .bold)).foregroundStyle(Color.sanInk)
                            Text("\(stats[v.id]?[AnalyticsMetric.redemptions] ?? 0) погашено")
                                .font(.golos(12)).foregroundStyle(Color.sanInkSoft)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(stats[v.id]?[AnalyticsMetric.views] ?? 0)")
                                .font(.golos(17, .heavy)).foregroundStyle(Color.sanInk)
                            Text("просмотров").font(.golos(11)).foregroundStyle(Color.sanInkSoft)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                }
            }
            .sanGroupCard(radius: SanRadius.card)
        }
    }

    // MARK: Пусто

    private var emptyState: some View {
        VStack(spacing: 14) {
            SanIconTile(systemName: "chart.line.uptrend.xyaxis", filled: true, size: 64)
            Text("Данных пока нет").font(.golos(18, .bold)).foregroundStyle(Color.sanInk)
            Text("Статистика появится после первых просмотров заведения.")
                .font(.golos(15)).foregroundStyle(Color.sanInkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(24).padding(.top, 40)
    }

    private func load() async {
        loading = true
        var result: [String: [String: Int]] = [:]
        var daily: [String: Int] = [:]     // день → просмотры по всем заведениям
        for v in host.state.venues {
            result[v.id] = await store.analyticsStats(venueID: v.id, days: period)
            for (day, metrics) in await store.analyticsDaily(venueID: v.id, days: period) {
                daily[day, default: 0] += metrics[AnalyticsMetric.views] ?? 0
            }
        }
        stats = result
        series = Self.buckets(daily: daily, period: period)
        loading = false
    }

    /// Ряд по дням → столбики: 7 дней = 7 столбиков, иначе 12 равных корзин.
    /// Пустой ряд возвращает пустой массив — график тогда не рисуется вовсе.
    static func buckets(daily: [String: Int], period: Int) -> [Int] {
        guard !daily.isEmpty else { return [] }
        let ordered = daily.keys.sorted().map { daily[$0] ?? 0 }
        let count = period <= 7 ? min(7, ordered.count) : 12
        guard ordered.count > count else { return ordered }
        let size = Double(ordered.count) / Double(count)
        return (0..<count).map { i in
            let lo = Int((Double(i) * size).rounded(.down))
            let hi = min(ordered.count, Int((Double(i + 1) * size).rounded(.down)))
            return ordered[lo..<max(hi, lo + 1)].reduce(0, +)
        }
    }

    private func total(_ metric: String) -> Int {
        stats.values.reduce(0) { $0 + ($1[metric] ?? 0) }
    }
}

/// 12 (или 7) столбиков, растущих от базовой линии с шагом 45 мс (ANIMATIONS.md §6).
/// Пересобирается при смене периода — это намеренно читается как «данные загрузились».
struct AnalyticsBarChart: View {
    let values: [Int]
    let period: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    private var maxValue: Int { max(values.max() ?? 1, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                let fraction = CGFloat(v) / CGFloat(maxValue)
                UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 2,
                                       bottomTrailingRadius: 2, topTrailingRadius: 5,
                                       style: .continuous)
                    .fill(.white.opacity(0.55))
                    .frame(height: max(4, 74 * fraction * (grown ? 1 : 0)))
                    .animation(reduceMotion ? nil
                               : .sanStandard(0.7).delay(Double(i) * 0.045), value: grown)
            }
        }
        .frame(height: 74, alignment: .bottom)
        .onAppear { grown = true }
        .onChange(of: period) { _, _ in
            grown = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { grown = true }
        }
    }
}

struct HostPromoteView: View {
    @EnvironmentObject private var host: HostStore
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var showCreate = false
    @State private var stats: [String: (views: Int, taps: Int)] = [:]   // campaignID → метрики

    var body: some View {
        // Без собственного NavigationStack: этот экран ВСЕГДА открывается
        // пушем с «Заведений» (у «Продвижения» нет своей вкладки), а стек
        // внутри пуша ломал сам переход — по кнопке ничего не происходило.
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Продвижение")
                    .sanEditorialTitle(42)
                    .foregroundStyle(Color.sanInk)
                promoHero
                typeCards
                if host.state.campaigns.isEmpty {
                    emptyHint
                } else {
                    Text("Ваши кампании")
                        .textCase(.uppercase)
                        .sanEyebrowText()
                        .foregroundStyle(Color(hex: 0x9A9188))
                        .padding(.top, 2)
                    ForEach(Array(host.state.campaigns.enumerated()), id: \.element.id) { index, c in
                        campaignCard(c).sanRise(index, stagger: 0.08, duration: 0.5)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 28)
        }
        // Экран открывается пушем, поэтому ему нужна кнопка «назад». Раньше
        // здесь стоял `.toolbar(.hidden, for: .navigationBar)` — он был уместен,
        // пока экран был корнем вкладки со своим стеком, а после переезда на
        // пуш просто прятал единственный выход: «Заведения» пропадали насовсем.
        .sanNavBar { dismiss() }
        .sanScreenBackground()
        // Системную панель прячем — «назад» даёт `sanNavBar`, иначе кнопки две.
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: HostPromoteTarget.self) { HostPromoteCreateView(venueID: $0.venueID) }
        .sheet(isPresented: $showCreate) {
            NavigationStack { HostPromoteCreateView(venueID: nil) }
        }
        .task(id: host.state.campaigns.count) { await loadStats() }
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
                Text(host.state.venues.isEmpty ? "Сначала добавьте заведение" : "Запустить продвижение")
                    .font(.golos(16, .bold)).foregroundStyle(Color.sanAccentDeep)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain).disabled(host.state.venues.isEmpty).opacity(host.state.venues.isEmpty ? 0.7 : 1)
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
        .buttonStyle(.plain).disabled(host.state.venues.isEmpty)
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
                    Text(host.state.venue(id: c.venueID)?.name ?? "Заведение")
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
            // Полоса «сколько кампании прошло» — из её же дат, не из выдумки.
            SanProgressBar(fraction: c.elapsedFraction, height: 6,
                           track: Color.sanSurfaceMuted, fill: Color.sanAccent)
            HStack(spacing: 18) {
                metric("eye.fill", "\(m?.views ?? c.impressions)")
                metric("hand.tap.fill", "\(m?.taps ?? c.taps)")
                metric("creditcard.fill", "\(c.spend) сом")
            }
            if status == .active || status == .scheduled {
                Button { host.send(.cancelCampaign(id: c.id)) } label: { Text("Отменить кампанию") }
                    .buttonStyle(SanPillButton())
            }
        }
        .padding(15)
        .sanCard(padding: 0, radius: SanRadius.card)
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
        for c in host.state.campaigns {
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

    private var venueDeals: [HostDealDTO] { host.state.deals(forVenue: selectedVenue) }

    private let durations = [7, 14, 30, 0]        // 0 = бессрочно
    private func price(_ d: Int) -> Int { d == 0 ? 3000 : d * 150 }
    private func durationLabel(_ d: Int) -> String {
        d == 0 ? "Бессрочно — \(price(0)) сом" : "\(d) дней — \(price(d)) сом"
    }

    var body: some View {
        VStack(spacing: 0) {
            SanFormHeader(title: "Новая кампания") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Тип кампании — карточки с ценой за день (SCREENS.md H8).
                    HStack(spacing: 10) {
                        kindCard(.boost, "Буст в ленте", "180 сом/день")
                        kindCard(.push, "Push", "240 сом/день")
                    }

                    SanFieldCard {
                        SanFieldRow(label: "Заведение") {
                            NavigationLink {
                                VenueSearchPicker(venues: host.state.venues, selected: $selectedVenue)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(host.state.venue(id: selectedVenue)?.name ?? "Выбрать")
                                        .font(.golos(15.5, .semibold))
                                        .foregroundStyle(selectedVenue.isEmpty ? Color(hex: 0xC0B8AE) : Color.sanInk)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Color.sanInkSoft)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        if kind == .push {
                            SanHairline(leading: 16)
                            SanFieldRow(label: "Что продвигаем") {
                                Menu {
                                    Button("Вся витрина заведения") { selectedDeal = "" }
                                    ForEach(venueDeals) { d in Button(d.title) { selectedDeal = d.id } }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(venueDeals.first { $0.id == selectedDeal }?.title
                                             ?? "Вся витрина заведения")
                                            .font(.golos(15.5, .semibold)).foregroundStyle(Color.sanInk)
                                            .lineLimit(1)
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Color.sanInkSoft)
                                        Spacer(minLength: 0)
                                    }
                                }
                            }
                            SanHairline(leading: 16)
                            SanFieldRow(label: "Заголовок push (до 60)") {
                                SanFieldInput(placeholder: "Скидка 30% сегодня", text: $pushHeadline)
                            }
                            SanHairline(leading: 16)
                            SanFieldRow(label: "Текст push (до 120)") {
                                SanFieldInput(placeholder: "Приходите с 11 до 15", text: $pushBody, axis: .vertical)
                            }
                        }
                    }
                    .onChange(of: selectedDeal) { _, id in
                        if let d = venueDeals.first(where: { $0.id == id }) {
                            pushHeadline = String(d.title.prefix(60))
                            pushBody = String(d.details.prefix(120))
                        }
                    }
                    .onChange(of: pushHeadline) { _, v in if v.count > 60 { pushHeadline = String(v.prefix(60)) } }
                    .onChange(of: pushBody) { _, v in if v.count > 120 { pushBody = String(v.prefix(120)) } }

                    if kind == .boost { durationCard }

                    previewPanel
                }
                .padding(.horizontal, SanMetrics.screenPadding)
                .padding(.top, 4).padding(.bottom, 24)
            }
            SanStickyFooter {
                HStack {
                    Text("Итого").font(.golos(13.5, .semibold)).foregroundStyle(Color.sanInkSoft)
                    Spacer()
                    Text("\(price(kind == .boost ? duration : 0)) сом")
                        .font(.golos(24, .heavy)).tracking(-0.9)
                        .foregroundStyle(Color.sanInk)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: duration)
                }
                Button("Запустить кампанию") { launch() }
                    .buttonStyle(SanPrimaryButton())
                    .disabled(selectedVenue.isEmpty)
                    .opacity(selectedVenue.isEmpty ? 0.6 : 1)
            }
        }
        .sanScreenBackground()
        .sanStatusBarCap()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if selectedVenue.isEmpty {
                selectedVenue = venueID ?? host.state.venues.first?.id ?? ""
            }
        }
    }

    private func kindCard(_ value: AdCampaign.Kind, _ title: LocalizedStringKey,
                          _ rate: LocalizedStringKey) -> some View {
        let isOn = kind == value
        return Button {
            SanHaptics.selection()
            withAnimation(.sanStandard) { kind = value }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.golos(14.5, .heavy))
                    .foregroundStyle(isOn ? Color.white : Color.sanInk)
                Text(rate)
                    .font(.golos(11.5))
                    .foregroundStyle(isOn ? Color.white.opacity(0.88) : Color.sanInkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background {
                let shape = RoundedRectangle(cornerRadius: SanRadius.card, style: .continuous)
                if isOn {
                    shape.fill(LinearGradient.sanAccentGradient)
                        .shadow(color: Color.sanAccent.opacity(0.28), radius: 12, y: 10)
                } else {
                    shape.fill(Color.sanSurface)
                        .overlay(shape.strokeBorder(Color.sanHairline, lineWidth: 0.5))
                }
            }
        }
        .buttonStyle(.sanPress(0.97))
    }

    private var durationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(duration) \(Self.daysWord(duration))")
                .sanText(34, .heavy, tracking: -1.6)
                .foregroundStyle(Color.sanInk)
            HStack(spacing: 8) {
                ForEach(durations, id: \.self) { d in
                    let isOn = d == duration
                    Button {
                        SanHaptics.selection()
                        withAnimation(.sanStandard) { duration = d }
                    } label: {
                        Text(d == 0 ? "∞" : "\(d)")
                            .font(.golos(13.5, .bold))
                            .foregroundStyle(isOn ? Color.white : Color.sanInkSoft)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background {
                                if isOn { Capsule().fill(LinearGradient.sanAccentGradient) }
                                else {
                                    Capsule().fill(Color.sanSurface)
                                        .overlay(Capsule().strokeBorder(Color.sanHairline, lineWidth: 0.5))
                                }
                            }
                    }
                    .buttonStyle(.sanPress(0.93))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sanCard(padding: 0, radius: SanRadius.card)
    }

    /// Предпросмотр на кремовой riso-панели: как заведение выглядит в ленте
    /// с меткой «РЕКЛАМА».
    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Предпросмотр")
                .textCase(.uppercase)
                .sanEyebrowText()
                .foregroundStyle(Color.sanEyebrow)
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(colors: host.state.venue(id: selectedVenue)?.asVenue.gradientColors
                                         ?? [.sanAccent, Color(hex: Palette.orange)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(host.state.venue(id: selectedVenue)?.name ?? "Ваше заведение")
                        .font(.golos(14, .bold)).foregroundStyle(Color.sanInk).lineLimit(1)
                    Text("Реклама")
                        .textCase(.uppercase)
                        .font(.golos(9.5, .heavy)).tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(LinearGradient.sanAccentGradient, in: Capsule())
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.86),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text("Так гости увидят вас в ленте")
                .font(.golos(12)).foregroundStyle(Color(hex: 0x7A5B41))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sanSandPanel(radius: SanRadius.hero)
    }

    private static func daysWord(_ n: Int) -> String {
        if n == 0 { return "бессрочно" }
        let n10 = n % 10, n100 = n % 100
        if n10 == 1 && n100 != 11 { return "день" }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return "дня" }
        return "дней"
    }

    private func launch() {
        // Бессрочно (duration == 0) → дата далеко в будущем.
        let boostDays = duration == 0 ? 365 * 50 : duration
        let end = Calendar.current.date(byAdding: .day, value: kind == .boost ? boostDays : 1, to: .now)!
        // Push — разовая отправка (сразу «Отправлено»); буст — «Активна» до конца срока.
        let c = AdCampaign(id: host.campaignID(), kind: kind, venueID: selectedVenue,
                           status: kind == .push ? .sent : .active, startAt: .now, endAt: end,
                           impressions: 0, taps: 0, spend: kind == .boost ? price(duration) : 100)
        host.send(.addCampaign(c))
        // Буст в ленте: помечаем заведение boostedUntil — оно поднимется вверх с меткой «Реклама».
        if kind == .boost {
            host.send(.boostVenue(id: selectedVenue, until: end))
        }
        // Push-кампания: реально ставим в очередь рассылки (Cloud Function → FCM).
        if kind == .push {
            let venueName = host.state.venue(id: selectedVenue)?.name ?? "заведение"
            host.send(.launchPush(
                headline: pushHeadline.isEmpty ? venueName : pushHeadline,
                body: pushBody.isEmpty ? "Новое предложение в \(venueName)" : pushBody,
                venueID: selectedVenue,
                dealID: selectedDeal.isEmpty ? nil : selectedDeal))
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
                        Image(systemName: "checkmark").foregroundStyle(Color.sanAccentText)
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
    @Environment(\.dismiss) private var dismiss
    @AppStorage("san.hostMode") private var hostMode = false
    @AppStorage("san.host.notify") private var notify = true
    @State private var showSignOutConfirm = false

    private var isVerified: Bool { host.state.profile?.verification == .verified }
    private var isPending: Bool { host.state.profile?.verification == .pending }
    private var businessName: String { host.state.profile?.businessName ?? "" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 10) {
                        Text("Профиль")
                            .sanEditorialTitle(42)
                            .foregroundStyle(Color.sanInk)
                        if isVerified {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.seal.fill").font(.system(size: 12))
                                Text("Проверено").font(.golos(12, .bold))
                            }
                            .foregroundStyle(Color.sanOpen)
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(Color.sanOpen.opacity(0.12), in: Capsule())
                        }
                        Spacer(minLength: 0)
                    }
                    headerCard
                    businessInfoCard
                    verificationCard
                    notificationsCard
                    paymentCard
                    actionsCard
                }
                .padding(.horizontal, SanMetrics.screenPadding)
                .padding(.top, 12).padding(.bottom, 32)
                .sanScreenEnter()
            }
            .sanNavBar { dismiss() }
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
            Text(host.state.profile?.verification.title ?? "Не подтверждено").font(.golos(12, .semibold))
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
        guard let p = host.state.profile else { return "Название, телефон, ИП, ИНН…" }
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
                    Button { host.send(.requestVerification) } label: { Text("Запросить «Проверено»") }
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
            // Спрашиваем подтверждение, как и в профиле пользователя: случайный
            // тап здесь выкидывает владельца из режима заведения посреди работы.
            Button { showSignOutConfirm = true } label: {
                Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.golos(15, .semibold)).foregroundStyle(.red)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .confirmationDialog("Выйти из аккаунта?", isPresented: $showSignOutConfirm,
                            titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { session.signOut() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Вы вернётесь на экран входа. Заведения и статистика сохранятся.")
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
        guard let p = host.state.profile else { return }
        name = p.businessName; category = p.category; phone = p.phone; email = p.email
        legalForm = p.legalForm; legalName = p.legalName; inn = p.inn
        regAddress = p.registrationAddress; website = p.website; about = p.about
    }

    private func save() {
        host.send(.updateBusinessInfo(BusinessInfo(
            businessName: name, category: category, phone: phone, email: email,
            legalForm: legalForm, legalName: legalName, inn: inn,
            registrationAddress: regAddress, website: website, about: about)))
        dismiss()
    }
}
