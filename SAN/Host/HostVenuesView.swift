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
// • несколько — та же страница, а над ней — подписанная полоса «Ваши
//   заведения · N»: чипы всех заведений (фото + название + статус),
//   «Добавить» в конце и «Все» — лист со списком.
//
// Владельцу одного заведения переключатель не показываем вовсе: второе
// заводится в «Профиль → Заведения» и в листе «Все». Название в шапке
// больше не кнопка — заголовок-переключатель многие не узнавали.
// Устройство самой страницы — в комментарии к `HostVenueDetailView`,
// данные заведения — `HostVenueSettingsView`.
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
            .navigationDestination(for: HostVenueSettingsTarget.self) {
                HostVenueSettingsView(venueID: $0.venueID)
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
///
/// «Лояльности» здесь больше нет: у неё своя вкладка кабинета рядом, и
/// второй вход в те же настройки только путал, где их искать.
private enum HostVenueTab: CaseIterable {
    case deals, menu, coupons

    var title: LocalizedStringKey {
        switch self {
        case .deals: return "Акции"
        case .menu: return "Меню"
        case .coupons: return "Купоны"
        }
    }
}

/// Страница заведения — корень первой вкладки (см. `HostVenuesView`).
///
/// Здесь только ежедневная работа; всё о самом заведении (название, адреса,
/// часы, контакты, видимость, удаление) — на странице «Данные заведения»
/// (`HostVenueSettingsView`), куда ведёт карточка. Сверху вниз:
/// 1. **Какое заведение открыто** — при двух и больше: подписанная полоса
///    «Ваши заведения» с чипами всех заведений и кнопкой «Все».
/// 2. **Плашка модерации** — только когда гость не видит заведение не по
///    воле хозяина (на проверке / отклонено).
/// 3. **Карточка заведения** — фото, название, статус одной строкой и
///    подписанный вход «Данные заведения».
/// 4. **Предложение дня** — одна строка.
/// 5. **Разделы** Акции · Меню · Купоны — закреплены при прокрутке; в каждом
///    сверху одинаково: главное действие + второй способ (Instagram / файл).
///
/// Ничего важного не спрятано в иконках без подписи.
struct HostVenueDetailView: View {
    let venueID: String
    /// Выбрать другое заведение (чипы полосы «Ваши заведения»).
    var onSelectVenue: ((String) -> Void)? = nil
    /// «Добавить заведение» — в конце чипов и в листе заведений.
    var onAddVenue: (() -> Void)? = nil
    /// Лист со списком заведений — кнопка «Все» на полосе.
    var onShowAllVenues: (() -> Void)? = nil
    @EnvironmentObject private var host: HostStore
    @State private var activeSheet: HostVenueSheet?
    /// Блюдо, удаление которого ждёт подтверждения.
    @State private var itemPendingDelete: VenueItem?
    @State private var tab: HostVenueTab = .deals

    private var dto: HostVenueDTO? { host.state.venue(id: venueID) }
    private var hasSeveralVenues: Bool { host.state.venues.count > 1 }

    var body: some View {
        ScrollView {
            if let v = dto {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    HostHomeTopBar()
                    if hasSeveralVenues { venueSwitcher(current: v) }
                    VStack(alignment: .leading, spacing: 12) {
                        HostSyncFailureBanner()
                        moderationBanner(v)
                        venueCard(v)
                        todaySpecialRow(v)
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
            case .todaySpecial: if let v = dto { HostTodaySpecialSheet(venue: v) }
            case .addDeal: HostDealFormView(venueID: venueID, existing: nil)
            case .editDeal(let d): HostDealFormView(venueID: venueID, existing: d)
            case .addItem(let section): HostItemFormView(venueID: venueID, presetSection: section)
            case .menuImport: if let v = dto { HostMenuImportView(venue: v).environmentObject(host) }
            case .editItem(let item): HostItemEditView(venueID: venueID, item: item).environmentObject(host)
            case .addCoupon:
                HostCouponFormView(venueID: venueID, venueName: dto?.name ?? "", existing: nil)
            case .editCoupon(let c):
                HostCouponFormView(venueID: venueID, venueName: dto?.name ?? "", existing: c)
            }
        }
        .alert("Удалить блюдо?",
               isPresented: Binding(get: { itemPendingDelete != nil },
                                    set: { if !$0 { itemPendingDelete = nil } }),
               presenting: itemPendingDelete) { item in
            Button("Удалить", role: .destructive) {
                host.send(.deleteItem(venueID: venueID, itemID: item.id))
            }
            Button("Отмена", role: .cancel) {}
        } message: { item in
            Text("«\(item.name)» пропадёт из меню вместе с отзывами о нём.")
        }
    }

    // MARK: 1. Какое заведение открыто

    /// Полоса заведений — только при двух и больше. Подписана словами
    /// («Ваши заведения · 3»), чтобы было понятно, что это переключатель, а
    /// не украшение; выбранное — залито и с галочкой; у неопубликованных и
    /// скрытых — точка статуса прямо в чипе. «Все» открывает лист со
    /// списком, статусами и «Добавить заведение».
    ///
    /// Название в шапке больше не переключатель: заголовок, который ведёт
    /// себя как кнопка, многие не узнавали.
    private func venueSwitcher(current: HostVenueDTO) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Ваши заведения · \(host.state.venues.count)")
                    .textCase(.uppercase)
                    .font(.golos(11, .heavy)).tracking(0.8)
                    .foregroundStyle(Color.sanHostEyebrow)
                Spacer(minLength: 8)
                if let onShowAllVenues {
                    Button {
                        SanHaptics.selection()
                        onShowAllVenues()
                    } label: {
                        HStack(spacing: 3) {
                            Text("Все")
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        }
                        .font(.golos(13.5, .semibold))
                        .foregroundStyle(Color.sanAccentText)
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Все заведения")
                }
            }
            .padding(.horizontal, SanMetrics.screenPadding)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(host.state.venues) { venue in
                            venueChip(venue, selected: venue.id == current.id)
                                .id(venue.id)
                        }
                        if let onAddVenue {
                            Button(action: onAddVenue) {
                                Label("Добавить", systemImage: "plus")
                                    .font(.golos(14, .semibold))
                                    .foregroundStyle(Color.sanAccentText)
                                    .padding(.horizontal, 14)
                                    .frame(height: 40)
                                    .background(Color.sanAccent.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.sanPress(0.96))
                        }
                    }
                    .padding(.horizontal, SanMetrics.screenPadding)
                }
                // Без якоря — прокрутка ровно настолько, чтобы выбранный
                // чип был виден: `.center` обрезал первый чип у края, когда
                // все и так помещались.
                .onAppear { proxy.scrollTo(current.id) }
            }
        }
        .padding(.bottom, 12)
        .background(Color.sanHostHeader)
    }

    private func venueChip(_ venue: HostVenueDTO, selected: Bool) -> some View {
        Button {
            guard !selected else { return }
            SanHaptics.selection()
            onSelectVenue?(venue.id)
        } label: {
            HStack(spacing: 8) {
                VenuePhoto(urlString: venue.imageURL.isEmpty ? nil : venue.imageURL,
                           gradient: venue.asVenue.gradientColors)
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                Text(venue.name)
                    .font(.golos(14, .semibold))
                    .lineLimit(1)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                } else if venue.moderation != .approved || venue.isPaused {
                    // Не опубликовано или скрыто — видно прямо в чипе.
                    Circle()
                        .fill(venue.moderation == .rejected ? Color.red : Color.orange)
                        .frame(width: 7, height: 7)
                }
            }
            .foregroundStyle(selected ? Color.white : Color.sanInk)
            .padding(.leading, 6).padding(.trailing, 14)
            .frame(height: 40)
            .background(selected ? AnyShapeStyle(LinearGradient.sanAccentGradient)
                                 : AnyShapeStyle(Color.sanSurface),
                        in: Capsule())
            .overlay(Capsule().strokeBorder(Color.sanHairline, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.sanPress(0.96))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(selected ? Text("Открыто сейчас") : Text("Открыть это заведение"))
    }

    // MARK: 2. Плашка модерации

    /// Только «на проверке» и «отклонено»: опубликованному заведению плашка
    /// не нужна — всё сказано строкой статуса на карточке.
    @ViewBuilder
    private func moderationBanner(_ v: HostVenueDTO) -> some View {
        let state = HostVenueVisibility(v)
        if state.needsAttention {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: state.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(state.color)
                        .frame(width: 32, height: 32)
                        .background(state.color.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title).font(.golos(15, .bold)).foregroundStyle(Color.sanInk)
                        Text(state.text).font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                if v.moderation == .rejected {
                    NavigationLink(value: HostVenueSettingsTarget(venueID: v.id)) {
                        Text("Исправить данные")
                            .font(.golos(13.5, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 16).frame(height: 36)
                            .background(state.color, in: Capsule())
                    }
                    .buttonStyle(.sanPress(0.97))
                    .padding(.leading, 44)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(state.color.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // MARK: 3. Карточка заведения

    /// Вся карточка — одна кнопка в «Данные заведения», и это написано
    /// словами внизу карточки, а не спрятано в карандаше без подписи.
    private func venueCard(_ v: HostVenueDTO) -> some View {
        let state = HostVenueVisibility(v)
        return NavigationLink(value: HostVenueSettingsTarget(venueID: v.id)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    VenuePhoto(urlString: v.imageURL.isEmpty ? nil : v.imageURL,
                               gradient: v.asVenue.gradientColors)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(v.name)
                            .font(.golos(19, .heavy)).tracking(-0.3)
                            .foregroundStyle(Color.sanInk)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(verbatim: cardSubtitle(v))
                            .font(.golos(13)).foregroundStyle(Color.sanInkSoft)
                            .lineLimit(1)
                        // При модерации статус уже сказан плашкой над карточкой.
                        if !state.needsAttention {
                            HStack(spacing: 6) {
                                Circle().fill(state.color).frame(width: 7, height: 7)
                                Text(state.title)
                                    .font(.golos(12.5, .semibold)).foregroundStyle(state.color)
                            }
                            .padding(.top, 1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                SanHairline()
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.sanAccentText)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Данные заведения")
                            .font(.golos(14.5, .semibold)).foregroundStyle(Color.sanInk)
                        Text("Адреса, часы, контакты, видимость")
                            .font(.golos(12)).foregroundStyle(Color.sanInkSoft)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.sanInkSoft)
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .sanCard(padding: 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.sanPress(0.98))
        .accessibilityHint(Text("Название, адреса, часы работы, контакты, видимость"))
    }

    /// Категория и адрес: один адрес — пишем его, несколько — число.
    private func cardSubtitle(_ v: HostVenueDTO) -> String {
        let places = v.locations.filter { !$0.address.isEmpty }
        let where_: String
        switch places.count {
        case 0: where_ = v.district
        case 1: where_ = places[0].address
        default: where_ = "\(places.count) \(Plural.ru(places.count, "адрес", "адреса", "адресов"))"
        }
        return [LS(v.category.rawValue), where_].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: 4. Предложение дня

    private func todaySpecialRow(_ v: HostVenueDTO) -> some View {
        let special = v.todaySpecial ?? ""
        return Button { activeSheet = .todaySpecial } label: {
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.sanAccentText)
                    .frame(width: 32, height: 32)
                    .background(Color.sanAccent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text("Предложение дня")
                        .font(.golos(12, .semibold)).foregroundStyle(Color.sanInkSoft)
                    Text(special.isEmpty ? LS("Не задано — нажмите, чтобы добавить") : special)
                        .font(.golos(14.5, .medium))
                        .foregroundStyle(special.isEmpty ? Color.sanInkSoft : Color.sanInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.sanInkSoft)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sanCard(padding: 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.sanPress(0.98))
    }

    // MARK: 5. Разделы

    /// Три раздела помещаются без прокрутки — делим ширину поровну.
    private func tabBar(_ v: HostVenueDTO) -> some View {
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
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    // Акцент, а не `sanInk`: в тёмной теме `sanInk` светлый,
                    // и белая подпись выбранного пропадала на нём.
                    .background(selected ? AnyShapeStyle(LinearGradient.sanAccentGradient)
                                         : AnyShapeStyle(Color.sanSurface),
                                in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.sanHairline, lineWidth: selected ? 0 : 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.sanCanvas)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.sanHairline).frame(height: 0.5) }
    }

    private func count(_ t: HostVenueTab, _ v: HostVenueDTO) -> Int? {
        switch t {
        case .deals: return host.state.deals(forVenue: v.id).count
        case .menu: return v.items.count
        case .coupons: return host.state.couponOffers(forVenue: v.id).count
        }
    }

    @ViewBuilder
    private func tabContent(_ v: HostVenueDTO) -> some View {
        switch tab {
        case .deals: dealsTab(v)
        case .menu: menuTab(v)
        case .coupons: couponsTab(v)
        }
    }

    // MARK: Действия раздела

    /// Главное действие раздела — залитая кнопка с текстом. Одинаковое место
    /// и вид во всех трёх разделах: хозяин учит его один раз.
    private func primaryAction(_ title: LocalizedStringKey, icon: String = "plus") -> some View {
        Label(title, systemImage: icon)
            .font(.golos(14.5, .semibold)).foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 44)
            .background(LinearGradient.sanAccentGradient,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Второй способ добавить то же самое (Instagram, файл) — рядом, тоже
    /// с текстом, но без заливки.
    private func secondaryAction<Accessory: View>(
        _ title: LocalizedStringKey, icon: String,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title).lineLimit(1)
            accessory()
        }
        .font(.golos(14.5, .semibold)).foregroundStyle(Color.sanInk)
        .frame(maxWidth: .infinity).frame(height: 44)
        .background(Color.sanSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.sanHairline, lineWidth: 1))
    }

    private func emptyState(icon: String, title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.sanInkSoft)
            Text(title)
                .font(.golos(16, .bold)).foregroundStyle(Color.sanInk)
            Text(text)
                .font(.golos(13)).foregroundStyle(Color.sanInkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32).padding(.vertical, 36)
    }

    private func footnote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.golos(12)).foregroundStyle(Color.sanInkSoft)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 28)
    }

    // MARK: Акции — сетка как в Instagram

    /// Сверху — две кнопки с текстом (создать / взять из Instagram), под
    /// ними — сетка 3 в ряд до краёв экрана, как профиль Instagram.
    @ViewBuilder
    private func dealsTab(_ v: HostVenueDTO) -> some View {
        let deals = host.state.deals(forVenue: v.id)
        let ig = host.state.instagram(venueID: v.id)
        HStack(spacing: 8) {
            Button { activeSheet = .addDeal } label: { primaryAction("Новая акция") }
                .buttonStyle(.sanPress(0.97))
            NavigationLink(value: HostInstagramTarget(venueID: v.id)) {
                secondaryAction("Из Instagram", icon: "camera.on.rectangle") {
                    if ig.isConnected {
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                    }
                }
            }
            .buttonStyle(.sanPress(0.97))
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 14)

        if deals.isEmpty {
            emptyState(icon: "photo.on.rectangle.angled", title: "Пока нет акций",
                       text: "Акции видят гости в ленте, скидку вы применяете сами на кассе. Первая появится здесь плиткой — как пост в Instagram.")
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
            footnote("Нажмите на акцию, чтобы изменить. Удержите — пауза, копия, удаление.")
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

    // MARK: Меню

    /// «Меню» — бывшие «Объекты для отзывов». Сверху тот же порядок, что в
    /// «Акциях»: добавить вручную / взять из файла (PDF, Excel, CSV).
    @ViewBuilder
    private func menuTab(_ v: HostVenueDTO) -> some View {
        HStack(spacing: 8) {
            Button { activeSheet = .addItem(section: "") } label: { primaryAction("Блюдо") }
                .buttonStyle(.sanPress(0.97))
            Button { activeSheet = .menuImport } label: {
                secondaryAction("Из файла", icon: "doc.text.magnifyingglass")
            }
            .buttonStyle(.sanPress(0.97))
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 14)

        if v.items.isEmpty {
            emptyState(icon: "menucard", title: "Меню пока пустое",
                       text: "Загрузите меню файлом — PDF, Excel или CSV: блюда, цены и описания заполнятся сами. Или добавьте первое блюдо вручную.")
        } else {
            let groups = MenuImport.grouped(v.items) { $0.section }
            VStack(alignment: .leading, spacing: 14) {
                // По разделам, в порядке меню; без разделов — одним списком.
                ForEach(groups, id: \.section) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        // Блюда без раздела при других разделах подписаны —
                        // иначе они выглядели продолжением соседнего.
                        if !group.section.isEmpty || groups.count > 1 {
                            sectionHeader(group.section)
                        }
                        VStack(spacing: 0) {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { SanHairline(leading: 64) }
                                itemRow(item)
                            }
                        }
                        .sanGroupCard()
                    }
                }
            }
            .padding(.horizontal, 16)
            footnote("Нажмите на блюдо, чтобы добавить фото или поправить цену. Удержите — удалить.")
        }
    }

    /// Заголовок раздела с «+»: блюдо добавляется сразу в этот раздел.
    private func sectionHeader(_ section: String) -> some View {
        HStack(spacing: 8) {
            Text(section.isEmpty ? LS("Без раздела") : section)
                .textCase(.uppercase)
                .font(.golos(11, .heavy)).tracking(0.8)
                .foregroundStyle(Color.sanInkSoft)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button { activeSheet = .addItem(section: section) } label: {
                Label("Добавить", systemImage: "plus")
                    .font(.golos(12.5, .semibold))
                    .foregroundStyle(Color.sanAccentText)
                    .frame(minHeight: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(section.isEmpty ? Text("Добавить блюдо") : Text("Добавить блюдо в «\(section)»"))
        }
        .padding(.horizontal, 4)
    }

    /// Удаление — в меню по удержанию, а не корзиной в строке: корзина стояла
    /// вплотную к строке, и промах пальцем стирал блюдо вместе с отзывами.
    private func itemRow(_ item: VenueItem) -> some View {
        Button { activeSheet = .editItem(item) } label: {
            HStack(spacing: 12) {
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
            .padding(.horizontal, 12).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { activeSheet = .editItem(item) } label: { Label("Изменить", systemImage: "pencil") }
            Button(role: .destructive) { itemPendingDelete = item } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    // MARK: Купоны за бонусы

    /// Купоны, которые гость покупает за бонусы.
    ///
    /// Отдельно от акций намеренно: акция — объявление и ничего не стоит,
    /// купон — товар, у него цена, остаток и расход для заведения. Держать их
    /// в одном списке значило бы снова смешать рекламу и обязательство.
    @ViewBuilder
    private func couponsTab(_ v: HostVenueDTO) -> some View {
        let offers = host.state.couponOffers(forVenue: v.id)
        HStack(spacing: 10) {
            Button { activeSheet = .addCoupon } label: { primaryAction("Новый купон") }
                .buttonStyle(.sanPress(0.97))
            // Откуда у гостя бонусы — вопрос про деньги, поэтому объяснение
            // доступно всегда, а не только в пустом состоянии.
            SanInfoDot(
                title: "Чем платит гость",
                text: "Бонусы — валюта приложения: гость копит их в играх и за время в приложении, а не покупками у вас.\n\nПоэтому цену купона стоит ставить как за подарок постоянному гостю, а не как за товар: выпуск ограничен вами, и больше выпущенного не купят.")
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 14)

        if offers.isEmpty {
            emptyState(icon: "ticket", title: "Купонов пока нет",
                       text: "Выпустите купон — гость купит его за бонусы, которые заработал в приложении, и придёт к вам.")
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
            .padding(.horizontal, 16)
            footnote("Нажмите на купон — изменить, снять с продажи или удалить.")
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sanCard(padding: 0)
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
}

/// Маршрут к продвижению конкретного заведения.
struct HostPromoteTarget: Hashable { let venueID: String }

/// Единый источник модальных листов на детальном экране заведения.
private enum HostVenueSheet: Identifiable {
    /// «Предложение дня» (бывший «Специал дня») — строка в шапке. Раньше редактор стоял отдельной
    /// секцией и занимал полэкрана ради одной строки.
    case todaySpecial
    case addDeal
    case editDeal(HostDealDTO)
    /// Новое блюдо; раздел — если «+» нажат у раздела меню.
    case addItem(section: String)
    /// Меню из файла (PDF/Excel/CSV): разбор, проверка, сохранение (`HostMenuImportView`).
    case menuImport
    /// Правка блюда и его фото.
    case editItem(VenueItem)
    case addCoupon
    case editCoupon(CouponOffer)

    var id: String {
        switch self {
        case .todaySpecial: return "todaySpecial"
        case .addDeal: return "addDeal"
        case .editDeal(let d): return "editDeal_\(d.id)"
        case .addItem(let section): return "addItem_\(section)"
        case .menuImport: return "menuImport"
        case .editItem(let item): return "editItem_\(item.id)"
        case .addCoupon: return "addCoupon"
        case .editCoupon(let c): return "editCoupon_\(c.id)"
        }
    }
}

// MARK: - Предложение дня

/// Короткая строка на карточке заведения — до 100 символов.
private struct HostTodaySpecialSheet: View {
    let venue: HostVenueDTO
    @EnvironmentObject private var host: HostStore
    @Environment(\.dismiss) private var dismiss
    @State private var special = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text("Одна строка о том, что есть у вас сегодня. Гости видят её на странице заведения с пометкой «Предложение дня» и в ленте.")
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
                        Button("Убрать предложение", role: .destructive) { save("") }
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
            .navigationTitle("Предложение дня")
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

// MARK: - Форма объекта (блюдо/услуга)

/// Новое блюдо вручную — те же поля, что у правки (`HostItemEditView`):
/// фото, название, цена, раздел меню, описание. Раньше здесь были только
/// название, эмодзи и тип, и раздел появлялся у блюда лишь после импорта
/// файла — вручную добавленное падало в меню гостя без раздела.
struct HostItemFormView: View {
    let venueID: String
    /// Раздел, из которого нажали «+» (пусто — из общей кнопки «Блюдо»).
    var presetSection: String = ""
    @EnvironmentObject private var host: HostStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var section = ""
    @State private var priceText = ""
    @State private var details = ""
    @State private var kind = "food"
    @State private var imageURL = ""

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            SanFormHeader(title: "Новое блюдо") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DishFields(name: $name, section: $section, priceText: $priceText, details: $details,
                               sections: MenuImport.sections(host.state.venue(id: venueID)?.items ?? []))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Фото")
                            .textCase(.uppercase)
                            .font(.golos(11, .heavy)).tracking(0.9)
                            .foregroundStyle(Color(hex: 0x9A9188))
                        ImagePickerField(imageURL: $imageURL)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sanGroupCard(radius: SanRadius.card)
                    // Тип нужен не только кафе: у салона в «Меню» — услуги.
                    Picker("Тип", selection: $kind) {
                        Text("Блюдо").tag("food")
                        Text("Услуга").tag("service")
                        Text("Другое").tag("other")
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, SanMetrics.screenPadding)
                .padding(.top, 8).padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            SanStickyFooter {
                Button("Добавить") {
                    SanHaptics.save()
                    let item = VenueItem(id: "", name: name, emoji: "🍽", kind: kind, imageURL: imageURL,
                                         price: MenuImport.validPrice(Int(priceText.filter(\.isNumber))),
                                         details: details, section: section)
                    host.send(.addItem(venueID: venueID, item: item))
                    dismiss()
                }
                .buttonStyle(SanPrimaryButton())
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.6)
            }
        }
        .sanScreenBackground()
        .onAppear { if section.isEmpty { section = presetSection } }
    }
}

// MARK: - Форма заведения (создание/редактирование)

struct HostVenueFormView: View {
    let existing: HostVenueDTO?
    /// Какую часть данных показывать (строка «Данных заведения»); `nil` —
    /// форму целиком, для нового заведения. Скрытые части остаются в
    /// состоянии формы и уходят в `save()` как были — правка часов не
    /// затирает адреса.
    var part: HostVenueFormPart? = nil
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
    /// Какой адрес правится в листе (см. `AddressEdit`).
    @State private var editingAddress: AddressEdit?
    /// «Сохранить изменения?» — по «Отмене» и по свайпу вниз при черновике.
    @State private var confirmingDiscard = false
    /// Поля формы в момент открытия: с ними сравнивается `fields`, чтобы
    /// понять, есть ли что терять. Задаются в `onAppear`, а не в `init` —
    /// там ещё нет `@State`-значений.
    @State private var initialFields: HostForms.VenueFields?

    init(existing: HostVenueDTO?, part: HostVenueFormPart? = nil) {
        self.existing = existing
        self.part = part
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
                SanFormHeader(title: formTitle) {
                    if isDirty { confirmingDiscard = true } else { dismiss() }
                }
            Form {
                if shows(.basics) {
                Section("Основное") {
                    TextField("Название", text: $name)
                    Picker("Категория", selection: $category) {
                        ForEach(catStore.categories) { Text($0.locKey).tag($0) }
                    }
                    TextField("Эмодзи", text: $emoji)
                    TextField("Район", text: $district)
                }
                Section("Фото заведения") {
                    ImagePickerField(imageURL: $imageURL)
                }
                }
                if shows(.contacts) {
                Section("Контакты") {
                    TextField("Телефон", text: $phone).keyboardType(.phonePad)
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
                }
                if shows(.priceList) {
                Section("Прайс-лист / каталог (PDF)") {
                    PDFPickerField(urlString: $pdfMenuURL)
                    Text("Список блюд или услуг. Гости откроют его на странице заведения.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                }
                // «Принимать купоны» убран из формы: акции больше не выдают
                // купон (купон — товар, `couponOffers`), и переключатель
                // обещал то, чего нет. Поле остаётся в состоянии формы и
                // сохраняется как было.
                // Карта штампов здесь больше не правится: у неё свой лист
                // («Карта лояльности» на карточке заведения) и вкладка
                // «Лояльность». Поля остаются в состоянии формы и уходят в
                // `save()` как были — иначе сохранение данных заведения
                // выключало бы карту.
                // Все адреса одним списком: «главного» больше нет (см.
                // `VenueLocations`). Первый хранится в полях заведения,
                // остальные — в `branches`; для хозяина это просто «Адреса».
                if shows(.addresses) {
                Section {
                    ForEach(addressRows) { row in
                        Button { editingAddress = row.edit } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundStyle(Color.sanAccentText)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: row.place.address.isEmpty ? LS("Укажите адрес") : row.place.address)
                                        .font(.subheadline)
                                        .foregroundStyle(row.place.address.isEmpty ? Color.sanInkSoft : Color.sanInk)
                                    if !row.place.phone.isEmpty {
                                        Text(verbatim: row.place.phone).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        // Первый адрес не удаляется: у заведения должен быть хотя
                        // бы один. Его можно поправить — нажатием.
                        .deleteDisabled(row.edit == .first)
                    }
                    .onDelete { offsets in
                        // Строка 0 — первый адрес, в `branches` индексы на 1 меньше.
                        branches.remove(atOffsets: IndexSet(offsets.compactMap { $0 > 0 ? $0 - 1 : nil }))
                    }
                    Button { editingAddress = .new } label: {
                        Label("Добавить адрес", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Адреса")
                } footer: {
                    Text("Гости видят все адреса списком. Акцию можно сделать только для некоторых адресов — это выбирается в самой акции.")
                }
                }
                if shows(.hours) {
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
            .sheet(item: $editingAddress) { edit in
                switch edit {
                case .first:
                    HostBranchFormView(existing: firstAddress, showsPhone: false) { place in
                        address = place.address
                        latitude = String(place.latitude)
                        longitude = String(place.longitude)
                    }
                case .branch(let branch):
                    HostBranchFormView(existing: branch) { place in
                        if let i = branches.firstIndex(where: { $0.id == place.id }) { branches[i] = place }
                    }
                case .new:
                    HostBranchFormView { place in
                        // Первым заполняется пустой первый адрес — иначе у нового
                        // заведения «первый» так и остался бы пустым.
                        if address.trimmingCharacters(in: .whitespaces).isEmpty {
                            address = place.address
                            latitude = String(place.latitude)
                            longitude = String(place.longitude)
                        } else {
                            branches.append(place)
                        }
                    }
                }
            }
        }
        .onAppear { if initialFields == nil { initialFields = fields } }
        .sanConfirmDismiss(isDirty: isDirty) { confirmingDiscard = true }
        .confirmationDialog("Сохранить изменения?", isPresented: $confirmingDiscard,
                            titleVisibility: .visible) {
            Button("Сохранить") { save() }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Не сохранять", role: .destructive) { dismiss() }
            Button("Продолжить редактирование", role: .cancel) {}
        } message: {
            Text("Если закрыть без сохранения, правки пропадут.")
        }
    }

    private func shows(_ p: HostVenueFormPart) -> Bool { part == nil || part == p }

    private var formTitle: LocalizedStringKey {
        if existing == nil { return "Новое заведение" }
        return part?.title ?? "Изменить заведение"
    }

    /// Что правит лист адреса: первый адрес (поля заведения), дополнительный
    /// (элемент `branches`) или новый.
    private enum AddressEdit: Identifiable, Equatable {
        case first, new
        case branch(Branch)
        var id: String {
            switch self {
            case .first: return "first"
            case .new: return "new"
            case .branch(let b): return b.id
            }
        }
    }

    private struct AddressRow: Identifiable {
        let place: Branch
        let edit: AddressEdit
        var id: String { edit.id }
    }

    /// Первый адрес — из полей заведения; координаты — как введены.
    private var firstAddress: Branch {
        Branch(id: VenueLocations.firstID, address: address,
               latitude: Double(latitude.replacingOccurrences(of: ",", with: ".")) ?? City.bishkek.latitude,
               longitude: Double(longitude.replacingOccurrences(of: ",", with: ".")) ?? City.bishkek.longitude)
    }

    /// Строки списка «Адреса»: первый адрес (даже пустой — чтобы было куда
    /// нажать у нового заведения), затем остальные.
    private var addressRows: [AddressRow] {
        [AddressRow(place: firstAddress, edit: .first)]
            + branches.map { AddressRow(place: $0, edit: .branch($0)) }
    }

    /// Есть ли правки, которые потеряются при закрытии.
    private var isDirty: Bool {
        guard let initialFields else { return false }
        return fields != initialFields
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

    private func save() {
        host.send(.saveVenue(existing: existing, fields: fields))
        dismiss()
    }

    /// Поля формы как они есть сейчас — и для сохранения, и для сравнения
    /// с `initialFields`. Сборка DTO — в HostStore.saveVenueForm.
    private var fields: HostForms.VenueFields {
        // Разбор координат из полей ввода.
        let lat = Double(latitude.replacingOccurrences(of: ",", with: ".")) ?? City.bishkek.latitude
        let lng = Double(longitude.replacingOccurrences(of: ",", with: ".")) ?? City.bishkek.longitude
        return HostForms.VenueFields(
            name: name, category: category, district: district, address: address,
            phone: phone, emoji: emoji, latitude: lat, longitude: lng,
            openHour: openHour, closeHour: closeHour, imageURL: imageURL,
            weekHours: weekHours, pdfMenuURL: pdfMenuURL, whatsapp: whatsapp,
            instagram: instagram, telegram: telegram, branches: branches,
            loyaltyEnabled: loyaltyEnabled, loyaltyGoal: loyaltyGoal,
            loyaltyReward: loyaltyReward, couponsEnabled: couponsEnabled)
    }
}

// MARK: - Форма адреса

/// Один адрес заведения: новый или правка существующего.
///
/// Бывшая «Форма филиала». Адреса больше не делятся на главный и
/// дополнительные (см. `VenueLocations`), поэтому эта же форма правит и
/// первый адрес — только без телефона: у первого адреса телефон — это
/// телефон заведения, он в «Основном».
struct HostBranchFormView: View {
    /// Правка: id сохраняется — на него ссылаются акции «только по адресу».
    var existing: Branch? = nil
    var showsPhone = true
    var onSave: (Branch) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var address = ""
    @State private var phone = ""
    @State private var latitude = String(City.bishkek.latitude)
    @State private var longitude = String(City.bishkek.longitude)
    @State private var showingMapPicker = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Адрес") {
                    TextField("Улица и дом", text: $address)
                    if showsPhone {
                        TextField("Телефон этого адреса (необязательно)", text: $phone).keyboardType(.phonePad)
                    }
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
            .navigationTitle(existing == nil ? "Новый адрес" : "Адрес")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !loaded, let existing else { return }
                loaded = true
                address = existing.address; phone = existing.phone
                latitude = String(existing.latitude); longitude = String(existing.longitude)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Добавить" : "Готово") {
                        let c = coordinate ?? CLLocationCoordinate2D(latitude: City.bishkek.latitude,
                                                                     longitude: City.bishkek.longitude)
                        onSave(Branch(id: existing?.id ?? "br_\(UUID().uuidString.prefix(6))",
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
    /// «Во всех адресах» — галочка по умолчанию. Снята — акция действует
    /// только в `selectedLocations`, и гость видит «Действует только по адресу …».
    @State private var allLocations: Bool
    @State private var selectedLocations: Set<String>

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
        _allLocations = State(initialValue: existing?.locationIDs.isEmpty ?? true)
        _selectedLocations = State(initialValue: Set(existing?.locationIDs ?? []))
    }

    private var venue: HostVenueDTO? { host.state.venue(id: venueID) }
    private var locations: [Branch] { venue?.locations ?? [] }
    /// Что уйдёт в `locationIDs`: пусто — во всех адресах. Удалённые с тех пор
    /// адреса отбрасываются — отмечать можно только существующие.
    private var locationIDsToSave: [String] {
        allLocations ? [] : locations.map(\.id).filter(selectedLocations.contains)
    }

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
            // Сняли «во всех» и не выбрали ни одного адреса — акция нигде.
            && (allLocations || !locationIDsToSave.isEmpty)
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

                        // Выбор адресов — только когда их больше одного: при одном
                        // адресе «во всех» и «только здесь» — одно и то же.
                        if locations.count > 1 {
                            SanFieldCard {
                                SanFieldRow(label: "Где действует",
                                            hint: allLocations || !locationIDsToSave.isEmpty
                                                ? nil : "Отметьте хотя бы один адрес") {
                                    locationPicker
                                }
                            }
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
            sourcePostID: imported?.postID,
            locationIDs: locationIDsToSave)))
        dismiss()
    }

    /// Галочки адресов: «Во всех адресах» сверху, под ней — каждый адрес.
    /// Отметить конкретный адрес при включённом «во всех» — значит сузить
    /// акцию до него: галочка «во всех» снимается сама.
    private var locationPicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            checkboxRow(Text("Во всех адресах"), checked: allLocations) {
                allLocations.toggle()
            }
            ForEach(locations) { place in
                checkboxRow(Text(verbatim: place.address),
                            checked: !allLocations && selectedLocations.contains(place.id)) {
                    if allLocations {
                        allLocations = false
                        selectedLocations = [place.id]
                    } else if selectedLocations.contains(place.id) {
                        selectedLocations.remove(place.id)
                    } else {
                        selectedLocations.insert(place.id)
                    }
                }
                .padding(.leading, 26)
                .opacity(allLocations ? 0.55 : 1)
            }
        }
    }

    private func checkboxRow(_ title: Text, checked: Bool,
                             action: @escaping () -> Void) -> some View {
        Button {
            SanHaptics.selection()
            withAnimation(.sanStandard(0.2)) { action() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(checked ? Color.sanAccentText : Color(hex: 0xB8B0A6))
                title
                    .font(.golos(14.5, .semibold)).foregroundStyle(Color.sanInk)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
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
