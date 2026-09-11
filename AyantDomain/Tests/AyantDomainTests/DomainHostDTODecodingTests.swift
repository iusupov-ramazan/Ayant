import XCTest
@testable import AyantDomain

/// Кэш кабинета хоста переживает смену схемы.
///
/// Синтезированный `Decodable` не подставляет значения по умолчанию: поле,
/// которого нет в JSON, — ошибка. Так однажды исчез кабинет: кэш, записанный
/// старой версией (без `branches`, без `points*`), новая версия не смогла
/// прочитать и показала пустой список. Эти тесты пинят терпимый декодер.
final class DomainHostDTODecodingTests: XCTestCase {

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    // MARK: Заведение

    func testVenueDecodesFromMinimalJSONWithDefaults() throws {
        let json = #"{"id":"hv_1","name":"Тест"}"#.data(using: .utf8)!
        let dto = try decoder.decode(HostVenueDTO.self, from: json)
        XCTAssertEqual(dto.id, "hv_1")
        XCTAssertEqual(dto.name, "Тест")
        XCTAssertEqual(dto.status, ModerationStatus.pending.rawValue)
        XCTAssertEqual(dto.weekHours.count, 7)
        XCTAssertEqual(dto.loyaltyGoal, 6)
        XCTAssertTrue(dto.couponsEnabled)
        XCTAssertEqual(dto.pointsMode, "flat")
        XCTAssertEqual(dto.earnCooldownMinutes, 60)
        XCTAssertEqual(dto.latitude, City.bishkek.latitude, accuracy: 0.0001)
    }

    func testVenueDecodesOlderSchemaMissingLaterFields() throws {
        // Кэш «старой версии»: кодируем актуальный DTO и выкидываем поля,
        // которых у той версии не было.
        let full = HostVenueDTO(id: "hv_2", name: "Кафе", categoryRaw: "Кафе", district: "Центр",
                                address: "Чуй 1", phone: "", emoji: "☕️",
                                latitude: 42.87, longitude: 74.59, openHour: 9, closeHour: 22,
                                todaySpecial: nil, isPaused: false, isVerified: true,
                                loyaltyEnabled: true, loyaltyGoal: 4)
        var object = try JSONSerialization.jsonObject(with: encoder.encode(full)) as! [String: Any]
        for key in ["branches", "pointsBands", "pointsRewards", "boostedUntil", "earnCooldownMinutes",
                    "redeemMode", "pointsExpiryMonths", "cashbackPercent", "pdfMenuURL", "items"] {
            object.removeValue(forKey: key)
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        let dto = try decoder.decode(HostVenueDTO.self, from: data)
        XCTAssertEqual(dto.id, "hv_2")
        XCTAssertTrue(dto.isVerified)
        XCTAssertTrue(dto.loyaltyEnabled)
        XCTAssertEqual(dto.loyaltyGoal, 4)
        XCTAssertEqual(dto.branches, [])
        XCTAssertEqual(dto.earnCooldownMinutes, 60)
    }

    func testVenueRoundTripIsLossless() throws {
        let dto = HostVenueDTO(id: "hv_3", name: "Нават", categoryRaw: "Чайхана", district: "Юг",
                               address: "Ахунбаева 1", phone: "0555", emoji: "🍵",
                               latitude: 42.8, longitude: 74.6, openHour: 8, closeHour: 23,
                               todaySpecial: "Плов", isPaused: true, isVerified: false,
                               status: ModerationStatus.approved.rawValue,
                               branches: [Branch(id: "b1", address: "Филиал", latitude: 42.9, longitude: 74.7, phone: "")],
                               boostedUntil: Date(timeIntervalSince1970: 1_800_000_000),
                               loyaltyEnabled: true, loyaltyGoal: 5, loyaltyReward: "Кофе",
                               pointsEnabled: true, pointsMode: "cashback", cashbackPercent: 7.5,
                               pointsRewards: [PointsReward(id: "r1", type: "item", title: "Десерт", cost: 300, ratio: 1, active: true)],
                               earnCooldownMinutes: 0)
        let back = try decoder.decode(HostVenueDTO.self, from: encoder.encode(dto))
        XCTAssertEqual(back, dto)
    }

    func testVenueStillFailsWithoutIdentity() {
        let json = #"{"name":"Без id"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try decoder.decode(HostVenueDTO.self, from: json))
    }

    // MARK: Акция

    func testDealDecodesFromMinimalJSONWithDefaults() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        {"id":"hd_1","venueID":"hv_1","title":"Скидка","startDate":\(start.timeIntervalSinceReferenceDate)}
        """.data(using: .utf8)!
        let dto = try decoder.decode(HostDealDTO.self, from: json)
        XCTAssertEqual(dto.id, "hd_1")
        XCTAssertEqual(dto.venueID, "hv_1")
        XCTAssertEqual(dto.startDate.timeIntervalSince1970, start.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(dto.type, .discount)
        XCTAssertEqual(dto.status, .active)
        XCTAssertNil(dto.newPrice)
        XCTAssertEqual(dto.imageURLs, [])
        XCTAssertEqual(dto.terms, [])
    }

    func testDealRoundTripIsLossless() throws {
        let dto = HostDealDTO(id: "hd_2", venueID: "hv_1", typeRaw: "promo", title: "Кола в подарок",
                              details: "Только сегодня", emoji: "🥤", newPrice: 650, discountPercent: nil,
                              startDate: Date(timeIntervalSince1970: 1_700_000_000),
                              endDate: Date(timeIntervalSince1970: 1_700_500_000), statusRaw: "draft",
                              imageURL: "https://x/1.jpg", imageURLs: ["https://x/1.jpg"], terms: ["Одна на гостя"])
        let back = try decoder.decode(HostDealDTO.self, from: encoder.encode(dto))
        XCTAssertEqual(back, dto)
    }
}
