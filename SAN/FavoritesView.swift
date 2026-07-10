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
            .background(Color.sanCanvas.ignoresSafeArea())
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
                    .listRowInsets(EdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 22))
                    .listRowSeparator(.hidden)
                    .listRowBackground(savedCardBG)
                    .swipeActions {
                        Button(role: .destructive) { store.unsaveVenue(venue) } label: {
                            Label("Убрать", systemImage: "bookmark.slash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
                        .listRowInsets(EdgeInsets(top: 14, leading: 28, bottom: 14, trailing: 22))
                        .listRowSeparator(.hidden)
                        .listRowBackground(savedCardBG)
                        .swipeActions {
                            Button(role: .destructive) { store.unsaveDeal(deal) } label: {
                                Label("Убрать", systemImage: "bookmark.slash")
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    /// Скруглённая карточка-подложка для строк «Сохранённого»
    /// (внутренние отступы задаёт listRowInsets, промежуток между строк — вертикальный паддинг).
    private var savedCardBG: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.sanSurface)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.sanHairline, lineWidth: 0.5))
            .padding(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}

#Preview {
    SavedView()
        .environmentObject(AppStore())
        .environmentObject(LocationManager())
        .tint(.sanAccent)
}
