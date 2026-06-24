import SwiftUI

/// Поиск по заведениям с фильтрами (по спецификации).
struct SearchView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var location: LocationManager

    @State private var query = ""
    @State private var openNow = false
    @State private var minRating = 0        // 0 | 3 | 4
    @State private var maxDistance: Double? = nil   // км: 0.5 | 1 | 3 | 5
    @State private var category: VenueCategory?

    private var results: [Venue] {
        store.venuesInSelectedCity().filter { venue in
            matchesQuery(venue) && matchesFilters(venue)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                if results.isEmpty {
                    ScrollView {
                        ContentUnavailableView("Ничего не нашлось", systemImage: "magnifyingglass",
                            description: Text("Попробуй другое название или расширь расстояние."))
                            .padding(.top, 80)
                    }
                    .refreshable { await store.load() }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(results) { venue in
                                NavigationLink(value: venue) {
                                    VenueCard(venue: venue,
                                              distanceKm: location.distanceKm(to: venue.latitude, venue.longitude))
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .refreshable { await store.load() }
                }
            }
            .navigationTitle("Поиск")
            .searchable(text: $query, prompt: "Заведение, категория или акция")
            .navigationDestination(for: Venue.self) { VenueDetailView(venue: $0) }
        }
    }

    // MARK: Фильтры

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Открыто", systemImage: "clock", isOn: openNow) { openNow.toggle() }

                Menu {
                    Button("Любой рейтинг") { minRating = 0 }
                    Button("★ 3+") { minRating = 3 }
                    Button("★ 4+") { minRating = 4 }
                } label: {
                    chipLabel(minRating == 0 ? "Рейтинг" : "★ \(minRating)+",
                              systemImage: "star", isOn: minRating > 0)
                }

                Menu {
                    Button("Любое расстояние") { maxDistance = nil }
                    Button("500 м") { maxDistance = 0.5 }
                    Button("1 км") { maxDistance = 1 }
                    Button("3 км") { maxDistance = 3 }
                    Button("5 км") { maxDistance = 5 }
                } label: {
                    chipLabel(maxDistance == nil ? "Расстояние" : "≤ \(maxDistance!.distanceText)",
                              systemImage: "location", isOn: maxDistance != nil)
                }

                Menu {
                    Button("Все категории") { category = nil }
                    ForEach(VenueCategory.allCases) { cat in
                        Button { category = cat } label: { Label(cat.rawValue, systemImage: cat.icon) }
                    }
                } label: {
                    chipLabel(category?.rawValue ?? "Категория",
                              systemImage: "square.grid.2x2", isOn: category != nil)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
        .overlay(Divider(), alignment: .bottom)
    }

    private func chip(_ title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title, systemImage: systemImage, isOn: isOn) }
            .buttonStyle(.plain)
    }

    private func chipLabel(_ title: String, systemImage: String, isOn: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(isOn ? Color.sanAccent : Color(.systemGray6), in: Capsule())
            .foregroundStyle(isOn ? .white : .primary)
    }

    // MARK: Логика фильтрации

    private func matchesQuery(_ venue: Venue) -> Bool {
        guard !query.isEmpty else { return true }
        if venue.name.localizedCaseInsensitiveContains(query) { return true }
        if venue.category.rawValue.localizedCaseInsensitiveContains(query) { return true }
        if venue.district.localizedCaseInsensitiveContains(query) { return true }
        return store.deals(for: venue).contains {
            $0.title.localizedCaseInsensitiveContains(query)
        }
    }

    private func matchesFilters(_ venue: Venue) -> Bool {
        if openNow && !venue.isOpenNow { return false }
        if let category, venue.category != category { return false }
        if minRating > 0 && store.aggregate(for: venue).rating < Double(minRating) { return false }
        if let maxDistance {
            guard let d = location.distanceKm(to: venue.latitude, venue.longitude),
                  d <= maxDistance else { return false }
        }
        return true
    }
}

#Preview {
    SearchView()
        .environmentObject(AppStore())
        .environmentObject(LocationManager())
        .tint(.sanAccent)
}
