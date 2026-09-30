import XCTest
@testable import AyantDomain

/// Какое заведение открыто на первой вкладке кабинета.
///
/// Вкладка — это страница одного заведения, а выбранный id живёт на
/// устройстве. Если его разрешение сломается, хозяин с заведениями увидит
/// «у вас пока нет заведений» или прыгнет на чужое после создания нового.
final class DomainHostVenueSelectionTests: XCTestCase {

    private func venue(_ id: String) -> HostVenueDTO {
        HostVenueDTO(id: id, name: id, categoryRaw: VenueCategory.cafe.rawValue,
                     district: "", address: "", phone: "", emoji: "🍽",
                     latitude: 0, longitude: 0, openHour: 9, closeHour: 22,
                     todaySpecial: nil, isPaused: false, isVerified: false)
    }

    private func state(_ ids: [String]) -> HostState {
        HostState(venues: ids.map(venue))
    }

    func testStoredSelectionWins() {
        XCTAssertEqual(state(["a", "b", "c"]).currentVenue(preferredID: "b")?.id, "b")
    }

    func testMissingSelectionFallsBackToFirstVenue() {
        // Заведение удалили — показываем первое, а не пустое состояние.
        XCTAssertEqual(state(["a", "b"]).currentVenue(preferredID: "gone")?.id, "a")
        XCTAssertEqual(state(["a", "b"]).currentVenue(preferredID: nil)?.id, "a")
        XCTAssertEqual(state(["a", "b"]).currentVenue(preferredID: "")?.id, "a")
    }

    func testNoVenuesMeansNoSelection() {
        XCTAssertNil(state([]).currentVenue(preferredID: "a"))
    }

    func testSingleNewVenueIsDetected() {
        XCTAssertEqual(state(["a", "b", "new"]).addedVenueID(since: ["a", "b"]), "new")
    }

    func testNothingOrSeveralNewVenuesAreIgnored() {
        // Форму закрыли без сохранения.
        XCTAssertNil(state(["a"]).addedVenueID(since: ["a"]))
        // Несколько сразу пришли синхронизацией — угадывать не берёмся.
        XCTAssertNil(state(["a", "x", "y"]).addedVenueID(since: ["a"]))
    }
}
