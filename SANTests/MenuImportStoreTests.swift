import XCTest
@testable import SAN
import AyantDomain
import AyantFeatures

/// Сервис разбора, который отвечает заданным результатом.
private final class StubMenuParser: MenuParsingService, @unchecked Sendable {
    var result: Result<[MenuDraftItem], AppError>
    private(set) var calls = 0
    init(_ result: Result<[MenuDraftItem], AppError>) { self.result = result }
    func parseMenu(file: Data, kind: MenuFileKind,
                   progress: @escaping @Sendable (Double) -> Void) async throws -> [MenuDraftItem] {
        calls += 1
        progress(0.5)
        return try result.get()
    }
}

@MainActor
final class MenuImportStoreTests: XCTestCase {

    private let dishes = [
        MenuDraftItem(id: "a", section: "Супы", name: "Лагман", price: 350, details: ""),
        MenuDraftItem(id: "b", section: "Горячее", name: "Плов", price: 380, details: ""),
    ]

    private func waitForPhaseChange(_ store: MenuImportStore) async {
        for _ in 0..<100 where store.isReading {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testSuccessfulParseGoesToReview() async {
        let store = MenuImportStore(service: StubMenuParser(.success(dishes)))
        store.send(.parse(file: Data("%PDF-".utf8), kind: .pdf))
        XCTAssertTrue(store.isReading)
        await waitForPhaseChange(store)
        XCTAssertEqual(store.state.phase, .review)
        XCTAssertEqual(store.state.drafts.count, 2)
        XCTAssertEqual(store.state.includedCount, 2)
    }

    func testServerErrorIsKeptForTheScreen() async {
        let store = MenuImportStore(service: StubMenuParser(.failure(.server(code: "pdf_locked"))))
        store.send(.parse(file: Data("%PDF-".utf8), kind: .pdf))
        await waitForPhaseChange(store)
        XCTAssertEqual(store.state.phase, .failed(.server(code: "pdf_locked")))
    }

    func testEmptyMenuIsAFailureNotAnEmptyReview() async {
        let store = MenuImportStore(service: StubMenuParser(.success([])))
        store.send(.parse(file: Data("%PDF-".utf8), kind: .pdf))
        await waitForPhaseChange(store)
        XCTAssertEqual(store.state.phase, .failed(.server(code: "no_items")))
    }

    func testTooLargeFileIsRejectedBeforeParsing() {
        let parser = StubMenuParser(.success(dishes))
        let store = MenuImportStore(service: parser)
        store.send(.parse(file: Data(count: MenuImport.maxFileBytes + 1), kind: .pdf))
        XCTAssertEqual(store.state.phase, .failed(.server(code: "file_too_large")))
        XCTAssertEqual(parser.calls, 0, "огромный файл не открываем — память телефона")
    }

    func testEditingToggleAndSelectAll() async {
        let store = MenuImportStore(service: StubMenuParser(.success(dishes)))
        store.send(.parse(file: Data("%PDF-".utf8), kind: .pdf))
        await waitForPhaseChange(store)
        store.send(.toggle(id: "a"))
        XCTAssertEqual(store.state.includedCount, 1)
        var plov = store.state.drafts[1]
        plov.price = 400
        store.send(.update(plov))
        XCTAssertEqual(store.state.drafts[1].price, 400)
        store.send(.setAll(include: true))
        XCTAssertEqual(store.state.includedCount, 2)
        store.send(.reset)
        XCTAssertEqual(store.state, MenuImportState())
    }
}
