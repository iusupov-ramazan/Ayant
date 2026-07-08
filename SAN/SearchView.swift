import SwiftUI
import MapKit
import UIKit

/// Поиск по заведениям с фильтрами (по спецификации).
struct SearchView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var location: LocationManager

    @State private var query = ""
    @State private var openNow = false
    @State private var minRating = 0        // 0 | 3 | 4
    @State private var maxDistance: Double? = nil   // км: 0.5 | 1 | 3 | 5
    @State private var category: VenueCategory?
    @ObservedObject private var catStore = CategoryStore.shared
    @State private var withDeals = false        // только с активными предложениями
    @State private var showMap = false
    @State private var mapSelection: Venue?
    @State private var previewVenue: Venue?      // мини-карточка по тапу на одиночный пин
    @State private var clusterSelection: VenueCluster?   // список заведений в кластере
    @State private var visibleCount = 10         // пагинация списка результатов
    private static let pageSize = 10

    /// Подпись текущего фильтра — при её смене сбрасываем пагинацию.
    private var filterSignature: String {
        "\(query)|\(openNow)|\(withDeals)|\(minRating)|\(maxDistance ?? -1)|\(category?.rawValue ?? "")"
    }

    private var anyFilterOn: Bool {
        openNow || withDeals || minRating > 0 || maxDistance != nil || category != nil
    }
    private func resetFilters() {
        openNow = false; withDeals = false; minRating = 0; maxDistance = nil; category = nil
    }

    private var results: [Venue] {
        // База уже отсортирована по релевантности (алгоритм ранжирования).
        store.rankedVenues().filter { venue in
            matchesQuery(venue) && matchesFilters(venue)
        }
    }

    /// Для карты: все заведения города, подходящие под фильтры-чипы (текстовый
    /// поиск игнорируем — на карте показываем все пины города, чтобы их можно
    /// было листать в мини-карточках).
    private var mapVenues: [Venue] {
        store.rankedVenues().filter { matchesFilters($0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                if !showMap && (anyFilterOn || !query.isEmpty) {
                    HStack {
                        Text("Найдено: \(results.count)").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                }
                if showMap {
                    ZStack(alignment: .bottom) {
                        VenuesMapView(
                            venues: mapVenues,
                            selectedID: previewVenue?.id,
                            onSelectVenue: { v in
                                withAnimation(.spring(response: 0.3)) { previewVenue = v }
                            },
                            onSelectCluster: { vs in
                                previewVenue = nil
                                clusterSelection = VenueCluster(venues: vs)
                            },
                            onTapEmpty: { withAnimation { previewVenue = nil } })
                        if let v = previewVenue {
                            MapPreviewCard(
                                venue: v,
                                distanceKm: location.distanceKm(to: v.latitude, v.longitude),
                                onOpen: { mapSelection = v },
                                onClose: { withAnimation { previewVenue = nil } })
                            .padding(.horizontal, 16)
                            .padding(.bottom, 14)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .sheet(item: $clusterSelection) { cluster in
                        ClusterVenuesView(venues: cluster.venues)
                            .presentationDetents([.medium, .large])
                    }
                } else if results.isEmpty {
                    ScrollView {
                        ContentUnavailableView("Ничего не нашлось", systemImage: "magnifyingglass",
                            description: Text("Попробуй другое название или расширь расстояние."))
                            .padding(.top, 80)
                    }
                    .refreshable { await store.load() }
                } else {
                    let shown = Array(results.prefix(visibleCount))
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(shown) { venue in
                                NavigationLink(value: venue) {
                                    VenueCard(venue: venue,
                                              distanceKm: location.distanceKm(to: venue.latitude, venue.longitude))
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                                .onAppear { loadMoreIfNeeded(venue, in: shown) }
                            }
                            if visibleCount < results.count {
                                ProgressView().padding(.vertical, 12)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .refreshable { await store.load() }
                }
            }
            .background(Color.sanCanvas.ignoresSafeArea())
            .navigationTitle("Поиск")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showMap.toggle() } label: {
                        Image(systemName: showMap ? "list.bullet" : "map")
                    }
                }
            }
            .navigationDestination(item: $mapSelection) { VenueDetailView(venue: $0) }
            .searchable(text: $query, prompt: "Заведение, категория или акция")
            .onSubmit(of: .search) {
                AnalyticsLog.log(.search, ["query": query, "results": results.count])
            }
            .onChange(of: filterSignature) { _, _ in visibleCount = Self.pageSize }
            .navigationDestination(for: Venue.self) { VenueDetailView(venue: $0) }
        }
    }

    // MARK: Фильтры

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if anyFilterOn {
                    Button { withAnimation { resetFilters() } } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body).foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                }
                chip("Открыто", systemImage: "clock", isOn: openNow) { openNow.toggle() }
                chip("Со скидкой", systemImage: "tag.fill", isOn: withDeals) { withDeals.toggle() }

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
                    // Picker вместо набора Button — корректный single-select с галочкой
                    // текущей категории (иначе выбор визуально «терялся»).
                    Picker("Категория", selection: $category) {
                        Text("Все категории").tag(VenueCategory?.none)
                        ForEach(catStore.categories) { cat in
                            Label(cat.locKey, systemImage: cat.icon).tag(VenueCategory?.some(cat))
                        }
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
        Label(L(title), systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(isOn ? Color.sanAccent : Color(.systemGray6), in: Capsule())
            .foregroundStyle(isOn ? .white : .primary)
    }

    // MARK: Логика фильтрации

    private func loadMoreIfNeeded(_ venue: Venue, in shown: [Venue]) {
        guard venue.id == shown.last?.id, visibleCount < results.count else { return }
        visibleCount = min(visibleCount + Self.pageSize, results.count)
    }

    private func matchesQuery(_ venue: Venue) -> Bool {
        guard !query.isEmpty else { return true }
        let q = query.trimmingCharacters(in: .whitespaces)
        // Заведение
        if venue.name.localizedCaseInsensitiveContains(q) { return true }
        if venue.category.rawValue.localizedCaseInsensitiveContains(q) { return true }
        if venue.district.localizedCaseInsensitiveContains(q) { return true }
        if venue.address.localizedCaseInsensitiveContains(q) { return true }
        // Объекты внутри заведения (блюда / услуги)
        if venue.items.contains(where: { $0.name.localizedCaseInsensitiveContains(q) }) { return true }
        // Предложения (название + описание)
        if store.deals(for: venue).contains(where: {
            $0.title.localizedCaseInsensitiveContains(q) || $0.details.localizedCaseInsensitiveContains(q)
        }) { return true }
        // Отзывы (текст + упомянутый объект)
        if store.reviews(for: venue).contains(where: {
            $0.text.localizedCaseInsensitiveContains(q) ||
            ($0.itemName?.localizedCaseInsensitiveContains(q) ?? false)
        }) { return true }
        return false
    }

    private func matchesFilters(_ venue: Venue) -> Bool {
        if openNow && !venue.isOpenNow { return false }
        if withDeals && store.deals(for: venue).isEmpty { return false }
        if let category, venue.category != category { return false }
        if minRating > 0 && store.aggregate(for: venue).rating < Double(minRating) { return false }
        if let maxDistance {
            guard let d = location.distanceKm(to: venue.latitude, venue.longitude),
                  d <= maxDistance else { return false }
        }
        return true
    }
}

// MARK: - Карта заведений с кластеризацией (MKMapView)

/// Обёртка над MKMapView: близкие/совпадающие пины группируются в кластер
/// с числом. Тап по одиночному пину → мини-карточка; тап по кластеру → список.
struct VenuesMapView: UIViewRepresentable {
    let venues: [Venue]
    var selectedID: String? = nil
    var onSelectVenue: (Venue) -> Void
    var onSelectCluster: ([Venue]) -> Void
    var onTapEmpty: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        map.register(MKMarkerAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: Coordinator.pinID)
        map.register(MKMarkerAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        context.coordinator.mapView = map
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        let current = map.annotations.compactMap { $0 as? VenueAnnotation }
        let currentIDs = Set(current.map(\.venue.id))
        let newIDs = Set(venues.map(\.id))
        if currentIDs != newIDs {
            map.removeAnnotations(current)
            map.addAnnotations(venues.map(VenueAnnotation.init))
            context.coordinator.fitAll(animated: false)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        static let pinID = "venuePin"
        var parent: VenuesMapView
        weak var mapView: MKMapView?
        init(_ p: VenuesMapView) { parent = p }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let cluster = annotation as? MKClusterAnnotation {
                let view = MKMarkerAnnotationView(
                    annotation: cluster,
                    reuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
                view.markerTintColor = UIColor(Color.sanAccent)
                view.glyphText = "\(cluster.memberAnnotations.count)"
                view.displayPriority = .required
                return view
            }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: Self.pinID)
            view.clusteringIdentifier = "venue"          // включает кластеризацию
            view.markerTintColor = UIColor(Color.sanAccent)
            view.glyphImage = UIImage(systemName: "fork.knife")
            // Приоритет НЕ .required — иначе пины не кластеризуются. defaultHigh
            // группирует близкие/совпадающие пины в кластер вместо скрытия.
            view.displayPriority = .defaultHigh
            view.titleVisibility = .adaptive
            return view
        }

        func mapView(_ map: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation else { return }
            map.deselectAnnotation(annotation, animated: false)
            if let cluster = annotation as? MKClusterAnnotation {
                let vs = cluster.memberAnnotations.compactMap { ($0 as? VenueAnnotation)?.venue }
                if vs.count == 1 { parent.onSelectVenue(vs[0]) }
                else if !vs.isEmpty { parent.onSelectCluster(vs) }
            } else if let va = annotation as? VenueAnnotation {
                parent.onSelectVenue(va.venue)
            }
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let map = mapView else { return }
            var view = map.hitTest(g.location(in: map), with: nil)
            while let v = view {
                if v is MKAnnotationView { return }   // тап по пину — обрабатывает didSelect
                view = v.superview
            }
            parent.onTapEmpty()
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        /// Вписать все пины города в кадр (с отступом снизу под мини-карточку).
        func fitAll(animated: Bool) {
            guard let map = mapView, !parent.venues.isEmpty else { return }
            let rect = parent.venues.reduce(MKMapRect.null) { acc, v in
                let p = MKMapPoint(CLLocationCoordinate2D(latitude: v.latitude, longitude: v.longitude))
                return acc.union(MKMapRect(x: p.x, y: p.y, width: 0, height: 0))
            }
            guard !rect.isNull else { return }
            map.setVisibleMapRect(
                rect,
                edgePadding: UIEdgeInsets(top: 70, left: 60, bottom: 170, right: 60),
                animated: animated)
        }
    }
}

/// Аннотация заведения на карте.
final class VenueAnnotation: NSObject, MKAnnotation {
    let venue: Venue
    init(_ v: Venue) { venue = v }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: venue.latitude, longitude: venue.longitude)
    }
    var title: String? { venue.name }
}

/// Заведения, попавшие в один кластер (для листа-списка).
struct VenueCluster: Identifiable {
    let id = UUID()
    let venues: [Venue]
}

/// Список заведений, сгруппированных в одной точке/кластере.
struct ClusterVenuesView: View {
    let venues: [Venue]
    @EnvironmentObject private var location: LocationManager

    var body: some View {
        NavigationStack {
            List(venues) { v in
                NavigationLink(value: v) {
                    VenueCompactRow(venue: v,
                                    distanceKm: location.distanceKm(to: v.latitude, v.longitude))
                }
            }
            .listStyle(.plain)
            .navigationTitle("Заведения здесь")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Venue.self) { VenueDetailView(venue: $0) }
        }
    }
}

/// Мини-карточка заведения: краткая сводка, тап — открыть страницу, ✕ — скрыть.
struct MapPreviewCard: View {
    let venue: Venue
    var distanceKm: Double?
    var onOpen: () -> Void
    var onClose: () -> Void

    @EnvironmentObject private var store: AppStore

    var body: some View {
        let agg = store.aggregate(for: venue)
        HStack(spacing: 12) {
            VenueAvatar(venue: venue, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(venue.name).font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary).lineLimit(1)
                // Категория • район • расстояние — одной строкой, чтобы освободить
                // место под статус (иначе «Открыто» обрезалось).
                (Text(venue.category.locKey)
                    + Text(verbatim: " • \(venue.district)")
                    + (distanceKm.map { Text(verbatim: " • \($0.distanceText)") } ?? Text(verbatim: "")))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    StarRatingView(rating: agg.rating, count: agg.count)
                    if venue.isOpenNow {
                        Text("Открыто").font(.caption2.weight(.semibold)).foregroundStyle(.green)
                    }
                }
                .lineLimit(1)
            }
            Spacer(minLength: 24)   // место под кнопку ✕, чтобы текст не заходил под неё
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 88)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color(.systemGray), Color(.systemGray5))
            }
            .padding(8)
        }
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        // Тап по карточке (кроме ✕) — открыть заведение.
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { onOpen() }
    }
}

#Preview {
    SearchView()
        .environmentObject(AppStore())
        .environmentObject(LocationManager())
        .tint(.sanAccent)
}
