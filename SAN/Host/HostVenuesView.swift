import SwiftUI
import MapKit

// MARK: - Tab 1 — Мои заведения

struct HostVenuesView: View {
    @EnvironmentObject private var host: HostStore
    @EnvironmentObject private var store: AppStore
    @State private var showAddVenue = false
    @State private var showScanner = false
    @State private var venueToDelete: HostVenueDTO?
    @State private var editingVenue: HostVenueDTO?
    @State private var addDealTarget: AddDealTarget?
    @State private var statsTarget: VenueStatsTarget?
    @State private var viewsTotal = 0

    private var activeDeals: Int {
        host.venueDTOs.reduce(0) { $0 + host.deals(forVenue: $1.id).filter { $0.status == .active }.count }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    topBar
                    SanScreenTitle("Мои заведения")
                    if host.venueDTOs.isEmpty {
                        emptyState
                    } else {
                        statsRow
                        ForEach(host.venueDTOs) { v in venueCard(v) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .sanScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await host.sync() }
            .task(id: host.venueDTOs.count) { await loadViews() }
            .navigationDestination(for: String.self) { id in
                if let dto = host.venueDTO(id: id) { HostVenueDetailView(venueID: dto.id) }
            }
            .navigationDestination(for: HostPromoteTarget.self) {
                HostPromoteCreateView(venueID: $0.venueID)
            }
            .sheet(isPresented: $showAddVenue) { HostVenueFormView(existing: nil) }
            .sheet(isPresented: $showScanner) { HostScannerView().environmentObject(host) }
            .sheet(item: $editingVenue) { HostVenueFormView(existing: $0) }
            .sheet(item: $addDealTarget) { HostDealFormView(venueID: $0.venueID, existing: nil) }
            .sheet(item: $statsTarget) { HostVenueStatsSheet(venueID: $0.venueID) }
            .alert("Удалить заведение?", isPresented: Binding(
                get: { venueToDelete != nil },
                set: { if !$0 { venueToDelete = nil } }
            ), presenting: venueToDelete) { v in
                Button("Удалить", role: .destructive) { host.deleteVenue(id: v.id) }
                Button("Отмена", role: .cancel) {}
            } message: { v in
                Text("«\(v.name)» и все его предложения будут удалены без возможности восстановления.")
            }
        }
    }

    // MARK: Верхняя панель

    private var topBar: some View {
        HStack {
            if !host.venueDTOs.isEmpty {
                SanCircleButton(systemName: "qrcode.viewfinder") { showScanner = true }
            }
            Spacer()
            SanCircleButton(systemName: "plus", filled: true) { showAddVenue = true }
        }
    }

    // MARK: Статистика

    private var statsRow: some View {
        HStack(spacing: 12) {
            SanStatCard(value: "\(host.venueDTOs.count)", label: Self.venuePlural(host.venueDTOs.count))
            SanStatCard(value: "\(activeDeals)", label: "Активных акций")
            SanStatCard(value: "\(viewsTotal)", label: "Просмотров", accent: true)
        }
    }

    // MARK: Пусто

    private var emptyState: some View {
        VStack(spacing: 14) {
            SanIconTile(systemName: "storefront.fill", filled: true, size: 64)
            Text("У вас пока нет заведений").font(.golos(18, .bold)).foregroundStyle(Color.sanInk)
            Text("Добавьте первое заведение, чтобы начать привлекать гостей.")
                .font(.golos(15, .regular)).foregroundStyle(Color.sanInkSoft)
                .multilineTextAlignment(.center)
            Button { showAddVenue = true } label: { Text("Добавить заведение") }
                .buttonStyle(SanPrimaryButton())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .padding(.top, 40)
    }

    // MARK: Карточка заведения

    private func venueCard(_ v: HostVenueDTO) -> some View {
        VStack(spacing: 0) {
            NavigationLink(value: v.id) {
                HStack(alignment: .top, spacing: 12) {
                    VenuePhoto(urlString: v.imageURL)
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(v.name).font(.golos(17, .bold)).foregroundStyle(Color.sanInk)
                            if v.isVerified {
                                Image(systemName: "checkmark.seal.fill").font(.system(size: 12))
                                    .foregroundStyle(.blue)
                            }
                        }
                        Text("\(v.category.rawValue) · \(v.district)")
                            .font(.golos(13, .medium)).foregroundStyle(Color.sanInkSoft)
                        let active = host.deals(forVenue: v.id).filter { $0.status == .active }.count
                        Text("\(active) активных предложений")
                            .font(.golos(13, .medium)).foregroundStyle(Color.sanInkSoft)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 8) {
                        statusPill(v)
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.sanInkSoft)
                    }
                }
                .padding(14)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(role: .destructive) { venueToDelete = v } label: { Label("Удалить", systemImage: "trash") }
            }
            SanHairline(leading: 14)
            HStack(spacing: 10) {
                Button { addDealTarget = AddDealTarget(venueID: v.id) } label: { Text("+ Акция") }
                    .buttonStyle(SanPillButton(accent: true))
                Button { statsTarget = VenueStatsTarget(venueID: v.id) } label: { Text("Аналитика") }
                    .buttonStyle(SanPillButton())
                Button { editingVenue = v } label: { Text("Изменить") }
                    .buttonStyle(SanPillButton())
            }
            .padding(12)
        }
        .sanGroupCard()
    }

    private func statusPill(_ v: HostVenueDTO) -> some View {
        HStack(spacing: 5) {
            Circle().fill(v.moderation.color).frame(width: 6, height: 6)
            Text(L(v.moderation.title))
                .font(.golos(12, .bold)).foregroundStyle(v.moderation.color)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(v.moderation.color.opacity(0.14), in: Capsule())
    }

    private func loadViews() async {
        var total = 0
        for v in host.venueDTOs {
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
            .navigationTitle(host.venueDTO(id: venueID)?.name ?? "Аналитика")
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

    private var dto: HostVenueDTO? { host.venueDTO(id: venueID) }

    var body: some View {
        ScrollView {
            if let v = dto {
                VStack(alignment: .leading, spacing: 20) {
                    header(v)
                    if v.moderation != .approved { moderationBanner(v) }
                    todaySpecialEditor(v)
                    loyaltySection(v)
                    itemsSection(v)
                    dealsSection(v)
                    actions(v)
                }
                .padding(.bottom, 28)
            }
        }
        .sanScreenBackground()
        .navigationTitle(dto?.name ?? "Заведение")
        .navigationBarTitleDisplayMode(.inline)
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

    private func header(_ v: HostVenueDTO) -> some View {
        VStack(spacing: 0) {
            VenuePhoto(urlString: v.imageURL)
                .frame(height: 130).clipShape(RoundedRectangle(cornerRadius: 16))
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(v.name).font(.golos(18, .bold))
                    Text("\(v.category.rawValue) · \(v.district)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { !v.isPaused },
                    set: { _ in host.togglePause(venueID: v.id) }
                )).labelsHidden().tint(.green)
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 16)
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
                            host.deleteItem(venueID: v.id, itemID: item.id)
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
                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.sanAccent)
            TextField("До 100 символов — пусто, чтобы убрать", text: $special, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)
                .onChange(of: special) { _, new in
                    if new.count > 100 { special = String(new.prefix(100)) }
                }
            Button("Сохранить специал") { host.setTodaySpecial(venueID: v.id, text: special) }
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
            let deals = host.deals(forVenue: v.id)
            if deals.isEmpty {
                Text("Пока нет предложений. Добавьте, чтобы привлекать гостей.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(deals) { d in
                        Menu {
                            Button("Изменить") { activeSheet = .editDeal(d) }
                            Button(d.status == .paused ? "Возобновить" : "На паузу") {
                                host.setDealStatus(id: d.id, status: d.status == .paused ? .active : .paused)
                            }
                            Button("Дублировать") { host.duplicateDeal(id: d.id) }
                            Button("Удалить", role: .destructive) { host.deleteDeal(id: d.id) }
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
            NavigationLink(value: HostPromoteTarget(venueID: v.id)) {
                Label("Продвигать это заведение", systemImage: "megaphone.fill")
                    .font(.golos(15, .semibold)).foregroundStyle(Color.sanAccent)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.sanAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    host.deleteVenue(id: v.id)
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
                        host.addItem(venueID: venueID, name: name, emoji: emoji, kind: kind,
                                     imageURL: imageURL.trimmingCharacters(in: .whitespaces))
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
                        brandTile("phone.fill", Color(hex: 0x25D366))
                        TextField("WhatsApp (номер, напр. 996700123456)", text: $whatsapp)
                            .keyboardType(.phonePad)
                    }
                    HStack(spacing: 12) {
                        brandTile("camera.fill", Color(hex: 0xE1306C))
                        TextField("Instagram (ник или ссылка)", text: $instagram)
                            .autocapitalization(.none)
                    }
                    HStack(spacing: 12) {
                        brandTile("paperplane.fill", Color(hex: 0x2AABEE))
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
            .sanFormBackground()
            .navigationTitle(existing == nil ? "Новое заведение" : "Изменить заведение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
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
    private func brandTile(_ systemName: String, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(color)
            .frame(width: 34, height: 34)
            .overlay(Image(systemName: systemName).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white))
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

    private func save() {
        // Разбор координат из полей ввода; сборка DTO — в HostStore.saveVenueForm.
        let lat = Double(latitude.replacingOccurrences(of: ",", with: ".")) ?? City.bishkek.latitude
        let lng = Double(longitude.replacingOccurrences(of: ",", with: ".")) ?? City.bishkek.longitude
        host.saveVenueForm(existing: existing, name: name, category: category, district: district,
                           address: address, phone: phone, emoji: emoji, latitude: lat, longitude: lng,
                           openHour: openHour, closeHour: closeHour, imageURL: imageURL,
                           weekHours: weekHours, pdfMenuURL: pdfMenuURL, whatsapp: whatsapp,
                           instagram: instagram, telegram: telegram, branches: branches,
                           loyaltyEnabled: loyaltyEnabled, loyaltyGoal: loyaltyGoal,
                           loyaltyReward: loyaltyReward, couponsEnabled: couponsEnabled)
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
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Предложение") {
                    TextField("Заголовок", text: $title)
                    Picker("Тип", selection: $type) {
                        ForEach(DealType.allCases) { Text($0.locKey).tag($0) }
                    }
                    TextField("Эмодзи", text: $emoji)
                    TextField("Описание", text: $details, axis: .vertical).lineLimit(2...5)
                }
                Section("Цена / скидка (необязательно)") {
                    TextField("Новая цена, сом", text: $newPrice).keyboardType(.numberPad)
                    TextField("Процент скидки", text: $discount).keyboardType(.numberPad)
                }
                Section("Фото (до 3 — листаются каруселью)") {
                    MultiImagePickerField(urls: $imageURLs)
                }
                Section("Срок") {
                    Toggle("Есть дата окончания", isOn: $hasEnd)
                    if hasEnd { DatePicker("Действует до", selection: $endDate, displayedComponents: .date) }
                }
                Section {
                    Toggle("Сохранить как черновик", isOn: $isDraft)
                }
            }
            .sanFormBackground()
            .navigationTitle(existing == nil ? "Новое предложение" : "Изменить предложение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        host.saveDealForm(existing: existing, venueID: venueID, type: type, title: title,
                          details: details, emoji: emoji, newPrice: Int(newPrice),
                          discountPercent: Int(discount), endDate: hasEnd ? endDate : nil,
                          isDraft: isDraft, imageURLs: imageURLs)
        dismiss()
    }
}
