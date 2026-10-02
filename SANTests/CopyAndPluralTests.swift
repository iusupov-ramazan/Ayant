import XCTest
import AyantFeatures
@testable import SAN

/// Тексты, которые раньше были сломаны: «1 активных купонов», «3 / 6» без
/// голоса, «%@ баллов» без склонения, кыргызское «чегерүү» (вычет) и для
/// начисления, и для списания, и общий «подарок уже забрали» на любую ошибку.
final class CopyAndPluralTests: XCTestCase {

    private var savedLanguage: String?

    override func setUp() {
        super.setUp()
        savedLanguage = UserDefaults.standard.string(forKey: AppLanguage.defaultsKey)
    }

    override func tearDown() {
        if let savedLanguage {
            UserDefaults.standard.set(savedLanguage, forKey: AppLanguage.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppLanguage.defaultsKey)
        }
        super.tearDown()
    }

    private func inLanguage(_ lang: String, _ body: () -> Void) {
        UserDefaults.standard.set(lang, forKey: AppLanguage.defaultsKey)
        body()
    }

    func testActiveCouponsInflectInRussian() {
        inLanguage("ru") {
            XCTAssertEqual(LF("%lld активных купонов", 1), "1 активный купон")
            XCTAssertEqual(LF("%lld активных купонов", 3), "3 активных купона")
            XCTAssertEqual(LF("%lld активных купонов", 5), "5 активных купонов")
            XCTAssertEqual(LF("%lld активных купонов", 21), "21 активный купон")
        }
    }

    func testStampProgressLabel() {
        inLanguage("ru") {
            XCTAssertEqual(LF("%lld из %lld штампов", 3, 6), "3 из 6 штампов")
            XCTAssertEqual(LF("%lld из %lld штампов", 3, 21), "3 из 21 штампа")
        }
        inLanguage("en") {
            XCTAssertEqual(LF("%lld из %lld штампов", 0, 1), "0 of 1 stamp")
            XCTAssertEqual(LF("%lld из %lld штампов", 3, 6), "3 of 6 stamps")
        }
    }

    func testHostPointsSummaries() {
        inLanguage("ru") {
            XCTAssertEqual(LF("%lld баллов за визит", 1), "1 балл за визит")
            XCTAssertEqual(LF("%lld баллов за визит", 2), "2 балла за визит")
            XCTAssertEqual(LF("от %lld баллов", 1), "от 1 балла")
            XCTAssertEqual(LF("от %lld баллов", 5), "от 5 баллов")
        }
        inLanguage("en") {
            XCTAssertEqual(LF("Обменять за %lld бонусов", 1), "Get for 1 bonus")
            XCTAssertEqual(LF("%lld баллов за визит", 10), "10 points per visit")
        }
    }

    func testGiftClaimErrorsAreNotAllReadAsAlreadyClaimed() {
        let retry = "Не получилось забрать подарок. Откройте ссылку ещё раз через минуту — подарок никуда не денется."
        XCTAssertEqual(AppStore.giftClaimMessage(forError: "no_wallet"), retry)
        XCTAssertEqual(AppStore.giftClaimMessage(forError: "claim_failed"), retry)
        XCTAssertEqual(AppStore.giftClaimMessage(forError: "anonymous_not_allowed"),
                       "Войдите в аккаунт, чтобы забрать подарок.")
        XCTAssertEqual(AppStore.giftClaimMessage(forError: "app_check_failed"),
                       "Обновите приложение, чтобы забрать подарок.")
        XCTAssertEqual(AppStore.giftClaimMessage(forError: "already_claimed"),
                       "Этот подарок уже забрали или ссылка недействительна")
        XCTAssertEqual(AppStore.giftClaimMessage(forError: "not_found"),
                       "Этот подарок уже забрали или ссылка недействительна")
    }

    // MARK: Каталог целиком

    private func catalog() throws -> [String: [String: Any]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SAN/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(root["strings"] as? [String: [String: Any]])
    }

    private static func isPlural(_ loc: Any?) -> Bool {
        guard let loc = loc as? [String: Any] else { return false }
        if let v = loc["variations"] as? [String: Any], v["plural"] != nil { return true }
        return loc["substitutions"] != nil
    }

    /// Если английский склоняет ключ по числу, русский — тоже: иначе
    /// «1 активных купонов» при правильном «1 active coupon».
    func testEveryEnglishPluralHasRussianPlural() throws {
        var offenders: [String] = []
        for (key, entry) in try catalog() {
            let loc = entry["localizations"] as? [String: Any] ?? [:]
            if Self.isPlural(loc["en"]), !Self.isPlural(loc["ru"]), key != "%lld акц." {
                offenders.append(key)
            }
        }
        XCTAssertEqual(offenders.sorted(), [])
    }

    /// «Чегерүү» — вычет. Им переводили и «начислено», и «списано».
    func testKyrgyzDoesNotUseDeductionVerb() throws {
        var offenders: [String] = []
        for (key, entry) in try catalog() {
            guard let ky = (entry["localizations"] as? [String: Any])?["ky"] as? [String: Any],
                  let value = (ky["stringUnit"] as? [String: Any])?["value"] as? String else { continue }
            if value.lowercased().contains("чегер") { offenders.append(key) }
        }
        XCTAssertEqual(offenders.sorted(), [])
    }
}
