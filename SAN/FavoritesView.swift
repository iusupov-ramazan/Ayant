import SwiftUI

/// Сохранённое: заведения и предложения (по спецификации).
struct SavedView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var location: LocationManager
    @State private var tab = 0
    @State private var selectedDeal: Deal?

    var body: some View {
        NavigationStack {
            Group {
                if store.isGuest {
                    ContentUnavailableView("Только для аккаунтов", systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("Войдите, чтобы сохранять заведения и предложения. Гостям доступен только просмотр."))
                } else {
                    VStack(spacing: 0) {
                        Picker("", selection: $tab) {
                            Text("Заведения").tag(0)
                            Text("Предложения").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(16)

                        if tab == 0 { savedVenues } else { savedDeals }
                    }
                }
            }
            .navigationTitle("Сохранённое")
            .navigationDestination(for: Venue.self) { VenueDetailView(venue: $0) }
            .sheet(item: $selectedDeal) { DealDetailView(deal: $0) }
        }
    }

    // MARK: Заведения

    @ViewBuilder
    private var savedVenues: some View {
        if store.savedVenues.isEmpty {
            ContentUnavailableView("Сохраняй любимые места", systemImage: "bookmark",
                description: Text("Они появятся здесь — нажми закладку на любом заведении."))
        } else {
            List {
                ForEach(store.savedVenues) { venue in
                    NavigationLink(value: venue) {
                        VenueCompactRow(venue: venue,
                                        distanceKm: location.distanceKm(to: venue.latitude, venue.longitude))
                    }
                    .swipeActions {
                        Button(role: .destructive) { store.unsaveVenue(venue) } label: {
                            Label("Убрать", systemImage: "bookmark.slash")
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: Предложения

    @ViewBuilder
    private var savedDeals: some View {
        if store.favoriteDeals.isEmpty {
            ContentUnavailableView("Сохраняй предложения", systemImage: "tag",
                description: Text("Нажми закладку на любом предложении, чтобы сохранить его сюда."))
        } else {
            List {
                ForEach(store.favoriteDeals) { deal in
                    CompactDealRow(deal: deal)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedDeal = deal }
                        .swipeActions {
                            Button(role: .destructive) { store.unsaveDeal(deal) } label: {
                                Label("Убрать", systemImage: "bookmark.slash")
                            }
                        }
                }
            }
            .listStyle(.plain)
        }
    }
}

#Preview {
    SavedView()
        .environmentObject(AppStore())
        .environmentObject(LocationManager())
        .tint(.sanAccent)
}
