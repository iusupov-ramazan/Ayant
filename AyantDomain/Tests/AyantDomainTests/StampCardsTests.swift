import XCTest
@testable import AyantDomain

/// Несколько карт штампов у заведения. Правило id документа и отбор карт
/// повторены в `functions/src/index.ts` (`stampCardDocID`, `activeStampCards`)
/// и закреплены там тестом «CARDS: … зеркальное StampCards.swift».
final class StampCardsTests: XCTestCase {

    private let pizza = StampCard(id: "pizza", title: "Пицца", goal: 3, reward: "Пицца в подарок")

    // MARK: id документа

    func testFirstCardKeepsLegacyLedgerDocument() {
        // На этом документе уже накоплены штампы, и его читают клиенты,
        // которые о картах не знают.
        XCTAssertEqual(StampCards.ledgerDocID(userID: "u", venueID: "v", cardID: "default"), "u_v")
        XCTAssertEqual(StampCards.ledgerDocID(userID: "u", venueID: "v", cardID: ""), "u_v")
        XCTAssertEqual(StampCards.ledgerDocID(userID: "u", venueID: "v", cardID: "pizza"), "u_v_pizza")
    }

    // MARK: Активные карты

    func testDisabledProgramHasNoCards() {
        XCTAssertTrue(StampCards.active(enabled: false, title: "", goal: 6, reward: "Кофе",
                                        extras: [pizza]).isEmpty)
    }

    func testFirstCardComesFromScalarFieldsAndLeads() {
        let cards = StampCards.active(enabled: true, title: "Кофе", goal: 40, reward: "Кофе",
                                      extras: [pizza])
        XCTAssertEqual(cards.map(\.id), ["default", "pizza"])
        XCTAssertEqual(cards[0].title, "Кофе")
        XCTAssertEqual(cards[0].goal, 40, "первую карту сверху не зажимаем — как было до нескольких карт")
    }

    func testInactiveExtraIsHiddenButNotLost() {
        var off = pizza; off.active = false
        let venue = HostVenueDTO(id: "v", name: "П", categoryRaw: "cafe", district: "", address: "",
                                 phone: "", emoji: "🍕", latitude: 0, longitude: 0, openHour: 9,
                                 closeHour: 22, todaySpecial: nil, isPaused: false, isVerified: false,
                                 loyaltyEnabled: true, extraStampCards: [off])
        XCTAssertEqual(venue.stampCards.map(\.id), ["default"])
        XCTAssertEqual(venue.extraStampCards.count, 1, "выключенная карта хранится — её можно включить")
    }

    // MARK: Очистка перед сохранением

    func testSanitizeDropsBadCardsAndKeepsTheLimit() {
        let input: [StampCard] = [
            pizza,
            StampCard(id: "default", title: "", goal: 6, reward: "подмена первой"),
            StampCard(id: "bad/id", title: "", goal: 6, reward: "x"),
            StampCard(id: "empty", title: "", goal: 6, reward: "   "),
            StampCard(id: "pizza", title: "дубль", goal: 6, reward: "дубль"),
            StampCard(id: "a", title: "  Чай  ", goal: 1, reward: " Чай "),
            StampCard(id: "b", title: "", goal: 6, reward: "b"),
            StampCard(id: "c", title: "", goal: 6, reward: "c"),
            StampCard(id: "d", title: "", goal: 6, reward: "d"),
        ]
        let out = StampCards.sanitizedExtras(input)
        XCTAssertEqual(out.map(\.id), ["pizza", "a", "b", "c"],
                       "всего карт не больше \(StampCards.maxCards), считая первую")
        XCTAssertEqual(out[1].title, "Чай")
        XCTAssertEqual(out[1].reward, "Чай")
        XCTAssertEqual(out[1].goal, 2, "цель зажата снизу")
    }

    func testNewIDIsValidForAFirestoreDocumentName() {
        let id = StampCards.newID(random: { 123_456 })
        XCTAssertTrue(StampCards.isValidID(id))
        XCTAssertFalse(id.contains("_"), "подчёркивание разделяет части id документа")
    }

    // MARK: Форма заведения не затирает карты

    func testGeneralVenueFormKeepsStampCards() {
        var dto = HostVenueDTO(id: "v", name: "Пармезан", categoryRaw: "cafe", district: "",
                               address: "", phone: "", emoji: "🍕", latitude: 0, longitude: 0,
                               openHour: 9, closeHour: 22, todaySpecial: nil, isPaused: false,
                               isVerified: false, loyaltyEnabled: true)
        dto.loyaltyTitle = "Кофе"
        dto.extraStampCards = [pizza]
        // Общая форма собирает поля сама и о картах не знает (`nil`).
        var fields = HostForms.fields(from: dto)
        fields.loyaltyTitle = nil
        fields.extraStampCards = nil
        fields.name = "Пармезан 2"
        let saved = HostForms.venue(existing: dto, fields: fields, newID: "x")
        XCTAssertEqual(saved.name, "Пармезан 2")
        XCTAssertEqual(saved.loyaltyTitle, "Кофе")
        XCTAssertEqual(saved.extraStampCards, [pizza])
    }

    func testStampEditorReplacesCards() {
        let dto = HostVenueDTO(id: "v", name: "Пармезан", categoryRaw: "cafe", district: "",
                               address: "", phone: "", emoji: "🍕", latitude: 0, longitude: 0,
                               openHour: 9, closeHour: 22, todaySpecial: nil, isPaused: false,
                               isVerified: false, loyaltyEnabled: true, extraStampCards: [pizza])
        var fields = HostForms.fields(from: dto)
        fields.loyaltyTitle = "  Кофе  "
        fields.extraStampCards = []          // «удалить все дополнительные»
        let saved = HostForms.venue(existing: dto, fields: fields, newID: "x")
        XCTAssertEqual(saved.loyaltyTitle, "Кофе")
        XCTAssertTrue(saved.extraStampCards.isEmpty)
    }

    // MARK: Кэш

    func testOldCachedLoyaltyCardDecodesAsFirstCard() throws {
        let old = #"{"venueID":"v","venueName":"Кафе","stamps":3,"completedRounds":1,"goal":6,"reward":"Кофе"}"#
        let card = try JSONDecoder().decode(LoyaltyCard.self, from: Data(old.utf8))
        XCTAssertEqual(card.cardID, "default")
        XCTAssertEqual(card.id, "v", "у первой карты id — по-прежнему заведение")
        XCTAssertEqual(LoyaltyCard(venueID: "v", venueName: "", cardID: "pizza").id, "v#pizza")
    }
}

/// Кэш кабинета из сборки без карт не должен считаться «карт нет».
final class StampCardsCacheTests: XCTestCase {

    func testOldCachedVenueDoesNotClaimToKnowStampCards() throws {
        let old = #"{"id":"v","name":"Пармезан","loyaltyEnabled":true}"#
        let dto = try JSONDecoder().decode(HostVenueDTO.self, from: Data(old.utf8))
        XCTAssertFalse(dto.stampCardsLoaded, "иначе первое же сохранение стёрло бы карты в Firestore")
    }

    func testEditingCardsMarksCopyAsKnowing() throws {
        let old = #"{"id":"v","name":"Пармезан","loyaltyEnabled":true}"#
        let dto = try JSONDecoder().decode(HostVenueDTO.self, from: Data(old.utf8))
        var fields = HostForms.fields(from: dto)
        fields.extraStampCards = [StampCard(id: "pizza", title: "Пицца", goal: 5, reward: "Пицца")]
        XCTAssertTrue(HostForms.venue(existing: dto, fields: fields, newID: "x").stampCardsLoaded)
        // Общая форма карт не передаёт — и «знание» не появляется из ниоткуда.
        var general = HostForms.fields(from: dto)
        general.extraStampCards = nil
        XCTAssertFalse(HostForms.venue(existing: dto, fields: general, newID: "x").stampCardsLoaded)
    }

    func testCacheRoundTripKeepsTheFlag() throws {
        var dto = HostVenueDTO(id: "v", name: "П", categoryRaw: "cafe", district: "", address: "",
                               phone: "", emoji: "🍕", latitude: 0, longitude: 0, openHour: 9,
                               closeHour: 22, todaySpecial: nil, isPaused: false, isVerified: false)
        dto.stampCardsLoaded = true
        let back = try JSONDecoder().decode(HostVenueDTO.self, from: JSONEncoder().encode(dto))
        XCTAssertTrue(back.stampCardsLoaded)
    }
}
