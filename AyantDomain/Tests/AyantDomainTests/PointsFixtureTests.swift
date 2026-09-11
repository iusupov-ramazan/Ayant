import XCTest
@testable import AyantDomain

/// Прогон общего фикстура `specs/fixtures/points-fixtures.json` через `PointsMath`.
///
/// Тот же файл гоняют Android (`PointsFixtureTest.kt`) и сервер
/// (`functions/test/fixtures.test.js`). Это единственное место, где ловится
/// расхождение трёх реализаций математики баллов: ошибка в округлении кэшбэка не
/// падает тестом «на глаз», а всплывает через недели жалобой заведения — уже в сомах.
///
/// Новый кейс добавляется **в JSON**, а не сюда: иначе он проверит одну платформу
/// из трёх, ради чего фикстур и заводился.
final class PointsFixtureTests: XCTestCase {

    // MARK: Загрузка

    /// Фикстур лежит в репозитории, а не в бандле теста: его читают три разных
    /// сборки, у каждой свой способ упаковки ресурсов. `#filePath` даёт путь к
    /// этому исходнику на момент компиляции — от него и отсчитываем корень репо.
    private static let fixtureURL: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // AyantDomainTests/
        .deletingLastPathComponent()   // Tests/
        .deletingLastPathComponent()   // AyantDomain/
        .deletingLastPathComponent()   // корень репозитория
        .appendingPathComponent("specs/fixtures/points-fixtures.json")

    private lazy var fixture: Fixture = {
        guard let data = try? Data(contentsOf: Self.fixtureURL) else {
            XCTFail("Фикстур не найден: \(Self.fixtureURL.path)")
            return Fixture.empty
        }
        do {
            return try JSONDecoder().decode(Fixture.self, from: data)
        } catch {
            XCTFail("Фикстур не разбирается: \(error)")
            return Fixture.empty
        }
    }()

    // MARK: Константы

    func testConstantsMatchFixture() {
        let c = fixture.constants
        XCTAssertEqual(PointsMath.maxPointsPerEarn, c.maxPointsPerEarn)
        XCTAssertEqual(PointsMath.maxCashbackPercent, c.maxCashbackPercent)
        XCTAssertEqual(PointsMath.defaultEarnCooldownMinutes, c.defaultEarnCooldownMinutes)
        XCTAssertEqual(PointsMath.defaultStampCooldownMinutes, c.defaultStampCooldownMinutes)
        XCTAssertEqual(PointsMath.defaultExpiryMonths, c.defaultExpiryMonths)
    }

    // MARK: Начисление

    func testAwardCases() {
        XCTAssertFalse(fixture.award.isEmpty, "В фикстуре нет кейсов начисления")
        for c in fixture.award {
            let result = PointsMath.award(config: c.config.toConfig(),
                                          billAmount: c.billAmount,
                                          bandIndex: c.bandIndex)
            switch result {
            case .success(let points):
                XCTAssertNil(c.expect.error, "«\(c.name)»: ожидалась ошибка \(c.expect.error ?? ""), начислено \(points)")
                XCTAssertEqual(points, c.expect.points, "«\(c.name)»: неверное начисление")
            case .failure(let error):
                XCTAssertNil(c.expect.points, "«\(c.name)»: ожидалось \(c.expect.points ?? 0) баллов, отказ \(error.code)")
                XCTAssertEqual(error.code, c.expect.error, "«\(c.name)»: неверный код отказа")
            }
        }
    }

    // MARK: Кулдаун

    func testCooldownCases() {
        XCTAssertFalse(fixture.cooldown.isEmpty, "В фикстуре нет кейсов кулдауна")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        for c in fixture.cooldown {
            let last = c.minutesSinceLastEarn.map { now.addingTimeInterval(-Double($0) * 60) }
            let can = PointsMath.canEarn(lastEarnAt: last,
                                         cooldownMinutes: c.earnCooldownMinutes,
                                         now: now)
            XCTAssertEqual(can, c.expect.canEarn, "«\(c.name)»: неверное решение по кулдауну")
        }
    }

    /// Обратный отсчёт до следующего начисления — чисто клиентская математика
    /// (сервер её не считает), поэтому в фикстуре её нет.
    func testCooldownRemainingSeconds() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(PointsMath.cooldownRemainingSeconds(lastEarnAt: nil, cooldownMinutes: 60, now: now), 0)
        XCTAssertEqual(PointsMath.cooldownRemainingSeconds(lastEarnAt: now.addingTimeInterval(-600),
                                                           cooldownMinutes: 60, now: now), 3000)
        XCTAssertEqual(PointsMath.cooldownRemainingSeconds(lastEarnAt: now.addingTimeInterval(-3600),
                                                           cooldownMinutes: 60, now: now), 0)
        // Отрицательный кулдаун отключён — ждать нечего.
        XCTAssertEqual(PointsMath.cooldownRemainingSeconds(lastEarnAt: now, cooldownMinutes: -5, now: now), 0)
    }

    // MARK: Списание

    func testRedeemCases() {
        XCTAssertFalse(fixture.redeem.isEmpty, "В фикстуре нет кейсов списания")
        for c in fixture.redeem {
            switch PointsMath.findReward(in: c.rewards, id: c.rewardId) {
            case .failure(let error):
                XCTAssertEqual(error.code, c.expect.error, "«\(c.name)»: неверный код отказа поиска награды")
                continue
            case .success(let reward):
                let result = PointsMath.redeemCost(reward: reward,
                                                   pointsToSpend: c.pointsToSpend,
                                                   balance: c.balance)
                switch result {
                case .success(let cost):
                    XCTAssertNil(c.expect.error, "«\(c.name)»: ожидалась ошибка \(c.expect.error ?? ""), списано \(cost)")
                    XCTAssertEqual(cost, c.expect.cost, "«\(c.name)»: неверное списание")
                    XCTAssertEqual(c.balance - cost, c.expect.newBalance, "«\(c.name)»: неверный остаток")
                    XCTAssertEqual(PointsMath.somOff(reward: reward, cost: cost), c.expect.somOff,
                                   "«\(c.name)»: неверная скидка в сомах")
                case .failure(let error):
                    XCTAssertNil(c.expect.cost, "«\(c.name)»: ожидалось списание \(c.expect.cost ?? 0), отказ \(error.code)")
                    XCTAssertEqual(error.code, c.expect.error, "«\(c.name)»: неверный код отказа")
                    if case .belowMin(let minRedeem) = error {
                        XCTAssertEqual(minRedeem, c.expect.minRedeem, "«\(c.name)»: неверный минимум к списанию")
                    }
                }
            }
        }
    }
}

// MARK: - Разбор фикстура

/// Ключи с `$` (комментарии внутри JSON) декодер игнорирует как неизвестные.
private struct Fixture: Decodable {
    let version: Int
    let constants: Constants
    let award: [AwardCase]
    let cooldown: [CooldownCase]
    let redeem: [RedeemCase]

    static let empty = Fixture(version: 0,
                               constants: Constants(maxPointsPerEarn: 0, maxCashbackPercent: 0,
                                                    defaultEarnCooldownMinutes: 0,
                                                    defaultStampCooldownMinutes: 0,
                                                    defaultExpiryMonths: 0),
                               award: [], cooldown: [], redeem: [])
}

private struct Constants: Decodable {
    let maxPointsPerEarn: Int
    let maxCashbackPercent: Double
    let defaultEarnCooldownMinutes: Int
    let defaultStampCooldownMinutes: Int
    let defaultExpiryMonths: Int
}

/// Поля конфига опциональны: кейс задаёт только то, что для него важно, остальное
/// берётся из дефолтов `PointsConfig` — ровно как отсутствующее поле в Firestore.
private struct ConfigJSON: Decodable {
    let pointsEnabled: Bool?
    let pointsMode: String?
    let pointsFlat: Int?
    let pointsBands: [PointsBand]?
    let cashbackPercent: Double?
    let earnCooldownMinutes: Int?

    func toConfig() -> PointsConfig {
        var config = PointsConfig()
        if let pointsEnabled { config.pointsEnabled = pointsEnabled }
        if let pointsMode { config.pointsMode = pointsMode }
        if let pointsFlat { config.pointsFlat = pointsFlat }
        if let pointsBands { config.pointsBands = pointsBands }
        if let cashbackPercent { config.cashbackPercent = cashbackPercent }
        if let earnCooldownMinutes { config.earnCooldownMinutes = earnCooldownMinutes }
        return config
    }
}

private struct ExpectJSON: Decodable {
    let points: Int?
    let error: String?
    let canEarn: Bool?
    let minRedeem: Int?
    let cost: Int?
    let newBalance: Int?
    let somOff: Int?
}

private struct AwardCase: Decodable {
    let name: String
    let config: ConfigJSON
    let billAmount: Int?
    let bandIndex: Int?
    let expect: ExpectJSON
}

private struct CooldownCase: Decodable {
    let name: String
    let earnCooldownMinutes: Int
    let minutesSinceLastEarn: Int?
    let expect: ExpectJSON
}

private struct RedeemCase: Decodable {
    let name: String
    let rewards: [PointsReward]
    let rewardId: String
    let pointsToSpend: Int
    let balance: Int
    let expect: ExpectJSON
}
