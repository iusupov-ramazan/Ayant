import XCTest
@testable import AyantDomain

/// Адреса заведения одним списком и акции «только по адресу …».
final class DomainVenueLocationsTests: XCTestCase {

    private let second = Branch(id: "b2", address: "Токтогула, 93", latitude: 42.1, longitude: 74.1)
    private let third = Branch(id: "b3", address: "Джал, 5", latitude: 42.2, longitude: 74.2)

    private func locations(first: String = "Манаса, 57", branches: [Branch]? = nil) -> [Branch] {
        VenueLocations.all(address: first, latitude: 42.0, longitude: 74.0,
                           branches: branches ?? [second, third])
    }

    func testFirstAddressComesFirstWithStableID() {
        let all = locations()
        XCTAssertEqual(all.map(\.id), [VenueLocations.firstID, "b2", "b3"])
        XCTAssertEqual(all.first?.address, "Манаса, 57")
        XCTAssertEqual(all.first?.latitude, 42.0)
    }

    func testEmptyAddressesAreDropped() {
        // Заведение без адреса в полях, но с филиалами — не рисуем пустую строку.
        XCTAssertEqual(locations(first: "  ").map(\.id), ["b2", "b3"])
        let blank = Branch(id: "b4", address: " ", latitude: 0, longitude: 0)
        XCTAssertEqual(locations(branches: [blank]).map(\.id), [VenueLocations.firstID])
    }

    func testNoIDsMeansEverywhere() {
        XCTAssertNil(VenueLocations.restricted(to: [], in: locations()))
    }

    func testSubsetIsRestrictedInVenueOrder() {
        let only = VenueLocations.restricted(to: ["b3", VenueLocations.firstID], in: locations())
        XCTAssertEqual(only?.map(\.id), [VenueLocations.firstID, "b3"])
    }

    func testAllAddressesSelectedMeansEverywhere() {
        // Отметить все адреса — то же, что «во всех»: гостю не нужна строка
        // «только по адресам» со списком всех адресов.
        XCTAssertNil(VenueLocations.restricted(to: [VenueLocations.firstID, "b2", "b3"], in: locations()))
    }

    func testDeletedAddressesAreForgiven() {
        // Хозяин удалил адрес, на который была настроена акция: акция не
        // пропадает и не пишет гостю про несуществующий адрес.
        XCTAssertNil(VenueLocations.restricted(to: ["gone"], in: locations()))
        XCTAssertEqual(VenueLocations.restricted(to: ["gone", "b2"], in: locations())?.map(\.id), ["b2"])
    }

    func testDealFormKeepsLocationsWithoutDuplicates() {
        let fields = HostForms.DealFields(
            venueID: "v1", type: .discount, title: "t", details: "", emoji: "🔥",
            newPrice: nil, discountPercent: nil, endDate: nil, isDraft: false,
            imageURLs: [], locationIDs: ["b2", "", "b2", VenueLocations.firstID])
        let dto = HostForms.deal(existing: nil, fields: fields,
                                 now: Date(timeIntervalSince1970: 0), newID: "hd_1")
        XCTAssertEqual(dto.locationIDs, ["b2", VenueLocations.firstID])
        // Доезжает до пользовательской модели — её читает страница акции.
        XCTAssertEqual(dto.asDeal.locationIDs, ["b2", VenueLocations.firstID])
    }

    func testOldCacheWithoutLocationsDecodesAsEverywhere() throws {
        // Кэш кабинета из сборки без адресов акций не должен превращаться
        // в «не декодируется» — см. терпимый декодер `HostDealDTO`.
        let json = #"{"id":"hd_1","venueID":"v1","title":"t","startDate":0}"#
        let dto = try JSONDecoder().decode(HostDealDTO.self, from: Data(json.utf8))
        XCTAssertEqual(dto.locationIDs, [])
    }
}
