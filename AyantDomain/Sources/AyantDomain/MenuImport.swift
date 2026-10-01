import Foundation

// Меню из файла → блюда заведения.
//
// Разбор — на устройстве и бесплатно: PDF читают `MenuPDFTextExtractor`
// (текстовый слой или распознавание) и `MenuTextParser`, таблицы —
// `MenuTable` (CSV/Excel). Здесь — то, что происходит после: чистка,
// черновик, который хозяин правит, и слияние с уже заведёнными блюдами.
// Результат разбора не публикуется как есть: цены и названия проверяет
// человек.

/// Формат файла меню.
public enum MenuFileKind: String, Sendable, Equatable {
    case pdf, csv, xlsx

    /// По расширению имени файла; `nil` — формат не поддерживается.
    public init?(fileName: String) {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "pdf": self = .pdf
        case "csv", "tsv", "txt": self = .csv
        case "xlsx": self = .xlsx
        default: return nil
        }
    }
}

/// Блюдо в черновике разбора — ещё не сохранено в заведение.
public struct MenuDraftItem: Identifiable, Hashable, Sendable {
    public let id: String
    public var section: String
    public var name: String
    /// Сом; `nil` — цены в меню нет.
    public var price: Int?
    public var details: String
    /// Снятая галочка — хозяин не хочет это блюдо в меню.
    public var include: Bool

    public init(id: String, section: String, name: String, price: Int?, details: String,
                include: Bool = true) {
        self.id = id; self.section = section; self.name = name
        self.price = price; self.details = details; self.include = include
    }
}

public enum MenuImport {
    /// Разбор идёт на телефоне — предел задаёт память, а не сеть: меню с
    /// фото на 100 страниц весит ~30 МБ.
    public static let maxFileBytes = 60 * 1024 * 1024
    public static let maxItems = 300
    public static let nameLimit = 80
    public static let sectionLimit = 40
    public static let detailsLimit = 300
    public static let priceLimit = 1_000_000

    /// Чистка — повторяет серверную: обрезка и схлопывание пробелов, пустые
    /// названия и дубли (раздел + название без учёта регистра) — вон, цена вне
    /// (0, 1 000 000) — «не указана». Нужна и на клиенте: мок-сервис и правки
    /// хозяина идут мимо сервера.
    public static func cleaned(_ items: [MenuDraftItem]) -> [MenuDraftItem] {
        var seen: Set<String> = []
        var out: [MenuDraftItem] = []
        for item in items {
            let name = clip(item.name, nameLimit)
            guard !name.isEmpty else { continue }
            let section = clip(item.section, sectionLimit)
            let key = section.lowercased() + "|" + name.lowercased()
            guard seen.insert(key).inserted else { continue }
            out.append(MenuDraftItem(id: item.id, section: section, name: name,
                                     price: validPrice(item.price),
                                     details: clip(item.details, detailsLimit),
                                     include: item.include))
            if out.count == maxItems { break }
        }
        return out
    }

    public static func validPrice(_ price: Int?) -> Int? {
        guard let price, price > 0, price < priceLimit else { return nil }
        return price
    }

    /// Ключ сравнения названий: «Лагман  » и «лагман» — одно блюдо.
    public static func normalizedName(_ name: String) -> String {
        clip(name, nameLimit).lowercased()
    }

    /// Слияние отмеченных блюд черновика с уже заведёнными.
    ///
    /// Совпавшее по названию блюдо ОБНОВЛЯЕТСЯ (цена, описание, раздел), но
    /// сохраняет свой id, фото и эмодзи: по id к нему привязаны отзывы гостей,
    /// а фото хозяин мог загрузить руками. Новые — дописываются в конец в
    /// порядке меню. Незатронутые блюда остаются как были — разбор нового PDF
    /// не удаляет то, что хозяин завёл вручную.
    public static func merge(existing: [VenueItem], drafts: [MenuDraftItem],
                             newID: () -> String) -> [VenueItem] {
        var result = existing
        var indexByName: [String: Int] = [:]
        for (i, item) in result.enumerated() where indexByName[normalizedName(item.name)] == nil {
            indexByName[normalizedName(item.name)] = i
        }
        for draft in cleaned(drafts) where draft.include {
            let key = normalizedName(draft.name)
            if let i = indexByName[key] {
                result[i].price = draft.price
                if !draft.details.isEmpty { result[i].details = draft.details }
                if !draft.section.isEmpty { result[i].section = draft.section }
            } else {
                result.append(VenueItem(id: newID(), name: draft.name, emoji: "🍽", kind: "food",
                                        price: draft.price, details: draft.details,
                                        section: draft.section))
                indexByName[key] = result.count - 1
            }
        }
        return result
    }

    /// Сколько из отмеченных блюд уже есть в меню (для подписи кнопки).
    public static func updatesCount(existing: [VenueItem], drafts: [MenuDraftItem]) -> Int {
        let names = Set(existing.map { normalizedName($0.name) })
        return cleaned(drafts).filter { $0.include && names.contains(normalizedName($0.name)) }.count
    }

    /// Блюда по разделам в порядке появления — для экрана проверки и меню гостя.
    public static func grouped<T>(_ items: [T], section: (T) -> String) -> [(section: String, items: [T])] {
        var order: [String] = []
        var groups: [String: [T]] = [:]
        for item in items {
            let key = section(item)
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    public static func clip(_ s: String, _ limit: Int) -> String {
        let collapsed = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(collapsed.prefix(limit))
    }

    /// Разделы меню в порядке появления, без пустых и без повторов.
    public static func sections(_ items: [VenueItem]) -> [String] {
        grouped(items) { $0.section }.map(\.section).filter { !$0.isEmpty }
    }

    /// Раздел, введённый руками, — к написанию уже существующего: «супы» и
    /// « Супы » попадают в «Супы». Меню группируется по точной строке, и без
    /// этого одна опечатка регистра заводила второй раздел «Супы» в меню
    /// гостя. Нового раздела нет — возвращается очищенный ввод.
    public static func canonicalSection(_ typed: String, existing: [String]) -> String {
        let clean = clip(typed, sectionLimit)
        guard !clean.isEmpty else { return "" }
        let key = clean.lowercased()
        return existing.first { clip($0, sectionLimit).lowercased() == key } ?? clean
    }
}

/// Этап импорта меню — одно значение вместо разрозненных флагов.
public enum MenuImportPhase: Equatable, Sendable {
    case idle
    /// Файл читается; доля 0…1 — сканы распознаются постранично.
    case reading(progress: Double)
    case review
    case failed(AppError)
}

public struct MenuImportState: Equatable, Sendable {
    public var phase: MenuImportPhase = .idle
    public var drafts: [MenuDraftItem] = []

    public init(phase: MenuImportPhase = .idle, drafts: [MenuDraftItem] = []) {
        self.phase = phase; self.drafts = drafts
    }

    public var includedCount: Int { drafts.filter(\.include).count }
}

public enum MenuImportIntent: Sendable {
    case parse(file: Data, kind: MenuFileKind)
    /// Промежуточный прогресс чтения (присылает сам стор).
    case progress(Double)
    case update(MenuDraftItem)
    case toggle(id: String)
    case setAll(include: Bool)
    case reset
}
