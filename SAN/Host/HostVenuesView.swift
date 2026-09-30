import SwiftUI
import MapKit
import AyantDomain
import AyantFeatures

// MARK: - Tab 1 — Заведение
//
// Первая вкладка кабинета — это СТРАНИЦА заведения, а не список заведений.
//
// Раньше здесь была витрина: шапка со счётчиками, переключатель
// «Заведения / Акции» и сетка плиток 3×N, из которой заведение открывалось
// вторым тапом. У почти всех хозяев заведение одно — сетка из одной плитки
// была лишним шагом перед каждым действием, а «Акции» дублировали блок
// «Предложения» на самой странице. Поэтому:
//
// • нет заведений — пустое состояние с «Добавить заведение»;
// • одно — сразу его страница, без «назад»;
// • несколько — та же страница, а под шапкой — чипы всех заведений
//   (фото + название) с «Добавить» в конце.
//
// Название в шапке — всегда переключатель (лист со списком и «Добавить
// заведение»), даже при одном заведении: так второе заводится там же, где
// потом между ними переключаются. Устройство самой страницы — в
// комментарии к `HostVenueDetailView`.
//
// Выбранное заведение помнится между запусками (`HostSelection.venueKey`).
// Второе место, где заводят заведения и переходят между ними, — «Профиль».
// Не возвращайте сетку «ради второго заведения»: полоса решает это,
// не заставляя владельца одного заведения каждый раз проходить через список.

/// Ключи выбора на устройстве. Имя ключа — часть данных установленных
/// приложений: переименование молча сбросит выбор у всех.
enum HostSelection {
    /// id заведения, открытого на первой вкладке. Пусто — первое по списку.
    static let venueKey = "san.host.selectedVenueID"
}

struct HostVenuesView: View {
    @EnvironmentObject private var host: HostStore
    @AppStorage(HostSelection.venueKey) private var selectedVenueID = ""
    /// Путь стека — свой, чтобы сбрасывать его при смене заведения: иначе
    /// открытый импорт из Instagram остался бы от прошлого заведения.
    @State private var path = NavigationPath()
    @State private var showAddVenue = false
    @State private var showSwitcher = false

    /// Удалённое или чужое сохранённое id не оставляет экран пустым —
    /// правило в домене, `HostState.currentVenue(preferredID:)`.
    private var current: HostVenueDTO? { host.state.currentVenue(preferredID: selectedVenueID) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let v = current {
                    HostVenueDetailView(
                        venueID: v.id,
                        onSelectVenue: { selectedVenueID = $0 },
                        onAddVenue: { showAddVenue = true },
                        onShowAllVenues: { showSwitcher = true })
                        // Другое заведение — другой экран. Без `.id` SwiftUI
                        // переиспользовал бы состояние страницы, и черновик
                        // «Сегодняшнего специала» переехал бы к соседу.
                        .id(v.id)
                } else {
                    HostNoVenuesView { showAddVenue = true }
                }
            }
            .navigationDestination(for: HostPromoteTarget.self) {
                HostPromoteCreateView(venueID: $0.venueID)
            }
            .navigationDestination(for: HostInstagramTarget.self) {
                HostInstagramView(venueID: $0.venueID)
            }
            .navigationDestination(for: HostQuickAction.self) { action in
                switch action {
                case .promote: HostPromoteView()
                }
            }
            .hostAddVenueSheet(isPresented: $showAddVenue) { selectedVenueID = $0 }
            .sheet(isPresented: $showSwitcher) {
                HostVenueSwitcherSheet(selectedID: current?.id) { selectedVenueID = $0 }
            }
            .onChange(of: current?.id) { _, _ in path = NavigationPath() }
        }
    }
}

// MARK: - Верхняя строка кабинета

/// «Режим заведения» и «Я гость» над страницей заведения.
///
/// Раньше они жили в песочной шапке витрины. Шапка ушла вместе с сеткой, а
/// дверь обратно в гостевое приложение должна оставаться на первом экране:
/// её ищут именно там, где вошли.
struct HostHomeTopBar: View {
    @AppStorage("san.hostMode") private var hostMode = true

    var body: some View {
        HStack(spacing: 8) {
            HostModeChip()
            Spacer(minLength: 8)
            HostGuestPill { hostMode = false }
        }
        .padding(.horizontal, SanMetrics.screenPadding)
        .padding(.top, 6).padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color.sanHostHeader)
    }
}

// MARK: - Плашка «не синхронизировалось»

/// Провал записи на сервер раньше жил только в консоли: заведение выглядело
/// сохранённым, а существовало лишь в кэше телефона. Теперь это видно на
/// первом экране кабинета — в стиле `SanNoteCard`, с кнопкой повтора.
struct HostSyncFailureBanner: View {
    @EnvironmentObject private var host: HostStore

    var body: some View {
        if case .failed(let error) = host.state.sync {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xC24A12))
                    Text(Self.text(for: error))
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
        }
    }

    private static func text(for error: AppError) -> LocalizedStringKey {
        switch error {
        case .permissionDenied:
            return "Сервер отклонил сохранение: у аккаунта нет прав на это заведение. Данные видны только на этом устройстве."
        case .network:
            return "Нет связи с сервером. Изменения сохранены на устройстве и отправятся при следующем обновлении."
        default:
            return "Не удалось синхронизировать с сервером."
        }
    }
}

// MARK: - Нет заведений

private struct HostNoVenuesView: View {
    @EnvironmentObject private var host: HostStore
    let onAdd: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HostHomeTopBar()
                HostSyncFailureBanner()
                    .padding(.horizontal, SanMetrics.screenPadding)
                    .padding(.top, 12)
                VStack(spacing: 10) {
                    SanIconTile(systemName: "storefront.fill", filled: true, size: 64)
                    Text("У вас пока нет заведений").font(.golos(18, .bold)).foregroundStyle(Color.sanInk)
                    Text("Добавьте первое заведение, чтобы начать привлекать гостей.")
                        .font(.golos(15, .regular)).foregroundStyle(Color.sanInkSoft)
                        .multilineTextAlignment(.center)
                    Button("Добавить заведение", action: onAdd)
                        .buttonStyle(SanPrimaryButton())
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .padding(.top, 48)
            }
        }
        .sanScreenBackground()
        .sanStatusBarCap(.sanHostHeader)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { host.send(.sync) }
    }
}

// MARK: - Переключатель заведений

/// Лист «Ваши заведения»: выбор заведения для первой вкладки и вход в
/// создание нового. Статус модерации — в каждой строке: владелец нескольких
/// заведений открывает этот лист в том числе чтобы увидеть, что не опубликовано.
struct HostVenueSwitcherSheet: View {
    let selectedID: String?
    let onSelect: (String) -> Void
    @EnvironmentObject private var host: HostStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAddVenue = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(host.state.venues.enumerated()), id: \.element.id) { index, v in
                        if index > 0 { SanHairline(leading: 70) }
                        Button {
                            SanHaptics.selection()
                            onSelect(v.id)
                            dismiss()
                        } label: {
                            HostVenueRow(venue: v, selected: v.id == selectedID)
                        }
                        .buttonStyle(.plain)
                    }
                    SanHairline(leading: 70)
                    Button { showAddVenue = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Color.sanAccentText)
                                .frame(width: 44, height: 44)
                                .background(Color.sanAccent.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text("Добавить заведение")
                                .font(.golos(16, .semibold)).foregroundStyle(Color.sanAccentText)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .sanGroupCard()
                .padding(16)
            }
            .sanScreenBackground()
            .navigationTitle("Ваши заведения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
            // Созданное заведение сразу становится текущим: следующий шаг
            // после создания — наполнить именно его (меню, акции, лояльность).
            .hostAddVenueSheet(isPresented: $showAddVenue) { id in
                onSelect(id)
                dismiss()
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Строка заведения: обложка, название, категория и район, статус модерации.
/// Общая для листа-переключателя и группы «Заведения» в профиле.
struct HostVenueRow: View {
    let venue: HostVenueDTO
    var selected = false
    var chevron = false
    /// 34 — под иконки строк профиля, 44 — в листе-переключателе.
    var thumb: CGFloat = 44

    var body: some View {
        HStack(spacing: 12) {
            VenuePhoto(urlString: venue.imageURL.isEmpty ? nil : venue.imageURL,
                       gradient: venue.asVenue.gradientColors)
                .frame(width: thumb, height: thumb)
                .clipShape(RoundedRectangle(cornerRadius: thumb * 0.28, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(venue.name)
                    .font(.golos(16, .semibold)).foregroundStyle(Color.sanInk)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            HostModerationChip(status: venue.moderation)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.sanAccentText)
                    .accessibilityLabel("Выбрано")
            } else if chevron {
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.sanInkSoft)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var subtitle: String {
        [LS(venue.category.rawValue), venue.district]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// Статус модерации заведения короткой пилюлей.
struct HostModerationChip: View {
    let status: ModerationStatus

    var body: some View {
        Text(L(status.title))
            .font(.golos(11, .bold)).foregroundStyle(color)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch status {
        case .approved: return Color(hex: 0x1F7D3A)
        case .pending:  return Color(hex: 0xC26A00)
        case .rejected: return Color(hex: 0xC4262B)
        }
    }
}

// MARK: - Создание заведения

extension View {
    /// Лист «Новое заведение», который после сохранения сообщает id созданного.
    ///
    /// Форма сама ничего не возвращает — она шлёт намерение в `HostStore` и
    /// закрывается. Новое заведение находим сравнением списков до и после
    /// (`HostState.addedVenueID(since:)`); закрытие без сохранения ничего не
    /// выбирает.
    func hostAddVenueSheet(isPresented: Binding<Bool>,
                           onAdded: @escaping (String) -> Void) -> some View {
        modifier(HostAddVenueSheet(isPresented: isPresented, onAdded: onAdded))
    }
}

private struct HostAddVenueSheet: ViewModifier {
    @Binding var isPresented: Bool
    let onAdded: (String) -> Void
    @EnvironmentObject private var host: HostStore
    @State private var before: Set<String> = []

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, open in
                if open { before = host.state.ownedVenueIDs }
            }
            .sheet(isPresented: $isPresented, onDismiss: {
                if let id = host.state.addedVenueID(since: before) { onAdded(id) }
            }) {
                HostVenueFormView(existing: nil)
            }
    }
}

// MARK: - Детальный экран заведения (хост)

/// Разделы страницы заведения. Подписаны словами, а не иконками: хозяин
/// должен читать, куда нажимает, а не угадывать, что значит «билетик».
private enum HostVenueTab: CaseIterable {
    case deals, menu, coupons, loyalty

    var title: LocalizedStringKey {
        switch self {
        case .deals: return "Акции"
        case .menu: return "Меню"
        case .coupons: return "Купоны"
        case .loyalty: return "Лояльность"
        }
    }
}

/// Страница заведения — корень первой вкладки (см. `HostVenuesView`).
///
/// Читается сверху вниз, по одному вопросу на блок:
/// 1. **Какое заведение открыто** — переключатель в шапке (и чипы всех
///    заведений под ним, если их несколько).
/// 2. **Что это за заведение** — одна карточка: фото, название, адрес,
///    специал дня, «Изменить».
/// 3. **Видят ли его гости** — одна строка статуса с подписанным
///    переключателем «Показывать гостям».
/// 4. **Что в нём есть** — разделы словами (Акции · Меню · Купоны ·
///    Лояльность), закреплены при прокрутке; в каждом сверху — главное
///    действие раздела кнопкой с текстом.
///
/// Ничего важного не спрятано в иконках без подписи: единственное меню «•••»
/// хранит только редкое (продвижение, удаление).
struct HostVenueDetailView: View {
    let venueID: String
    /// Выбрать другое заведение (чипы под шапкой).
    var onSelectVenue: ((String) -> Void)? = nil
    /// «Добавить заведение» — в конце чипов и в листе заведений.
    var onAddVenue: (() -> Void)? = nil
    /// Лист со списком заведений — по нажатию на название в шапке.
    var onShowAllVenues: (() -> Void)? = nil
    @EnvironmentObject private var host: HostStore
    @AppStorage("san.hostMode") private var hostMode = true
    @State private var activeSheet: HostVenueSheet?
    @State private var showDeleteConfirm = false
    @State private var tab: HostVenueTab = .deals

    private var dto: HostVenueDTO? { host.state.venue(id: venueID) }
    private var hasSeveralVenues: Bool { host.state.venues.count > 1 }

    var body: some View {
        ScrollView {
            if let v = dto {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    header(v)
                    if hasSeveralVenues { venueChips(current: v) }
                    VStack(alignment: .leading, spacing: 12) {
                        HostSyncFailureBanner()
                        infoCard(v)
                        statusCard(v)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14).padding(.bottom, 18)
                    Section {
                        tabContent(v)
                    } header: {
                        tabBar(v)
                    }
                }
            }
        }
        .sanScreenBackground()
        .sanStatusBarCap(.sanHostHeader)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { host.send(.sync) }
        // Слушатель подключения Instagram нужен уже здесь: кнопка в «Акциях»
        // показывает «подключено / нет» до перехода на экран импорта.
        .task(id: venueID) { host.observeInstagram(venueID: venueID) }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editVenue: if let v = dto { HostVenueFormView(existing: v) }
            case .stampCard: if let v = dto { HostStampCardFormView(venue: v) }
            case .todaySpecial: if let v = dto { HostTodaySpecialSheet(venue: v) }
            case .addDeal: HostDealFormView(venueID: venueID, existing: nil)
            case .editDeal(let d): HostDealFormView(venueID: venueID, existing: d)
            case .addItem: HostItemFormView(venueID: venueID)
            case .menuImport: if let v = dto { HostMenuImportView(venue: v).environmentObject(host) }
            case .editItem(let item): HostItemEditView(venueID: venueID, item: item).environmentObject(host)
            case .addCoupon:
                HostCouponFormView(venueID: venueID, venueName: dto?.name ?? "", existing: nil)
            case .editCoupon(let c):
                HostCouponFormView(venueID: venueID, venueName: dto?.name ?? "", existing: c)
            }
        }
        .alert("Удалить заведение?", isPresented: $showDeleteConfirm) {
            // Страница — корень вкладки, закрывать нечего: после удаления
            // вкладка сама покажет следующее заведение или пустое состояние.
            Button("Удалить", role: .destructive) { host.send(.deleteVenue(id: venueID)) }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("«\(dto?.name ?? "")» и все его предложения будут удалены без возможности восстановления.")
        }
    }

    // MARK: 1. Шапка — какое заведение открыто

    /// Одна строка вместо трёх: «Режим заведения» стал подписью над
    /// названием, а название — переключателем. Он есть всегда, даже при одном
    /// заведении: в листе — «Добавить заведение», и владельцу одного не
    /// нужно искать, где заводится второе.
    private func header(_ v: HostVenueDTO) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                SanHaptics.selection()
                onShowAllVenues?()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasSeveralVenues ? "Ваши заведения · \(host.state.venues.count)" : "Режим заведения")
                        .textCase(.uppercase)
                        .font(.golos(10.5, .heavy)).tracking(1)
                        .foregroundStyle(Color.sanHostEyebrow)
                    HStack(spacing: 6) {
                        Text(v.name)
                            .font(.golos(22, .heavy)).tracking(-0.5)
                            .foregroundStyle(Color.sanInk)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.sanInkSoft)
                            .padding(5)
                            .background(Color.sanSurfaceMuted, in: Circle())
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.sanPress(0.97))
            .accessibilityHint(Text("Выбрать или добавить заведение"))
            Spacer(minLength: 8)
            HostGuestPill { hostMode = false }
        }
        .padding(.horizontal, SanMetrics.screenPadding)
        .padding(.top, 6).padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color.sanHostHeader)
    }

    /// Все заведения — чипами с фото И названием: кружки без подписи
    /// приходилось узнавать по картинке. Только при двух и больше.
    private func venueChips(current: HostVenueDTO) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(host.state.venues) { venue in
                        let selected = venue.id == current.id
                        Button {
                            guard !selected else { return }
                            SanHaptics.selection()
                            onSelectVenue?(venue.id)
                        } label: {
                            HStack(spacing: 8) {
                                VenuePhoto(urlString: venue.imageURL.isEmpty ? nil : venue.imageURL,
                                           gradient: venue.asVenue.gradientColors)
                                    .frame(width: 26, height: 26)
                                    .clipShape(Circle())
                                Text(venue.name)
                                    .font(.golos(14, .semibold))
                                    .lineLimit(1)
                                // Не опубликовано или скрыто — видно прямо в чипе.
                                if venue.moderation != .approved || venue.isPaused {
                                    Circle()
                                        .fill(venue.moderation == .rejected ? Color.red : Color.orange)
                                        .frame(width: 7, height: 7)
                                }
                            }
                            .foregroundStyle(selected ? Color.white : Color.sanInk)
                            .padding(.leading, 5).padding(.trailing, 14)
                            .frame(height: 36)
                            .background(selected ? AnyShapeStyle(LinearGradient.sanAccentGradient)
                                                 : AnyShapeStyle(Color.sanSurface),
                                        in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.sanHairline, lineWidth: selected ? 0 : 1))
                        }
                        .buttonStyle(.sanPress(0.96))
                        .id(venue.id)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                    if let onAddVenue {
                        Button(action: onAddVenue) {
                            Label("Добавить", systemImage: "plus")
                                .font(.golos(14, .semibold))
                                .foregroundStyle(Color.sanAccentText)
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .background(Color.sanAccent.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.sanPress(0.96))
                    }
                }
                .padding(.horizontal, SanMetrics.screenPadding)
                .padding(.vertical, 10)
            }
            .background(Color.sanHostHeader)
            .onAppear { proxy.scrollTo(current.id, anchor: .center) }
        }
    }

    // MARK: 2. Карточка — что это за заведение

    private func infoCard(_ v: HostVenueDTO) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VenuePhoto(urlString: v.imageURL.isEmpty ? nil : v.imageURL,
                           gradient: v.asVenue.gradientColors)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(v.name)
                        .font(.golos(18, .bold)).foregroundStyle(Color.sanInk)
                        .lineLimit(2)
                    let subtitle = [LS(v.category.rawValue), v.district]
                        .filter { !$0.isEmpty }.joined(separator: " · ")
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.golos(13.5)).foregroundStyle(Color.sanInkSoft)
                    }
                    if !v.address.isEmpty {
                        Text(v.address).font(.golos(13.5)).foregroundStyle(Color.sanInkSoft)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                moreMenu(v)
            }

            // Специал дня — строкой в карточке, с понятным «что это».
            Button { activeSheet = .todaySpecial } label: {
                HStack(spacing: 10) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.sanAccentText)
                        .frame(width: 30, height: 30)
                        .background(Color.sanAccent.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Специал дня")
                            .font(.golos(12, .semibold)).foregroundStyle(Color.sanInkSoft)
                        Text((v.todaySpecial ?? "").isEmpty ? LS("Не задан — нажмите, чтобы добавить") : v.todaySpecial!)
                            .font(.golos(14, .medium))
                            .foregroundStyle((v.todaySpecial ?? "").isEmpty ? Color.sanInkSoft : Color.sanInk)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.sanInkSoft)
                }
                .padding(10)
                .background(Color.sanSurfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { activeSheet = .editVenue } label: {
                Label("Изменить данные заведения", systemImage: "pencil")
                    .font(.golos(14, .semibold)).foregroundStyle(Color.sanInk)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(Color.sanSurfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.sanPress(0.98))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sanCard(padding: 0)
    }

    /// Только редкое: то, что нажимают раз в месяц, не должно стоять рядом
    /// с тем, что нажимают каждый день.
    private func moreMenu(_ v: HostVenueDTO) -> some View {
        Menu {
            // Продвижение скрыто до подключения оплаты — см. `ReleaseFlags.promote`.
            if ReleaseFlags.promote {
                NavigationLink(value: HostPromoteTarget(venueID: v.id)) {
                    Label("Продвигать заведение", systemImage: "megaphone")
                }
                NavigationLink(value: HostQuickAction.promote) {
                    Label("Все кампании продвижения", systemImage: "list.bullet.rectangle")
                }
                Divider()
            }
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                Label("Удалить заведение", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.sanInkSoft)
                .frame(width: 36, height: 36)
                .background(Color.sanSurfaceMuted, in: Circle())
        }
        .accessibilityLabel("Ещё")
    }

    // MARK: 3. Статус — видят ли гости

    /// Модерация и видимость — в одной строке, потому что отвечают на один
    /// вопрос: «увидит ли гость моё заведение сейчас». Переключатель раньше
    /// стоял у названия без подписи; теперь он называется тем, что делает.
    private func statusCard(_ v: HostVenueDTO) -> some View {
        let (icon, color, title, text) = statusCopy(v)
        // Одобренному заведению отдельная строка «Опубликовано» не нужна:
        // всё сказано подписью под переключателем. Место — под акции.
        let approved = v.moderation == .approved
        return VStack(alignment: .leading, spacing: 0) {
            if !approved {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.golos(15, .bold)).foregroundStyle(Color.sanInk)
                    Text(text).font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            SanHairline().padding(.vertical, 12)
            }
            Toggle(isOn: Binding(
                get: { !v.isPaused },
                set: { _ in host.send(.togglePause(venueID: v.id)) }
            )) {
                HStack(spacing: 12) {
                    if approved {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(color)
                            .frame(width: 32, height: 32)
                            .background(color.opacity(0.12), in: Circle())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Показывать гостям")
                            .font(.golos(14.5, .semibold)).foregroundStyle(Color.sanInk)
                        Text(approved ? text : "Выключите на ремонт или отпуск — данные сохранятся")
                            .font(.golos(12)).foregroundStyle(approved ? color : Color.sanInkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .tint(Color.sanOpen)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sanCard(padding: 0)
    }

    private func statusCopy(_ v: HostVenueDTO) -> (String, Color, LocalizedStringKey, LocalizedStringKey) {
        switch v.moderation {
        case .rejected:
            return ("xmark.octagon.fill", .red, "Отклонено модерацией",
                    "Исправьте данные в «Изменить данные заведения» и сохраните — отправим на проверку снова.")
        case .pending:
            return ("clock.fill", Color(hex: 0xC26A00), "На проверке",
                    "Обычно в течение суток. После одобрения заведение появится в ленте.")
        case .approved:
            return v.isPaused
                ? ("eye.slash.fill", Color(hex: 0xC26A00), "Скрыто от гостей",
                   "Скрыто: заведения и его акций нет в ленте и поиске.")
                : ("eye.fill", Color(hex: 0x1F7D3A), "Опубликовано",
                   "Сейчас гости видят заведение в ленте.")
        }
    }

    // MARK: 4. Разделы

    /// Закреплённые разделы — словами и с количеством: «Акции 7» читается
    /// сразу, иконка «сетка» — нет.
    private func tabBar(_ v: HostVenueDTO) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(HostVenueTab.allCases, id: \.self) { t in
                    let selected = tab == t
                    Button {
                        SanHaptics.selection()
                        withAnimation(.snappy(duration: 0.2)) { tab = t }
                    } label: {
                        HStack(spacing: 5) {
                            Text(t.title).font(.golos(14, .semibold)).lineLimit(1)
                            if let n = count(t, v), n > 0 {
                                Text("\(n)")
                                    .font(.golos(12, .bold)).monospacedDigit()
                                    .foregroundStyle(selected ? Color.sanAccentText : Color.sanInkSoft)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(selected ? Color.white : Color.sanSurfaceMuted, in: Capsule())
                            }
                        }
                        .foregroundStyle(selected ? Color.white : Color.sanInk)
                        .padding(.horizontal, 11)
                        .frame(height: 36)
                        // Акцент, а не `sanInk`: в тёмной теме `sanInk` светлый,
                        // и белая подпись выбранного пропадала на нём.
                        .background(selected ? AnyShapeStyle(LinearGradient.sanAccentGradient)
                                             : AnyShapeStyle(Color.sanSurface),
                                    in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.sanHairline, lineWidth: selected ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(Color.sanCanvas)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.sanHairline).frame(height: 0.5) }
    }

    private func count(_ t: HostVenueTab, _ v: HostVenueDTO) -> Int? {
        switch t {
        case .deals: return host.state.deals(forVenue: v.id).count
        case .menu: return v.items.count
        case .coupons: return host.state.couponOffers(forVenue: v.id).count
        case .loyalty: return nil
        }
    }

    @ViewBuilder
    private func tabContent(_ v: HostVenueDTO) -> some View {
        switch tab {
        case .deals:
            dealsTab(v)
        case .menu:
            itemsSection(v).padding(16).padding(.bottom, 20)
        case .coupons:
            couponsSection(v).padding(16).padding(.bottom, 20)
        case .loyalty:
            VStack(alignment: .leading, spacing: 16) {
                loyaltySection(v)
                if v.pointsEnabled { pointsCard(v) }
            }
            .padding(16).padding(.bottom, 20)
        }
    }

    // MARK: Акции — сетка как в Instagram

    /// Сверху — две кнопки с текстом (создать / взять из Instagram), под
    /// ними — сетка 3 в ряд до краёв экрана, как профиль Instagram.
    @ViewBuilder
    private func dealsTab(_ v: HostVenueDTO) -> some View {
        let deals = host.state.deals(forVenue: v.id)
        let ig = host.state.instagram(venueID: v.id)
        VStack(alignment: .leading, spacing: 12) {
            Text("Акции видят гости в ленте. Скидку заведение применяет само, на кассе.")
                .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button { activeSheet = .addDeal } label: {
                    Label("Новая акция", systemImage: "plus")
                        .font(.golos(14.5, .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(LinearGradient.sanAccentGradient,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.sanPress(0.97))
                NavigationLink(value: HostInstagramTarget(venueID: v.id)) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.on.rectangle")
                        Text("Из Instagram")
                        if ig.isConnected {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                        }
                    }
                    .font(.golos(14.5, .semibold)).foregroundStyle(Color.sanInk)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Color.sanSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.sanHairline, lineWidth: 1))
                }
                .buttonStyle(.sanPress(0.97))
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 14)

        if deals.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Color.sanInkSoft)
                Text("Пока нет акций")
                    .font(.golos(16, .bold)).foregroundStyle(Color.sanInk)
                Text("Первая акция появится здесь плиткой — как пост в Instagram.")
                    .font(.golos(13)).foregroundStyle(Color.sanInkSoft)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32).padding(.vertical, 40)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
                      spacing: 2) {
                ForEach(deals) { d in
                    Button { activeSheet = .editDeal(d) } label: { dealTile(d, venue: v) }
                        .buttonStyle(.plain)
                        .contextMenu { dealActions(d) }
                        .accessibilityLabel(Text(d.title))
                }
            }
            Text("Нажмите на акцию, чтобы изменить. Удержите — пауза, копия, удаление.")
                .font(.golos(12)).foregroundStyle(Color.sanInkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 28)
        }
    }

    @ViewBuilder
    private func dealActions(_ d: HostDealDTO) -> some View {
        Button { activeSheet = .editDeal(d) } label: { Label("Изменить", systemImage: "pencil") }
        Button {
            host.send(.setDealStatus(id: d.id, status: d.status == .paused ? .active : .paused))
        } label: {
            d.status == .paused
                ? Label("Возобновить", systemImage: "play")
                : Label("На паузу", systemImage: "pause")
        }
        Button { host.send(.duplicateDeal(id: d.id)) } label: {
            Label("Дублировать", systemImage: "plus.square.on.square")
        }
        Button(role: .destructive) { host.send(.deleteDeal(id: d.id)) } label: {
            Label("Удалить", systemImage: "trash")
        }
    }

    /// Плитка 3:4 без текста поверх фото, кроме скидки и статуса: заголовок
    /// на маленькой плитке читался плохо и закрывал фото. Статус — словом
    /// («Пауза», «Черновик»), а не значком, который нужно расшифровывать.
    private func dealTile(_ d: HostDealDTO, venue v: HostVenueDTO) -> some View {
        let cover = d.imageURL.isEmpty ? d.imageURLs.first : d.imageURL
        let inactive = d.status != .active
        // Color.clear задаёт размер по ширине колонки — не зависит от картинки.
        return Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                CoverImage(urlString: cover, gradient: v.asVenue.gradientColors,
                           emoji: d.emoji, emojiSize: 34)
            }
            .saturation(inactive ? 0.15 : 1)
            .overlay { if inactive { Color.black.opacity(0.25) } }
            .overlay(alignment: .topLeading) {
                if inactive {
                    Text(L(d.status.title))
                        .font(.golos(10.5, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if d.imageURLs.count > 1 {
                    Image(systemName: "square.fill.on.square.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .padding(7)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let pct = d.discountPercent, pct > 0 {
                    Text("−\(pct)%")
                        .font(.golos(11.5, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.sanAccent, in: Capsule())
                        .padding(6)
                }
            }
            .clipped()
            .contentShape(Rectangle())
    }

    // MARK: Секции вкладок

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
                glassTile(LF("%lld мин", PointsMath.effectiveCooldownMinutes(v.earnCooldownMinutes)), "Пауза скана")
                glassTile("\(v.pointsRewards.count)", "Награды")
                glassTile(LF("%lld мес", v.pointsExpiryMonths > 0 ? v.pointsExpiryMonths : 6), "Сгорание")
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

    /// «Меню» — бывшие «Объекты для отзывов». Хозяин думает не «объект
    /// для отзыва», а «моё меню»; то, что по блюду можно оставить отзыв, —
    /// свойство, а не название раздела.
    private func itemsSection(_ v: HostVenueDTO) -> some View {
        sectionCard("Меню", icon: "menucard.fill",
                    subtitle: "Блюда и услуги, которые гости могут оценить") {
            Spacer(minLength: 8)
            addButton { activeSheet = .addItem }
        } content: {
            menuImportRow(v)
            if v.items.isEmpty {
                Text("Пока пусто. Загрузите PDF меню или добавьте первое блюдо вручную.")
                    .font(.golos(13)).foregroundStyle(Color.sanInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // По разделам, в порядке меню; без разделов — одним списком.
                ForEach(MenuImport.grouped(v.items) { $0.section }, id: \.section) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        if !group.section.isEmpty {
                            Text(group.section)
                                .textCase(.uppercase)
                                .font(.golos(11, .heavy)).tracking(0.8)
                                .foregroundStyle(Color.sanInkSoft)
                                .padding(.top, 2)
                        }
                        ForEach(group.items) { item in itemRow(item, venueID: v.id) }
                    }
                }
                if v.items.contains(where: { $0.imageURL.isEmpty }) {
                    Text("Нажмите на блюдо, чтобы добавить фото или поправить цену.")
                        .font(.golos(12)).foregroundStyle(Color.sanInkSoft)
                }
            }
        }
    }

    private func itemRow(_ item: VenueItem, venueID: String) -> some View {
        HStack(spacing: 10) {
            Button { activeSheet = .editItem(item) } label: {
                HStack(spacing: 10) {
                    ItemThumb(item: item, size: 40)
                        .overlay(alignment: .bottomTrailing) {
                            if item.imageURL.isEmpty {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                    .padding(4).background(Color.sanAccent, in: Circle())
                                    .offset(x: 4, y: 4)
                            }
                        }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).font(.golos(14.5, .semibold)).foregroundStyle(Color.sanInk)
                            .lineLimit(1)
                        Text(item.details.isEmpty ? item.kindTitle : item.details)
                            .font(.golos(11.5)).foregroundStyle(Color.sanInkSoft)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let price = item.price {
                        Text("\(price) сом")
                            .font(.golos(13.5, .bold)).foregroundStyle(Color.sanInk)
                            .monospacedDigit()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(role: .destructive) {
                host.send(.deleteItem(venueID: venueID, itemID: item.id))
            } label: { Image(systemName: "trash").foregroundStyle(.red) }
            .buttonStyle(.plain)
            .accessibilityLabel("Удалить")
        }
        .padding(10)
        .background(Color.sanSurfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Вход в разбор меню из файла — там же, где хозяин думает о меню.
    private func menuImportRow(_ v: HostVenueDTO) -> some View {
        Button { activeSheet = .menuImport } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.sanAccentText)
                    .frame(width: 38, height: 38)
                    .background(Color.sanAccent.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Меню из файла")
                        .font(.golos(14.5, .semibold)).foregroundStyle(Color.sanInk)
                    Text(v.items.isEmpty
                         ? LS("PDF, Excel или CSV — блюда, цены и описания заполнятся сами")
                         : LS("Обновить цены и добавить новые блюда из файла"))
                        .font(.golos(12)).foregroundStyle(Color.sanInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x9A9188))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sanSurfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Купоны, которые гость покупает за бонусы.
    ///
    /// Отдельно от акций намеренно: акция — объявление и ничего не стоит,
    /// купон — товар, у него цена, остаток и расход для заведения. Держать их
    /// в одном списке значило бы снова смешать рекламу и обязательство.
    private func couponsSection(_ v: HostVenueDTO) -> some View {
        let offers = host.state.couponOffers(forVenue: v.id)
        return sectionCard("Купоны за бонусы", icon: "ticket.fill") {
                // Объяснение, откуда у гостя бонусы, раньше жило только в
                // пустом состоянии — заведение с одним купоном его больше
                // никогда не видело. А это вопрос про деньги: платят не
                // покупками у вас, а валютой, заработанной в приложении.
                SanInfoDot(
                    title: "Чем платит гость",
                    text: "Бонусы — валюта приложения: гость копит их в играх и за время в приложении, а не покупками у вас.\n\nПоэтому цену купона стоит ставить как за подарок постоянному гостю, а не как за товар: выпуск ограничен вами, и больше выпущенного не купят.")
            Spacer(minLength: 8)
            addButton { activeSheet = .addCoupon }
        } content: {
            if offers.isEmpty {
                Text("Выпустите купон — гость купит его за бонусы, которые заработал в приложении, и придёт к вам.")
                    .font(.golos(13)).foregroundStyle(Color.sanInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    ForEach(offers) { offer in
                        Menu {
                            Button("Изменить") { activeSheet = .editCoupon(offer) }
                            Button(offer.isPaused ? "Вернуть в продажу" : "Снять с продажи") {
                                host.send(.toggleCouponPause(id: offer.id))
                            }
                            Button("Удалить", role: .destructive) {
                                host.send(.deleteCouponOffer(id: offer.id))
                            }
                        } label: { couponRow(offer) }
                    }
                }
            }
        }
    }

    private func couponRow(_ offer: CouponOffer) -> some View {
        HStack(spacing: 12) {
            Text(offer.emoji).font(.system(size: 26))
                .frame(width: 44, height: 44)
                .background(Color.sanSurfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(offer.title)
                    .font(.golos(14.5, .semibold)).foregroundStyle(Color.sanInk)
                    .lineLimit(1)
                // Одна строка вместо четырёх бейджей: цена — главное, остальное
                // уточняет. Всё сразу превратило бы список в таблицу.
                Text(couponSubtitle(offer))
                    .font(.golos(12)).foregroundStyle(Color.sanInkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            couponStatusChip(offer)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sanSurfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func couponSubtitle(_ offer: CouponOffer) -> String {
        var parts = [LF("%lld бонусов", offer.cost)]
        if let remaining = offer.remaining {
            parts.append(LF("осталось %lld", remaining))
        }
        if offer.soldCount > 0 { parts.append(LF("продано %lld", offer.soldCount)) }
        return parts.joined(separator: " · ")
    }

    /// Что мешает продаже прямо сейчас — по одной причине за раз, в порядке
    /// важности: снятый с продажи купон не нужно ещё и модерировать.
    @ViewBuilder
    private func couponStatusChip(_ offer: CouponOffer) -> some View {
        if offer.isPaused {
            hostChip("Не в продаже", color: Color.sanInkSoft)
        } else if offer.status == .pending {
            hostChip("На модерации", color: Color.orange)
        } else if offer.status == .rejected {
            hostChip("Отклонён", color: .red)
        } else if offer.isSoldOut {
            hostChip("Разобрали", color: Color.sanInkSoft)
        } else {
            hostChip("В продаже", color: Color(hex: 0x1F7D3A))
        }
    }

    private func hostChip(_ text: LocalizedStringKey, color: Color) -> some View {
        Text(text)
            .font(.golos(11, .bold)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
            .fixedSize()
    }

    // MARK: Карта лояльности (обзор для бизнеса)

    private func loyaltySection(_ v: HostVenueDTO) -> some View {
        sectionCard("Карта лояльности", icon: "creditcard.fill") {
            Spacer(minLength: 8)
            Text(v.loyaltyEnabled ? "Включена" : "Выключена")
                .font(.golos(12, .bold))
                .foregroundStyle(v.loyaltyEnabled ? Color.sanOpen : Color.sanInkSoft)
        } content: {
            if v.loyaltyEnabled {
                // Карт может быть несколько («Кофе», «Пицца») — по строке на каждую.
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(v.stampCards) { StampCardSummaryRow(card: $0) }
                }
                Text(v.stampCards.count > 1
                     ? "Гость показывает карту на кассе, сотрудник сканирует и выбирает, какой карте засчитать штамп."
                     : "Гость показывает карту на кассе, сотрудник сканирует — +1 штамп. На \(v.loyaltyGoal)-м штампе гость получает «\(v.loyaltyReward)».")
                    .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Включите программу лояльности, чтобы гости возвращались: копили штампы за визиты и получали награду.")
                    .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { activeSheet = .stampCard } label: {
                Label(v.loyaltyEnabled ? "Настроить" : "Включить",
                      systemImage: v.loyaltyEnabled ? "slider.horizontal.3" : "plus.circle")
                    .font(.golos(13.5, .semibold))
            }
            .buttonStyle(.bordered).tint(.sanAccent)
        }
    }

    // MARK: Каркас секции

    /// Каждая секция — отдельная карточка, как «Карта лояльности»: заголовок
    /// с иконкой, действие справа, пояснение и содержимое на одной подложке.
    /// Раньше «Меню», «Предложения» и «Купоны» шли голым текстом по фону и
    /// сливались в одну ленту — было не видно, где кончается одна и
    /// начинается другая.
    private func sectionCard<Trailing: View, Content: View>(
        _ title: LocalizedStringKey, icon: String, subtitle: LocalizedStringKey? = nil,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.sanAccentText)
                        .frame(width: 28, height: 28)
                        .background(Color.sanAccent.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    Text(title)
                        .font(.golos(17, .bold)).foregroundStyle(Color.sanInk)
                        .lineLimit(1)
                    trailing()
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sanCard(padding: 0)
    }

    /// Круглый «+» вместо «+ Добавить»: подпись съедала строку заголовка,
    /// и «Купоны за бонусы» обрезались до «Купоны за бо…».
    private func addButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.sanAccentText)
                .frame(width: 34, height: 34)
                .background(Color.sanAccent.opacity(0.12), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Добавить")
        .padding(.vertical, -5)
    }
}

/// Маршрут к продвижению конкретного заведения.
struct HostPromoteTarget: Hashable { let venueID: String }

/// Единый источник модальных листов на детальном экране заведения.
private enum HostVenueSheet: Identifiable {
    case editVenue
    /// Только карта штампов. Кнопка на карточке лояльности раньше открывала
    /// общую форму заведения, и настройку карты приходилось искать среди
    /// часов работы и соцсетей.
    case stampCard
    /// «Специал дня» — строка в шапке. Раньше редактор стоял отдельной
    /// секцией и занимал полэкрана ради одной строки.
    case todaySpecial
    case addDeal
    case editDeal(HostDealDTO)
    case addItem
    /// Меню из файла (PDF/Excel/CSV): разбор, проверка, сохранение (`HostMenuImportView`).
    case menuImport
    /// Правка блюда и его фото.
    case editItem(VenueItem)
    case addCoupon
    case editCoupon(CouponOffer)

    var id: String {
        switch self {
        case .editVenue: return "editVenue"
        case .stampCard: return "stampCard"
        case .todaySpecial: return "todaySpecial"
        case .addDeal: return "addDeal"
        case .editDeal(let d): return "editDeal_\(d.id)"
        case .addItem: return "addItem"
        case .menuImport: return "menuImport"
        case .editItem(let item): return "editItem_\(item.id)"
        case .addCoupon: return "addCoupon"
        case .editCoupon(let c): return "editCoupon_\(c.id)"
        }
    }
}

// MARK: - Специал дня

/// Короткая строка на карточке заведения — до 100 символов.
private struct HostTodaySpecialSheet: View {
    let venue: HostVenueDTO
    @EnvironmentObject private var host: HostStore
    @Environment(\.dismiss) private var dismiss
    @State private var special = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("Короткая строка на карточке заведения: гости видят её в ленте.")
                    .font(.golos(13)).foregroundStyle(Color.sanInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Например: суп дня — борщ", text: $special, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.golos(15))
                    .padding(12)
                    .background(Color.sanSurfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .onChange(of: special) { _, new in
                        if new.count > 100 { special = String(new.prefix(100)) }
                    }
                HStack {
                    if !(venue.todaySpecial ?? "").isEmpty {
                        Button("Убрать специал", role: .destructive) { save("") }
                            .font(.golos(13.5, .semibold))
                    }
                    Spacer()
                    Text("\(special.count)/100")
                        .font(.golos(11.5)).foregroundStyle(Color.sanInkSoft)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(SanMetrics.screenPadding)
            .sanScreenBackground()
            .navigationTitle("Специал дня")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save(special) }
                        .disabled(special == (venue.todaySpecial ?? ""))
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear { special = venue.todaySpecial ?? "" }
    }

    private func save(_ text: String) {
        host.send(.setTodaySpecial(venueID: venue.id, text: text))
        dismiss()
    }
}

// MARK: - Карта штампов (лист с карточки заведения)

/// Настройка карты штампов — и больше ничего. Сохраняет через ту же
/// `saveVenue`, что и вкладка «Лояльность»: форма собирается из DTO целиком
/// (`HostForms.fields(from:)`), меняются только три поля карты, и остальные
/// данные заведения не затираются.
struct HostStampCardFormView: View {
    let venue: HostVenueDTO
    @EnvironmentObject private var host: HostStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: StampCardsDraft

    init(venue: HostVenueDTO) {
        self.venue = venue
        var d = StampCardsDraft(venue)
        if d.first.reward.isEmpty { d.first.reward = LS("Награда за лояльность") }
        _draft = State(initialValue: d)
    }

    private var isDirty: Bool { draft != StampCardsDraft(venue) }
    private var canSave: Bool { isDirty && draft.problem == nil }

    var body: some View {
        VStack(spacing: 0) {
            SanFormHeader(title: "Карта лояльности") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    StampCardsEditor(draft: $draft)
                    // Механика лояльности у заведения одна (`LoyaltyKind`):
                    // при включённых баллах сервер штампы не начисляет.
                    if draft.enabled && venue.pointsEnabled {
                        SanNoteCard(text: "У заведения включены баллы САН — пока они включены, штампы не начисляются. Механика лояльности одна: либо баллы, либо штампы.")
                    }
                }
                .padding(.horizontal, SanMetrics.screenPadding)
                .padding(.top, 8).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            SanStickyFooter {
                Button("Сохранить") { save() }
                    .buttonStyle(SanPrimaryButton())
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.6)
                if let problem = draft.problem {
                    Text(problem)
                        .font(.golos(11.5, .semibold)).foregroundStyle(Color(hex: 0xC24A12))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .sanScreenBackground()
    }

    private func save() {
        SanHaptics.save()
        var fields = HostForms.fields(from: venue)
        draft.apply(to: &fields, keepingReward: venue.loyaltyReward)
        host.send(.saveVenue(existing: venue, fields: fields))
        dismiss()
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
        _loyaltyReward = State(initialValue: existing?.loyaltyReward ?? LS("Награда за лояльность"))
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
                // Карта штампов здесь больше не правится: у неё свой лист
                // («Карта лояльности» на карточке заведения) и вкладка
                // «Лояльность». Поля остаются в состоянии формы и уходят в
                // `save()` как были — иначе сохранение данных заведения
                // выключало бы карту.
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
    /// Импорт из инстаграма: подпись и фото поста. Заполняет форму при
    /// создании; у правки существующей акции его нет.
    let imported: InstagramImport?
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

    init(venueID: String, existing: HostDealDTO?, imported: InstagramImport? = nil) {
        self.venueID = venueID
        self.existing = existing
        self.imported = imported
        // Подпись поста разбирается на заголовок и описание (`InstagramCaption`):
        // первая строка — витрина, остальное — текст. Ничего не теряется, хост
        // правит это руками.
        let parsed = imported.map { InstagramCaption.parse($0.caption) }
        _title = State(initialValue: existing?.title ?? parsed?.title ?? "")
        _details = State(initialValue: existing?.details ?? parsed?.details ?? "")
        // «Новинка» — самый безобидный тип для поста: скидку и срок хост
        // выставит сам, если это действительно акция.
        _type = State(initialValue: existing?.type ?? (imported != nil ? .novelty : .discount))
        _emoji = State(initialValue: existing?.emoji ?? "🔥")
        _newPrice = State(initialValue: existing?.newPrice.map(String.init) ?? "")
        _discount = State(initialValue: existing?.discountPercent.map(String.init) ?? "")
        _hasEnd = State(initialValue: existing?.endDate != nil)
        _endDate = State(initialValue: existing?.endDate ?? Calendar.current.date(byAdding: .day, value: 14, to: .now)!)
        // Импорт всегда открывается черновиком: пост писался для инстаграма —
        // без срока и условий, — и уходить в ленту не глядя он не должен.
        _isDraft = State(initialValue: existing?.status == .draft || (existing == nil && imported != nil))
        _imageURL = State(initialValue: existing?.imageURL ?? imported?.imageURLs.first ?? "")
        let imgs = existing?.imageURLs ?? imported?.imageURLs ?? []
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
            // Первое загруженное фото — как в карточке ленты. Размер задаёт
            // контейнер (`VenuePhoto` обрезает снимок сам).
            if let photo = imageURLs.first(where: { !$0.isEmpty }) {
                VenuePhoto(urlString: photo, gradient: gradient)
            }
            LinearGradient(
                stops: [.init(color: Color(hex: 0x17130F).opacity(0.94), location: 0),
                        .init(color: Color(hex: 0x17130F).opacity(0.74), location: 0.34),
                        .init(color: Color(hex: 0x17130F).opacity(0.10), location: 0.72),
                        .init(color: Color(hex: 0x17130F).opacity(0.28), location: 1)],
                startPoint: .bottom, endPoint: .top)

            VStack(alignment: .leading, spacing: 0) {
                Text(venue?.name ?? LS("Ваше заведение"))
                    .font(.golos(13, .bold)).foregroundStyle(.white.opacity(0.9))
                Text(title.isEmpty ? LS("Заголовок предложения") : title)
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
            terms: termsText.split(separator: "\n").map(String.init),
            sourcePostID: imported?.postID)))
        dismiss()
    }
}

/// Маршруты из карточки заведения к экранам без собственного маршрута.
enum HostQuickAction: Hashable {
    /// Список кампаний продвижения. Показывается только при `ReleaseFlags.promote`.
    case promote
}

// MARK: - Форма купона за бонусы

/// Заведение выпускает купон: что отдаёт, во сколько бонусов ценит, сколько
/// штук и до какой даты.
///
/// Цена и остаток — не украшения формы, а обязательство заведения: купленный
/// купон придётся отдать. Поэтому цена обязательна (`HostForms.minCouponCost`),
/// а остаток нельзя опустить ниже проданного — это делает `HostForms`, здесь
/// только поля.
struct HostCouponFormView: View {
    let venueID: String
    let venueName: String
    let existing: CouponOffer?
    @EnvironmentObject private var host: HostStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var details: String
    @State private var emoji: String
    @State private var cost: String
    @State private var limited: Bool
    @State private var stock: String
    @State private var hasExpiry: Bool
    @State private var expiresAt: Date
    @State private var isPaused: Bool

    init(venueID: String, venueName: String, existing: CouponOffer?) {
        self.venueID = venueID
        self.venueName = venueName
        self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _details = State(initialValue: existing?.details ?? "")
        _emoji = State(initialValue: existing?.emoji ?? "🎁")
        _cost = State(initialValue: existing.map { String($0.cost) } ?? "")
        _limited = State(initialValue: existing?.stock != nil)
        _stock = State(initialValue: existing?.stock.map(String.init) ?? "")
        _hasExpiry = State(initialValue: existing?.expiresAt != nil)
        _expiresAt = State(initialValue: existing?.expiresAt
                           ?? Calendar.current.date(byAdding: .month, value: 1, to: .now)!)
        _isPaused = State(initialValue: existing?.isPaused ?? false)
    }

    private var costValue: Int? { Int(cost.trimmingCharacters(in: .whitespaces)) }
    private var stockValue: Int? { Int(stock.trimmingCharacters(in: .whitespaces)) }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && (costValue ?? 0) >= HostForms.minCouponCost
            && (!limited || (stockValue ?? 0) > 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Что получает гость") {
                    TextField("Например, бесплатный капучино", text: $title)
                    TextField("Условия — необязательно", text: $details, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Эмодзи", text: $emoji)
                }

                Section("Цена в бонусах") {
                    TextField("Например, 500", text: $cost)
                        .keyboardType(.numberPad)
                    Text("Гость копит бонусы в приложении и обменивает их на этот купон. Цену выбираете вы — купон вы и отдаёте.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Сколько выпустить") {
                    Toggle("Ограничить количество", isOn: $limited.animation())
                    if limited {
                        TextField("Например, 50", text: $stock)
                            .keyboardType(.numberPad)
                        if let sold = existing?.soldCount, sold > 0 {
                            Text("Уже куплено: \(sold). Меньше этого числа выпуск не опустится.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Без ограничения — купон можно купить сколько угодно раз.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Срок") {
                    Toggle("Ограничить сроком", isOn: $hasExpiry.animation())
                    if hasExpiry {
                        DatePicker("Действует до", selection: $expiresAt, displayedComponents: .date)
                    }
                }

                Section {
                    Toggle("Снять с продажи", isOn: $isPaused)
                    Text(existing == nil
                         ? "Новый купон проходит модерацию — он появится у гостей после проверки."
                         : "Правка текста и цены модерацию не сбрасывает.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(existing == nil ? "Новый купон" : "Купон")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }.disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        host.send(.saveCouponOffer(existing: existing, fields: HostForms.CouponFields(
            venueID: venueID, venueName: venueName,
            title: title, details: details, emoji: emoji,
            cost: costValue ?? HostForms.minCouponCost,
            stock: limited ? stockValue : nil,
            expiresAt: hasExpiry ? expiresAt : nil,
            isPaused: isPaused)))
        dismiss()
    }
}
