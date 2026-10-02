import Foundation
import Compression
import AyantDomain

// Excel (.xlsx) → строки ячеек для `MenuTable`.
//
// .xlsx — это ZIP с XML внутри. Публичного API распаковки ZIP в iOS нет,
// поэтому здесь минимальный читатель: центральный каталог ZIP → нужные
// файлы → deflate через системный Compression → XML через XMLParser. Только
// то, что нужно меню: имена листов, общие строки, значения ячеек. Формулы
// берутся по сохранённому значению, форматирование и стили не читаются.
// Старый .xls (двоичный формат) не поддерживается — экран просит сохранить
// как .xlsx или CSV.
//
// Без Firebase — собирается в проверочный стенд на Mac вместе с PDF.
public enum MenuXLSXReader {

    public static func sheets(from data: Data) throws -> [MenuTable.Sheet] {
        let zip = try ZipArchive(data)
        guard let workbook = zip.file("xl/workbook.xml") else { throw AppError.server(code: "not_xlsx") }
        let shared = zip.file("xl/sharedStrings.xml").map(SharedStringsParser.parse) ?? []
        let rels = zip.file("xl/_rels/workbook.xml.rels").map(RelationshipsParser.parse) ?? [:]
        var out: [MenuTable.Sheet] = []
        for sheet in WorkbookParser.parse(workbook) {
            // Цель связи — относительно xl/: «worksheets/sheet1.xml» или «/xl/…».
            var target = rels[sheet.relationID] ?? "worksheets/sheet\(out.count + 1).xml"
            if target.hasPrefix("/") { target.removeFirst() } else { target = "xl/" + target }
            guard let xml = zip.file(target) else { continue }
            let rows = SheetParser.parse(xml, sharedStrings: shared)
            if !rows.isEmpty { out.append(MenuTable.Sheet(name: sheet.name, rows: rows)) }
        }
        return out
    }

    // MARK: ZIP

    /// Потолок распакованного размера одного файла книги. Заголовок ZIP
    /// объявляет размер сам, и «ZIP-бомба» на 30 КБ просила бы `Data(count:)`
    /// на гигабайты — приложение убивала система. Меню столько не весит.
    static let maxUncompressedBytes = 50 * 1024 * 1024

    struct ZipArchive {
        struct Entry { let method: UInt16; let compressedSize: Int; let size: Int; let localOffset: Int }
        let data: Data
        var entries: [String: Entry] = [:]
        /// ZIP64 — маркер 0xFFFFFFFF в 32-битных полях (настоящие размеры —
        /// в extra-поле, которое мы не читаем). Для меню не бывает; принять
        /// маркер за размер — читать 4 ГБ.
        static let zip64Marker: UInt32 = 0xFFFF_FFFF

        init(_ data: Data) throws {
            self.data = data
            let bytes = [UInt8](data)
            // Конец центрального каталога — сигнатура 0x06054b50 в последних 64 КБ.
            let lower = max(0, bytes.count - 65_557)
            guard bytes.count >= 22,
                  let eocd = stride(from: bytes.count - 22, through: lower, by: -1).first(where: {
                      Self.u32(bytes, $0) == 0x0605_4b50 }) else {
                throw AppError.server(code: "not_xlsx")
            }
            let count = Int(Self.u16(bytes, eocd + 10))
            var p = Int(Self.u32(bytes, eocd + 16))
            for _ in 0..<count {
                guard p + 46 <= bytes.count, Self.u32(bytes, p) == 0x0201_4b50 else { break }
                let method = Self.u16(bytes, p + 10)
                let rawCompressed = Self.u32(bytes, p + 20)
                let rawSize = Self.u32(bytes, p + 24)
                let rawOffset = Self.u32(bytes, p + 42)
                if rawCompressed == Self.zip64Marker || rawSize == Self.zip64Marker
                    || rawOffset == Self.zip64Marker {
                    throw AppError.server(code: "not_xlsx")
                }
                let compressed = Int(rawCompressed)
                let size = Int(rawSize)
                let nameLength = Int(Self.u16(bytes, p + 28))
                let extraLength = Int(Self.u16(bytes, p + 30))
                let commentLength = Int(Self.u16(bytes, p + 32))
                let offset = Int(rawOffset)
                guard p + 46 + nameLength <= bytes.count else { break }
                let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLength)], as: UTF8.self)
                entries[name] = Entry(method: method, compressedSize: compressed, size: size, localOffset: offset)
                p += 46 + nameLength + extraLength + commentLength
            }
            if entries.isEmpty { throw AppError.server(code: "not_xlsx") }
        }

        func file(_ name: String) -> Data? {
            guard let e = entries[name], e.size <= MenuXLSXReader.maxUncompressedBytes else { return nil }
            let bytes = data
            let base = bytes.startIndex
            guard e.localOffset + 30 <= bytes.count else { return nil }
            let header = [UInt8](bytes[(base + e.localOffset)..<(base + e.localOffset + 30)])
            guard Self.u32(header, 0) == 0x0403_4b50 else { return nil }
            let start = e.localOffset + 30 + Int(Self.u16(header, 26)) + Int(Self.u16(header, 28))
            guard start + e.compressedSize <= bytes.count else { return nil }
            let payload = bytes[(base + start)..<(base + start + e.compressedSize)]
            switch e.method {
            case 0: return e.compressedSize <= MenuXLSXReader.maxUncompressedBytes ? Data(payload) : nil
            case 8: return Self.inflate(Data(payload), size: e.size)
            default: return nil
            }
        }

        /// Сырой deflate (без заголовка zlib) — `COMPRESSION_ZLIB` в Compression.
        static func inflate(_ input: Data, size: Int) -> Data? {
            guard size > 0 else { return Data() }
            // Пустой поток при ненулевом размере — битый файл; без этой
            // проверки `baseAddress!` пустого буфера = падение.
            guard !input.isEmpty, size <= MenuXLSXReader.maxUncompressedBytes else { return nil }
            var output = Data(count: size)
            let written = output.withUnsafeMutableBytes { dst -> Int in
                input.withUnsafeBytes { src -> Int in
                    guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                          let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_decode_buffer(d, size, s, input.count, nil, COMPRESSION_ZLIB)
                }
            }
            return written == size ? output : nil
        }

        static func u16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
        static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
            UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
        }
    }

    // MARK: XML

    /// Общие строки: `<si>` → текст (включая форматированные куски `<r><t>`).
    final class SharedStringsParser: NSObject, XMLParserDelegate {
        var strings: [String] = []
        private var current = ""
        private var inText = false

        static func parse(_ data: Data) -> [String] {
            let p = SharedStringsParser()
            let parser = XMLParser(data: data)
            parser.delegate = p
            parser.parse()
            return p.strings
        }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            if name == "si" { current = "" }
            if name == "t" { inText = true }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if inText { current += string } }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "t" { inText = false }
            if name == "si" { strings.append(current) }
        }
    }

    /// Листы книги по порядку: имя и id связи на файл листа.
    final class WorkbookParser: NSObject, XMLParserDelegate {
        var sheets: [(name: String, relationID: String)] = []
        static func parse(_ data: Data) -> [(name: String, relationID: String)] {
            let p = WorkbookParser()
            let parser = XMLParser(data: data)
            parser.delegate = p
            parser.parse()
            return p.sheets
        }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            guard name == "sheet" else { return }
            // Скрытые листы (служебные справочники) в меню не берём.
            if attributes["state"] == "hidden" || attributes["state"] == "veryHidden" { return }
            sheets.append((attributes["name"] ?? "", attributes["r:id"] ?? ""))
        }
    }

    final class RelationshipsParser: NSObject, XMLParserDelegate {
        var map: [String: String] = [:]
        static func parse(_ data: Data) -> [String: String] {
            let p = RelationshipsParser()
            let parser = XMLParser(data: data)
            parser.delegate = p
            parser.parse()
            return p.map
        }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            if name == "Relationship", let id = attributes["Id"], let target = attributes["Target"] {
                map[id] = target
            }
        }
    }

    /// Лист → строки ячеек. Позиция ячейки — из адреса («C7»): пустые ячейки
    /// в файле пропущены, а столбцы должны остаться на своих местах.
    final class SheetParser: NSObject, XMLParserDelegate {
        let shared: [String]
        var rows: [[String]] = []
        private var row: [Int: String] = [:]
        private var column = 0
        private var type = ""
        private var value = ""
        private var inValue = false

        init(shared: [String]) { self.shared = shared }

        static func parse(_ data: Data, sharedStrings: [String]) -> [[String]] {
            let p = SheetParser(shared: sharedStrings)
            let parser = XMLParser(data: data)
            parser.delegate = p
            parser.parse()
            return p.rows
        }
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            switch name {
            case "row": row = [:]; column = 0
            case "c":
                type = attributes["t"] ?? ""
                if let ref = attributes["r"] { column = Self.columnIndex(ref) }
                value = ""
            case "v", "t": inValue = true
            default: break
            }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) { if inValue { value += string } }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "v", "t": inValue = false
            case "c":
                var text = value
                if type == "s", let i = Int(value), shared.indices.contains(i) { text = shared[i] }
                if type == "b" { text = value == "1" ? "TRUE" : "FALSE" }
                // «350.0» из числовой ячейки — «350».
                if type.isEmpty || type == "n", let d = Double(value), d == d.rounded(), abs(d) < 1e12 {
                    text = String(Int(d))
                }
                row[column] = text.trimmingCharacters(in: .whitespacesAndNewlines)
                column += 1
            case "row":
                let width = (row.keys.max() ?? -1) + 1
                rows.append((0..<width).map { row[$0] ?? "" })
            default: break
            }
        }
        /// Последний столбец Excel — XFD (16384). Длинный «адрес» из битого
        /// файла иначе переполнял `Int` (падение) или раздувал строку до
        /// миллионов пустых ячеек.
        static let maxColumns = 16_384

        /// «AB12» → 27 (с нуля), не больше `maxColumns - 1`.
        static func columnIndex(_ ref: String) -> Int {
            var n = 0
            for ch in ref.uppercased() {
                guard let a = ch.asciiValue, a >= 65, a <= 90 else { break }
                n = n * 26 + Int(a - 64)
                if n > maxColumns { return maxColumns - 1 }
            }
            return max(0, n - 1)
        }
    }
}
