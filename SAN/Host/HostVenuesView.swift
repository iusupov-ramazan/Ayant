import SwiftUI

// MARK: - Tab 1 — Мои заведения

struct HostVenuesView: View {
    @EnvironmentObject private var host: HostStore
    @State private var showAddVenue = false

    var body: some View {
        NavigationStack {
            Group {
                if host.venueDTOs.isEmpty {
                    ContentUnavailableView {
                        Label("У вас пока нет заведений", systemImage: "storefront")
                    } description: {
                        Text("Добавьте первое заведение, чтобы начать привлекать гостей.")
                    } actions: {
                        Button("+ Добавить заведение") { showAddVenue = true }
                            .buttonStyle(.borderedProminent).tint(.sanAccent)
                    }
                } else {
                    List {
                        ForEach(host.venueDTOs) { v in
                            NavigationLink(value: v.id) { venueRow(v) }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Мои заведения")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddVenue = true } label: { Image(systemName: "plus") }
                }
            }
            .navigationDestination(for: String.self) { id in
                if let dto = host.venueDTO(id: id) { HostVenueDetailView(venueID: dto.id) }
            }
            .navigationDestination(for: HostPromoteTarget.self) {
                HostPromoteCreateView(venueID: $0.venueID)
            }
            .sheet(isPresented: $showAddVenue) {
                HostVenueFormView(existing: nil)
            }
        }
    }

    private func venueRow(_ v: HostVenueDTO) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [.sanAccent, .orange],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                Text(v.emoji).font(.title2)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(v.name).font(.subheadline.weight(.semibold))
                    if v.isVerified { Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.blue) }
                }
                Text("\(v.category.rawValue) · \(v.district)").font(.caption).foregroundStyle(.secondary)
                let active = host.deals(forVenue: v.id).filter { $0.status == .active }.count
                Text("\(active) активных предложений").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(v.moderation.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(v.moderation.color)
                if v.moderation == .approved {
                    Text(v.isPaused ? "На паузе" : "Активно")
                        .font(.caption2)
                        .foregroundStyle(v.isPaused ? .orange : .secondary)
                }
            }
        }
    }
}

// MARK: - Детальный экран заведения (хост)

struct HostVenueDetailView: View {
    let venueID: String
    @EnvironmentObject private var host: HostStore
    @State private var special = ""
    @State private var activeSheet: HostVenueSheet?

    private var dto: HostVenueDTO? { host.venueDTO(id: venueID) }

    var body: some View {
        ScrollView {
            if let v = dto {
                VStack(alignment: .leading, spacing: 20) {
                    header(v)
                    if v.moderation != .approved { moderationBanner(v) }
                    todaySpecialEditor(v)
                    itemsSection(v)
                    dealsSection(v)
                    actions(v)
                }
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(dto?.name ?? "Заведение")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { special = dto?.todaySpecial ?? "" }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .editVenue: if let v = dto { HostVenueFormView(existing: v) }
            case .addDeal: HostDealFormView(venueID: venueID, existing: nil)
            case .editDeal(let d): HostDealFormView(venueID: venueID, existing: d)
            case .addItem: HostItemFormView(venueID: venueID)
            }
        }
    }

    private func header(_ v: HostVenueDTO) -> some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [.sanAccent, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(v.emoji).font(.system(size: 60))
            }
            .frame(height: 130).clipShape(RoundedRectangle(cornerRadius: 16))
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(v.name).font(.headline)
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
                Text(v.moderation.title).font(.subheadline.weight(.semibold))
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
                Text("Объекты для отзывов").font(.headline)
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
                        Text(item.emoji)
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
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
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
                Text("Предложения").font(.headline)
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
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(d.emoji).font(.system(size: 30)).frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(d.status.title)
                .font(.system(size: 8).weight(.bold)).foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(d.status.color, in: Capsule()).padding(5)
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func actions(_ v: HostVenueDTO) -> some View {
        VStack(spacing: 10) {
            Button { activeSheet = .editVenue } label: {
                Label("Изменить данные заведения", systemImage: "pencil")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            NavigationLink(value: HostPromoteTarget(venueID: v.id)) {
                Label("Продвигать это заведение", systemImage: "megaphone.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.sanAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.sanAccent)
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

    var id: String {
        switch self {
        case .editVenue: return "editVenue"
        case .addDeal: return "addDeal"
        case .editDeal(let d): return "editDeal_\(d.id)"
        case .addItem: return "addItem"
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Объект для отзывов") {
                    TextField("Название (напр. Лагман)", text: $name)
                    TextField("Эмодзи", text: $emoji)
                    Picker("Тип", selection: $kind) {
                        Text("Блюдо").tag("food")
                        Text("Услуга").tag("service")
                        Text("Объект").tag("other")
                    }
                }
            }
            .navigationTitle("Новый объект")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Добавить") {
                        host.addItem(venueID: venueID, name: name, emoji: emoji, kind: kind)
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
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Основное") {
                    TextField("Название", text: $name)
                    Picker("Категория", selection: $category) {
                        ForEach(VenueCategory.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Эмодзи", text: $emoji)
                    TextField("Район", text: $district)
                    TextField("Адрес", text: $address)
                    TextField("Телефон", text: $phone).keyboardType(.phonePad)
                }
                Section("Координаты (Бишкек по умолчанию)") {
                    TextField("Широта", text: $latitude).keyboardType(.decimalPad)
                    TextField("Долгота", text: $longitude).keyboardType(.decimalPad)
                }
                Section("Часы работы") {
                    Stepper("Открытие: \(openHour):00", value: $openHour, in: 0...24)
                    Stepper("Закрытие: \(closeHour):00", value: $closeHour, in: 0...24)
                }
            }
            .navigationTitle(existing == nil ? "Новое заведение" : "Изменить заведение")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let lat = Double(latitude.replacingOccurrences(of: ",", with: ".")) ?? City.bishkek.latitude
        let lng = Double(longitude.replacingOccurrences(of: ",", with: ".")) ?? City.bishkek.longitude
        if var dto = existing {
            dto.name = name; dto.categoryRaw = category.rawValue; dto.district = district
            dto.address = address; dto.phone = phone; dto.emoji = emoji
            dto.latitude = lat; dto.longitude = lng; dto.openHour = openHour; dto.closeHour = closeHour
            host.updateVenue(dto)
        } else {
            host.addVenue(name: name, category: category, district: district, address: address,
                          phone: phone, emoji: emoji, latitude: lat, longitude: lng,
                          openHour: openHour, closeHour: closeHour)
        }
        dismiss()
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
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Предложение") {
                    TextField("Заголовок", text: $title)
                    Picker("Тип", selection: $type) {
                        ForEach(DealType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Эмодзи", text: $emoji)
                    TextField("Описание", text: $details, axis: .vertical).lineLimit(2...5)
                }
                Section("Цена / скидка (необязательно)") {
                    TextField("Новая цена, сом", text: $newPrice).keyboardType(.numberPad)
                    TextField("Процент скидки", text: $discount).keyboardType(.numberPad)
                }
                Section("Срок") {
                    Toggle("Есть дата окончания", isOn: $hasEnd)
                    if hasEnd { DatePicker("Действует до", selection: $endDate, displayedComponents: .date) }
                }
                Section {
                    Toggle("Сохранить как черновик", isOn: $isDraft)
                }
            }
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
        let dto = HostDealDTO(
            id: existing?.id ?? host.newDealID(),
            venueID: venueID, typeRaw: type.rawValue, title: title, details: details, emoji: emoji,
            newPrice: Int(newPrice), discountPercent: Int(discount),
            startDate: existing?.startDate ?? .now,
            endDate: hasEnd ? endDate : nil,
            statusRaw: (isDraft ? DealStatus.draft : .active).rawValue)
        host.saveDeal(dto)
        dismiss()
    }
}
