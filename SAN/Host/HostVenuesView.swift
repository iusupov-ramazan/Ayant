import SwiftUI
import MapKit
import AyantDomain
import AyantFeatures

// MARK: - Tab 1 — Мои заведения
//
// Витрина, а не список. Прежний экран показывал карточки с обложкой 120pt: на
// экран влезало три заведения, между ними жил ряд кнопок, и «Заведения»
// читались как раздел настроек. Сетка 3×N квадратами встык показывает девять и
// отвечает на два вопроса без единого тапа — что опубликовано и где нет акций.
//
// Ряд быстрых действий («Лояльность» / «Продвижение») убран: «Лояльность» —
// это вкладка таб-бара, а продвижение живёт в списке действий заведения.

/// Какая витрина открыта. Это фильтр одной и той же сетки, а не навигация:
/// поэтому переключение — кросс-фейд на месте, без выезда плиток заново.
private enum HostGridTab: Hashable { case venues, deals }

struct HostVenuesView: View {
    @EnvironmentObject private var host: HostStore
    @EnvironmentObject private var store: AppStore
    @AppStorage("san.hostMode") private var hostMode = true
    @State private var showAddVenue = false
    @State private var venueToDelete: HostVenueDTO?
    @State private var editingVenue: HostVenueDTO?
    @State private var editingDeal: HostDealDTO?
    @State private var addDealTarget: AddDealTarget?
    @State private var statsTarget: VenueStatsTarget?
    @State private var viewsTotal = 0
    @State private var gridTab: HostGridTab = .venues
    /// Позиция страничной прокрутки. Отдельно от `gridTab`, потому что её
    /// двигает и палец, и нажатие на вкладку.
    @State private var pagedTab: HostGridTab? = .venues
    /// Высота окна прокрутки и высота шапки со вкладками — из них считается,
    /// сколько места остаётся странице. См. `pageMinHeight`.
    @State private var viewportHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var tabsHeight: CGFloat = 0
    /// Выезд плиток уже проигран — дальше вкладки меняются кросс-фейдом.
    @State private var didStagger = false
    @State private var pickVenueForDeal = false

    private var activeDeals: Int {
        host.state.venues.reduce(0) { $0 + host.state.deals(forVenue: $1.id).filter { $0.status == .active }.count }
    }

    /// Все акции всех заведений: порядок заведений, внутри — порядок акций
    /// (`deals(forVenue:)` уже отдаёт новые сверху).
    private var allDeals: [(deal: HostDealDTO, venue: HostVenueDTO)] {
        host.state.venues.flatMap { v in
            host.state.deals(forVenue: v.id).map { (deal: $0, venue: v) }
        }
    }

    /// Сколько остаётся странице под шапкой и вкладками.
    ///
    /// Без этого страница была ровно по своим плиткам, и пустота под ними
    /// принадлежала уже вертикальной прокрутке: пролистать витрину пальцем
    /// можно было только по самим плиткам. У заведения с одной-двумя карточками
    /// это почти весь экран, на котором свайп не работает.
    private var pageMinHeight: CGFloat {
        max(0, viewportHeight - headerHeight - tabsHeight)
    }

    var body: some View {
        NavigationStack {
            // `LazyVStack` + `Section` — ради закрепления вкладок: шапка уезжает,
            // переключатель витрин остаётся под часами. Обычный `VStack` этого
            // не умеет, закрепление живёт только в ленивом контейнере.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    sandHeader
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                    Section {
                        // Провал записи на сервер раньше жил только в консоли:
                        // заведение выглядело сохранённым, а существовало лишь
                        // в кэше телефона. Теперь это видно на самом экране.
                        if case .failed(let err) = host.state.sync { syncFailureBanner(err) }
                        // Без заведений — только пустое состояние: сетка с одной
                        // плиткой «+» под ним дублировала бы призыв.
                        if host.state.venues.isEmpty { emptyState } else { grid }
                    } header: {
                        segmentedTabs
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabsHeight = $0 }
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height - $0.safeAreaInsets.bottom
            } action: { viewportHeight = $0 }
            .sanScreenBackground()
            // Безопасную зону сверху БОЛЬШЕ НЕ игнорируем: закреплённые вкладки
            // прилипали бы к нулю и лезли под часы. Полосу под статус-баром
            // по-прежнему закрашивает `sanStatusBarCap`, поэтому кремовая шапка
            // выглядит так же, как раньше.
            .sanStatusBarCap(.sanHostHeader)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { host.send(.sync) }
            .task(id: host.state.venues.count) { await loadViews() }
            .navigationDestination(for: String.self) { id in
                if let dto = host.state.venue(id: id) { HostVenueDetailView(venueID: dto.id) }
            }
            .navigationDestination(for: HostPromoteTarget.self) {
                HostPromoteCreateView(venueID: $0.venueID)
            }
            .navigationDestination(for: HostQuickAction.self) { action in
                switch action {
                case .promote: HostPromoteView()
                }
            }
            .sheet(isPresented: $showAddVenue) { HostVenueFormView(existing: nil) }
            .sheet(item: $editingVenue) { HostVenueFormView(existing: $0) }
            .sheet(item: $editingDeal) { HostDealFormView(venueID: $0.venueID, existing: $0) }
            .sheet(item: $addDealTarget) { HostDealFormView(venueID: $0.venueID, existing: nil) }
            .sheet(item: $statsTarget) { HostVenueStatsSheet(venueID: $0.venueID) }
            // Для какого заведения заводим акцию: спрашиваем, только если
            // заведений больше одного — на единственном выбор не нужен.
            .confirmationDialog("Для какого заведения?", isPresented: $pickVenueForDeal, titleVisibility: .visible) {
                ForEach(host.state.venues) { v in
                    Button(v.name) { addDealTarget = AddDealTarget(venueID: v.id) }
                }
                Button("Отмена", role: .cancel) {}
            }
            .alert("Удалить заведение?", isPresented: Binding(
                get: { venueToDelete != nil },
                set: { if !$0 { venueToDelete = nil } }
            ), presenting: venueToDelete) { v in
                Button("Удалить", role: .destructive) { host.send(.deleteVenue(id: v.id)) }
                Button("Отмена", role: .cancel) {}
            } message: { v in
                Text("«\(v.name)» и все его предложения будут удалены без возможности восстановления.")
            }
        }
    }

    // MARK: Песочная шапка (SCREENS.md H2)

    private var sandHeader: some View {
        HostSandHeader(flat: true) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    HostModeChip()
                    Spacer(minLength: 8)
                    // Профиль — отдельная вкладка «Профиль», аватар из шапки убран.
                    HostGuestPill { hostMode = false }
                }
                .padding(.top, 2)

                Text("Заведения")
                    .sanEditorialTitle(42)
                    .foregroundStyle(Color.sanInk)
                    .padding(.top, 18)

                // Счётчики — реальные метрики приложения, а не выдуманные «за сегодня».
                HStack(spacing: 20) {
                    counter("\(host.state.venues.count)", LocalizedStringKey(Self.venuePlural(host.state.venues.count)))
                    counter("\(activeDeals)", "активных акций", accent: true)
                    counter("\(viewsTotal)", "просмотров")
                    Spacer(minLength: 0)
                }
                .padding(.top, 16)
            }
        }
    }

    private func counter(_ value: String, _ label: LocalizedStringKey, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.golos(24, .heavy)).tracking(-1)
                .foregroundStyle(accent ? Color(hex: 0xE04206) : Color.sanInk)
            Text(label)
                .font(.golos(11.5, .semibold))
                .foregroundStyle(Color.sanHostCaption)
        }
    }

    // MARK: Переключатель витрин

    private var segmentedTabs: some View {
        // Прокрутка по горизонтали, как в профиле Instagram: вкладки шириной по
        // содержимому, а не по 1/N экрана. Пока их две, ряд просто не двигается;
        // третья («Сохранённое», «Отзывы») въедет сюда, ничего не ломая, — тогда
        // как деление на равные доли пришлось бы переверстывать.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                tabButton(.venues, icon: "square.grid.2x2.fill",
                          label: "Заведения", count: host.state.venues.count)
                tabButton(.deals, icon: "tag.fill",
                          label: "Акции", count: host.state.deals.count)
            }
        }
        // Не пружинить, пока вкладки влезают целиком.
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background(alignment: .bottom) {
            Rectangle().fill(Color.sanHairline).frame(height: 0.5)
        }
        // Полоса закрепляется поверх сетки — сквозь прозрачный фон было бы
        // видно едущие под ней плитки.
        .background(Color.sanCanvas)
    }

    private func tabButton(_ t: HostGridTab, icon: String, label: String, count: Int) -> some View {
        let active = gridTab == t
        return Button { select(t) } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                (Text(L(label)) + Text(" \(count)"))
                    .textCase(.uppercase)
                    .font(.golos(12.5, .heavy)).tracking(0.3)
            }
            .foregroundStyle(active ? Color.sanInk : Color.sanTabIdle)
            .padding(.horizontal, 20)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(active ? Color.sanInk : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.sanPress(0.97))
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: Сетка

    private static let gap: CGFloat = 2

    /// Плитка акции — прямоугольник 4:5 (ширина/высота), как пост в Instagram.
    /// Заведение — это обложка, ему квадрата хватает; у акции под скримом живут
    /// заголовок и название заведения, и на квадрате они жмутся к самому краю.
    /// Пропорция ОДНА для всех акций: разнобой здесь читался бы как разный вес
    /// предложений, а его нет — это просто витрина.
    private static let dealAspect: CGFloat = 0.8

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Self.gap), count: 3)
    }

    /// Две витрины лежат рядом и листаются постранично, как в профиле
    /// Instagram: содержимое едет за пальцем и защёлкивается на странице.
    ///
    /// Раньше здесь была смена с кросс-фейдом по свайпу — жест срабатывал, но
    /// горизонтального движения не было видно, и на экране это не читалось как
    /// прокрутка. Обе сетки теперь всегда в дереве; высота ряда — по более
    /// высокой из них, поэтому под короткой остаётся пустое место.
    /// Плашка «не синхронизировалось» — в стиле `SanNoteCard`, с кнопкой повтора.
    private func syncFailureBanner(_ error: AppError) -> some View {
        let text: LocalizedStringKey
        switch error {
        case .permissionDenied:
            text = "Сервер отклонил сохранение: у аккаунта нет прав на это заведение. Данные видны только на этом устройстве."
        case .network:
            text = "Нет связи с сервером. Изменения сохранены на устройстве и отправятся при следующем обновлении."
        default:
            text = "Не удалось синхронизировать с сервером."
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xC24A12))
                Text(text)
                    .font(.golos(13)).foregroundStyle(Color(hex: 0xC24A12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Повторить") { host.send(.sync) }
                .buttonStyle(SanPillButton(accent: true))
                .disabled(host.state.sync.isSyncing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(hex: 0xFFF3EC),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, SanMetrics.screenPadding)
        .padding(.top, 12)
    }

    private var grid: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 0) {
                page(venuesGrid).id(HostGridTab.venues)
                page(dealsGrid).id(HostGridTab.deals)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $pagedTab)
        .onChange(of: pagedTab) { _, new in
            guard let new, new != gridTab else { return }
            didStagger = true        // выезд играем один раз, на входе
            SanHaptics.selection()
            gridTab = new
        }
    }

    /// Страница витрины: ширина — во всё окно, высота — не меньше оставшегося
    /// места. Заливка канвасом здесь не украшение: прозрачная область не ловит
    /// касания, и пустота под плитками не листалась бы.
    private func page<Content: View>(_ content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: pageMinHeight, alignment: .top)
            .containerRelativeFrame(.horizontal)
            .background(Color.sanCanvas)
    }

    /// Переключение витрины — один путь и для вкладок, и для пальца.
    private func select(_ t: HostGridTab) {
        guard t != gridTab else { return }
        didStagger = true
        SanHaptics.selection()
        withAnimation(.easeInOut(duration: 0.25)) { gridTab = t; pagedTab = t }
    }

    private var venuesGrid: some View {
        LazyVGrid(columns: columns, spacing: Self.gap) {
            ForEach(Array(host.state.venues.enumerated()), id: \.element.id) { index, v in
                NavigationLink(value: v.id) { venueTile(v) }
                    .buttonStyle(.sanPress(0.96))
                    .contextMenu { venueMenu(v) }
                    .sanRise(index, stagger: SanTiming.hostGridRise.stagger,
                             duration: SanTiming.hostGridRise.duration,
                             cap: SanTiming.gridStaggerCap, enabled: !didStagger)
            }
            addTile("Заведение") { showAddVenue = true }
        }
    }

    private var dealsGrid: some View {
        LazyVGrid(columns: columns, spacing: Self.gap) {
            ForEach(Array(allDeals.enumerated()), id: \.element.deal.id) { index, pair in
                Button { editingDeal = pair.deal } label: { dealTile(pair.deal, venue: pair.venue) }
                    .buttonStyle(.sanPress(0.96))
                    .sanRise(index, stagger: SanTiming.hostGridRise.stagger,
                             duration: SanTiming.hostGridRise.duration,
                             cap: SanTiming.gridStaggerCap, enabled: !didStagger)
            }
            addTile("Акция", aspect: Self.dealAspect) {
                // Акция всегда принадлежит заведению: без заведений вести
                // некуда, поэтому отправляем создавать его.
                if host.state.venues.isEmpty { showAddVenue = true }
                else if host.state.venues.count == 1 {
                    addDealTarget = AddDealTarget(venueID: host.state.venues[0].id)
                } else { pickVenueForDeal = true }
            }
        }
    }

    // MARK: Плитки

    /// Каркас плитки: размер задаёт ТОЛЬКО ширина колонки и пропорция.
    ///
    /// Основа — `Color.clear`: у неё нет собственного идеального размера,
    /// поэтому `aspectRatio` считает высоту от ширины и больше ни от чего.
    /// Пока фотография лежала прямо в стеке, её пропорция участвовала в
    /// расчёте, и плитки разъезжались по высоте, как только подгружались
    /// настоящие снимки. На моках с градиентом это не видно — там у подложки
    /// нет своей пропорции, и всё выглядит ровно.
    private func tile<Chrome: View>(aspect: CGFloat,
                                    photo: String?,
                                    gradient: [Color],
                                    @ViewBuilder chrome: () -> Chrome) -> some View {
        Color.clear
            .aspectRatio(aspect, contentMode: .fit)
            .overlay { VenuePhoto(urlString: photo, gradient: gradient) }
            .overlay { Self.scrim }
            .overlay { chrome().padding(7).allowsHitTesting(false) }
            .clipped()
            .contentShape(Rectangle())
    }

    /// Затемнение снизу — единственное, что держит белый текст читаемым на
    /// произвольной фотографии. Останавливается на 62 %, чтобы не пачкать кадр.
    private static let scrim = LinearGradient(
        stops: [
            .init(color: Color(hex: 0x17130F).opacity(0.86), location: 0),
            .init(color: Color(hex: 0x17130F).opacity(0.34), location: 0.34),
            .init(color: Color(hex: 0x17130F).opacity(0),    location: 0.62),
        ],
        startPoint: .bottom, endPoint: .top)

    private func venueTile(_ v: HostVenueDTO) -> some View {
        let dealCount = host.state.deals(forVenue: v.id).count
        return tile(aspect: 1, photo: v.imageURL, gradient: v.asVenue.gradientColors) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 4) {
                    if v.moderation != .approved { moderationTag(v.moderation) }
                    Spacer(minLength: 0)
                    dealCountBadge(dealCount)
                }
                Spacer(minLength: 0)
                HStack(alignment: .top, spacing: 5) {
                    statusDot(color: Self.color(for: v.moderation), size: 6,
                              ring: Color(hex: 0x17130F).opacity(0.5))
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(v.name)
                            .font(.golos(11, .heavy))
                            .foregroundStyle(.white)
                            .lineLimit(1).truncationMode(.tail)
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                        Text("\(v.category.rawValue) · \(v.district)")
                            .font(.golos(9.5, .bold))
                            .foregroundStyle(.white.opacity(0.86))
                            .lineLimit(1).truncationMode(.tail)
                            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(v.name), \(LS(v.moderation.title)), \(dealCount) акций")
    }

    private func dealTile(_ d: HostDealDTO, venue: HostVenueDTO) -> some View {
        tile(aspect: Self.dealAspect, photo: Self.cover(of: d),
             gradient: venue.asVenue.gradientColors) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 4) {
                    discountBadge(d)
                    Spacer(minLength: 0)
                    statusDot(color: Self.color(for: d.status), size: 9,
                              ring: .white.opacity(0.9))
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(d.title)
                        .font(.golos(11.5, .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1).truncationMode(.tail)
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    Text(venue.name)
                        .font(.golos(9.5, .bold))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(1).truncationMode(.tail)
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(d.title), \(venue.name), \(LS(d.status.title))")
    }

    private func addTile(_ label: String, aspect: CGFloat = 1,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Color.sanTileEmpty
                .aspectRatio(aspect, contentMode: .fit)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color.sanAccentText)
                        Text(L(label))
                            .font(.golos(10.5, .heavy))
                            .foregroundStyle(Color.sanInkSoft)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.sanPress(0.96))
    }

    // MARK: Мелочи плиток

    /// Значок числа акций. Ноль — тоже сигнал, поэтому плитка есть у любого
    /// заведения, а «0» просто гасится: витрина без акций видна с одного взгляда.
    private func dealCountBadge(_ n: Int) -> some View {
        Text("\(n)")
            .font(.golos(11, .heavy))
            .foregroundStyle(n > 0 ? Color(hex: 0x17130F) : .white)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(n > 0 ? Color.white.opacity(0.92) : Color(hex: 0x17130F).opacity(0.55),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func moderationTag(_ status: ModerationStatus) -> some View {
        Text(L(status == .rejected ? "Отклонено" : "Модерация"))
            .textCase(.uppercase)
            .font(.golos(9, .heavy)).tracking(0.4)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Self.color(for: status).opacity(0.94),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// Скидка, если она есть; иначе — тип публикации. Пустой угол ничего не
    /// сообщает, а «Новинка» отвечает на тот же вопрос, что и «−40 %».
    private func discountBadge(_ d: HostDealDTO) -> some View {
        Text(d.discountPercent.map { "−\($0)%" } ?? d.type.rawValue)
            .font(.golos(11, .heavy))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(LinearGradient.sanAccentGradient,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: Color(hex: 0xFF3B00).opacity(0.4), radius: 6, y: 4)
    }

    /// Точка статуса с кольцом СНАРУЖИ: `strokeBorder` съел бы половину
    /// шестипиксельной точки внутрь и оставил три пикселя цвета.
    private func statusDot(color: Color, size: CGFloat, ring: Color) -> some View {
        Circle().fill(color)
            .frame(width: size, height: size)
            .padding(1.5)
            .background(Circle().fill(ring))
    }

    private static func color(for status: ModerationStatus) -> Color {
        switch status {
        case .approved: return Color(hex: 0x4ADE80)
        case .pending:  return Color(hex: 0xFFB347)
        case .rejected: return Color(hex: 0xE5484D)
        }
    }

    private static func color(for status: DealStatus) -> Color {
        switch status {
        case .active:            return Color(hex: 0x4ADE80)
        case .draft:             return Color(hex: 0xFFB347)
        case .paused, .expired:  return Color(hex: 0xB9B0A6)
        }
    }

    private static func cover(of d: HostDealDTO) -> String {
        if let first = d.imageURLs.first(where: { !$0.isEmpty }) { return first }
        return d.imageURL
    }

    /// Действия заведения переехали с ряда кнопок под карточкой вдолгий тап по
    /// плитке: на квадрате 1/3 ширины кнопкам места нет, а сами действия нужны.
    @ViewBuilder
    private func venueMenu(_ v: HostVenueDTO) -> some View {
        Button { addDealTarget = AddDealTarget(venueID: v.id) } label: {
            Label("Добавить акцию", systemImage: "plus")
        }
        Button { statsTarget = VenueStatsTarget(venueID: v.id) } label: {
            Label("Аналитика", systemImage: "chart.bar.fill")
        }
        Button { editingVenue = v } label: {
            Label("Изменить", systemImage: "pencil")
        }
        Button(role: .destructive) { venueToDelete = v } label: {
            Label("Удалить", systemImage: "trash")
        }
    }

    // MARK: Пусто

    private var emptyState: some View {
        VStack(spacing: 10) {
            SanIconTile(systemName: "storefront.fill", filled: true, size: 64)
            Text("У вас пока нет заведений").font(.golos(18, .bold)).foregroundStyle(Color.sanInk)
            Text("Добавьте первое заведение, чтобы начать привлекать гостей.")
                .font(.golos(15, .regular)).foregroundStyle(Color.sanInkSoft)
                .multilineTextAlignment(.center)
            Button("Добавить заведение") { showAddVenue = true }
                .buttonStyle(SanPrimaryButton())
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .padding(.top, 24)
    }

    private func loadViews() async {
        var total = 0
        for v in host.state.venues {
            total += await store.analyticsStats(venueID: v.id, days: 30)[AnalyticsMetric.views] ?? 0
        }
        viewsTotal = total
    }

    private static func venuePlural(_ n: Int) -> String {
        let n10 = n % 10, n100 = n % 100
        if n10 == 1 && n100 != 11 { return "Заведение" }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return "Заведения" }
        return "Заведений"
    }
}

/// Обёртки для .sheet(item:).
struct AddDealTarget: Identifiable { var id: String { venueID }; let venueID: String }
struct VenueStatsTarget: Identifiable { var id: String { venueID }; let venueID: String }

// MARK: - Быстрая аналитика заведения (лист «Аналитика» на карточке)

struct HostVenueStatsSheet: View {
    let venueID: String
    @EnvironmentObject private var host: HostStore
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var period = 30
    @State private var stats: [String: Int] = [:]
    @State private var loading = false

    private let days = [7, 30, 90]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Период", selection: $period) {
                        ForEach(days, id: \.self) { Text("\($0)д").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        metric("Просмотры", AnalyticsMetric.views, "eye.fill")
                        metric("Погашено купонов", AnalyticsMetric.redemptions, "checkmark.seal.fill")
                        metric("Клики по акциям", AnalyticsMetric.dealTaps, "hand.tap.fill")
                        metric("Сохранения", AnalyticsMetric.saves, "bookmark.fill")
                        metric("Звонки", AnalyticsMetric.calls, "phone.fill")
                        metric("Маршруты", AnalyticsMetric.maps, "map.fill")
                    }
                }
                .padding(16)
            }
            .sanScreenBackground()
            .navigationTitle(host.state.venue(id: venueID)?.name ?? "Аналитика")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .task(id: period) { await load() }
        }
    }

    private func metric(_ title: String, _ key: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SanIconTile(systemName: icon, size: 36)
            Text("\(stats[key] ?? 0)").font(.golos(26, .heavy)).foregroundStyle(Color.sanInk)
            Text(title).font(.golos(13, .medium)).foregroundStyle(Color.sanInkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .sanCard(padding: 0)
    }

    private func load() async {
        loading = true
        stats = await store.analyticsStats(venueID: venueID, days: period)
        loading = false
    }
}

// MARK: - Детальный экран заведения (хост)

struct HostVenueDetailView: View {
    let venueID: String
    @EnvironmentObject private var host: HostStore
    @Environment(\.dismiss) private var dismiss
    @State private var special = ""
    @State private var activeSheet: HostVenueSheet?
    @State private var showDeleteConfirm = false

    private var dto: HostVenueDTO? { host.state.venue(id: venueID) }

    var body: some View {
        ScrollView {
            if let v = dto {
                VStack(alignment: .leading, spacing: 0) {
                    cover(v)
                    VStack(alignment: .leading, spacing: 20) {
                        titleBlock(v)
                        if v.moderation != .approved { moderationBanner(v) }
                        todaySpecialEditor(v)
                        if v.pointsEnabled { pointsCard(v) }
                        loyaltySection(v)
                        itemsSection(v)
                        dealsSection(v)
                        actions(v)
                    }
                    // 14 вместо общего экранного отступа 20: на карточке
                    // заведения внутренние блоки сами держат поля, и суммарно
                    // по бокам оставалось слишком много воздуха.
                    .padding(.horizontal, 14)
                    .padding(.top, 22).padding(.bottom, 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.sanCanvas,
                                in: UnevenRoundedRectangle(topLeadingRadius: SanRadius.sheet,
                                                           topTrailingRadius: SanRadius.sheet,
                                                           style: .continuous))
                    .padding(.top, -28)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) { if let v = dto { coverControls(v) } }
        .sanScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { special = dto?.todaySpecial ?? "" }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editVenue: if let v = dto { HostVenueFormView(existing: v) }
            case .addDeal: HostDealFormView(venueID: venueID, existing: nil)
            case .editDeal(let d): HostDealFormView(venueID: venueID, existing: d)
            case .addItem: HostItemFormView(venueID: venueID)
            case .scanCoupons: HostScannerView(fixedVenueID: venueID).environmentObject(host)
            }
        }
    }

    /// Обложка 220 + кнопка «назад» + чип статуса модерации (SCREENS.md H3).
    private func cover(_ v: HostVenueDTO) -> some View {
        ZStack(alignment: .top) {
            ZStack {
                LinearGradient(colors: v.asVenue.gradientColors,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                SanRisoHatch(opacity: 0.2, stripe: 1.5, period: 14)
                if let url = v.imageURL as String?, !url.isEmpty {
                    VenuePhoto(urlString: url)
                }
                LinearGradient(colors: [Color(hex: 0x17130F).opacity(0.30), .clear],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .clipped()

        }
    }

    /// Плавающие кнопки обложки. Живут ОВЕРЛЕЕМ поверх экрана, а не внутри
    /// скролла: иначе «назад» уезжает вместе с обложкой.
    private func coverControls(_ v: HostVenueDTO) -> some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.sanInk)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .background(Color.white.opacity(0.55),
                                in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.sanPress(0.90))
            .accessibilityLabel("Назад")
            Spacer()
            Text(L(v.moderation.title))
                .font(.golos(11.5, .heavy)).foregroundStyle(.white)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(v.moderation == .approved ? Color.sanOpen.opacity(0.9)
                                                     : Color(hex: Palette.orange).opacity(0.92),
                            in: Capsule())
        }
        .padding(.horizontal, 18)
        // Оверлей уважает безопасную зону: 58pt от верха экрана уже отмерены.
        .padding(.top, 0)
    }

    private func titleBlock(_ v: HostVenueDTO) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(v.name)
                    .sanText(32, .heavy, tracking: -1.6, lineHeight: 1)
                    .foregroundStyle(Color.sanInk)
                Text(v.address.isEmpty ? "\(v.category.rawValue) · \(v.district)" : v.address)
                    .font(.golos(13.5)).foregroundStyle(Color.sanInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            // Пауза скрывает заведение из ленты — переключатель остаётся здесь.
            Toggle("", isOn: Binding(
                get: { !v.isPaused },
                set: { _ in host.send(.togglePause(venueID: v.id)) }
            ))
            .labelsHidden()
            .tint(Color.sanOpen)
        }
    }

    /// «Баллы САН»: сколько начислено и три стеклянные плитки правил.
    private func pointsCard(_ v: HostVenueDTO) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Баллы САН")
                        .font(.golos(12.5, .semibold)).foregroundStyle(.white.opacity(0.9))
                    Text(v.pointsRewards.isEmpty ? "Награды не заведены" : "\(v.pointsRewards.count) наград")
                        .sanText(24, .heavy, tracking: -1)
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 8)
                if let mode = v.asVenue.pointsModeLabel {
                    Text(mode)
                        .font(.golos(12, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(.white.opacity(0.2), in: Capsule())
                        .fixedSize()
                }
            }
            HStack(spacing: 8) {
                glassTile("\(PointsMath.effectiveCooldownMinutes(v.earnCooldownMinutes)) мин", "Пауза скана")
                glassTile("\(v.pointsRewards.count)", "Награды")
                glassTile("\(v.pointsExpiryMonths > 0 ? v.pointsExpiryMonths : 6) мес", "Сгорание")
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.sanAccentGradient,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .sanShadow(.hero)
    }

    private func glassTile(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.golos(15, .heavy)).foregroundStyle(.white).lineLimit(1)
            Text(label).font(.golos(10.5)).foregroundStyle(.white.opacity(0.88))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color.white.opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func moderationBanner(_ v: HostVenueDTO) -> some View {
        HStack(spacing: 10) {
            Image(systemName: v.moderation == .rejected ? "xmark.octagon.fill" : "clock.fill")
                .foregroundStyle(v.moderation.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(L(v.moderation.title)).font(.subheadline.weight(.semibold))
                Text(v.moderation == .rejected
                     ? "Заведение отклонено. Отредактируйте данные и сохраните повторно."
                     : "Заведение на проверке. Появится в ленте после одобрения.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(v.moderation.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    private func itemsSection(_ v: HostVenueDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Объекты для отзывов").font(.golos(18, .bold))
                Spacer()
                Button { activeSheet = .addItem } label: { Label("Добавить", systemImage: "plus") }
                    .font(.caption.weight(.semibold))
            }
            Text("Блюда и услуги, которые гости смогут оценивать отдельно.")
                .font(.caption).foregroundStyle(.secondary)
            if v.items.isEmpty {
                Text("Пока нет объектов.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(v.items) { item in
                    HStack(spacing: 10) {
                        ItemThumb(item: item, size: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.subheadline)
                            Text(item.kindTitle).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            host.send(.deleteItem(venueID: v.id, itemID: item.id))
                        } label: { Image(systemName: "trash").foregroundStyle(.red) }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color.sanSurfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func todaySpecialEditor(_ v: HostVenueDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Сегодняшний специал", systemImage: "star.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.sanAccentText)
            TextField("До 100 символов — пусто, чтобы убрать", text: $special, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .onChange(of: special) { _, new in
                    if new.count > 100 { special = String(new.prefix(100)) }
                }
            Button("Сохранить специал") { host.send(.setTodaySpecial(venueID: v.id, text: special)) }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered).tint(.sanAccent)
        }
        .padding(.horizontal, 16)
    }

    private func dealsSection(_ v: HostVenueDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Предложения").font(.golos(18, .bold))
                Spacer()
                Button { activeSheet = .addDeal } label: { Label("Добавить", systemImage: "plus") }
                    .font(.caption.weight(.semibold))
            }
            let deals = host.state.deals(forVenue: v.id)
            if deals.isEmpty {
                Text("Пока нет предложений. Добавьте, чтобы привлекать гостей.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(deals) { d in
                        Menu {
                            Button("Изменить") { activeSheet = .editDeal(d) }
                            Button(d.status == .paused ? "Возобновить" : "На паузу") {
                                host.send(.setDealStatus(id: d.id, status: d.status == .paused ? .active : .paused))
                            }
                            Button("Дублировать") { host.send(.duplicateDeal(id: d.id)) }
                            Button("Удалить", role: .destructive) { host.send(.deleteDeal(id: d.id)) }
                        } label: { dealCell(d, gradient: [.sanAccent, .orange]) }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func dealCell(_ d: HostDealDTO, gradient: [Color]) -> some View {
        // Color.clear задаёт квадрат по ширине колонки — размер не зависит от картинки.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                CoverImage(urlString: d.imageURL.isEmpty ? nil : d.imageURL,
                           gradient: gradient, emoji: d.emoji, emojiSize: 30)
            }
            .overlay(alignment: .bottomLeading) {
                Text(L(d.status.title))
                    .font(.system(size: 8).weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(d.status.color, in: Capsule()).padding(5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Карта лояльности (обзор для бизнеса)

    private func loyaltySection(_ v: HostVenueDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Карта лояльности", systemImage: "creditcard.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(v.loyaltyEnabled ? "Включена" : "Выключена")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(v.loyaltyEnabled ? .green : .secondary)
            }
            if v.loyaltyEnabled {
                Text("\(v.loyaltyGoal) визитов → «\(v.loyaltyReward)»")
                    .font(.subheadline).foregroundStyle(.primary)
                Text("Гость получает штамп за каждое погашение вашего купона/акции. На \(v.loyaltyGoal)-м штампе ему автоматически выдаётся купон «\(v.loyaltyReward)», который он показывает вам.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Включите программу лояльности, чтобы гости возвращались: копили штампы за визиты и получали награду.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button { activeSheet = .editVenue } label: {
                Label(v.loyaltyEnabled ? "Настроить" : "Включить",
                      systemImage: v.loyaltyEnabled ? "slider.horizontal.3" : "plus.circle")
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sanCard(padding: 0)
        .padding(.horizontal, 16)
    }

    private func actions(_ v: HostVenueDTO) -> some View {
        VStack(spacing: 10) {
            Button { activeSheet = .scanCoupons } label: {
                Label("Сканировать купоны гостей", systemImage: "qrcode.viewfinder")
            }
            .buttonStyle(SanPrimaryButton())
            Button { activeSheet = .editVenue } label: {
                Label("Изменить данные заведения", systemImage: "pencil")
            }
            .buttonStyle(SanPillButton())
            // Продвижение скрыто до подключения оплаты — см. `ReleaseFlags.promote`.
            if ReleaseFlags.promote {
                NavigationLink(value: HostPromoteTarget(venueID: v.id)) {
                    Label("Продвигать это заведение", systemImage: "megaphone.fill")
                        .font(.golos(15, .semibold)).foregroundStyle(Color.sanAccentText)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.sanAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                // Единственный вход в список кампаний: ряд быстрых действий на
                // «Заведениях» убран вместе с карточками, а без этой строки хост
                // перестал бы видеть, что у него уже крутится.
                NavigationLink(value: HostQuickAction.promote) {
                    Label("Все кампании продвижения", systemImage: "list.bullet.rectangle")
                        .font(.golos(15, .semibold)).foregroundStyle(Color.sanInk)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.sanSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Удалить заведение", systemImage: "trash")
                    .font(.golos(15, .semibold)).foregroundStyle(.red)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .alert("Удалить заведение?", isPresented: $showDeleteConfirm) {
                Button("Удалить", role: .destructive) {
                    host.send(.deleteVenue(id: v.id))
                    dismiss()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("«\(v.name)» и все его предложения будут удалены без возможности восстановления.")
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Маршрут к продвижению конкретного заведения.
struct HostPromoteTarget: Hashable { let venueID: String }

/// Единый источник модальных листов на детальном экране заведения.
private enum HostVenueSheet: Identifiable {
    case editVenue
    case addDeal
    case editDeal(HostDealDTO)
    case addItem
    case scanCoupons

    var id: String {
        switch self {
        case .editVenue: return "editVenue"
        case .addDeal: return "addDeal"
        case .editDeal(let d): return "editDeal_\(d.id)"
        case .addItem: return "addItem"
        case .scanCoupons: return "scanCoupons"
        }
    }
}

// MARK: - Форма объекта (блюдо/услуга)

struct HostItemFormView: View {
    let venueID: String
    @EnvironmentObject private var host: HostStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var emoji = "🍽"
    @State private var kind = "food"
    @State private var imageURL = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Объект для отзывов") {
                    TextField("Название (напр. Лагман)", text: $name)
                    TextField("Эмодзи (если без фото)", text: $emoji)
                    Picker("Тип", selection: $kind) {
                        Text("Блюдо").tag("food")
                        Text("Услуга").tag("service")
                        Text("Объект").tag("other")
                    }
                }
                Section("Фото объекта") {
                    ImagePickerField(imageURL: $imageURL)
                }
            }
            .sanFormBackground()
            .navigationTitle("Новый объект")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        host.send(.addItem(venueID: venueID, name: name, emoji: emoji, kind: kind,
                                           imageURL: imageURL.trimmingCharacters(in: .whitespaces)))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Форма заведения (создание/редактирование)

struct HostVenueFormView: View {
    let existing: HostVenueDTO?
    @EnvironmentObject private var host: HostStore
    @ObservedObject private var catStore = CategoryStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var category: VenueCategory
    @State private var district: String
    @State private var address: String
    @State private var phone: String
    @State private var emoji: String
    @State private var latitude: String
    @State private var longitude: String
    @State private var openHour: Int
    @State private var closeHour: Int
    @State private var imageURL: String
    @State private var weekHours: [DayHours]
    @State private var pdfMenuURL: String
    @State private var whatsapp: String
    @State private var instagram: String
    @State private var telegram: String
    @State private var branches: [Branch]
    @State private var loyaltyEnabled: Bool
    @State private var loyaltyGoal: Int
    @State private var loyaltyReward: String
    @State private var couponsEnabled: Bool
    @State private var showingMapPicker = false
    @State private var showingBranchForm = false

    init(existing: HostVenueDTO?) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _category = State(initialValue: existing?.category ?? .cafe)
        _district = State(initialValue: existing?.district ?? "")
        _address = State(initialValue: existing?.address ?? "")
        _phone = State(initialValue: existing?.phone ?? "")
        _emoji = State(initialValue: existing?.emoji ?? "🍽")
        _latitude = State(initialValue: existing.map { String($0.latitude) } ?? String(City.bishkek.latitude))
        _longitude = State(initialValue: existing.map { String($0.longitude) } ?? String(City.bishkek.longitude))
        _openHour = State(initialValue: existing?.openHour ?? 9)
        _closeHour = State(initialValue: existing?.closeHour ?? 22)
        _imageURL = State(initialValue: existing?.imageURL ?? "")
        _pdfMenuURL = State(initialValue: existing?.pdfMenuURL ?? "")
        _whatsapp = State(initialValue: existing?.whatsapp ?? "")
        _instagram = State(initialValue: existing?.instagram ?? "")
        _telegram = State(initialValue: existing?.telegram ?? "")
        _branches = State(initialValue: existing?.branches ?? [])
        _loyaltyEnabled = State(initialValue: existing?.loyaltyEnabled ?? false)
        _loyaltyGoal = State(initialValue: existing?.loyaltyGoal ?? 6)
        _loyaltyReward = State(initialValue: existing?.loyaltyReward ?? "Награда за лояльность")
        _couponsEnabled = State(initialValue: existing?.couponsEnabled ?? true)
        let wh = existing?.weekHours ?? []
        _weekHours = State(initialValue: wh.count == 7 ? wh : Venue.defaultWeek())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SanFormHeader(title: existing == nil ? "Новое заведение" : "Изменить заведение") {
                    dismiss()
                }
                // Обложка-цель загрузки (SCREENS.md H4).
                coverTarget
                    .padding(.horizontal, SanMetrics.screenPadding)
                    .padding(.bottom, 8)
            Form {
                Section("Основное") {

                    TextField("Название", text: $name)
                    Picker("Категория", selection: $category) {
                        ForEach(catStore.categories) { Text($0.locKey).tag($0) }
                    }
                    TextField("Эмодзи", text: $emoji)
                    TextField("Район", text: $district)
                    TextField("Адрес", text: $address)
                    TextField("Телефон", text: $phone).keyboardType(.phonePad)
                }
                Section("Фото заведения") {
                    ImagePickerField(imageURL: $imageURL)
                }
                Section("Прайс-лист / каталог (PDF)") {
                    PDFPickerField(urlString: $pdfMenuURL)
                    Text("Список блюд или услуг. Гости откроют его на странице заведения.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Section("Соцсети") {
                    HStack(spacing: 12) {
                        brandTile("whatsapp")
                        TextField("WhatsApp (номер, напр. 996700123456)", text: $whatsapp)
                            .keyboardType(.phonePad)
                    }
                    HStack(spacing: 12) {
                        brandTile("instagram")
                        TextField("Instagram (ник или ссылка)", text: $instagram)
                            .autocapitalization(.none)
                    }
                    HStack(spacing: 12) {
                        brandTile("telegram")
                        TextField("Telegram (ник или ссылка)", text: $telegram)
                            .autocapitalization(.none)
                    }
                }
                Section {
                    Toggle("Принимать купоны", isOn: $couponsEnabled.animation())
                } header: {
                    Text("Купоны")
                } footer: {
                    Text(couponsEnabled
                         ? "Гости смогут получать и гасить купоны на ваши акции. Рекомендуем оставить включённым — купоны заметно повышают посещаемость."
                         : "⚠️ Купоны выключены — гости не увидят кнопку получения купона на ваших акциях. Рекомендуем включить: это привлекает больше гостей.")
                }
                Section {
                    Toggle("Карта лояльности", isOn: $loyaltyEnabled.animation())
                    if loyaltyEnabled {
                        Stepper("Штампов до награды: \(loyaltyGoal)",
                                value: $loyaltyGoal, in: 2...12)
                        TextField("Награда (напр. Бесплатный кофе)", text: $loyaltyReward)
                    }
                } header: {
                    Text("Программа лояльности")
                } footer: {
                    Text(loyaltyEnabled
                         ? "Гость получает штамп за каждое погашение купона у вас. На \(loyaltyGoal)-м штампе — «\(loyaltyReward)» купоном."
                         : "Включите, чтобы гости копили штампы за визиты и получали награду.")
                }
                Section("Филиалы (доп. адреса)") {
                    ForEach(branches) { b in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.address).font(.subheadline)
                            if !b.phone.isEmpty {
                                Text(b.phone).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { branches.remove(atOffsets: $0) }
                    Button {
                        showingBranchForm = true
                    } label: {
                        Label("Добавить филиал", systemImage: "plus.circle")
                    }
                }
                Section("Местоположение") {
                    Button {
                        showingMapPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                            Text("Выбрать точку на карте")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let coord = currentCoordinate {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: coord,
                            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)))) {
                            Marker("", coordinate: coord).tint(.red)
                        }
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .allowsHitTesting(false)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                    DisclosureGroup("Ввести координаты вручную") {
                        TextField("Широта", text: $latitude).keyboardType(.decimalPad)
                        TextField("Долгота", text: $longitude).keyboardType(.decimalPad)
                    }
                }
                Section("Часы работы") {
                    ForEach(0..<7, id: \.self) { i in
                        VStack(spacing: 6) {
                            Toggle(isOn: Binding(
                                get: { !weekHours[i].closed },
                                set: { weekHours[i].closed = !$0 }
                            )) {
                                Text(Venue.weekdayLong[i]).font(.subheadline)
                            }
                            if !weekHours[i].closed {
                                HStack {
                                    DatePicker("с", selection: timeBinding(i, \.open),
                                               displayedComponents: .hourAndMinute)
                                    DatePicker("до", selection: timeBinding(i, \.close),
                                               displayedComponents: .hourAndMinute)
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    Button("Применить понедельник ко всем дням") {
                        let mon = weekHours[0]
                        weekHours = Array(repeating: mon, count: 7)
                    }
                    .font(.caption)
                }
            }
            .scrollContentBackground(.hidden)
            SanStickyFooter {
                Button("Сохранить") { save() }
                    .buttonStyle(SanPrimaryButton())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1)
                // Правка сохраняет статус (`HostForms` не трогает `status`) —
                // на модерацию уходит только новое заведение.
                Text(existing == nil
                     ? "Новое заведение попадёт на модерацию — обычно до 24 часов."
                     : "Изменения сохранятся сразу, статус публикации не изменится.")
                    .font(.golos(11.5)).foregroundStyle(Color(hex: 0x9A9188))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            }
            .sanScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingMapPicker) {
                VenueLocationPicker(initial: currentCoordinate ?? bishkekCoordinate) { coord in
                    latitude = String(coord.latitude)
                    longitude = String(coord.longitude)
                }
            }
            .sheet(isPresented: $showingBranchForm) {
                HostBranchFormView { branches.append($0) }
            }
        }
    }

    /// Плитка-иконка соцсети с брендовым цветом.
    /// Круглая иконка соцсети с фирменным логотипом из `Assets.xcassets`.
    /// Логотипы — квадраты «в край» со своей подложкой, поэтому цвет не задаём.
    /// `scaledToFit` — картинка вписывается целиком, без растяжения по осям.
    private func brandTile(_ asset: String) -> some View {
        Image(asset)
            .resizable().scaledToFit()
            .frame(width: 34, height: 34)
            .clipShape(Circle())
    }

    /// Биндинг «минуты ↔ Date» для DatePicker часов работы.
    private func timeBinding(_ i: Int, _ key: WritableKeyPath<DayHours, Int>) -> Binding<Date> {
        Binding(
            get: {
                let mins = weekHours[i][keyPath: key]
                return Calendar.current.date(bySettingHour: mins / 60, minute: mins % 60, second: 0, of: Date()) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                weekHours[i][keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }

    /// Координаты из введённых строк, если они валидны.
    private var currentCoordinate: CLLocationCoordinate2D? {
        guard let lat = Double(latitude.replacingOccurrences(of: ",", with: ".")),
              let lng = Double(longitude.replacingOccurrences(of: ",", with: ".")),
              CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lng))
        else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private var bishkekCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: City.bishkek.latitude, longitude: City.bishkek.longitude)
    }

    /// Цель загрузки обложки: градиент + штриховка + подпись (SCREENS.md H4).
    private var coverTarget: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SanRadius.hero, style: .continuous)
                .fill(LinearGradient.sanAccentGradient)
            SanRisoHatch(opacity: 0.2, stripe: 1.5, period: 14)
                .clipShape(RoundedRectangle(cornerRadius: SanRadius.hero, style: .continuous))
            if !imageURL.isEmpty {
                VenuePhoto(urlString: imageURL)
                    .clipShape(RoundedRectangle(cornerRadius: SanRadius.hero, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "camera")
                        .font(.system(size: 26, weight: .light)).foregroundStyle(.white)
                    Text("Загрузить обложку")
                        .font(.golos(12.5, .bold)).foregroundStyle(.white)
                }
            }
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
    }

    private func save() {
        // Разбор координат из полей ввода; сборка DTO — в HostStore.saveVenueForm.
        let lat = Double(latitude.replacingOccurrences(of: ",", with: ".")) ?? City.bishkek.latitude
        let lng = Double(longitude.replacingOccurrences(of: ",", with: ".")) ?? City.bishkek.longitude
        host.send(.saveVenue(existing: existing, fields: HostForms.VenueFields(
            name: name, category: category, district: district, address: address,
            phone: phone, emoji: emoji, latitude: lat, longitude: lng,
            openHour: openHour, closeHour: closeHour, imageURL: imageURL,
            weekHours: weekHours, pdfMenuURL: pdfMenuURL, whatsapp: whatsapp,
            instagram: instagram, telegram: telegram, branches: branches,
            loyaltyEnabled: loyaltyEnabled, loyaltyGoal: loyaltyGoal,
            loyaltyReward: loyaltyReward, couponsEnabled: couponsEnabled)))
        dismiss()
    }
}

// MARK: - Форма филиала (дополнительный адрес)

struct HostBranchFormView: View {
    var onSave: (Branch) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var phone = ""
    @State private var latitude = String(City.bishkek.latitude)
    @State private var longitude = String(City.bishkek.longitude)
    @State private var showingMapPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Филиал") {
                    TextField("Адрес", text: $address)
                    TextField("Телефон (необязательно)", text: $phone).keyboardType(.phonePad)
                }
                Section("Местоположение") {
                    Button { showingMapPicker = true } label: {
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                            Text("Выбрать точку на карте")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let coord = coordinate {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: coord,
                            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)))) {
                            Marker("", coordinate: coord).tint(.red)
                        }
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .allowsHitTesting(false)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                    DisclosureGroup("Ввести координаты вручную") {
                        TextField("Широта", text: $latitude).keyboardType(.decimalPad)
                        TextField("Долгота", text: $longitude).keyboardType(.decimalPad)
                    }
                }
            }
            .sanFormBackground()
            .navigationTitle("Новый филиал")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        let c = coordinate ?? CLLocationCoordinate2D(latitude: City.bishkek.latitude,
                                                                     longitude: City.bishkek.longitude)
                        onSave(Branch(id: "br_\(UUID().uuidString.prefix(6))",
                                      address: address.trimmingCharacters(in: .whitespaces),
                                      latitude: c.latitude, longitude: c.longitude,
                                      phone: phone.trimmingCharacters(in: .whitespaces)))
                        dismiss()
                    }
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingMapPicker) {
                VenueLocationPicker(initial: coordinate ?? CLLocationCoordinate2D(
                    latitude: City.bishkek.latitude, longitude: City.bishkek.longitude)) { coord in
                    latitude = String(coord.latitude)
                    longitude = String(coord.longitude)
                }
            }
        }
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = Double(latitude.replacingOccurrences(of: ",", with: ".")),
              let lng = Double(longitude.replacingOccurrences(of: ",", with: ".")),
              CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lng))
        else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

// MARK: - Форма предложения

struct HostDealFormView: View {
    let venueID: String
    let existing: HostDealDTO?
    @EnvironmentObject private var host: HostStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var details: String
    @State private var type: DealType
    @State private var emoji: String
    @State private var newPrice: String
    @State private var discount: String
    @State private var hasEnd: Bool
    @State private var endDate: Date
    @State private var isDraft: Bool
    @State private var imageURL: String
    @State private var imageURLs: [String]
    /// Условия — по строке на пункт. Так их и правят: список из трёх коротких
    /// фраз проще набрать в одном поле, чем в трёх отдельных.
    @State private var termsText: String

    init(venueID: String, existing: HostDealDTO?) {
        self.venueID = venueID
        self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _details = State(initialValue: existing?.details ?? "")
        _type = State(initialValue: existing?.type ?? .discount)
        _emoji = State(initialValue: existing?.emoji ?? "🔥")
        _newPrice = State(initialValue: existing?.newPrice.map(String.init) ?? "")
        _discount = State(initialValue: existing?.discountPercent.map(String.init) ?? "")
        _hasEnd = State(initialValue: existing?.endDate != nil)
        _endDate = State(initialValue: existing?.endDate ?? Calendar.current.date(byAdding: .day, value: 14, to: .now)!)
        _isDraft = State(initialValue: existing?.status == .draft)
        _imageURL = State(initialValue: existing?.imageURL ?? "")
        let imgs = existing?.imageURLs ?? []
        _imageURLs = State(initialValue: imgs.isEmpty ? [existing?.imageURL].compactMap { $0 }.filter { !$0.isEmpty } : imgs)
        _termsText = State(initialValue: (existing?.terms ?? []).joined(separator: "\n"))
    }

    private var venue: HostVenueDTO? { host.state.venue(id: venueID) }

    // MARK: Проверка полей

    /// Пустое поле — «не задано», а не ошибка; ноль в скидке — тоже «без скидки».
    private var priceText: String { newPrice.trimmingCharacters(in: .whitespaces) }
    private var discountText: String { discount.trimmingCharacters(in: .whitespaces) }
    private var priceIsValid: Bool { priceText.isEmpty || (Int(priceText).map { $0 >= 0 } ?? false) }
    private var discountIsValid: Bool { discountText.isEmpty || (Int(discountText).map { (0...99).contains($0) } ?? false) }
    /// Значения, которые уйдут в DTO: цена ≥ 0, скидка 1…99, иначе `nil`.
    private var priceValue: Int? { Int(priceText).map { max(0, $0) } }
    private var discountValue: Int? { Int(discountText).flatMap { $0 <= 0 ? nil : min($0, 99) } }
    /// Только «Скидка» обязана нести цену или процент; акция, новинка и
    /// объявление — это текст.
    private var needsOffer: Bool { type == .discount }
    private var hasOffer: Bool { priceValue != nil || discountValue != nil }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && priceIsValid && discountIsValid
            && (!needsOffer || hasOffer)
    }
    private var priceHint: LocalizedStringKey? {
        priceIsValid ? nil : "Цена — целое число сомов, не меньше 0"
    }
    private var discountHint: LocalizedStringKey? {
        if !discountIsValid { return "Скидка — целое число от 1 до 99" }
        if needsOffer && !hasOffer { return "Для скидки укажите новую цену или процент" }
        return nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SanFormHeader(title: existing == nil ? "Новое предложение" : "Изменить предложение") {
                    dismiss()
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        typeChips
                        SanFieldCard {
                            SanFieldRow(label: "Заголовок") {
                                SanFieldInput(placeholder: "−30% на манты по будням", text: $title)
                            }
                            SanHairline(leading: 16)
                            SanFieldRow(label: "Новая цена, сом", hint: priceHint) {
                                SanFieldInput(placeholder: "195", text: $newPrice, keyboard: .numberPad)
                                    .foregroundStyle(Color.sanAccentText)
                            }
                            SanHairline(leading: 16)
                            SanFieldRow(label: "Скидка, %", hint: discountHint) {
                                SanFieldInput(placeholder: "30", text: $discount, keyboard: .numberPad)
                            }
                            SanHairline(leading: 16)
                            // Поле называлось «Условия», хотя писали в него
                            // описание. Теперь условия — отдельный список, а
                            // это снова описание.
                            SanFieldRow(label: "Описание") {
                                SanFieldInput(placeholder: "С 11:00 до 15:00 на все виды мантов",
                                              text: $details, axis: .vertical)
                            }
                            SanHairline(leading: 16)
                            SanFieldRow(label: "Условия",
                                        hint: "По одному в строке — гость увидит их списком") {
                                SanFieldInput(placeholder: "Каждый день до 12:00\nОдин напиток на гостя",
                                              text: $termsText, axis: .vertical)
                            }
                            SanHairline(leading: 16)
                            SanFieldRow(label: "Эмодзи") {
                                SanFieldInput(placeholder: "🔥", text: $emoji)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            eyebrow("Фото")
                            MultiImagePickerField(urls: $imageURLs)
                        }

                        SanFieldCard {
                            SanFieldRow(label: "Действует") {
                                VStack(alignment: .leading, spacing: 10) {
                                    SanGradientToggle(title: "Есть дата окончания", isOn: $hasEnd)
                                    if hasEnd {
                                        DatePicker("", selection: $endDate, displayedComponents: .date)
                                            .labelsHidden()
                                    }
                                }
                            }
                            SanHairline(leading: 16)
                            SanFieldRow(label: "Публикация") {
                                SanGradientToggle(title: "Сохранить как черновик",
                                                  subtitle: "Черновик не виден гостям",
                                                  isOn: $isDraft)
                            }
                        }

                        // Живой предпросмотр карточки ленты (SCREENS.md H5).
                        VStack(alignment: .leading, spacing: 10) {
                            eyebrow("Как увидят гости")
                            dealPreview
                        }
                    }
                    .padding(.horizontal, SanMetrics.screenPadding)
                    .padding(.top, 4).padding(.bottom, 24)
                }
                SanStickyFooter {
                    Button(existing == nil ? "Опубликовать" : "Сохранить") { save() }
                        .buttonStyle(SanPrimaryButton())
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.6)
                    // Предложения модерацию не проходят: не черновик — виден гостям сразу.
                    Text(isDraft
                         ? "Черновик не виден гостям — опубликуйте, когда будет готово."
                         : "Предложение публикуется сразу, без модерации.")
                        .font(.golos(11.5)).foregroundStyle(Color(hex: 0x9A9188))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .sanScreenBackground()
            .toolbar(.hidden, for: .navigationBar)

        }
    }

    // MARK: Детали формы акции

    private func eyebrow(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .textCase(.uppercase)
            .sanEyebrowText()
            .foregroundStyle(Color(hex: 0x9A9188))
    }

    private var typeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DealType.allCases) { t in
                    let isOn = t == type
                    Button {
                        SanHaptics.selection()
                        withAnimation(.sanStandard) { type = t }
                    } label: {
                        Text(t.locKey)
                            .font(.golos(13, .bold))
                            .foregroundStyle(isOn ? Color.white : Color.sanInkSoft)
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
            }
            .padding(.horizontal, 1)
        }
        .scrollClipDisabled()
    }

    /// Мини-версия карточки ленты: те же слои, только 210pt и без кнопок.
    private var dealPreview: some View {
        let gradient = venue?.asVenue.gradientColors ?? [.sanAccent, Color(hex: Palette.orange)]
        return ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            SanRisoHatch(opacity: 0.2, stripe: 1.5, period: 14)
            LinearGradient(
                stops: [.init(color: Color(hex: 0x17130F).opacity(0.94), location: 0),
                        .init(color: Color(hex: 0x17130F).opacity(0.74), location: 0.34),
                        .init(color: Color(hex: 0x17130F).opacity(0.10), location: 0.72),
                        .init(color: Color(hex: 0x17130F).opacity(0.28), location: 1)],
                startPoint: .bottom, endPoint: .top)

            VStack(alignment: .leading, spacing: 0) {
                Text(venue?.name ?? "Ваше заведение")
                    .font(.golos(13, .bold)).foregroundStyle(.white.opacity(0.9))
                Text(title.isEmpty ? "Заголовок предложения" : title)
                    .sanText(22, .heavy, tracking: -1, lineHeight: 1.05)
                    .foregroundStyle(.white).lineLimit(2)
                    .padding(.top, 6)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let p = Int(newPrice) {
                        Text("\(p) сом")
                            .font(.golos(19, .heavy)).foregroundStyle(Color(hex: 0xFFB300))
                    }
                    // Старая цена в предпросмотре не показывается: формой она не
                    // задаётся, а придумывать её нельзя.
                }
                .padding(.top, 8)
            }
            .padding(16)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: SanRadius.hero, style: .continuous))
        .overlay(alignment: .topLeading) {
            if let d = Int(discount), d > 0 {
                Text("−\(d)%")
                    .font(.golos(13, .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(LinearGradient.sanAccentGradient,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .rotationEffect(.degrees(-3))
                    .padding(.leading, 16).padding(.top, 14)
            }
        }
    }

    private func save() {
        host.send(.saveDeal(existing: existing, fields: HostForms.DealFields(
            venueID: venueID, type: type, title: title, details: details, emoji: emoji,
            newPrice: priceValue, discountPercent: discountValue,
            endDate: hasEnd ? endDate : nil, isDraft: isDraft, imageURLs: imageURLs,
            terms: termsText.split(separator: "\n").map(String.init))))
        dismiss()
    }
}

/// Маршруты из карточки заведения к экранам без собственного маршрута.
enum HostQuickAction: Hashable {
    /// Список кампаний продвижения. Показывается только при `ReleaseFlags.promote`.
    case promote
}
