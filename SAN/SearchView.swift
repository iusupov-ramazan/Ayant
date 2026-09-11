import SwiftUI
import MapKit
import UIKit
import AyantDomain
import AyantFeatures

/// Порядок выдачи поиска. Отдельный тип, а не булевы флаги: варианты
/// взаимоисключающие, и чип-меню показывает выбранный прямо в заголовке.
enum SearchSort: String, CaseIterable {
    case best, near, rating, discount

    /// Полное название — в меню, где есть место на объяснение.
    var title: String {
        switch self {
        case .best: return "Сначала лучшие"
        case .near: return "Сначала ближние"
        case .rating: return "Сначала с высоким рейтингом"
        case .discount: return "Сначала с большой скидкой"
        }
    }

    /// Короткое — в самом чипе: строка фильтров и так уезжает за край экрана.
    var chipTitle: String {
        switch self {
        case .best: return "Лучшие"
        case .near: return "Ближние"
        case .rating: return "Рейтинг"
        case .discount: return "Скидка"
        }
    }
}

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
    @State private var showFilters = false
    @State private var pointsOnly = false        // только заведения с баллами САН
    /// Верхняя граница листа результатов = сколько карты видно сверху.
    /// 0 значит «лист на весь экран».
    ///
    /// ВАЖНО: карта НЕ меняет размер. Она всегда высотой `collapsedMap`, а лист
    /// просто едет по ней смещением. Пока лист менял высоту карты, `MKMapView`
    /// переразмечался на каждый кадр перетаскивания — и жест ощутимо лагал.
    @State private var sheetTop: CGFloat = SearchView.mediumMap
    /// Именно `@State`, а не `@StateObject`: экран владеет объектом, но НЕ
    /// подписывается на него — иначе каждый кадр жеста снова инвалидировал бы
    /// весь экран вместе со списком. Подписан только `SearchSheetStack`.
    @State private var sheetDrag = SheetDragModel()

    private static let collapsedMap: CGFloat = 520   // карта крупно, лист снизу
    /// Положение листа в режиме превью: карта остаётся крупной, но карточке
    /// выбранного заведения хватает места целиком — вместе с кнопкой возврата
    /// к списку и над таб-баром.
    private static let previewMap: CGFloat = 400
    private static let mediumMap: CGFloat = 270      // по умолчанию, как в макете
    private static let expandedMap: CGFloat = 0      // лист на весь экран
    /// Лист убран вниз: видна только его шапка. Нужен, чтобы карту можно было
    /// смотреть целиком — раньше самое нижнее положение всё равно закрывало
    /// треть экрана, и «убрать список» было нечем.
    private static let peekMap: CGFloat = 645
    static let stops: [CGFloat] = [expandedMap, mediumMap, collapsedMap, peekMap]
    /// Высота карты = самому нижнему положению листа: ниже него карта обязана
    /// быть нарисована, иначе под листом покажется пустой холст.
    private static let mapHeight: CGFloat = peekMap

    /// Осевшее положение — от него считаются отступы, которые не должны
    /// прыгать под пальцем.
    private var settledTop: CGFloat { sheetTop }
    /// Сортировка выдачи — отдельный чип-меню, как «Best overall» у UberEats.
    @State private var sort: SearchSort = .best
    @State private var mapSelection: Venue?
    /// Выбранный на карте пин. Пока он есть, лист показывает ОДНУ карточку
    /// этого заведения (режим превью) — как в UberEats: тап по пину сворачивает
    /// список, оставляя карту крупной.
    @State private var previewVenue: Venue?
    @State private var clusterSelection: VenueCluster?   // список заведений в кластере
    @State private var visibleCount = 10         // пагинация списка результатов
    private static let pageSize = 10
    /// Сколько пинов рисуем на карте сейчас. Карта с сотней подписей нечитаема,
    /// поэтому показываем ближайшую порцию, а остальное — по кнопке «Показать
    /// ещё» (в видео это «Load More» тёмной пилюлей над картой).
    @State private var pinBudget = Self.pinPageSize
    private static let pinPageSize = 24

    /// Подпись текущего фильтра — при её смене сбрасываем пагинацию.
    private var filterSignature: String {
        "\(query)|\(openNow)|\(withDeals)|\(pointsOnly)|\(minRating)|\(maxDistance ?? -1)|\(category?.rawValue ?? "")|\(sort.rawValue)"
    }

    private var anyFilterOn: Bool {
        openNow || withDeals || pointsOnly || minRating > 0 || maxDistance != nil || category != nil
    }
    private func resetFilters() {
        openNow = false; withDeals = false; pointsOnly = false
        minRating = 0; maxDistance = nil; category = nil
    }

    // Результаты КЭШИРУЮТСЯ, а не считаются в `body`.
    //
    // Раньше это были вычисляемые свойства, и каждое звало `rankedVenues()` —
    // а он на каждый вызов пересобирает снимок каталога с агрегатами по всем
    // отзывам. Плюс `matchesQuery` дёргает `deals(for:)`/`reviews(for:)` на
    // каждое заведение. Во время перетаскивания листа `body` пересчитывается на
    // каждый кадр, и весь этот перебор шёл 60 раз в секунду — вот откуда лаг.
    // Теперь он выполняется только когда меняются входные данные.
    @State private var results: [Venue] = []
    /// Для карты: подходящие под фильтры-чипы заведения (текстовый поиск
    /// игнорируем — на карте показываем пины города, чтобы их можно было
    /// листать в карточках). Ограничены `pinBudget`.
    @State private var mapVenues: [Venue] = []
    /// Всё, что прошло фильтры, — из него берём следующую порцию пинов.
    @State private var matchingVenues: [Venue] = []
    /// До первого пересчёта не показываем «ничего не нашлось».
    @State private var didComputeResults = false

    /// Всё, от чего зависит выдача. Строка дешёвая — сравнивается в `.task(id:)`.
    private var recomputeKey: String {
        let loc = location.lastLocation
            .map { String(format: "%.3f,%.3f", $0.latitude, $0.longitude) } ?? "-"
        return "\(filterSignature)|\(store.venues.count)|\(store.deals.count)|\(store.reviews.count)|\(loc)|\(pinBudget)"
    }

    /// Предложения и отзывы, разложенные по заведениям ОДНИМ проходом.
    ///
    /// Раньше фильтры звали `store.deals(for:)` и `store.reviews(for:)` на
    /// каждое заведение, а те каждый раз проходят по всему списку (отзывы — ещё
    /// и с сортировкой). На полсотни заведений и сотни отзывов это тот самый
    /// стомиллисекундный кадр, который видно на замере.
    private struct SearchIndex {
        var dealsByVenue: [String: [Deal]] = [:]
        var reviewsByVenue: [String: [Review]] = [:]
    }

    private func makeIndex() -> SearchIndex {
        var index = SearchIndex()
        for d in store.deals where d.isActive {
            index.dealsByVenue[d.venueID, default: []].append(d)
        }
        for r in store.reviews {
            index.reviewsByVenue[r.venueID, default: []].append(r)
        }
        return index
    }

    private func recomputeResults() {
        // `rankedVenues()` зовём ОДИН раз: список для карты — это те же
        // заведения без текстового фильтра, а выдача — его подмножество.
        let ranked = store.rankedVenues()
        let index = makeIndex()
        let byFilters = sorted(ranked.filter { matchesFilters($0, index) }, index)
        matchingVenues = byFilters
        mapVenues = Array(byFilters.prefix(pinBudget))
        results = byFilters.filter { matchesQuery($0, index) }
        didComputeResults = true
    }

    /// Порядок выдачи. `best` — то, что уже посчитал ранжировщик; остальные
    /// пересортировывают его результат, не трогая сам скоринг.
    private func sorted(_ venues: [Venue], _ index: SearchIndex) -> [Venue] {
        switch sort {
        case .best:
            return venues
        case .near:
            return venues.sorted {
                (location.distanceKm(to: $0.latitude, $0.longitude) ?? .greatestFiniteMagnitude)
                    < (location.distanceKm(to: $1.latitude, $1.longitude) ?? .greatestFiniteMagnitude)
            }
        case .rating:
            return venues.sorted { store.aggregate(for: $0).rating > store.aggregate(for: $1).rating }
        case .discount:
            func best(_ v: Venue) -> Int {
                index.dealsByVenue[v.id]?.compactMap(\.effectiveDiscountPercent).max() ?? 0
            }
            return venues.sorted { best($0) > best($1) }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Карта и лист строятся ЗДЕСЬ (один раз на изменение данных),
                // а ездят внутри контейнера — состояние жеста живёт в нём.
                SearchSheetStack(
                    top: sheetTop,
                    stops: Self.stops,
                    drag: sheetDrag,
                    map: mapPanel,
                    // Скрима над картой больше нет: затемнение съедало карту
                    // ради читаемости поля поиска, а у поля и чипов есть
                    // собственная непрозрачная подложка.
                    scrim: EmptyView(),
                    sheet: resultsSheet,
                    // Карточка выбранного пина переехала В ЛИСТ (режим превью),
                    // поэтому отдельного плавающего слоя больше нет.
                    preview: EmptyView())

                topBar
                    .padding(.top, 14)

                loadMorePinsButton
            }
            // Именно фон, а не слой ZStack: `Color.ignoresSafeArea()` внутри
            // стека раздувает его до полного экрана, и лист результатов уезжал
            // под таб-бар — последняя карточка обрезалась.
            .background(Color.sanCanvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $mapSelection) { VenueDetailView(venue: $0) }
            .navigationDestination(for: Venue.self) { VenueDetailView(venue: $0) }
            .sheet(item: $clusterSelection) { cluster in
                ClusterVenuesView(venues: cluster.venues)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showFilters) { filterSheet }
            .onChange(of: filterSignature) { _, _ in
                visibleCount = Self.pageSize
                pinBudget = Self.pinPageSize
            }
            .task(id: recomputeKey) { recomputeResults() }
        }
    }

    // MARK: Карта (SCREENS.md G8)
    //
    // В макете панель нарисована схематично — это фолбэк. В продакшене здесь
    // настоящая карта, поэтому берём её и надеваем сверху скримы и элементы.

    private var mapPanel: some View {
        VenuesMapView(
            venues: mapVenues,
            selectedID: previewVenue?.id,
            fixedHeight: Self.mapHeight,
            visibleHeight: max(sheetTop - 24, 0),
            dealsForPins: store.deals,
            onSelectVenue: { v in
                // Как в UberEats: выбор пина отдаёт экран карте, а лист
                // сжимается до карточки этого заведения.
                withAnimation(.sanStandard) {
                    previewVenue = v
                    sheetTop = Self.previewMap
                }
            },
            onSelectCluster: { vs in
                previewVenue = nil
                clusterSelection = VenueCluster(venues: vs)
            },
            onTapEmpty: {
                withAnimation(.sanStandard) {
                    previewVenue = nil
                    if sheetTop == Self.previewMap { sheetTop = Self.mediumMap }
                }
            })
        // Высота ФИКСИРОВАННАЯ и равна самому высокому положению листа. Ниже
        // карту просто накрывает непрозрачный лист, поэтому подрезать её не
        // нужно — а значит, и переразмечать MapKit на кадрах жеста тоже.
        .frame(height: Self.mapHeight, alignment: .top)
    }


    /// «Показать ещё» — тёмная пилюля по центру над картой (в видео «Load
    /// More»). Появляется, только пока часть подходящих заведений не нарисована.
    @ViewBuilder
    private var loadMorePinsButton: some View {
        if previewVenue == nil, mapVenues.count < matchingVenues.count, settledTop > Self.mediumMap {
            Button {
                SanHaptics.selection()
                withAnimation(.sanStandard) { pinBudget += Self.pinPageSize }
            } label: {
                Text("Показать ещё \(min(Self.pinPageSize, matchingVenues.count - mapVenues.count))")
                    .font(.golos(13, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Color.sanInk.opacity(0.92)))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            }
            .buttonStyle(.sanPress(0.94))
            .padding(.top, 116)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// Поиск + фильтры ОДНИМ блоком поверх карты.
    ///
    /// Раньше чипы жили внутри листа: стоило опустить его к карте — и фильтры
    /// уезжали с экрана вместе с выдачей, хотя именно на карте они и нужны.
    /// В UberEats строка фильтров закреплена под поиском и видна всегда;
    /// повторяем это.
    private var topBar: some View {
        VStack(spacing: 10) {
            searchBar.padding(.horizontal, 18)
            filterBar
        }
    }

    /// Строка фильтров: сначала «типизированные» чипы с меню (категория,
    /// сортировка), затем переключатели. Меню вместо отдельного экрана —
    /// выбор в один тап, как «Cuisine ▾» и «Best overall ▾» у UberEats.
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip
                sortChip
                quickChip("Открыто", isOn: openNow) { openNow.toggle() }
                quickChip("Есть акции", isOn: withDeals) { withDeals.toggle() }
                quickChip("Баллы САН", isOn: pointsOnly) { pointsOnly.toggle() }
                quickChip("Рейтинг 4+", isOn: minRating >= 4) {
                    minRating = minRating >= 4 ? 0 : 4
                }
                quickChip("Рядом", isOn: maxDistance != nil) {
                    maxDistance = maxDistance == nil ? 1 : nil
                }
                Button { showFilters = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 11, weight: .bold))
                        Text("Все фильтры").font(.golos(13, .bold)).lineLimit(1)
                    }
                    .foregroundStyle(Color.sanInk)
                    .padding(.horizontal, 15).padding(.vertical, 9)
                    .background {
                        Capsule().fill(Color.sanSurface.opacity(0.94))
                            .overlay(Capsule().strokeBorder(Color.sanHairline, lineWidth: 0.5))
                    }
                }
                .buttonStyle(.sanPress(0.93))

                if anyFilterOn {
                    Button {
                        SanHaptics.selection()
                        withAnimation(.sanStandard) { resetFilters() }
                    } label: {
                        Label("Сбросить", systemImage: "xmark")
                            .labelStyle(.titleAndIcon)
                            .font(.golos(13, .bold))
                            .foregroundStyle(Color.sanInkSoft)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Capsule().fill(Color.sanSurface.opacity(0.94)))
                    }
                    .buttonStyle(.sanPress(0.93))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    /// Чип-меню категории. Заголовок показывает выбранное, а не «Категория».
    private var categoryChip: some View {
        Menu {
            Button("Все категории") { category = nil }
            ForEach(catStore.categories, id: \.self) { cat in
                Button(LS(cat.rawValue)) { category = cat }
            }
        } label: {
            // Заголовок чипа — литерал, а не `LS`: ключ «Категория» есть в
            // каталоге строк, и на английской локали чип показывал «Category»
            // посреди русского интерфейса.
            menuChipLabel(category.map { LS($0.rawValue) } ?? "Категория",
                          isOn: category != nil)
        }
    }

    private var sortChip: some View {
        Menu {
            ForEach(SearchSort.allCases, id: \.self) { option in
                Button(option.title) { sort = option }
            }
        } label: {
            menuChipLabel(sort.chipTitle, isOn: sort != .best)
        }
    }

    private func menuChipLabel(_ title: String, isOn: Bool) -> some View {
        HStack(spacing: 5) {
            Text(title).font(.golos(13, .bold)).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(isOn ? Color.white : Color.sanInk)
        .padding(.horizontal, 15).padding(.vertical, 9)
        .background {
            if isOn { Capsule().fill(LinearGradient.sanAccentGradient) }
            else {
                Capsule().fill(Color.sanSurface.opacity(0.94))
                    .overlay(Capsule().strokeBorder(Color.sanHairline, lineWidth: 0.5))
            }
        }
    }

    /// Поле поиска — во всю ширину, как в видео. Акцентной кнопки рядом больше
    /// нет: она забирала четверть строки, а её содержимое (полный набор
    /// фильтров) теперь last-чипом в строке ниже — там же, где все остальные.
    private var searchBar: some View {
        HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x9A9188))
                TextField("", text: $query,
                          prompt: Text("Заведение, категория или акция")
                            .foregroundColor(Color(hex: 0x9A9188)))
                    .font(.golos(14.5, .medium))
                    .foregroundStyle(Color.sanInk)
                    .submitLabel(.search)
                    .onSubmit {
                        AnalyticsLog.log(.search, ["query": query, "results": results.count])
                    }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15)).foregroundStyle(Color(hex: 0x9A9188))
                    }
                    .buttonStyle(.plain)
                }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        // Без `.ultraThinMaterial`: живое размытие пересчитывается каждый раз,
        // когда меняется то, что под ним, — а под полем едет карта. Подложка и
        // так почти непрозрачная, визуально это то же самое, только без
        // пересчёта размытия на каждый кадр. Тень — на фигуре, а не на
        // составной вьюхе (иначе внеэкранный проход).
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.sanSurface.opacity(0.94))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 6)
        }
    }

    // MARK: Лист результатов

    private var resultsSheet: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(hex: 0xDDD7CE))
                .frame(width: 38, height: 4)
                // По макету: 18 сверху и 16 под полоской. На весь экран лист
                // подъезжает под плавающую строку поиска — тогда освобождаем ей
                // место: отступ 14 + высота поля (~48) + зазор.
                // Панель сверху стала выше: поиск (48) + чипы (38) + зазоры.
                .padding(.top, settledTop < 130 ? 118 : 18)
                .padding(.bottom, 16)
                // Зона захвата — вся ширина листа и ~40pt по высоте: в саму
                // полоску 4pt пальцем не попасть.
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .overlay {
                    SheetPanHandle(
                        onChange: { sheetDrag.delta = $0 },
                        onEnd: { translation, velocity in endSheetDrag(translation, velocity) })
                }
                .accessibilityLabel("Размер списка")

            if let venue = previewVenue {
                // Режим превью: пин выбран — показываем одну карточку и кнопку
                // возврата к списку (у UberEats это плавающая ☰ над карточкой).
                previewSheetContent(venue)
            } else {
                listSheetContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // На весь экран лист занимает всё — скругление там показывало бы карту
        // в углах и читалось как артефакт.
        .background(Color.sanCanvas,
                    in: UnevenRoundedRectangle(topLeadingRadius: settledTop == 0 ? 0 : SanRadius.sheet,
                                               topTrailingRadius: settledTop == 0 ? 0 : SanRadius.sheet,
                                               style: .continuous))
    }

    /// Одна карточка выбранного на карте заведения.
    @ViewBuilder
    private func previewSheetContent(_ venue: Venue) -> some View {
        VStack(spacing: 12) {
            VenueResultCard(venue: venue,
                            distanceKm: location.distanceKm(to: venue.latitude, venue.longitude),
                            deal: bestDeal(for: venue),
                            rating: store.aggregate(for: venue),
                            compact: true,
                            onOpen: { mapSelection = venue })
            Button {
                SanHaptics.selection()
                withAnimation(.sanStandard) {
                    previewVenue = nil
                    sheetTop = Self.mediumMap
                }
            } label: {
                Label("Показать список", systemImage: "list.bullet")
                    .font(.golos(14, .bold))
                    .foregroundStyle(Color.sanAccentText)
            }
            .buttonStyle(.sanPress(0.96))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SanMetrics.screenPadding)
    }

    @ViewBuilder
    private var listSheetContent: some View {
        VStack(spacing: 0) {
            Text(Self.foundKey(results.count), comment: "")
                .font(.golos(12.5, .semibold))
                .foregroundStyle(Color.sanInkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SanMetrics.screenPadding)

            if results.isEmpty {
                if didComputeResults {
                    ContentUnavailableView("Ничего не нашлось", systemImage: "magnifyingglass",
                        description: Text("Попробуй другое название или расширь расстояние."))
                        .padding(.top, 40)
                }
                Spacer(minLength: 0)
            } else {
                let shown = Array(results.prefix(visibleCount))
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, venue in
                            VenueResultCard(venue: venue,
                                            distanceKm: location.distanceKm(to: venue.latitude, venue.longitude),
                                            deal: bestDeal(for: venue),
                                            rating: store.aggregate(for: venue),
                                            onOpen: { mapSelection = venue })
                                .sanRise(index, stagger: SanTiming.resultRowRise.stagger,
                                         duration: SanTiming.resultRowRise.duration)
                                .onAppear { loadMoreIfNeeded(venue, in: shown) }
                        }
                        if visibleCount < results.count {
                            ProgressView().padding(.vertical, 12)
                        }
                    }
                    .padding(.horizontal, SanMetrics.screenPadding)
                    .padding(.top, 12)
                    // Лист высотой во весь экран съехал вниз на `sheetTop`, и
                    // ровно столько его хвоста ушло за нижний край. Компенсируем
                    // отступом, иначе до последней карточки не долистать.
                    .padding(.bottom, 20 + sheetTop)
                }
                .scrollDisabled(false)
                .refreshable { await store.load() }
            }
        }
    }

    /// Лучшая активная акция заведения — её ленту показываем на карточке.
    private func bestDeal(for venue: Venue) -> Deal? {
        store.deals(for: venue)
            .filter(\.isActive)
            .max { ($0.effectiveDiscountPercent ?? 0) < ($1.effectiveDiscountPercent ?? 0) }
    }

    /// Отпустили лист: прилипаем к ближайшей точке с учётом броска. Скорость —
    /// в пунктах в секунду; 0.15 с даёт примерно то же предсказание, что раньше
    /// давал `predictedEndTranslation`.
    private func endSheetDrag(_ translation: CGFloat, _ velocity: CGFloat) {
        let target = min(max(sheetTop + translation + velocity * 0.15,
                             Self.expandedMap), Self.peekMap)
        let nearest = Self.stops.min { abs($0 - target) < abs($1 - target) } ?? sheetTop
        SanHaptics.selection()
        sheetDrag.delta = 0
        withAnimation(.sanStandard(0.35)) { sheetTop = nearest }
    }

    /// Быстрые чипы из макета, привязанные к реальным фильтрам.
    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickChip("Открыто", isOn: openNow) { openNow.toggle() }
                quickChip("Рядом", isOn: maxDistance != nil) {
                    maxDistance = maxDistance == nil ? 1 : nil
                }
                quickChip("Баллы САН", isOn: pointsOnly) { pointsOnly.toggle() }
                quickChip("Рейтинг 4+", isOn: minRating >= 4) {
                    minRating = minRating >= 4 ? 0 : 4
                }
                quickChip("Есть акции", isOn: withDeals) { withDeals.toggle() }
            }
            .padding(.horizontal, SanMetrics.screenPadding)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func quickChip(_ title: LocalizedStringKey, isOn: Bool,
                           action: @escaping () -> Void) -> some View {
        Button {
            SanHaptics.selection()
            withAnimation(.sanStandard) { action() }
        } label: {
            Text(title)
                .font(.golos(13, .bold))
                .foregroundStyle(isOn ? Color.white : Color.sanInkSoft)
                .lineLimit(1)
                .padding(.horizontal, 15).padding(.vertical, 9)
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

    private func resultRow(_ venue: Venue) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: venue.gradientColors,
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 64, height: 64)
                .overlay {
                    if let url = venue.imageURL, !url.isEmpty {
                        VenuePhoto(urlString: url, gradient: venue.gradientColors)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        Text(venue.emoji).font(.system(size: 26))
                    }
                }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(venue.name)
                        .font(.golos(15, .bold)).tracking(-0.3)
                        .foregroundStyle(Color.sanInk).lineLimit(1)
                    if venue.isOpenNow {
                        Text("Открыто")
                            .font(.golos(12, .bold)).foregroundStyle(Color.sanOpen)
                    }
                }
                (Text(venue.category.locKey) + Text(" · \(venue.district)"))
                    .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                    .lineLimit(1)
                    .padding(.top, 4)
                HStack(spacing: 9) {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11)).foregroundStyle(Color(hex: Palette.orange))
                        Text(venue.rating.sanRatingText)
                            .font(.golos(12.5, .bold)).foregroundStyle(Color.sanInk)
                    }
                    if let km = location.distanceKm(to: venue.latitude, venue.longitude) {
                        Text(km.distanceText)
                            .font(.golos(12)).foregroundStyle(Color(hex: 0x9A9188))
                    }
                }
                .padding(.top, 7)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sanCard(padding: 0, radius: SanRadius.card)
    }

    /// Три отдельных ЛОКАЛИЗУЕМЫХ формата вместо подстановки русского слова в
    /// переведённую фразу. Раньше существительное склонялось строкой и уезжало в
    /// `%@`, поэтому по-английски получалось «Found 10 заведений».
    private static func foundKey(_ n: Int) -> LocalizedStringKey {
        let n10 = n % 10, n100 = n % 100
        if n10 == 1 && n100 != 11 { return "Найдено \(n) заведение" }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return "Найдено \(n) заведения" }
        return "Найдено \(n) заведений"
    }

    // MARK: Полный набор фильтров

    private var filterSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    filterGroup("Рейтинг") {
                        HStack(spacing: 8) {
                            quickChip("Любой", isOn: minRating == 0) { minRating = 0 }
                            quickChip("★ 3+", isOn: minRating == 3) { minRating = 3 }
                            quickChip("★ 4+", isOn: minRating == 4) { minRating = 4 }
                        }
                    }
                    filterGroup("Расстояние") {
                        HStack(spacing: 8) {
                            quickChip("Любое", isOn: maxDistance == nil) { maxDistance = nil }
                            quickChip("500 м", isOn: maxDistance == 0.5) { maxDistance = 0.5 }
                            quickChip("1 км", isOn: maxDistance == 1) { maxDistance = 1 }
                            quickChip("3 км", isOn: maxDistance == 3) { maxDistance = 3 }
                        }
                    }
                    filterGroup("Категория") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                            quickChip("Все", isOn: category == nil) { category = nil }
                            ForEach(catStore.categories) { cat in
                                quickChip(LocalizedStringKey(cat.rawValue), isOn: category == cat) {
                                    category = (category == cat) ? nil : cat
                                }
                            }
                        }
                    }
                }
                .padding(SanMetrics.screenPadding)
            }
            .sanScreenBackground()
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Сбросить") { withAnimation { resetFilters() } }
                        .disabled(!anyFilterOn)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { showFilters = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func filterGroup<Content: View>(_ title: LocalizedStringKey,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .textCase(.uppercase)
                .sanEyebrowText()
                .foregroundStyle(Color(hex: 0x9A9188))
            content()
        }
    }

    // MARK: Логика фильтрации

    private func loadMoreIfNeeded(_ venue: Venue, in shown: [Venue]) {
        guard venue.id == shown.last?.id, visibleCount < results.count else { return }
        visibleCount = min(visibleCount + Self.pageSize, results.count)
    }

    private func matchesQuery(_ venue: Venue, _ index: SearchIndex) -> Bool {
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
        if (index.dealsByVenue[venue.id] ?? []).contains(where: {
            $0.title.localizedCaseInsensitiveContains(q) || $0.details.localizedCaseInsensitiveContains(q)
        }) { return true }
        // Отзывы (текст + упомянутый объект)
        if (index.reviewsByVenue[venue.id] ?? []).contains(where: {
            $0.text.localizedCaseInsensitiveContains(q) ||
            ($0.itemName?.localizedCaseInsensitiveContains(q) ?? false)
        }) { return true }
        return false
    }

    private func matchesFilters(_ venue: Venue, _ index: SearchIndex) -> Bool {
        if openNow && !venue.isOpenNow { return false }
        if withDeals && (index.dealsByVenue[venue.id] ?? []).isEmpty { return false }
        if pointsOnly && !venue.pointsActive { return false }
        if let category, venue.category != category { return false }
        // `cachedAggregate` берёт рейтинг из уже собранного снимка каталога —
        // без повторного прохода по отзывам и без сортировки.
        if minRating > 0 && store.cachedAggregate(for: venue).rating < Double(minRating) { return false }
        if let maxDistance {
            guard let d = location.distanceKm(to: venue.latitude, venue.longitude),
                  d <= maxDistance else { return false }
        }
        return true
    }
}


// MARK: - Карточка результата поиска

/// Фото-карточка выдачи. Зеркалит подачу UberEats: крупный снимок, лента акции
/// поверх него, затем имя и одна строка фактов — рейтинг, «открыто», расстояние.
///
/// Прежняя строка (иконка 64×64 слева, текст справа) вмещала больше пунктов на
/// экран, но по ней невозможно выбрать заведение: еда и интерьер — это то, на
/// что люди смотрят в первую очередь, а в 64 точках их не видно.
struct VenueResultCard: View {
    let venue: Venue
    var distanceKm: Double?
    var deal: Deal?
    var rating: (rating: Double, count: Int)
    /// Превью выбранного пина: та же карточка, но ниже — под ней ещё кнопка
    /// возврата к списку, и всё это должно поместиться над таб-баром.
    var compact: Bool = false
    var onOpen: () -> Void

    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var session: SessionStore
    @State private var showGuestAlert = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                cover
                header
            }
        }
        .buttonStyle(.sanPress(0.98))
        .guestAlert(isPresented: $showGuestAlert, message: GuestGate.saveVenue)
    }

    private var cover: some View {
        VenuePhoto(urlString: venue.imageURL, gradient: venue.gradientColors)
            .frame(height: compact ? 132 : 168)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: SanRadius.card, style: .continuous))
            .overlay(alignment: .topLeading) {
                if let ribbon = ribbonText {
                    Text(ribbon)
                        .font(.golos(12, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(LinearGradient.sanAccentGradient, in: Capsule())
                        .padding(10)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    if session.isGuest { showGuestAlert = true }
                    else {
                        if !store.isSaved(venue) { SanHaptics.save() }
                        store.toggleSave(venue)
                    }
                } label: {
                    Image(systemName: store.isSaved(venue) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(9)
                        .background(Circle().fill(.black.opacity(0.35)))
                        .padding(10)
                }
                .buttonStyle(.plain)
            }
    }

    /// Лента акции: скидка важнее типа акции, тип — важнее «спец дня».
    private var ribbonText: String? {
        if let percent = deal?.effectiveDiscountPercent { return "−\(percent)%" }
        if let deal { return LS(deal.type.rawValue) }
        if venue.hasTodaySpecial { return LS("Сегодня") }
        return nil
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(venue.name)
                    .font(.golos(17, .bold)).tracking(-0.3)
                    .foregroundStyle(Color.sanInk).lineLimit(1)
                if venue.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13)).foregroundStyle(Color.sanAccentText)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11)).foregroundStyle(Color(hex: Palette.orange))
                    Text(rating.rating.sanRatingText)
                        .font(.golos(13, .bold)).foregroundStyle(Color.sanInk)
                    Text("(\(rating.count))")
                        .font(.golos(12)).foregroundStyle(Color.sanInkSoft)
                }
                dot
                Text(venue.category.locKey)
                    .font(.golos(13)).foregroundStyle(Color.sanInkSoft).lineLimit(1)
                if venue.isOpenNow {
                    dot
                    Text("Открыто").font(.golos(13, .semibold)).foregroundStyle(Color.sanOpen)
                }
                if let distanceKm {
                    dot
                    Text(distanceKm.distanceText)
                        .font(.golos(13)).foregroundStyle(Color.sanInkSoft)
                }
                Spacer(minLength: 0)
            }
            .lineLimit(1)
        }
    }

    private var dot: some View {
        Text("·").font(.golos(13)).foregroundStyle(Color.sanInkSoft)
    }
}

// MARK: - Карта заведений с кластеризацией (MKMapView)

/// Обёртка над MKMapView: близкие/совпадающие пины группируются в кластер
/// с числом. Тап по одиночному пину → мини-карточка; тап по кластеру → список.
/// Карта заведений.
///
/// Наружу отдаётся не сам `MKMapView`, а КОНТЕЙНЕР с `clipsToBounds`, внутри
/// которого карта всегда фиксированной высоты `fixedHeight`. Две причины, обе
/// про перетаскивание листа результатов поверх карты:
///
/// 1. Производительность. Пока SwiftUI менял высоту самого `MKMapView`, тот
///    переразмечался и перерисовывал тайлы на КАЖДЫЙ кадр жеста — это и был
///    лаг. Меняя высоту пустого контейнера, мы не трогаем карту вообще.
/// 2. Попадание по «ручке» листа. `MKMapView` — обычный UIKit-вью, и он
///    забирает касания в своих границах, даже если сверху нарисован SwiftUI.
///    Контейнер с `clipsToBounds` возвращает `nil` из `hitTest` за своими
///    пределами, поэтому под листом карта касания больше не перехватывает.
// MARK: - Карта + едущий по ней лист

/// Смещение листа под пальцем.
///
/// Отдельный объект, а не `@GestureState` в `SearchView`, ради производительности:
/// экран ДЕРЖИТ его в `@State`, но НЕ подписан на него, поэтому кадры жеста не
/// инвалидируют экран со списком результатов. Подписан только
/// `SearchSheetStack` — он один и перерисовывается на каждый кадр, заново
/// применяя `.frame`/`.offset` к уже построенным карте и листу.
@MainActor final class SheetDragModel: ObservableObject {
    @Published var delta: CGFloat = 0
}

/// Карта и лист результатов, который по ней ездит между тремя положениями.
///
/// `map`, `sheet` и `preview` — уже ПОСТРОЕННЫЕ значения: их `body` во время
/// жеста не вызывается, потому что их входные данные не менялись.
struct SearchSheetStack<Map: View, Scrim: View, Sheet: View, Preview: View>: View {
    /// Осевшее положение. Меняется только на прилипании.
    let top: CGFloat
    /// Точки прилипания, по возрастанию: «лист на весь экран» … «карта крупно».
    let stops: [CGFloat]
    @ObservedObject var drag: SheetDragModel
    let map: Map
    /// Скрим поверх видимой части карты — он один и меняет высоту на кадрах
    /// жеста, но это дешёвый градиент, а не UIKit-вью.
    let scrim: Scrim
    let sheet: Sheet
    let preview: Preview

    /// Положение под пальцем.
    private var live: CGFloat {
        min(max(top + drag.delta, stops.first ?? 0), stops.last ?? 0)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // Карта фиксированной высоты — ничего не переразмечается.
                map
                scrim.frame(height: live)

                // Лист всегда во всю высоту экрана и просто съезжает вниз:
                // меняется только смещение. Хвост, ушедший за нижний край,
                // компенсируется отступом внутри списка. −24 — нахлёст листа на
                // карту из макета.
                sheet
                    .frame(height: geo.size.height)
                    .offset(y: max(live - 24, 0))

                // Мини-карточка пина держится над верхней кромкой листа.
                preview.padding(.top, max(live - 116, 12))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Без `ignoresSafeArea(edges: .top)`: он увеличивал высоту стека на
            // верхнюю безопасную зону, не сдвигая его вверх, и лист ровно на
            // столько же уезжал под таб-бар.
            .animation(.sanStandard(0.35), value: top)
        }
    }
}

/// Ручка листа на UIKit-жесте.
///
/// Почему не `DragGesture`: жест SwiftUI живёт в дереве вьюх и пересоздаётся
/// вместе с ним. Экран подписан на `AppStore` через `@EnvironmentObject`, и
/// любая публикация стора (сработал слушатель Firestore, доехали отзывы)
/// пересобирает `body`, а вместе с ним и жест. Начатое перетаскивание при этом
/// обрывается: новый жест считает свой `translation` с нуля, лист прыгает
/// обратно к `sheetTop` и снова догоняет палец. На быстром рывке это не успевает
/// случиться, на медленном — случается по нескольку раз.
///
/// `UIPanGestureRecognizer` висит на живой `UIView`, которую SwiftUI при
/// пересборке переиспользует, поэтому жест не прерывается.
struct SheetPanHandle: UIViewRepresentable {
    /// Смещение пальца от начала жеста.
    var onChange: (CGFloat) -> Void
    /// Смещение и скорость (пункты/с) на отпускании.
    var onEnd: (CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handle(_:)))
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        // Замыкания пересобираются вместе с экраном — координатор зовёт свежие.
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: SheetPanHandle
        init(_ parent: SheetPanHandle) { self.parent = parent }

        @objc func handle(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view).y
            switch gesture.state {
            case .changed:
                parent.onChange(translation)
            case .ended, .cancelled, .failed:
                parent.onEnd(translation, gesture.velocity(in: gesture.view).y)
            default:
                break
            }
        }
    }
}

/// Контейнер карты. `clipsToBounds` прячет карту визуально, но `hitTest` всё
/// равно дошёл бы до подрезанной части — поэтому режем и его.
private final class ClipContainer: UIView {
    /// Докуда карта видна (ниже её накрывает лист результатов).
    ///
    /// Именно свойство, а не высота вьюхи: менять `frame` контейнера с картой на
    /// каждый кадр жеста — это layout всего поддерева MapKit 60 раз в секунду,
    /// и ровно от этого лист и тормозил. Присваивание `CGFloat` не стоит ничего.
    var visibleHeight: CGFloat = .greatestFiniteMagnitude

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard point.y <= visibleHeight else { return nil }
        return super.hitTest(point, with: event)
    }
}

struct VenuesMapView: UIViewRepresentable {
    let venues: [Venue]
    var selectedID: String? = nil
    /// Высота самой карты. Не меняется никогда.
    var fixedHeight: CGFloat
    /// Докуда карта видна и кликабельна — только для hit-теста, без layout.
    var visibleHeight: CGFloat
    /// Активные предложения — из них берётся подпись на пине.
    var dealsForPins: [Deal]
    var onSelectVenue: (Venue) -> Void
    var onSelectCluster: ([Venue]) -> Void
    var onTapEmpty: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Подписи пинов по макету: капсула с выгодой, а не иконка вилки.
    ///
    /// Правило: лучшая скидка заведения → `−40%`; иначе тип акции → `2+1`;
    /// иначе свежая акция или спецпредложение дня → `Новое`; иначе рейтинг.
    /// Самая большая скидка на карте получает акцентный градиент.
    static func annotations(for venues: [Venue], deals: [Deal]) -> [VenueAnnotation] {
        var byVenue: [String: [Deal]] = [:]
        for d in deals where d.isActive { byVenue[d.venueID, default: []].append(d) }

        let best = venues.compactMap { v -> (String, Int)? in
            guard let p = byVenue[v.id]?.compactMap(\.effectiveDiscountPercent).max() else { return nil }
            return (v.id, p)
        }.max { $0.1 < $1.1 }?.0

        return venues.enumerated().map { i, v in
            let venueDeals = byVenue[v.id] ?? []
            let label: String
            let style: VenueAnnotation.Style
            if let percent = venueDeals.compactMap(\.effectiveDiscountPercent).max() {
                label = "−\(percent)%"
                style = v.id == best ? .featured : .plain
            } else if let type = venueDeals.first?.type {
                label = LS(type.rawValue).uppercased()
                style = .plain
            } else if v.hasTodaySpecial {
                label = LS("Новое")
                style = .dark
            } else {
                label = "★ \(v.rating.sanRatingText)"
                style = .plain
            }
            // Разводим фазы «парения» — в макете задержки 0 / .5 / 1 / 1.4 с.
            let delays: [Double] = [0, 0.5, 1, 1.4]
            return VenueAnnotation(v, label: label, style: style,
                                   floatDelay: delays[i % delays.count])
        }
    }

    func makeUIView(context: Context) -> UIView {
        let container = ClipContainer()
        container.clipsToBounds = true
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        // Штатная кнопка «моё местоположение» — как компас-кнопка у UberEats.
        // Берём системную: она сама следит за режимом слежения и разрешениями.
        let locate = MKUserTrackingButton(mapView: map)
        locate.translatesAutoresizingMaskIntoConstraints = false
        locate.layer.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.94).cgColor
        locate.layer.cornerRadius = 10
        locate.layer.shadowColor = UIColor.black.cgColor
        locate.layer.shadowOpacity = 0.12
        locate.layer.shadowRadius = 8
        locate.layer.shadowOffset = CGSize(width: 0, height: 4)
        context.coordinator.locateButton = locate
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
        container.addSubview(map)
        container.addSubview(locate)
        // Кнопка держится за ВЕРХ карты: её нижняя часть уезжает под лист,
        // а верх всегда под строкой фильтров.
        NSLayoutConstraint.activate([
            locate.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            locate.topAnchor.constraint(equalTo: container.topAnchor, constant: 128),
            locate.widthAnchor.constraint(equalToConstant: 42),
            locate.heightAnchor.constraint(equalToConstant: 42),
        ])
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        context.coordinator.parent = self
        // Единственное, что реально меняется на кадрах жеста.
        (container as? ClipContainer)?.visibleHeight = visibleHeight

        guard let map = context.coordinator.mapView else { return }
        // Кадр ставим вручную и ТОЛЬКО когда он вправду поменялся: присваивание
        // `frame` дёргает layout MapKit, а во время жеста мы сюда заходим на
        // каждом кадре.
        let wanted = CGRect(x: 0, y: 0, width: container.bounds.width, height: fixedHeight)
        if map.frame != wanted { map.frame = wanted }

        // Дешёвая проверка «изменился ли список»: сравниваем сохранённые id, а
        // не собираем два множества заново каждый кадр.
        let newIDs = venues.map(\.id)
        guard context.coordinator.annotatedIDs != newIDs else { return }
        context.coordinator.annotatedIDs = newIDs
        map.removeAnnotations(map.annotations.compactMap { $0 as? VenueAnnotation })
        map.addAnnotations(Self.annotations(for: venues, deals: dealsForPins))
        context.coordinator.fitAll(animated: false)
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        static let pinID = "venuePin"
        var parent: VenuesMapView
        weak var mapView: MKMapView?
        /// Держим ссылку: кнопка слежения живёт столько же, сколько карта.
        var locateButton: MKUserTrackingButton?
        /// Что уже показано на карте — чтобы не пересобирать аннотации зря.
        var annotatedIDs: [String] = []
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
            guard let pin = annotation as? VenueAnnotation else { return nil }
            let view = (map.dequeueReusableAnnotationView(withIdentifier: VenuePinView.reuseID)
                        as? VenuePinView) ?? VenuePinView(annotation: pin,
                                                          reuseIdentifier: VenuePinView.reuseID)
            view.annotation = pin
            view.clusteringIdentifier = "venue"          // включает кластеризацию
            // Приоритет НЕ .required — иначе пины не кластеризуются. defaultHigh
            // группирует близкие/совпадающие пины в кластер вместо скрытия.
            view.displayPriority = .defaultHigh
            view.configure(pin, reduceMotion: UIAccessibility.isReduceMotionEnabled)
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
    /// Подпись на пине: по макету это не иконка, а капсула с выгодой
    /// (`−40%`, `2+1`, `Новое`).
    let label: String
    /// Оформление капсулы. `featured` — акцентный градиент (лучшая скидка),
    /// `dark` — чёрная («Новое»), `plain` — белая с чернильным текстом.
    enum Style { case featured, dark, plain }
    let style: Style
    /// Сдвиг фазы «парения», чтобы пины не качались синхронно.
    let floatDelay: Double

    init(_ v: Venue, label: String, style: Style, floatDelay: Double) {
        venue = v
        self.label = label
        self.style = style
        self.floatDelay = floatDelay
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: venue.latitude, longitude: venue.longitude)
    }
    var title: String? { venue.name }
}

/// Пин-капсула из макета: `padding 7×12`, радиус 999, 12/800, tracking −0.2,
/// тень `0 8px 18px rgba(0,0,0,.18)`. Парит `0 → −9 → 0` за 3.4 с.
final class VenuePinView: MKAnnotationView {
    static let reuseID = "venuePinCapsule"

    /// Готовые картинки капсул: ключ — «подпись|стиль».
    ///
    /// Пин — это КАРТИНКА, а не живой набор вьюх. Раньше каждый пин был UIView с
    /// подслоем-градиентом, лейблом и тенью на слое: при полусотне заведений
    /// карта таскала полсотни таких поддеревьев, и панорамирование лагало.
    /// Отрисовать один раз в `UIImage` (тень запекается в неё же) на порядок
    /// дешевле — дальше это просто спрайт, который MapKit двигает.
    private static let cache = NSCache<NSString, UIImage>()

    override func prepareForReuse() {
        super.prepareForReuse()
        layer.removeAllAnimations()
    }

    func configure(_ pin: VenueAnnotation, reduceMotion: Bool) {
        let img = Self.capsule(label: pin.label, style: pin.style)
        image = img
        centerOffset = CGPoint(x: 0, y: -img.size.height / 2)

        layer.removeAllAnimations()
        // Парит ТОЛЬКО акцентный пин. В макете плавают четыре штуки на весь
        // экран; на реальном городе их полсотни, и полсотни бесконечных
        // анимаций — это уже заметная работа для компоновщика на каждом кадре
        // панорамирования. Оставляем движение там, где оно несёт смысл.
        guard !reduceMotion, pin.style == .featured else { return }
        let float = CABasicAnimation(keyPath: "transform.translation.y")
        float.fromValue = 0
        float.toValue = -9
        float.duration = 1.7                    // 3.4 с на полный цикл
        float.autoreverses = true
        float.repeatCount = .infinity
        float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(float, forKey: "float")
    }

    /// Рисует капсулу по макету: `padding 7×12`, радиус 999, 12/800,
    /// tracking −0.2, тень `0 8px 18px rgba(0,0,0,.18)`.
    private static func capsule(label: String, style: VenueAnnotation.Style) -> UIImage {
        let key = "\(label)|\(style)" as NSString
        if let hit = cache.object(forKey: key) { return hit }

        let font = UIFont.systemFont(ofSize: 12, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: -0.2]
        let text = NSAttributedString(string: label, attributes: attributes)
        let textSize = text.size()
        let box = CGSize(width: ceil(textSize.width) + 24, height: ceil(textSize.height) + 14)

        // Поля под тень, чтобы она не обрезалась краем картинки.
        let blur: CGFloat = 9, dy: CGFloat = 8
        let inset = UIEdgeInsets(top: blur, left: blur, bottom: blur + dy, right: blur)
        let canvas = CGSize(width: box.width + inset.left + inset.right,
                            height: box.height + inset.top + inset.bottom)

        let renderer = UIGraphicsImageRenderer(size: canvas)
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(x: inset.left, y: inset.top, width: box.width, height: box.height)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: box.height / 2)

            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: dy), blur: blur * 2,
                         color: UIColor.black.withAlphaComponent(0.18).cgColor)
            // Тень рисуется от непрозрачной заливки; сам цвет перекроем ниже.
            UIColor.white.setFill()
            path.fill()
            cg.restoreGState()

            cg.saveGState()
            path.addClip()
            switch style {
            case .featured:
                let colors = [UIColor(Color(hex: Palette.accent)).cgColor,
                              UIColor(Color(hex: Palette.orange)).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                             colors: colors, locations: [0, 1]) {
                    cg.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY),
                                          end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
                }
            case .dark:
                UIColor(Color.sanInk).setFill(); path.fill()
            case .plain:
                UIColor.white.setFill(); path.fill()
            }
            cg.restoreGState()

            let color: UIColor = style == .plain ? UIColor(Color.sanInk) : .white
            var textAttributes = attributes
            textAttributes[.foregroundColor] = color
            let origin = CGPoint(x: rect.midX - textSize.width / 2,
                                 y: rect.midY - textSize.height / 2)
            NSAttributedString(string: label, attributes: textAttributes).draw(at: origin)
        }
        cache.setObject(img, forKey: key)
        return img
    }
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
        .environmentObject(AyantStores.app())
        .environmentObject(LocationManager())
        .tint(.sanAccent)
}
