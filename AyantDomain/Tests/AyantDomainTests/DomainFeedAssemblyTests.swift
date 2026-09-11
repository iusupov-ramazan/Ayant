import XCTest
@testable import AyantDomain

/// Юнит-тесты чистого наложения контента хоста (`Domain/FeedAssembly.swift`).
/// Обобщённый `overlay` тестируем на лёгкой Identifiable-модели — тип не важен.
final class DomainFeedAssemblyTests: XCTestCase {

    private struct Item: Identifiable, Equatable {
        let id: String
        let tag: String
    }

    func testOverlayReplacesInPlaceAndPreservesBaseOrder() {
        let base = [Item(id: "a", tag: "base"), Item(id: "b", tag: "base"), Item(id: "c", tag: "base")]
        let result = FeedAssembly.overlay(base, with: [Item(id: "b", tag: "host")])
        XCTAssertEqual(result.map(\.id), ["a", "b", "c"])          // порядок сохранён
        XCTAssertEqual(result.first { $0.id == "b" }?.tag, "host") // правка хоста выиграла
    }

    func testOverlayAppendsHostOnlyItemsAtTail() {
        let base = [Item(id: "a", tag: "base")]
        let result = FeedAssembly.overlay(base, with: [Item(id: "z", tag: "host")])
        XCTAssertEqual(result.map(\.id), ["a", "z"])
    }

    func testOverlayReplacesAndAppendsTogether() {
        let base = [Item(id: "a", tag: "base"), Item(id: "b", tag: "base")]
        let result = FeedAssembly.overlay(base, with: [Item(id: "b", tag: "host"), Item(id: "c", tag: "host")])
        XCTAssertEqual(result.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(result.first { $0.id == "b" }?.tag, "host")
        XCTAssertEqual(result.first { $0.id == "c" }?.tag, "host")
    }

    func testOverlayEmptyOverridesReturnsBaseUnchanged() {
        let base = [Item(id: "a", tag: "base"), Item(id: "b", tag: "base")]
        XCTAssertEqual(FeedAssembly.overlay(base, with: []), base)
    }
}
