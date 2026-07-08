import SwiftUI

/// Главная: лента заведений выбранного города (по спецификации).
struct HomeFeedView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var location: LocationManager
    @State private var category: VenueCategory?
    @State private var path = NavigationPath()
    @State private var visibleCount = 8       // пагинация ленты
    private static let pageSize = 8

    private var feed: [Deal] {
        store.feedDeals(category: category)
    }
    private var items: [FeedItem] {
        store.feedItems(category: category)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 18) {
                    categoryRow
                    if !store.savedTodaySpecials.isEmpty {
                        todaySpecialStrip
                    }
                    feedContent
                }
                .padding(.vertical, 10)
            }
            .refreshable { await store.load() }
            .navigationTitle("Ayant · \(store.selectedCity.name)")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Venue.self) { VenueDetailView(venue: $0) }
            .navigationDestination(for: Deal.self) { DealDetailView(deal: $0, isPushed: true) }
            // Сброс пагинации при смене категории.
            .onChange(of: category) { _, _ in visibleCount = Self.pageSize }
        }
    }

    // MARK: Категории-сторис

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                CategoryStoryCircle(label: "Все", icon: "square.grid.2x2.fill",
                                    color: .orange, isOn: category == nil) { category = nil }
                ForEach(VenueCategory.allCases) { cat in
                    CategoryStoryCircle(label: cat.rawValue, icon: cat.icon,
                                        color: .sanAccent, isOn: category == cat) {
                        category = (category == cat) ? nil : cat
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: «Сегодня» — горизонтальная лента специалов сохранённых заведений

    private var todaySpecialStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Сегодня в избранном", systemImage: "star.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.sanAccent)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.savedTodaySpecials) { venue in
                        NavigationLink(value: venue) { specialCard(venue) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func specialCard(_ venue: Venue) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(colors: venue.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(venue.emoji).font(.system(size: 40))
            }
            .frame(width: 220, height: 90)
            .clipped()
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(venue.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if venue.isOpenNow {
                        Text("Открыто").font(.caption2.weight(.semibold)).foregroundStyle(.green)
                    }
                }
                Text(venue.todaySpecialText ?? "")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(10)
        }
        .frame(width: 220)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.sanAccent.opacity(0.4), lineWidth: 1))
    }

    // MARK: Основная лента

    @ViewBuilder
    private var feedContent: some View {
        if store.isLoading {
            ProgressView().padding(.top, 40)
        } else if store.venuesInSelectedCity().isEmpty {
            emptyCity
        } else if feed.isEmpty {
            emptyCategory
        } else {
            let shown = Array(items.prefix(visibleCount))
            ForEach(shown) { item in
                switch item {
                case .deal(let deal):
                    DealCard(deal: deal,
                             onTap: { path.append(deal) },
                             onVenueTap: { if let v = store.venue(for: deal) { path.append(v) } })
                        .padding(.horizontal, 16)
                        .onAppear { loadMoreIfNeeded(item, in: shown) }
                case .adVenue(let venue):
                    Button { path.append(venue) } label: {
                        VenueCard(venue: venue,
                                  distanceKm: location.distanceKm(to: venue.latitude, venue.longitude),
                                  isSponsored: true)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .onAppear { loadMoreIfNeeded(item, in: shown) }
                }
            }
            if visibleCount < items.count {
                ProgressView().padding(.vertical, 16)
            }
        }
    }

    private func loadMoreIfNeeded(_ item: FeedItem, in shown: [FeedItem]) {
        guard item.id == shown.last?.id, visibleCount < items.count else { return }
        visibleCount = min(visibleCount + Self.pageSize, items.count)
    }

    private var emptyCity: some View {
        ContentUnavailableView {
            Label("Пока нет заведений в \(store.selectedCity.name)", systemImage: "storefront")
        } description: {
            Text("Знаешь хорошее место? Помоги нам — добавь заведение.")
        }
        .padding(.top, 40)
    }

    private var emptyCategory: some View {
        VStack(spacing: 12) {
            ContentUnavailableView {
                Label("Нет предложений в категории", systemImage: "tray")
            } description: {
                Text("В категории «\(category?.rawValue ?? "")» в городе \(store.selectedCity.name) пока нет акций.")
            }
            Button("Сбросить фильтр") { category = nil }
                .buttonStyle(.bordered)
                .tint(.sanAccent)
        }
        .padding(.top, 40)
    }
}

#Preview {
    HomeFeedView()
        .environmentObject(AppStore())
        .environmentObject(LocationManager())
        .tint(.sanAccent)
}
