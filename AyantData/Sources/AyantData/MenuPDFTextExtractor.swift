import Foundation
import PDFKit
import Vision
import CoreGraphics
import AyantDomain

// Текст страниц PDF-меню с рамками — для `MenuTextParser` (домен).
//
// Два источника, по странице:
// • текстовый слой PDF (PDFKit) — мгновенно и без ошибок распознавания, если
//   меню свёрстано в редакторе и экспортировано с текстом;
// • распознавание (Vision) — если текста нет (меню — картинки или скан) или
//   текстовый слой битый (шрифт без таблицы символов даёт «кракозябры»).
//
// Всё на устройстве: файл никуда не уходит, ключей и счетов нет.
// Файл без Firebase намеренно — он же собирается в проверочный стенд на Mac.
public enum MenuPDFTextExtractor {

    /// Больше — уже не меню, а каталог. Страницы с текстом читаются мгновенно,
    /// распознавание — около секунды на страницу.
    public static let maxPages = 120

    public static func fragments(from data: Data,
                                 progress: ((Int, Int) -> Void)? = nil) throws -> [MenuTextFragment] {
        guard let document = PDFDocument(data: data) else {
            throw AppError.server(code: "not_pdf")
        }
        if document.isLocked { throw AppError.server(code: "pdf_locked") }
        let count = min(document.pageCount, maxPages)
        var out: [MenuTextFragment] = []
        for index in 0..<count {
            progress?(index, count)
            guard let page = document.page(at: index) else { continue }
            let fromText = textLayer(page, index: index)
            out += fromText.isEmpty ? recognize(page, index: index) : fromText
        }
        return out
    }

    // MARK: Текстовый слой

    static func textLayer(_ page: PDFPage, index: Int) -> [MenuTextFragment] {
        guard let text = page.string, isReadable(text) else { return [] }
        let box = page.bounds(for: .mediaBox)
        guard let selection = page.selection(for: box) else { return [] }
        return selection.selectionsByLine().compactMap { line in
            let s = (line.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { return nil }
            let r = line.bounds(for: page)
            // PDF: начало снизу слева → переворачиваем в «сверху вниз».
            return MenuTextFragment(page: index, text: s,
                                    x: Double(r.minX - box.minX),
                                    y: Double(box.maxY - r.maxY),
                                    width: Double(r.width), height: Double(r.height),
                                    pageWidth: Double(box.width))
        }
    }

    /// Текстовый слой годится: букв достаточно и это действительно буквы, а
    /// не символы подменённого шрифта.
    static func isReadable(_ text: String) -> Bool {
        let visible = text.filter { !$0.isWhitespace }
        guard visible.count >= 20 else { return false }
        let letters = visible.filter { $0.isLetter || $0.isNumber }.count
        let broken = visible.filter { $0 == "\u{FFFD}" || ($0.unicodeScalars.first.map { $0.value >= 0xE000 && $0.value <= 0xF8FF } ?? false) }.count
        return Double(letters) >= Double(visible.count) * 0.6 && broken * 20 < visible.count
    }

    // MARK: Распознавание

    /// Два прохода распознавания с разной картинкой. Vision на отдельных
    /// масштабах теряет первые буквы строк («hopped beef» вместо «Chopped
    /// beef») и при этом уверен в ответе (confidence ≈ 1), так что «плохой»
    /// проход по уверенности не отличить. Потерянные буквы — меньше букв,
    /// поэтому берём проход, где их больше. Проверено на меню ZERNO:
    /// ни один из двух проходов не ошибается одновременно с другим.
    static let passes: [(pixels: CGFloat, padding: CGFloat)] = [(3200, 0), (2400, 0.06)]

    static func recognize(_ page: PDFPage, index: Int) -> [MenuTextFragment] {
        var best: [MenuTextFragment] = []
        var bestLetters = -1
        for pass in passes {
            let fragments = recognize(page, index: index, pixels: pass.pixels, padding: pass.padding)
            let letters = fragments.reduce(0) { $0 + $1.text.filter(\.isLetter).count }
            if letters > bestLetters { best = fragments; bestLetters = letters }
        }
        return best
    }

    static func recognize(_ page: PDFPage, index: Int, pixels: CGFloat, padding: CGFloat) -> [MenuTextFragment] {
        guard let cg = page.pageRef else { return [] }
        let box = cg.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return [] }
        let scale = pixels / max(box.width, box.height)
        let pad = padding * pixels
        let pw = box.width * scale, ph = box.height * scale
        let w = Int(pw + 2 * pad), h = Int(ph + 2 * pad)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return [] }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: pad, y: pad)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(cg)
        guard let image = ctx.makeImage() else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ru-RU", "en-US"]
        request.usesLanguageCorrection = true
        // Мелкий текст меню (граммовки, цены) — не отбрасывать.
        request.minimumTextHeight = 0.006
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return [] }

        // Нормированные координаты картинки (с полями, начало снизу слева) →
        // пункты страницы (начало сверху слева).
        let W = Double(w), H = Double(h), s = Double(scale), p = Double(pad)
        return (request.results ?? []).compactMap { obs in
            guard let candidate = obs.topCandidates(1).first, candidate.confidence >= 0.3 else { return nil }
            let b = obs.boundingBox
            let x = (Double(b.minX) * W - p) / s
            let yTop = ((1 - Double(b.maxY)) * H - p) / s
            return MenuTextFragment(page: index, text: candidate.string,
                                    x: x, y: yTop,
                                    width: Double(b.width) * W / s, height: Double(b.height) * H / s,
                                    pageWidth: Double(box.width))
        }
    }
}
