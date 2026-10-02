import Foundation

// Меню из PDF → блюда, целиком на устройстве и бесплатно.
//
// Текст страниц достаёт `MenuPDFTextExtractor` (слой данных): из текстового
// слоя PDF (PDFKit), а если его нет или он битый — распознаванием (Vision).
// Сюда приходят фрагменты текста с рамками; этот файл — чистые правила, как
// собрать из них блюда. Правила не обязаны быть безошибочными: хозяин
// проверяет и правит список перед сохранением (`HostMenuImportView`), а экран
// проверки подсвечивает блюда без цены.
//
// Разобраны две вёрстки, которые покрывают почти все меню:
// • «таблица»: `Название …… 330 г   450` в одну строку, под ней иногда
//   продолжение названия или состав мелким шрифтом (меню ZERNO);
// • «карточки»: НАЗВАНИЕ крупно или заглавными, абзац описания, отдельной
//   строкой `35 cm 820 som` / `0.75L 450KGS` (барные карты, меню с фото).
//
// Правила закреплены `MenuTextParserTests` на фрагментах настоящих меню.
// Меню, которое парсер читает неверно, — это новый тест там, а не правка
// наугад: у каждого правила есть меню, которое оно чинит, и меню, которое
// оно может сломать.

/// Кусок текста страницы с рамкой. Координаты — пункты страницы, начало в
/// ЛЕВОМ ВЕРХНЕМ углу (y растёт вниз), как читает человек.
public struct MenuTextFragment: Hashable, Sendable {
    public var page: Int
    public var text: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var pageWidth: Double

    public init(page: Int, text: String, x: Double, y: Double, width: Double, height: Double,
                pageWidth: Double) {
        self.page = page; self.text = text; self.x = x; self.y = y
        self.width = width; self.height = height; self.pageWidth = pageWidth
    }

    var maxX: Double { x + width }
    var maxY: Double { y + height }
    var midY: Double { y + height / 2 }
}

public enum MenuTextParser {

    public static func parse(_ fragments: [MenuTextFragment]) -> [MenuDraftItem] {
        let cleaned = fragments.compactMap { f -> MenuTextFragment? in
            var f = f
            f.text = normalizeSpaces(f.text)
            return f.text.isEmpty || f.height <= 0 ? nil : f
        }
        var rows: [Row] = []
        for page in Set(cleaned.map(\.page)).sorted() {
            for column in columns(cleaned.filter { $0.page == page }) {
                rows += makeRows(column)
            }
        }
        let heights = rows.map(\.height).sorted()
        let median = heights.isEmpty ? 0 : heights[heights.count / 2]
        let repeated = repeatedLines(rows)
        var assembler = Assembler(medianHeight: median)
        for row in rows where !repeated.contains(row.text.lowercased()) { assembler.consume(row) }
        return MenuImport.cleaned(assembler.finish())
    }

    // MARK: Колонки

    /// Колонки страницы слева направо — по вертикальным «коридорам» без
    /// текста. Столбцы из одних цен и граммовок (они выровнены по правому
    /// краю отдельно от названий) — не колонки, а правая часть соседней слева.
    static func columns(_ fragments: [MenuTextFragment]) -> [[MenuTextFragment]] {
        guard let pageWidth = fragments.first?.pageWidth, pageWidth > 0, fragments.count > 3 else {
            return fragments.isEmpty ? [] : [fragments]
        }
        let bins = 200
        var coverage = [Int](repeating: 0, count: bins)
        // Заголовки во всю ширину закрыли бы коридоры — их не считаем.
        for f in fragments where f.width < pageWidth * 0.55 {
            // Текст может выходить за поля страницы (вылеты, повёрнутые
            // подписи) — обе границы зажимаем в сетку.
            let a = min(bins - 1, max(0, Int(f.x / pageWidth * Double(bins))))
            let b = min(bins - 1, max(0, Int(f.maxX / pageWidth * Double(bins))))
            if a <= b { for i in a...b { coverage[i] += 1 } }
        }
        guard let first = coverage.firstIndex(where: { $0 > 0 }),
              let last = coverage.lastIndex(where: { $0 > 0 }) else { return [fragments] }
        var splits: [Double] = []
        var i = first
        while i <= last {
            if coverage[i] == 0 {
                var j = i
                while j <= last && coverage[j] == 0 { j += 1 }
                if j - i >= bins * 3 / 100 {
                    splits.append(Double(i + j) / 2 / Double(bins) * pageWidth)
                }
                i = j
            } else { i += 1 }
        }
        guard !splits.isEmpty else { return [fragments] }
        var cols = [[MenuTextFragment]](repeating: [], count: splits.count + 1)
        for f in fragments {
            cols[splits.firstIndex(where: { f.x < $0 }) ?? splits.count].append(f)
        }
        var merged: [[MenuTextFragment]] = []
        for col in cols where !col.isEmpty {
            if let lastIndex = merged.indices.last, isAttributeColumn(col) {
                merged[lastIndex] += col
            } else {
                merged.append(col)
            }
        }
        return merged
    }

    /// Столбец цен/граммовок: почти все фрагменты короткие и с цифрами.
    static func isAttributeColumn(_ col: [MenuTextFragment]) -> Bool {
        let numeric = col.filter { f in
            f.text.count <= 16 && f.text.contains(where: \.isNumber)
                && f.text.filter(\.isLetter).count <= 6
        }.count
        return Double(numeric) >= Double(col.count) * 0.7
    }

    // MARK: Строки

    struct Row: Equatable {
        var text: String
        var y: Double
        var height: Double
        var page: Int
    }

    /// Фрагменты колонки → визуальные строки сверху вниз. Фрагмент входит в
    /// строку, если по высоте он в основном внутри неё: название и цена,
    /// набранные разными шрифтами, — одна строка.
    static func makeRows(_ column: [MenuTextFragment]) -> [Row] {
        let sorted = column.sorted { $0.midY == $1.midY ? $0.x < $1.x : $0.midY < $1.midY }
        var groups: [[MenuTextFragment]] = []
        for f in sorted {
            if let lastIndex = groups.indices.last,
               let top = groups[lastIndex].map(\.y).min(),
               let bottom = groups[lastIndex].map(\.maxY).max() {
                let overlap = min(bottom, f.maxY) - max(top, f.y)
                if overlap >= min(f.height, bottom - top) * 0.5 {
                    groups[lastIndex].append(f)
                    continue
                }
            }
            groups.append([f])
        }
        return groups.map { g in
            // Высота строки — по тексту, а не по цене: цены часто крупнее.
            let words = g.filter { $0.text.filter(\.isLetter).count >= 3 }
            let heightSource = words.isEmpty ? g : words
            return Row(text: normalizeSpaces(g.sorted { $0.x < $1.x }.map(\.text).joined(separator: " ")),
                       y: g.map(\.y).min() ?? 0,
                       height: heightSource.map(\.height).max() ?? 0,
                       page: g.first?.page ?? 0)
        }
    }

    // MARK: Сборка

    struct Assembler {
        let medianHeight: Double
        var items: [MenuDraftItem] = []
        var section = ""
        /// Строки без цены с последнего блюда: описание, раздел или карточка.
        var pending: [Row] = []
        /// Последнее блюдо — из строки «название … цена» (таблица): к нему можно
        /// дописать продолжение названия и состав снизу.
        var tableDish: (index: Int, row: Row)?
        /// Низ предыдущей строки: по разрыву видно конец блока, по скачку
        /// вверх — новую колонку или страницу.
        var lastBottom: Double?
        var lastPage: Int?
        /// Название, к которому цепляются варианты «with banana», «с мясом».
        var variantBase: String?
        /// Последнее блюдо из карточки — для второй цены строкой ниже
        /// («200 g 130 som» / «1 kg 560 som»).
        var lastCard: Int?

        init(medianHeight: Double) { self.medianHeight = medianHeight }

        mutating func consume(_ row: Row) {
            if MenuTextParser.isNoise(row, medianHeight: medianHeight) { return }
            defer { lastBottom = row.y + row.height; lastPage = row.page }
            if let lastBottom, let lastPage {
                let newColumn = row.page != lastPage || row.y < lastBottom - medianHeight
                let bigGap = row.y - lastBottom > medianHeight * 2.2
                if newColumn {
                    // Колонка кончилась: хвост — состав последнего блюда из
                    // таблицы; хвост после карточки (бейджи, подписи к фото)
                    // — мусор. Карточка через колонку не переносится.
                    if tableDish != nil { flushPendingIntoLast() } else { pending = [] }
                    tableDish = nil
                } else if bigGap && tableDish != nil {
                    // Разрыв после блюда: дальше уже не его состав.
                    flushPendingIntoLast()
                    tableDish = nil
                }
            }

            let price = MenuPrice.parse(row.text)
            if let price, price.body.isEmpty {
                closeCard(with: price)
            } else if let price {
                addTableDish(row, price: price)
            } else if appendToTableDish(row) {
                return
            } else {
                pending.append(row)
            }
        }

        mutating func finish() -> [MenuDraftItem] {
            // Хвост без цены: состав последнего блюда из таблицы, иначе
            // карточка без цены (хозяин допишет), иначе мусор вроде подписи шефа.
            if tableDish != nil {
                flushPendingIntoLast()
            } else if items.isEmpty, let card = splitCard(pending), card.hasTitle {
                // Блок без цены в конце — адрес, слоган, подпись. Блюдом он
                // может быть, только если цен в меню нет вовсе.
                addItem(name: card.name, details: card.details, price: nil, portion: "")
            }
            pending = []
            return items
        }

        // MARK: Таблица: «Название … 330 г 450»

        mutating func addTableDish(_ row: Row, price: MenuPrice.Match) {
            // Строки над блюдом: состав предыдущего (таблица) и/или раздел.
            var carry: [Row] = []
            for r in pending {
                if MenuTextParser.isHeading(r, medianHeight: medianHeight) {
                    flush(carry); carry = []
                    section = MenuTextParser.cleanHeading(r.text)
                    variantBase = nil
                    tableDish = nil
                } else {
                    carry.append(r)
                }
            }
            if let lastCarry = carry.last, tableDish != nil,
               let first = price.body.first(where: \.isLetter), first.isLowercase,
               !MenuTextParser.looksLikeDescription(lastCarry.text) || lastCarry.text.hasSuffix(",") {
                // Название, перенесённое через строку, цена — у второй:
                // «Dorado with crispy asparagus,» / «baked onions … 1400».
                flush(Array(carry.dropLast()))
                pending = []
                tableDish = addItem(name: lastCarry.text + " " + price.body, details: "", price: price.value, portion: price.note)
                    .map { ($0, row) }
                return
            } else if tableDish != nil {
                flush(carry)
            } else if carry.count == 1, MenuTextParser.looksLikeDescription(price.body),
                      !MenuTextParser.looksLikeDescription(carry[0].text) {
                // Название на строку выше цены: «Бешбармак» / «с домашней
                // лапшой …… 550». Прочий текст над первым блюдом (вступление,
                // адрес) — не блюдо, отбрасываем.
                pending = []
                tableDish = addItem(name: carry[0].text, details: price.body, price: price.value, portion: price.note)
                    .map { ($0, row) }
                return
            }
            pending = []
            let (name, inline) = MenuTextParser.splitNameAndDetails(price.body)
            tableDish = addItem(name: name, details: inline, price: price.value, portion: price.note)
                .map { ($0, row) }
        }

        /// Строка без цены под блюдом из таблицы: продолжение названия
        /// (переносом, тем же шрифтом) или состав.
        mutating func appendToTableDish(_ row: Row) -> Bool {
            guard let (index, dishRow) = tableDish, pending.isEmpty,
                  items.indices.contains(index) else { return false }
            let text = row.text
            guard let first = text.first(where: \.isLetter) else { return false }
            let commas = text.filter { $0 == "," }.count
            if first.isLowercase, commas < 2, text.count <= 40,
               row.height >= dishRow.height * 0.8,
               items[index].name.count + text.count < MenuImport.nameLimit {
                items[index].name = MenuTextParser.cleanName(items[index].name + " " + text)
                return true
            }
            if MenuTextParser.looksLikeDescription(text) {
                items[index].details = MenuTextParser.join(items[index].details, text)
                return true
            }
            return false
        }

        mutating func flushPendingIntoLast() {
            flush(pending)
            pending = []
        }

        mutating func flush(_ rows: [Row]) {
            guard !rows.isEmpty, let (index, _) = tableDish, items.indices.contains(index) else { return }
            let text = rows.map(\.text).joined(separator: " ")
            items[index].details = MenuTextParser.join(items[index].details, text)
        }

        // MARK: Карточка: НАЗВАНИЕ / описание / «35 cm 820 som»

        mutating func closeCard(with price: MenuPrice.Match) {
            // Отдельная цена сразу под блюдом из таблицы без цены — его цена.
            if pending.isEmpty {
                if let (index, _) = tableDish, items.indices.contains(index), items[index].price == nil {
                    items[index].price = price.value
                } else if let index = lastCard, items.indices.contains(index) {
                    let extra = MenuTextParser.join(price.note, "\(price.value)")
                    items[index].details = MenuTextParser.join(items[index].details, extra)
                }
                return
            }
            if tableDish != nil {
                // Таблица кончилась карточкой: её начало — строки после
                // последнего описания предыдущего блюда.
                if let firstTitle = pending.firstIndex(where: { MenuTextParser.isTitleLike($0, medianHeight: medianHeight) }) {
                    flush(Array(pending[..<firstTitle]))
                    pending = Array(pending[firstTitle...])
                }
                tableDish = nil
            }
            guard let card = splitCard(pending) else { pending = []; return }
            if let heading = card.heading { section = heading; variantBase = nil }
            var name = card.name, details = card.details
            // «CHEBUREKS» / «with chives» / «150 g 290 som»: короткое уточнение
            // под названием — часть названия, а само название — основа для
            // следующих вариантов («with chicken and cheese» ниже).
            var base: String?
            if !details.isEmpty, details.count <= 40, MenuTextParser.isVariant(details) {
                base = MenuTextParser.sentenceCaseIfShouting(MenuTextParser.cleanName(name))
                name = base! + " " + details
                details = ""
            }
            lastCard = addItem(name: name, details: details, price: price.value, portion: price.note)
            if let base { variantBase = base }
            pending = []
        }

        struct Card { var heading: String?; var name: String; var details: String; var hasTitle: Bool }

        /// Строки карточки → раздел (крупнее названия), название (заглавные
        /// или крупные строки подряд), описание (остальное).
        func splitCard(_ allRows: [Row]) -> Card? {
            guard !allRows.isEmpty else { return nil }
            // Текст перед заголовком карточки — подписи и бейджи, не она сама.
            var rows = allRows
            if !MenuTextParser.isTitleLike(rows[0], medianHeight: medianHeight),
               let firstTitle = rows.firstIndex(where: { MenuTextParser.isTitleLike($0, medianHeight: medianHeight) }) {
                rows = Array(rows[firstTitle...])
            }
            let titles = Array(rows.prefix { MenuTextParser.isTitleLike($0, medianHeight: medianHeight) })
            var heading: String?
            var nameRows = titles
            if titles.count >= 2 {
                // «PIZZA» (26 pt) над «CHICKEN PIZZA» (19 pt): первое — раздел.
                let tail = titles.last!.height
                let headRows = titles.prefix { $0.height >= tail * 1.2 }
                if !headRows.isEmpty && headRows.count < titles.count {
                    heading = MenuTextParser.cleanHeading(headRows.map(\.text).joined(separator: " "))
                    nameRows = Array(titles.dropFirst(headRows.count))
                }
            }
            if nameRows.isEmpty { nameRows = [rows[0]] }
            let rest = rows.dropFirst(titles.isEmpty ? 1 : titles.count)
            return Card(heading: heading,
                        name: nameRows.map(\.text).joined(separator: " "),
                        details: rest.map(\.text).joined(separator: " "),
                        hasTitle: !titles.isEmpty)
        }

        /// Индекс добавленного блюда; `nil` — строка оказалась не блюдом.
        @discardableResult
        mutating func addItem(name: String, details: String, price: Int?, portion: String) -> Int? {
            // Граммовка в конце названия: «Десерт «Павлова» 155 г» — в описание.
            var portion = portion
            var name = name
            if let (rest, tail) = MenuPrice.trailingPortion(name) {
                name = rest
                portion = MenuTextParser.join(tail, portion)
            }
            var clean = MenuTextParser.cleanName(name)
            guard MenuTextParser.isMeaningful(clean) else { return nil }
            // Вариант без своего названия — «with banana» под «Pancakes».
            if MenuTextParser.isVariant(clean), let base = variantBase {
                clean = base + " " + clean
            } else if !MenuTextParser.isVariant(clean) {
                variantBase = MenuTextParser.sentenceCaseIfShouting(clean)
            }
            let fullDetails = MenuTextParser.join(MenuTextParser.cleanDetails(details), portion)
            items.append(MenuDraftItem(id: "d\(items.count)", section: section,
                                       name: MenuTextParser.sentenceCaseIfShouting(clean),
                                       price: price, details: fullDetails))
            return items.count - 1
        }
    }

    /// Строки без цены, повторённые 3+ раза: пометки («The seasons of
    /// Kyrgyzstan SUMMER» под каждым сезонным блюдом), колонтитулы, подписи
    /// вариантов («Standart/Premium»). Заглавные не трогаем — это могут быть
    /// разделы, повторённые на каждой странице.
    static func repeatedLines(_ rows: [Row]) -> Set<String> {
        var counts: [String: Int] = [:]
        for row in rows where MenuPrice.parse(row.text) == nil && row.text.count > 3 {
            let letters = row.text.filter(\.isLetter)
            if !letters.isEmpty && letters.allSatisfy(\.isUppercase) { continue }
            counts[row.text.lowercased(), default: 0] += 1
        }
        return Set(counts.filter { $0.value >= 3 }.keys)
    }

    // MARK: Классификация строк

    /// Раздел: коротко, без запятой в конце, и ЗАГЛАВНЫМИ (не мелким
    /// шрифтом — мелкие заглавные это пометки «*NEW») или заметно крупнее.
    static func isHeading(_ row: Row, medianHeight: Double) -> Bool {
        let text = row.text
        guard text.split(separator: " ").count <= 6, text.count <= 48,
              let last = text.last, !",;".contains(last) else { return false }
        let letters = text.filter(\.isLetter)
        guard letters.count >= 3 else { return false }
        let allCaps = Double(letters.filter(\.isUppercase).count) >= Double(letters.count) * 0.85
        let big = medianHeight > 0 && row.height >= medianHeight * 1.3
        return (allCaps && row.height >= medianHeight * 0.9) || big
    }

    /// Строка-заголовок карточки: заглавными или крупнее основного текста.
    static func isTitleLike(_ row: Row, medianHeight: Double) -> Bool {
        let letters = row.text.filter(\.isLetter)
        guard letters.count >= 2, row.text.count <= 60 else { return false }
        let allCaps = Double(letters.filter(\.isUppercase).count) >= Double(letters.count) * 0.85
        return allCaps || (medianHeight > 0 && row.height >= medianHeight * 1.2)
    }

    /// Уточнение варианта: «with chives», «с мясом», «со сметаной».
    static func isVariant(_ text: String) -> Bool {
        text.range(of: #"^(with|w/|without|in|on|с|со|без|из|на)\s"#, options: .regularExpression) != nil
    }

    /// Похоже на состав, а не на название: со строчной буквы, списком через
    /// запятую или длинное.
    static func looksLikeDescription(_ text: String) -> Bool {
        guard let first = text.first(where: \.isLetter) else { return false }
        if first.isLowercase { return true }
        if text.filter({ $0 == "," }).count >= 2 { return true }
        return text.count > 60
    }

    /// Служебное: пометки «*NEW», бейджи «New / Recommend», номера страниц,
    /// контакты, сноски про обслуживание.
    static func isNoise(_ row: Row, medianHeight: Double) -> Bool {
        let text = row.text
        let lower = text.lowercased()
        if text.hasPrefix("*") { return true }
        // Телефоны: «+7 777 844 11 27», «0 555 12 34 56».
        if text.range(of: #"\+\s?\d|\d{3}[\s-]\d{2}[\s-]\d{2}"#, options: .regularExpression) != nil { return true }
        if text.allSatisfy({ $0.isNumber || $0 == " " }) && text.count <= 3 { return true }
        let letters = text.filter(\.isLetter)
        if letters.isEmpty && MenuPrice.parse(text) == nil { return true }
        let badges: Set<String> = ["new", "recommend", "hit", "хит", "новинка", "new!", "хит!", "veg", "vegan",
                                   "spicy", "острое", "рекомендуем", "top", "sale", "акция"]
        if badges.contains(lower.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))) { return true }
        let markers = ["http", "www.", ".kg", ".com", "@", "+996", "instagram", "wi-fi", "wifi",
                       "обслуживан", "service charge", "цены указаны", "prices are", "все цены", "all prices",
                       "executive chef", "шеф-повар", "бренд-шеф", "allerg", "аллерг", "payment", "оплат",
                       "service fee", "сервисный сбор", "обслуживание", "national currency", "бронир", "reserv"]
        return markers.contains { lower.contains($0) }
    }

    /// «Название — состав» в одну строку: делим, если справа похоже на состав.
    static func splitNameAndDetails(_ text: String) -> (String, String) {
        for sep in [" — ", " – ", " - ", ": "] {
            if let r = text.range(of: sep) {
                let name = String(text[..<r.lowerBound]), rest = String(text[r.upperBound...])
                if !name.isEmpty, looksLikeDescription(rest) {
                    return (name, rest)
                }
            }
        }
        return (text, "")
    }

    // MARK: Чистка текста

    static func cleanName(_ text: String) -> String {
        var s = text
        // Пометка, приклеенная распознаванием: «cauliflowerGLUTEN-FREE».
        s = s.replacingOccurrences(of: #"(\p{Ll})(\p{Lu}{2,})"#, with: "$1 $2", options: .regularExpression)
        // Пометки «SUGAR-FREE / GLUTEN-FREE» набраны капителью, и распознавание
        // возвращает их с заглавными («GLUTEn-FREE», «GAR-FRE», «Ten fRee»).
        // Только такие и убираем: «Gluten-free» строчными — это название
        // блюда (хлеб без глютена), его трогать нельзя.
        s = s.replacingOccurrences(of: #"\s*\S*-FRE+E?\b\S*"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\s+\S{1,8})?\s+f[RР]e{1,2}$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+\S{0,8}FRE{1,2}$"#, with: "", options: .regularExpression)
        // Непарная кавычка, оставшаяся от пометки: «with mashed"».
        if s.filter({ $0 == "\"" }).count % 2 == 1 { s = s.replacingOccurrences(of: "\"", with: "") }
        // Пометки: «*NEW», «*SUGAR-FREE / GLUTEN-FREE», хвостовое «new».
        s = s.replacingOccurrences(of: #"\*[^\s*]+(\s*/\s*[^\s*]+)*"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)\s+(new|нов(ое|инка))!?\s*$"#, with: "", options: .regularExpression)
        // Бейдж в начале: «NEW Chef Nicoise», «NEW NewEel …», «НОВИНКА Плов».
        s = s.replacingOccurrences(of: #"^(?:(?:NEW|New|НОВИНКА|Новинка|ХИТ|HIT)!?\s*)+(?=\p{Lu})"#, with: "", options: .regularExpression)
        // Отточия и подчёркивания между названием и ценой.
        s = s.replacingOccurrences(of: #"[.…_·]{2,}"#, with: " ", options: .regularExpression)
        // Порядковый номер: «12. Лагман», «№5 Плов».
        s = s.replacingOccurrences(of: #"^(№\s?)?\d{1,3}[.)]\s+"#, with: "", options: .regularExpression)
        s = normalizeSpaces(s)
        return s.trimmingCharacters(in: CharacterSet(charactersIn: " -–—:|/•,.").union(.whitespaces))
    }

    static func cleanDetails(_ text: String) -> String {
        let s = text.replacingOccurrences(of: #"\*[^\s*]+(\s*/\s*[^\s*]+)*"#, with: " ", options: .regularExpression)
        return normalizeSpaces(s)
    }

    static func cleanHeading(_ text: String) -> String {
        sentenceCaseIfShouting(cleanName(text))
    }

    /// «CHICKEN PIZZA» → «Chicken pizza»: заглавные в меню — вёрстка. Смешанный
    /// регистр («Салат ZERNO») не трогаем — там заглавные что-то значат.
    static func sentenceCaseIfShouting(_ s: String) -> String {
        let letters = s.filter(\.isLetter)
        guard letters.count >= 2, letters.allSatisfy(\.isUppercase) else { return s }
        let lower = s.lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }

    /// Хоть две буквы: «350 / 450» — не блюдо.
    static func isMeaningful(_ name: String) -> Bool {
        name.filter(\.isLetter).count >= 2
    }

    public static func normalizeSpaces(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    static func join(_ a: String, _ b: String) -> String {
        a.isEmpty ? b : (b.isEmpty ? a : a + " " + b)
    }
}

// MARK: - Цена

/// Цена в конце строки. Отдельно, потому что это самое хрупкое место:
/// «350 г», «0,5 л», «1 200», «720/1220», «90/180KGS», «35 cm 820 som» и
/// «2024» должны читаться по-разному.
public enum MenuPrice {
    public struct Match: Equatable {
        /// Текст до цены и порции («Лагман»); пусто — строка из одной цены.
        public var body: String
        public var value: Int
        /// Порция и варианты цены для описания: «330/470 gr · 720/1220».
        public var note: String
    }

    static let currencies: Set<String> = ["сом", "сомов", "сома", "som", "soms", "kgs", "с", "c", "с.", "c.",
                                          "сом.", "руб", "р", "₽", "$", "₸", "тг"]
    static let units: Set<String> = ["г", "гр", "g", "gr", "кг", "kg", "мл", "ml", "л", "l", "cl", "cm", "см",
                                     "шт", "pcs", "pc", "порц", "oz", "г.", "гр.", "шт.", "мл.", "л.", "см."]

    public static func parse(_ raw: String) -> Match? {
        // «Service 15%», «скидка 10 %» — процент, а не цена.
        if raw.range(of: #"\d\s?%\s*$"#, options: .regularExpression) != nil { return nil }
        var tokens = tokenize(raw)
        guard !tokens.isEmpty else { return nil }
        var hasCurrency = false
        if let last = tokens.last, currencies.contains(last.lowercased()) {
            hasCurrency = true; tokens.removeLast()
        }
        guard let last = tokens.last, let prices = numberGroup(last) else { return nil }
        tokens.removeLast()
        // «1 200»: тысячи, разбитые пробелом (только однозначное число слева).
        var values = prices
        if values.count == 1, last.count == 3, let prev = tokens.last,
           prev.count == 1, let d = Int(prev), d > 0 {
            values = [d * 1000 + values[0]]
            tokens.removeLast()
        }
        if let prev = tokens.last, currencies.contains(prev.lowercased()) {   // «сом 350»
            hasCurrency = true; tokens.removeLast()
        }
        guard let value = values.first, valid(value, hasCurrency: hasCurrency, raw: last) else { return nil }
        // «24/7», «1/2» — не цены: без валюты каждая часть должна быть ценой.
        if !hasCurrency, values.contains(where: { $0 < 10 }) { return nil }
        // Порция перед ценой: «330/470 gr», «35 cm», «0.33/0.7 L».
        var portion: [String] = []
        while tokens.count >= 2, units.contains(tokens[tokens.count - 1].lowercased()),
              isQuantity(tokens[tokens.count - 2]) {
            portion.insert(tokens[tokens.count - 2] + " " + tokens[tokens.count - 1], at: 0)
            tokens.removeLast(2)
        }
        var note = portion.joined(separator: " ")
        if values.count > 1 { note = MenuTextParser.join(note, values.map(String.init).joined(separator: "/")) }
        let body = MenuTextParser.normalizeSpaces(tokens.joined(separator: " "))
            .trimmingCharacters(in: CharacterSet(charactersIn: " .…_·-–—:|/"))
        return Match(body: body, value: value, note: note)
    }

    /// Порция в самом конце текста: «Десерт 155 гр» → («Десерт», «155 гр»).
    static func trailingPortion(_ text: String) -> (String, String)? {
        var tokens = tokenize(text)
        guard tokens.count >= 3, units.contains(tokens[tokens.count - 1].lowercased()),
              isQuantity(tokens[tokens.count - 2]) else { return nil }
        let tail = tokens[tokens.count - 2] + " " + tokens[tokens.count - 1]
        tokens.removeLast(2)
        return (tokens.joined(separator: " "), tail)
    }

    /// Токены с отделёнными единицами: «90/180KGS» → «90/180 KGS», «210gr» → «210 gr».
    static func tokenize(_ raw: String) -> [String] {
        var s = MenuTextParser.normalizeSpaces(raw)
        // Маркеры перед числом: «•360», «~450», «—350».
        s = s.replacingOccurrences(of: #"(^|\s)[•·~–—*]+(\d)"#, with: "$1$2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(\d)([^\d\s.,/])"#, with: "$1 $2", options: .regularExpression)
        // «150 g/3 pcs»: единица, склеенная с числом через дробь.
        s = s.replacingOccurrences(of: #"(\p{L})/(\d)"#, with: "$1 / $2", options: .regularExpression)
        // Отточия «Лагман........350» — пробел.
        s = s.replacingOccurrences(of: #"[.…_·]{2,}"#, with: " ", options: .regularExpression)
        // Одиночные значки («•», «~») — не токены.
        return s.split(separator: " ").map(String.init).filter { token in
            token.contains(where: { $0.isLetter || $0.isNumber }) || currencies.contains(token)
        }
    }

    /// «450», «450.00», «1.200», «720/1220» → цены в сомах.
    static func numberGroup(_ token: String) -> [Int]? {
        let parts = token.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 4 else { return nil }
        var out: [Int] = []
        for p in parts {
            let part = String(p)
            if part.range(of: #"^\d{1,3}[.,]\d{3}$"#, options: .regularExpression) != nil {
                // 1.200 / 1,200 — тысячи. `\d` в регулярке — любые цифры Юникода
                // («١٬٢٠٠»), а `Int(_:)` понимает только ASCII: раньше здесь
                // было `!`, и такой токен ронял разбор меню.
                guard let v = Int(part.filter(\.isNumber)) else { return nil }
                out.append(v)
            } else if let m = part.range(of: #"^\d+([.,]\d{1,2})?$"#, options: .regularExpression), m == part.startIndex..<part.endIndex {
                let whole = part.split(whereSeparator: { $0 == "." || $0 == "," }).first.map(String.init) ?? part
                guard let v = Int(whole) else { return nil }
                // «0.5», «0,33» — объём, а не цена.
                if part.contains(where: { $0 == "." || $0 == "," }) && v < 10 { return nil }
                out.append(v)
            } else {
                return nil
            }
        }
        return out
    }

    static func isQuantity(_ token: String) -> Bool {
        token.range(of: #"^\d+([.,]\d+)?(/\d+([.,]\d+)?)*$"#, options: .regularExpression) != nil
    }

    /// Цены в Бишкеке — от десятков сомов; «5» без валюты — номер или
    /// количество, «2024» без валюты — год в шапке.
    static func valid(_ price: Int, hasCurrency: Bool, raw: String) -> Bool {
        guard price > 0, price < MenuImport.priceLimit else { return false }
        if hasCurrency { return true }
        if raw.count == 4, (1990...2035).contains(price) { return false }
        return price >= 10
    }
}
