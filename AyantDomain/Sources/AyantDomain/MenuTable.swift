import Foundation

// Меню из таблицы (CSV, Excel) → блюда.
//
// Таблицы у заведений бывают какие угодно: выгрузка из iiko/R-Keeper,
// прайс в Excel, CSV из Google Таблиц. Поэтому столбцы ищутся по заголовку
// (по-русски, по-английски, по-кыргызски), а если заголовка нет — по
// содержимому: столбец, где почти везде числа, — цена; самый «короткий»
// текстовый — название; самый длинный — описание. Строка, где заполнено
// только название, — раздел («Супы»). Как и у PDF, результат — черновик на
// проверку, а не сразу меню.
//
// Excel читает `MenuXLSXReader` (слой данных) и отдаёт сюда те же строки
// ячеек — правила одни на оба формата. Закреплено `MenuTableTests`.
public enum MenuTable {

    /// Лист таблицы: имя листа и строки ячеек.
    public struct Sheet: Equatable, Sendable {
        public var name: String
        public var rows: [[String]]
        public init(name: String, rows: [[String]]) { self.name = name; self.rows = rows }
    }

    enum Column: CaseIterable { case name, price, details, section, portion }

    /// Слова заголовков. Сравнение — по вхождению, без регистра.
    static let headerWords: [Column: [String]] = [
        .name: ["название", "наименование", "блюдо", "позиция", "товар", "name", "dish", "item", "title",
                "product", "аталышы", "тамак"],
        .price: ["цена", "стоимость", "сумма", "price", "cost", "баасы", "сом"],
        .details: ["описание", "состав", "ингредиенты", "description", "ingredients", "details",
                   "сүрөттөмө", "курамы"],
        .section: ["раздел", "категория", "группа", "category", "section", "group", "menu", "бөлүм",
                   "категориясы"],
        .portion: ["вес", "выход", "граммовка", "объём", "объем", "порция", "weight", "portion", "volume",
                   "size", "салмагы"],
    ]

    // MARK: Разбор

    public static func items(from sheets: [Sheet]) -> [MenuDraftItem] {
        var out: [MenuDraftItem] = []
        let named = sheets.count > 1
        for sheet in sheets {
            out += items(from: sheet.rows, defaultSection: named ? sheet.name : "", idOffset: out.count)
        }
        return MenuImport.cleaned(out)
    }

    static func items(from raw: [[String]], defaultSection: String, idOffset: Int) -> [MenuDraftItem] {
        let rows = raw.map { $0.map { MenuTextParser.normalizeSpaces($0) } }
            .filter { $0.contains(where: { !$0.isEmpty }) }
        guard !rows.isEmpty else { return [] }

        var map: [Column: Int]
        var body: ArraySlice<[String]>
        if let (headerIndex, found) = findHeader(rows) {
            map = found
            body = rows[(headerIndex + 1)...]
        } else {
            map = inferColumns(rows)
            body = rows[...]
        }
        guard map[.name] != nil else { return [] }

        var section = defaultSection
        var out: [MenuDraftItem] = []
        for row in body {
            func cell(_ c: Column) -> String {
                guard let i = map[c], i < row.count else { return "" }
                return row[i]
            }
            let name = cell(.name)
            let price = parsePrice(cell(.price))
            let filled = row.filter { !$0.isEmpty }.count
            if !cell(.section).isEmpty { section = cell(.section) }
            if name.isEmpty {
                // Раздел в отдельной строке, но не в столбце названия.
                if filled == 1, let only = row.first(where: { !$0.isEmpty }), parsePrice(only) == nil {
                    section = only
                }
                continue
            }
            if price == nil, filled == 1 {
                section = MenuTextParser.sentenceCaseIfShouting(name)   // строка-раздел
                continue
            }
            let portion = cell(.portion)
            out.append(MenuDraftItem(
                id: "t\(idOffset + out.count)", section: section,
                name: MenuTextParser.sentenceCaseIfShouting(name),
                price: price,
                details: MenuTextParser.join(cell(.details), portion)))
        }
        return out
    }

    /// Строка-заголовок: в первых строках, есть название и хотя бы ещё одно
    /// известное поле.
    static func findHeader(_ rows: [[String]]) -> (Int, [Column: Int])? {
        for (index, row) in rows.prefix(10).enumerated() {
            var map: [Column: Int] = [:]
            for (i, raw) in row.enumerated() {
                let cell = raw.lowercased()
                guard !cell.isEmpty, cell.count <= 40 else { continue }
                // Порядок важен: «наименование блюда» — название, а не раздел.
                for column in [Column.name, .details, .section, .portion, .price] where map[column] == nil {
                    if headerWords[column]!.contains(where: { cell.contains($0) }) {
                        if !map.values.contains(i) { map[column] = i }
                        break
                    }
                }
            }
            if map[.name] != nil, map.count >= 2 { return (index, map) }
        }
        return nil
    }

    /// Без заголовка: цена — столбец, где ≥ 60 % непустых ячеек — цены;
    /// название — первый текстовый столбец; описание — самый длинный из
    /// остальных текстовых.
    static func inferColumns(_ rows: [[String]]) -> [Column: Int] {
        let width = rows.map(\.count).max() ?? 0
        var priceColumn: Int?
        var textColumns: [(index: Int, meanLength: Double)] = []
        for c in 0..<width {
            let cells = rows.compactMap { c < $0.count ? $0[c] : nil }.filter { !$0.isEmpty }
            guard !cells.isEmpty else { continue }
            let prices = cells.filter { parsePrice($0) != nil }.count
            if Double(prices) >= Double(cells.count) * 0.6 {
                if priceColumn == nil { priceColumn = c }
                continue
            }
            let letters = cells.filter { $0.contains(where: \.isLetter) }.count
            if Double(letters) >= Double(cells.count) * 0.6 {
                let mean = Double(cells.reduce(0) { $0 + $1.count }) / Double(cells.count)
                textColumns.append((c, mean))
            }
        }
        var map: [Column: Int] = [:]
        if let priceColumn { map[.price] = priceColumn }
        if let first = textColumns.first { map[.name] = first.index }
        if let longest = textColumns.dropFirst().max(by: { $0.meanLength < $1.meanLength }),
           longest.meanLength > (textColumns.first?.meanLength ?? 0) {
            map[.details] = longest.index
        }
        return map
    }

    /// Цена в ячейке: «350», «350 сом», «1 200», «450.00», «720/1220».
    static func parsePrice(_ cell: String) -> Int? {
        guard !cell.isEmpty, let match = MenuPrice.parse(cell), match.body.isEmpty else { return nil }
        return match.value
    }

    // MARK: CSV

    /// CSV по RFC 4180 с угадыванием разделителя (`,` `;` табуляция — Excel в
    /// русской локали сохраняет с `;`) и кодировки (UTF-8, иначе Windows-1251).
    public static func csvRows(_ data: Data) -> [[String]] {
        let text = decode(data)
        let delimiter = guessDelimiter(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text)
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { inQuotes = false }
                } else {
                    field.append(ch)
                }
            } else if ch == "\"" && field.isEmpty {
                inQuotes = true
            } else if ch == delimiter {
                row.append(field); field = ""
            } else if ch == "\n" || ch == "\r" || ch == "\r\n" {
                row.append(field); field = ""
                rows.append(row); row = []
                if ch == "\r", i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
            } else {
                field.append(ch)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .windowsCP1251) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    /// Разделитель — тот, что встречается в первых строках одинаковое и
    /// ненулевое число раз.
    static func guessDelimiter(_ text: String) -> Character {
        let lines = text.split(whereSeparator: \.isNewline).prefix(10).map(String.init)
        var best: Character = ","
        var bestScore = -1
        for candidate in [";", "\t", ","] as [Character] {
            let counts = lines.map { $0.filter { $0 == candidate }.count }
            guard let first = counts.first, first > 0 else { continue }
            let consistent = counts.filter { $0 == first }.count
            let score = consistent * 10 + first
            if score > bestScore { bestScore = score; best = candidate }
        }
        return best
    }
}
