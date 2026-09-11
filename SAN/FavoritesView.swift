import SwiftUI
import AyantDomain
import AyantFeatures

/// Сохранённое: заведения и предложения (по спецификации).
///
/// После редизайна это больше не вкладка, а экран, в который приходят из шапки
/// ленты (закладка) и из профиля — поэтому своего `NavigationStack` у него нет,
/// он живёт в стеке вызывающего.
struct SavedView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var location: LocationManager
    @State private var tab = 0
    @State private var selectedDeal: Deal?
    @Namespace private var tabNamespace
    @Environment(\.dismiss) private var dismiss

    /// Сетка в две колонки с шагом 12 — по макету (SCREENS.md G7).
    ///
    /// Сохранённое — поверхность ПРОСМОТРА: сюда приходят выбирать из своего,
    /// а не залипать. Список во всю ширину показывал по три-четыре карточки на
    /// экран; плитками их влезает вдвое больше, и «своё» видно целиком.
    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        Group {
            if store.isGuest {
                ContentUnavailableView("Только для аккаунтов", systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Войдите, чтобы сохранять заведения и предложения. Гостям доступен только просмотр."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Сохранённое")
                            .sanEditorialTitle(44)
                            .foregroundStyle(Color.sanInk)
                        segmented
                        if tab == 0 { savedVenues } else { savedDeals }
                    }
                    .padding(.horizontal, SanMetrics.screenPadding)
                    .padding(.top, 8).padding(.bottom, 28)
                }
            }
        }
        .background(Color.sanCanvas.ignoresSafeArea())
        // Экран открывается пушем, поэтому «назад» обязателен: системную панель
        // прячем ради крупного заголовка в контенте, но выход оставляем.
        .sanNavBar { dismiss() }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: Venue.self) { VenueDetailView(venue: $0) }
        .sheet(item: $selectedDeal) { DealDetailView(deal: $0) }
    }

    // MARK: Переключатель

    private var segmented: some View {
        HStack(spacing: 4) {
            segmentButton("Заведения", 0)
            segmentButton("Предложения", 1)
        }
        .padding(4)
        .background(Color.sanSurfaceMuted, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func segmentButton(_ title: LocalizedStringKey, _ value: Int) -> some View {
        let isOn = tab == value
        return Button {
            SanHaptics.selection()
            withAnimation(.sanStandard) { tab = value }
        } label: {
            Text(title)
                .font(.golos(13.5, isOn ? .bold : .semibold))
                .foregroundStyle(isOn ? Color.sanInk : Color.sanInkSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background {
                    if isOn {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(Color.sanSurface)
                            .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
                            .matchedGeometryEffect(id: "savedTab", in: tabNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: Заведения

    @ViewBuilder
    private var savedVenues: some View {
        if store.savedVenues.isEmpty {
            emptyNote("Сохраняй любимые места",
                      "Они появятся здесь — нажми закладку на любом заведении.")
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(store.savedVenues.enumerated()), id: \.element.id) { index, venue in
                    NavigationLink(value: venue) {
                        savedTile(cover: venue.imageURL, gradient: venue.gradientColors,
                                  title: venue.name,
                                  subtitle: "\(venue.category.rawValue) · \(venue.district)",
                                  pill: venue.earnRateLabel) { store.unsaveVenue(venue) }
                    }
                    .buttonStyle(.sanPress(0.97))
                    .sanRise(index, stagger: SanTiming.gridTileRise.stagger,
                             duration: SanTiming.gridTileRise.duration)
                }
            }
        }
    }

    // MARK: Предложения

    @ViewBuilder
    private var savedDeals: some View {
        if store.favoriteDeals.isEmpty {
            emptyNote("Сохраняй предложения",
                      "Нажми закладку на любом предложении, чтобы сохранить его сюда.")
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Array(store.favoriteDeals.enumerated()), id: \.element.id) { index, deal in
                    let venue = store.venue(for: deal)
                    Button { selectedDeal = deal } label: {
                        savedTile(cover: deal.allImages.first,
                                  gradient: venue?.gradientColors ?? [.sanAccent, Color(hex: Palette.orange)],
                                  title: deal.title,
                                  subtitle: venue?.name ?? "",
                                  pill: deal.newPrice.map { "\($0) сом" }) { store.unsaveDeal(deal) }
                    }
                    .buttonStyle(.sanPress(0.97))
                    .sanRise(index, stagger: SanTiming.gridTileRise.stagger,
                             duration: SanTiming.gridTileRise.duration)
                }
            }
        }
    }

    // MARK: Плитка

    /// Обложка 104 + стеклянное сердечко · название 14/bold · подпись 11.5 ·
    /// пилюля `#FFF3EC` с акцентным текстом — всё по макету.
    private func savedTile(cover: String?, gradient: [Color], title: String,
                           subtitle: String, pill: String?,
                           onRemove: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VenuePhoto(urlString: cover, gradient: gradient)
                    .frame(height: 104)
                    .frame(maxWidth: .infinity)
                    .clipped()
                Button {
                    SanHaptics.selection()
                    onRemove()
                } label: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.sanAccentText)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                        .background(Color.white.opacity(0.55), in: Circle())
                }
                .buttonStyle(.sanPress(0.86))
                .padding(8)
                .accessibilityLabel("Убрать из сохранённых")
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .sanText(14, .bold, tracking: -0.25, lineHeight: 1.2)
                    .foregroundStyle(Color.sanInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.golos(11.5)).foregroundStyle(Color.sanInkSoft)
                        .lineLimit(1)
                        .padding(.top, 5)
                }
                if let pill {
                    Text(pill)
                        .font(.golos(11, .bold))
                        .foregroundStyle(Color.sanAccentText)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Color(hex: 0xFFF3EC), in: Capsule())
                        .padding(.top, 9)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(Color.sanSurface)
        .clipShape(RoundedRectangle(cornerRadius: SanRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SanRadius.card, style: .continuous)
            .strokeBorder(Color.sanHairline, lineWidth: 0.5))
    }

    private func emptyNote(_ title: LocalizedStringKey, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.golos(16, .bold)).foregroundStyle(Color.sanInk)
            Text(body).font(.golos(13.5)).foregroundStyle(Color.sanInkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .sanCard(padding: 0, radius: SanRadius.card)
    }
}

#Preview {
    SavedView()
        .environmentObject(AyantStores.app())
        .environmentObject(LocationManager())
        .tint(.sanAccent)
}
