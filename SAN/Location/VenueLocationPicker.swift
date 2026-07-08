import SwiftUI
import MapKit

/// Выбор точного местоположения заведения на карте.
///
/// Использует Apple Maps (MapKit) — бесплатно, без API-ключа и без биллинга,
/// работает в Кыргызстане. Точные координаты берутся не из базы адресов
/// (которая в КР неполная), а из визуального положения булавки на карте:
/// хост ставит/двигает точку → получаем ровно те широту и долготу, что нужно.
/// Поиск адреса (`MKLocalSearch`) лишь помогает быстро долететь до нужного района.
struct VenueLocationPicker: View {
    @Environment(\.dismiss) private var dismiss

    /// Колбэк с выбранными координатами обратно в форму.
    let onPick: (CLLocationCoordinate2D) -> Void

    @State private var coordinate: CLLocationCoordinate2D
    @State private var cameraPosition: MapCameraPosition
    @State private var query: String = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false

    init(initial: CLLocationCoordinate2D,
         onPick: @escaping (CLLocationCoordinate2D) -> Void) {
        self.onPick = onPick
        _coordinate = State(initialValue: initial)
        _cameraPosition = State(initialValue: .region(Self.region(around: initial, span: 0.02)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                if !results.isEmpty { resultsList }
                mapView
            }
            .navigationTitle("Точка на карте")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { onPick(coordinate); dismiss() }
                }
            }
        }
    }

    // MARK: - Карта

    private var mapView: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                // Annotation (не Marker): заголовок рисуется дефолтным цветом текста карты,
                // а не белым на красном балуне.
                Annotation("Заведение", coordinate: coordinate) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color.sanAccent)
                        .background(Circle().fill(.background).padding(3))
                }
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            // Тап по карте ставит булавку в это место.
            .gesture(
                SpatialTapGesture(coordinateSpace: .local)
                    .onEnded { value in
                        if let coord = proxy.convert(value.location, from: .local) {
                            coordinate = coord
                        }
                    }
            )
            .overlay(alignment: .bottom) {
                Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                    .font(.footnote.monospaced())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 14)
            }
            .overlay(alignment: .top) {
                Text("Нажмите на карту, чтобы поставить точку")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Поиск адреса

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Поиск адреса или места", text: $query)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit(runSearch)
            if isSearching {
                ProgressView()
            } else if !query.isEmpty {
                Button {
                    query = ""; results = []
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(results, id: \.self) { item in
                    Button { select(item) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "Без названия")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            if let subtitle = item.placemark.title {
                                Text(subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal)
                    }
                    Divider()
                }
            }
        }
        .frame(maxHeight: 200)
        .background(Color(.systemBackground))
    }

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { results = []; return }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        // Приоритет — текущий район карты, чтобы результаты были по Бишкеку/КР.
        request.region = Self.region(around: coordinate, span: 0.4)

        isSearching = true
        MKLocalSearch(request: request).start { response, _ in
            isSearching = false
            results = response?.mapItems ?? []
        }
    }

    private func select(_ item: MKMapItem) {
        let coord = item.placemark.coordinate
        coordinate = coord
        withAnimation {
            cameraPosition = .region(Self.region(around: coord, span: 0.01))
        }
        results = []
        query = item.name ?? query
    }

    private static func region(around coord: CLLocationCoordinate2D,
                               span: CLLocationDegrees) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coord,
                           span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))
    }
}
