import XCTest
@testable import SAN
import AyantDomain
import AyantFeatures

/// История баллов: грузится по запросу экрана, переживает моргнувшую сеть и
/// обновляется после списания — иначе гость видит устаревший журнал.
@MainActor
final class PointsStoreTests: XCTestCase {

    private var repo: FakePointsRepository!
    private var store: PointsStore!

    override func setUp() {
        super.setUp()
        repo = FakePointsRepository()
        store = PointsStore(repository: repo, clock: FixedClock(Date(timeIntervalSince1970: 1_700_000_000)))
        store.send(.observe(userID: "u1"))
    }

    private func entry(_ id: String, _ points: Int, kind: PointsLedgerEntry.Kind = .earn) -> PointsLedgerEntry {
        PointsLedgerEntry(id: id, kind: kind, points: points, at: Date(timeIntervalSince1970: 1_700_000_000))
    }

    private func waitUntil(_ condition: @autoclosure () -> Bool, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func testHistoryIsIdleUntilRequestedThenLoaded() async {
        repo.ledger["v1"] = [entry("a", 50), entry("b", -30, kind: .redeem)]
        XCTAssertEqual(store.state.history(for: "v1"), .idle)

        store.send(.loadHistory(venueID: "v1"))
        await waitUntil(self.store.state.history(for: "v1").value != nil)

        XCTAssertEqual(store.state.history(for: "v1").value?.map(\.id), ["a", "b"])
    }

    func testHistoryFailureKeepsAlreadyLoadedEntries() async {
        repo.ledger["v1"] = [entry("a", 50)]
        store.send(.loadHistory(venueID: "v1"))
        await waitUntil(self.store.state.history(for: "v1").value != nil)

        repo.ledgerError = .network
        store.send(.loadHistory(venueID: "v1"))
        await waitUntil(self.repo.ledgerRequests == 2)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(store.state.history(for: "v1").value?.map(\.id), ["a"], "сеть моргнула — журнал остаётся")
    }

    func testHistoryFailureWithoutDataIsVisible() async {
        repo.ledgerError = .network
        store.send(.loadHistory(venueID: "v1"))
        await waitUntil({ if case .failed = self.store.state.history(for: "v1") { return true }; return false }())

        XCTAssertEqual(store.state.history(for: "v1"), .failed(.network))
    }

    func testSuccessfulRedeemRefreshesShownHistory() async {
        repo.ledger["v1"] = [entry("a", 50)]
        store.send(.loadHistory(venueID: "v1"))
        await waitUntil(self.store.state.history(for: "v1").value != nil)

        repo.ledger["v1"] = [entry("r", -30, kind: .redeem), entry("a", 50)]
        store.send(.redeem(venueID: "v1", rewardID: "rw1", pointsToSpend: 30))
        await waitUntil(self.store.state.history(for: "v1").value?.count == 2)

        XCTAssertEqual(store.state.history(for: "v1").value?.first?.kind, .redeem)
    }

    func testGuestHistoryIsEmptyWithoutRequest() async {
        let guest = PointsStore(repository: repo)
        guest.send(.loadHistory(venueID: "v1"))
        XCTAssertEqual(guest.state.history(for: "v1"), .loaded([]))
        XCTAssertEqual(repo.ledgerRequests, 0)
    }
}
