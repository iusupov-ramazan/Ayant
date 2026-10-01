import SwiftUI
import UniformTypeIdentifiers
import AyantDomain
import AyantFeatures

// MARK: - Меню из файла

/// «Меню из файла»: PDF, Excel или CSV → блюда находятся на телефоне
/// (`OnDeviceMenuParsingService`) → хозяин проверяет и правит → блюда уходят
/// в «Меню» заведения (`HostIntent.importMenu`).
///
/// Ничего не сохраняется, пока хозяин не нажал «Сохранить»: разбор ошибается
/// в ценах и названиях (особенно на сканах), и его результат — черновик.
struct HostMenuImportView: View {
    let venue: HostVenueDTO
    @EnvironmentObject private var host: HostStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = AyantStores.menuImport()

    @State private var showImporter = false
    @State private var fileError: String?
    @State private var downloading = false
    @State private var editing: MenuDraftItem?

    private var state: MenuImportState { store.state }

    /// Разделы на выбор при правке черновика: уже есть в меню + найденные в
    /// файле, без повторов (без учёта регистра).
    private var draftSections: [String] {
        let parsed = MenuImport.grouped(state.drafts) { $0.section }.map(\.section)
        var seen = Set<String>()
        return (MenuImport.sections(venue.items) + parsed).filter {
            !$0.isEmpty && seen.insert($0.lowercased()).inserted
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SanFormHeader(title: "Меню из файла") {
                store.send(.reset)
                dismiss()
            }
            switch state.phase {
            case .idle:            intro
            case .reading(let p):  reading(p)
            case .failed(let e):   failed(e)
            case .review:          review
            }
        }
        .sanScreenBackground()
        .interactiveDismissDisabled(store.isReading || state.phase == .review)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.fileTypes) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let kind = MenuFileKind(fileName: url.lastPathComponent) else {
                fileError = LS("Поддерживаются PDF, Excel (.xlsx) и CSV.")
                return
            }
            guard let data = try? Data(contentsOf: url) else { fileError = LS("Не удалось открыть файл."); return }
            parse(data, kind: kind)
        }
        .sheet(item: $editing) { draft in
            DraftDishEditor(draft: draft, sections: draftSections) { store.send(.update($0)) }
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Шаг 1 — выбор файла

    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.sanAccentText)
                    Text("Загрузите меню — найдём блюда, цены и описания")
                        .font(.golos(18, .bold)).foregroundStyle(Color.sanInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Перед сохранением вы проверите список: поправите цены и названия, уберёте лишнее. Фото к каждому блюду можно добавить потом, в «Меню».")
                        .font(.golos(13.5)).foregroundStyle(Color.sanInkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sanCard(padding: 0)

                if !venue.pdfMenuURL.isEmpty {
                    Button { parseUploadedPDF() } label: {
                        Label(downloading ? LS("Скачиваем PDF…") : LS("Разобрать загруженное меню"),
                              systemImage: "doc.fill")
                    }
                    .buttonStyle(SanPrimaryButton())
                    .disabled(downloading)
                }
                Button { showImporter = true } label: {
                    Label(venue.pdfMenuURL.isEmpty ? "Выбрать файл" : "Выбрать другой файл",
                          systemImage: "doc.badge.plus")
                }
                .buttonStyle(venue.pdfMenuURL.isEmpty ? AnyButtonStyle(SanPrimaryButton()) : AnyButtonStyle(SanPillButton()))
                .disabled(downloading)

                if let fileError {
                    Text(fileError).font(.golos(12.5, .semibold)).foregroundStyle(Color(hex: 0xC24A12))
                }
                Text("PDF, Excel (.xlsx) или CSV. Всё читается на телефоне — бесплатно и без интернета. Лучше всего — меню с текстом или таблица; сканы тоже подойдут, если текст на них чёткий.")
                    .font(.golos(12)).foregroundStyle(Color.sanInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, SanMetrics.screenPadding)
            .padding(.top, 8).padding(.bottom, 24)
        }
    }

    // MARK: Шаг 2 — чтение

    private func reading(_ progress: Double) -> some View {
        VStack(spacing: 14) {
            Spacer()
            if progress > 0 {
                ProgressView(value: progress)
                    .tint(Color.sanAccent)
                    .frame(maxWidth: 220)
            } else {
                ProgressView().controlSize(.large).tint(Color.sanAccent)
            }
            Text("Читаем меню…").font(.golos(18, .bold)).foregroundStyle(Color.sanInk)
            Text("Меню с текстом — секунды, сканы — около секунды на страницу.")
                .font(.golos(13.5)).foregroundStyle(Color.sanInkSoft)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: Ошибка

    private func failed(_ error: AppError) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34)).foregroundStyle(Color(hex: 0xE8556B))
            Text(Self.message(for: error))
                .font(.golos(15.5, .semibold)).foregroundStyle(Color.sanInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Попробовать снова") { store.send(.reset) }
                .buttonStyle(SanPrimaryButton())
                .padding(.top, 6)
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    static func message(for error: AppError) -> String {
        switch error.code {
        case "file_too_large": return LS("Файл больше 60 МБ. Сожмите его или загрузите меню по частям.")
        case "not_pdf":        return LS("Файл не открывается как PDF. Попробуйте сохранить его заново.")
        case "pdf_locked":     return LS("PDF защищён паролем. Снимите защиту и попробуйте снова.")
        case "not_xlsx":       return LS("Файл не открывается как Excel. Сохраните его как .xlsx или CSV.")
        case "no_items":       return LS("В файле не нашлось блюд. Проверьте, что это меню.")
        case "network":        return LS("Нет соединения с интернетом.")
        default:               return LS("Не удалось прочитать меню. Попробуйте ещё раз или выберите другой файл.")
        }
    }

    // MARK: Шаг 3 — проверка

    private var review: some View {
        let groups = MenuImport.grouped(state.drafts) { $0.section }
        let updates = MenuImport.updatesCount(existing: venue.items, drafts: state.drafts)
        return VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Нашли \(state.drafts.count) позиций")
                                .font(.golos(18, .bold)).foregroundStyle(Color.sanInk)
                            Text("Проверьте цены и названия — нажмите на блюдо, чтобы поправить.")
                                .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Button(state.includedCount == state.drafts.count ? "Снять все" : "Выбрать все") {
                            store.send(.setAll(include: state.includedCount != state.drafts.count))
                        }
                        .font(.golos(13, .semibold)).foregroundStyle(Color.sanAccentText)
                    }
                    ForEach(groups, id: \.section) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            if !group.section.isEmpty {
                                Text(group.section)
                                    .textCase(.uppercase)
                                    .font(.golos(11.5, .heavy)).tracking(0.8)
                                    .foregroundStyle(Color.sanInkSoft)
                                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
                            }
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { i, draft in
                                if i > 0 { SanHairline(leading: 52) }
                                draftRow(draft)
                            }
                        }
                        .sanGroupCard(radius: SanRadius.card)
                    }
                }
                .padding(.horizontal, SanMetrics.screenPadding)
                .padding(.top, 8).padding(.bottom, 20)
            }
            SanStickyFooter {
                Button(state.includedCount == 0 ? LS("Ничего не выбрано") : LF("Сохранить %lld в меню", state.includedCount)) {
                    SanHaptics.save()
                    host.send(.importMenu(venueID: venue.id, drafts: state.drafts))
                    dismiss()
                }
                .buttonStyle(SanPrimaryButton())
                .disabled(state.includedCount == 0)
                .opacity(state.includedCount == 0 ? 0.6 : 1)
                if updates > 0 {
                    Text("Уже есть в меню: \(updates) — у них обновятся цена и описание, фото и отзывы останутся.")
                        .font(.golos(11.5)).foregroundStyle(Color(hex: 0x9A9188))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func draftRow(_ draft: MenuDraftItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { store.send(.toggle(id: draft.id)) } label: {
                Image(systemName: draft.include ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(draft.include ? Color.sanAccent : Color(hex: 0xC0B8AE))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(draft.include ? "Не добавлять" : "Добавить")
            Button { editing = draft } label: {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.name)
                            .font(.golos(15, .semibold))
                            .foregroundStyle(draft.include ? Color.sanInk : Color.sanInkSoft)
                        if !draft.details.isEmpty {
                            Text(draft.details)
                                .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 6)
                    Text(draft.price.map { LF("%lld сом", $0) } ?? LS("без цены"))
                        .font(.golos(14, draft.price == nil ? .regular : .bold))
                        .foregroundStyle(draft.price == nil ? Color(hex: 0xC24A12) : Color.sanInk)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .opacity(draft.include ? 1 : 0.55)
    }

    // MARK: Файл

    /// PDF, Excel и CSV. `.commaSeparatedText` покрывает .csv; .xlsx — по
    /// расширению (у системы нет готового типа для Excel).
    static let fileTypes: [UTType] = [.pdf, .commaSeparatedText, .tabSeparatedText, .spreadsheet]
        + [UTType(filenameExtension: "xlsx")].compactMap { $0 }

    private func parse(_ data: Data, kind: MenuFileKind) {
        fileError = nil
        guard data.count <= MenuImport.maxFileBytes else {
            fileError = LS("Файл больше 60 МБ. Сожмите его или загрузите меню по частям.")
            return
        }
        store.send(.parse(file: data, kind: kind))
    }

    /// Уже загруженный PDF заведения скачиваем и разбираем здесь же.
    private func parseUploadedPDF() {
        guard let url = URL(string: venue.pdfMenuURL) else { fileError = LS("Не удалось открыть файл."); return }
        downloading = true
        fileError = nil
        Task {
            defer { downloading = false }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                parse(data, kind: .pdf)
            } catch {
                fileError = LS("Не удалось скачать PDF. Проверьте интернет или выберите файл.")
            }
        }
    }
}

/// Стиль кнопки, выбираемый по условию (SwiftUI не даёт тернарник из двух стилей).
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

// MARK: - Правка блюда в черновике

private struct DraftDishEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MenuDraftItem
    @State private var priceText: String
    let sections: [String]
    let onSave: (MenuDraftItem) -> Void

    init(draft: MenuDraftItem, sections: [String], onSave: @escaping (MenuDraftItem) -> Void) {
        _draft = State(initialValue: draft)
        _priceText = State(initialValue: draft.price.map(String.init) ?? "")
        self.sections = sections
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            SanFormHeader(title: "Блюдо") { dismiss() }
            ScrollView {
                DishFields(name: $draft.name, section: $draft.section,
                           priceText: $priceText, details: $draft.details, sections: sections)
                    .padding(.horizontal, SanMetrics.screenPadding)
                    .padding(.top, 8).padding(.bottom, 20)
            }
            SanStickyFooter {
                Button("Готово") {
                    draft.price = MenuImport.validPrice(Int(priceText.filter(\.isNumber)))
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(SanPrimaryButton())
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .sanScreenBackground()
    }
}

/// Поля блюда — общие для черновика разбора и правки блюда в «Меню».
struct DishFields: View {
    @Binding var name: String
    @Binding var section: String
    @Binding var priceText: String
    @Binding var details: String
    /// Разделы, которые уже есть в меню, — на выбор в `MenuSectionPicker`.
    var sections: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            SanFieldRow(label: "Название") {
                SanFieldInput(placeholder: "Например: Лагман", text: $name)
            }
            SanHairline(leading: 16)
            SanFieldRow(label: "Цена, сом", hint: "Пусто — цена не указана") {
                SanFieldInput(placeholder: "Например, 350", text: $priceText, keyboard: .numberPad)
            }
            SanHairline(leading: 16)
            SanFieldRow(label: "Раздел меню",
                        hint: sections.isEmpty ? "Супы, Горячее, Напитки — гости увидят меню по разделам" : nil) {
                MenuSectionPicker(section: $section, sections: sections)
            }
            SanHairline(leading: 16)
            SanFieldRow(label: "Описание") {
                SanFieldInput(placeholder: "Состав или пара слов о блюде", text: $details, axis: .vertical)
            }
        }
        .sanGroupCard(radius: SanRadius.card)
    }
}

// MARK: - Выбор раздела меню

/// Раздел — выбором, а не вводом: «Без раздела», все разделы меню и
/// «+ Новый раздел». Свободное поле давало «Супы», «супы» и «Супы » тремя
/// разделами в меню гостя. Новый раздел сразу выбран и появляется в списке у
/// следующих блюд — разделы живут в самих блюдах (`VenueItem.section`),
/// отдельного списка нет: раздел без единого блюда гостю не нужен.
struct MenuSectionPicker: View {
    @Binding var section: String
    let sections: [String]
    @State private var creating = false
    @State private var newName = ""
    @FocusState private var focused: Bool

    /// Разделы меню плюс текущий, если его только что создали.
    private var options: [String] {
        let current = section.trimmingCharacters(in: .whitespaces)
        guard !current.isEmpty,
              !sections.contains(where: { $0.lowercased() == current.lowercased() }) else { return sections }
        return sections + [current]
    }

    private func isSelected(_ name: String) -> Bool {
        section.trimmingCharacters(in: .whitespaces).lowercased() == name.lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 6) {
                chip(LS("Без раздела"), selected: section.trimmingCharacters(in: .whitespaces).isEmpty) {
                    section = ""
                }
                ForEach(options, id: \.self) { name in
                    chip(name, selected: isSelected(name)) { section = name }
                }
                if !creating {
                    Button {
                        newName = ""
                        creating = true
                        focused = true
                    } label: {
                        Label("Новый раздел", systemImage: "plus")
                            .font(.golos(13, .semibold))
                            .foregroundStyle(Color.sanAccentText)
                            .padding(.horizontal, 12).frame(height: 32)
                            .overlay(Capsule().strokeBorder(Color.sanAccent.opacity(0.5),
                                                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            if creating {
                HStack(spacing: 8) {
                    TextField("Например: Супы", text: $newName)
                        .font(.golos(15))
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit(commitNew)
                        .padding(.horizontal, 12).frame(height: 40)
                        .background(Color.sanSurfaceMuted,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Button("Готово", action: commitNew)
                        .font(.golos(14, .semibold))
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button {
                        creating = false
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.sanInkSoft)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Отмена")
                }
            }
        }
        .padding(.top, 2)
    }

    /// Новый раздел с тем же именем, что уже есть, становится выбором
    /// существующего (`MenuImport.canonicalSection`), а не дублем.
    private func commitNew() {
        let name = MenuImport.canonicalSection(newName, existing: sections)
        guard !name.isEmpty else { return }
        SanHaptics.selection()
        section = name
        creating = false
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            SanHaptics.selection()
            action()
        } label: {
            HStack(spacing: 4) {
                if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)) }
                Text(verbatim: title).lineLimit(1)
            }
            .font(.golos(13, .semibold))
            .foregroundStyle(selected ? Color.white : Color.sanInk)
            .padding(.horizontal, 12).frame(height: 32)
            .background(selected ? AnyShapeStyle(LinearGradient.sanAccentGradient)
                                 : AnyShapeStyle(Color.sanSurfaceMuted),
                        in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Раскладка «строками с переносом» — чипы разделов видны все сразу, без
/// горизонтальной прокрутки, которую не все замечают.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.indices.append(index)
            row.height = max(row.height, size.height)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - Правка блюда в «Меню» (с фото)

/// Правка заведённого блюда: поля и фото. Фото — главное, ради чего сюда
/// заходят после разбора PDF: у блюд из меню картинок нет.
struct HostItemEditView: View {
    let venueID: String
    @EnvironmentObject private var host: HostStore
    @Environment(\.dismiss) private var dismiss
    @State private var item: VenueItem
    @State private var priceText: String

    init(venueID: String, item: VenueItem) {
        self.venueID = venueID
        _item = State(initialValue: item)
        _priceText = State(initialValue: item.price.map(String.init) ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            SanFormHeader(title: "Блюдо") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Фото")
                            .textCase(.uppercase)
                            .font(.golos(11, .heavy)).tracking(0.9)
                            .foregroundStyle(Color(hex: 0x9A9188))
                        ImagePickerField(imageURL: $item.imageURL)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sanGroupCard(radius: SanRadius.card)
                    DishFields(name: $item.name, section: $item.section,
                               priceText: $priceText, details: $item.details,
                               sections: MenuImport.sections(host.state.venue(id: venueID)?.items ?? []))
                }
                .padding(.horizontal, SanMetrics.screenPadding)
                .padding(.top, 8).padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            SanStickyFooter {
                Button("Сохранить") {
                    SanHaptics.save()
                    item.price = MenuImport.validPrice(Int(priceText.filter(\.isNumber)))
                    host.send(.updateItem(venueID: venueID, item: item))
                    dismiss()
                }
                .buttonStyle(SanPrimaryButton())
                .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .sanScreenBackground()
    }
}
