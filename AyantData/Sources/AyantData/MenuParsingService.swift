import Foundation
import AyantDomain

/// Разбор файла меню на устройстве: PDF (текстовый слой или распознавание
/// Vision), CSV и Excel. Без сети, ключей и оплаты — файл не покидает телефон.
///
/// Раньше PDF отправлялся в Cloud Function с языковой моделью; её убрали
/// ради нулевой стоимости (2026-09-29). Точность правил ниже модели, но
/// каждый разбор всё равно проходит проверку хозяином.
public final class OnDeviceMenuParsingService: MenuParsingService, @unchecked Sendable {
    public init() {}

    public func parseMenu(file: Data, kind: MenuFileKind,
                          progress: @escaping @Sendable (Double) -> Void) async throws -> [MenuDraftItem] {
        guard file.count <= MenuImport.maxFileBytes else { throw AppError.server(code: "file_too_large") }
        // Распознавание — секунды на страницу: не на главном потоке.
        return try await Task.detached(priority: .userInitiated) {
            switch kind {
            case .pdf:
                let fragments = try MenuPDFTextExtractor.fragments(from: file) { page, total in
                    progress(Double(page) / Double(max(total, 1)))
                }
                progress(1)
                return MenuTextParser.parse(fragments)
            case .csv:
                return MenuTable.items(from: [MenuTable.Sheet(name: "", rows: MenuTable.csvRows(file))])
            case .xlsx:
                return MenuTable.items(from: try MenuXLSXReader.sheets(from: file))
            }
        }.value
    }
}
