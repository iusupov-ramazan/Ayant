import XCTest
@testable import AyantDomain

/// `remoteconfig.template.json` (то, что публикуется в консоль Firebase) и
/// ключи в коде — один контракт. Опечатка в шаблоне не ломает сборку: ключ
/// просто никогда не приходит, и консольная «ручка» молча ничего не делает.
/// Этот тест — единственное, что их связывает.
final class RemoteConfigTemplateTests: XCTestCase {

    /// Ключи шаблона: все параметры во всех группах и на верхнем уровне.
    private func templateKeys() throws -> Set<String> {
        // AyantDomain/Tests/AyantDomainTests/<этот файл> → корень репозитория.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("remoteconfig.template.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var keys = Set((json["parameters"] as? [String: Any] ?? [:]).keys)
        for (_, group) in json["parameterGroups"] as? [String: Any] ?? [:] {
            keys.formUnion(((group as? [String: Any])?["parameters"] as? [String: Any] ?? [:]).keys)
        }
        return keys
    }

    /// Ключи, которые читает код.
    private var codeKeys: Set<String> {
        var keys = Set(GameRates.Key.all)
        for game in BonusGame.allCases {
            keys.insert(game.remoteKey)
            keys.insert(game.dailyCapKey)
        }
        // searchTab / promote / appleWallet в шаблон намеренно не вынесены:
        // их нечем включить (нет оплаты, pass type ID, экрана карты), а
        // выключены они и так сборкой.
        let unpublished: Set<RemoteFeature> = [.searchTab, .promote, .appleWallet]
        for feature in RemoteFeature.allCases where !unpublished.contains(feature) {
            keys.insert(feature.remoteKey)
        }
        keys.insert(RemoteSettings.Key.timeEarningEnabled)
        keys.insert(RemoteSettings.Key.minimumVersion)
        keys.insert(RemoteSettings.Key.updateURL)
        return keys
    }

    func testEveryCodeKeyIsInTheTemplate() throws {
        let missing = codeKeys.subtracting(try templateKeys())
        XCTAssertTrue(missing.isEmpty, "в remoteconfig.template.json нет ключей: \(missing.sorted())")
    }

    func testTemplateHasNoKeysTheCodeDoesNotRead() throws {
        let unknown = try templateKeys().subtracting(codeKeys)
        XCTAssertTrue(unknown.isEmpty, "шаблон публикует ключи, которых код не читает (опечатка?): \(unknown.sorted())")
    }
}
