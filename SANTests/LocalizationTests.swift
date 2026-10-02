import XCTest
import SwiftUI
@testable import SAN

/// Счётные строки каталога: «1 бонус / 3 бонуса / 5 бонусов / 21 бонус».
///
/// До 2026-10 в каталоге не было ни одной plural-вариации, и интерфейс писал
/// «+1 бонусов», «2 линий», «1 bonuses». Тест держит две вещи сразу: что формы
/// лежат в каталоге (а значит, скомпилированы в `*.lproj/Localizable.stringsdict`)
/// и что `LF` выбирает форму по правилу языка ПРИЛОЖЕНИЯ, а не системы
/// (`String(format:)` без `locale:` на английском симуляторе давал «5 бонуса»).
final class LocalizationTests: XCTestCase {

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

    func testRussianBonusPlurals() {
        inLanguage("ru") {
            XCTAssertEqual(LF("%lld бонусов", 1), "1 бонус")
            XCTAssertEqual(LF("%lld бонусов", 3), "3 бонуса")
            XCTAssertEqual(LF("%lld бонусов", 5), "5 бонусов")
            XCTAssertEqual(LF("%lld бонусов", 11), "11 бонусов")
            XCTAssertEqual(LF("%lld бонусов", 21), "21 бонус")
            XCTAssertEqual(LF("%lld бонусов", 0), "0 бонусов")
            XCTAssertEqual(LF("+%lld баллов", 22), "+22 балла")
            XCTAssertEqual(LF("%lld линий = 1 бонус", 3), "3 линии = 1 бонус")
            XCTAssertEqual(LF("Списано %lld мин назад", 1), "Списано 1 минуту назад")
        }
    }

    func testEnglishPlurals() {
        inLanguage("en") {
            XCTAssertEqual(LF("%lld бонусов", 1), "1 bonus")
            XCTAssertEqual(LF("%lld бонусов", 3), "3 bonuses")
            XCTAssertEqual(LF("%lld бонусов", 21), "21 bonuses")
            XCTAssertEqual(LF("+%lld баллов", 1), "+1 point")
            // Ключ, выбранный по русскому правилу (21 → «one»), всё равно
            // получает английскую форму по английскому правилу.
            XCTAssertEqual(LF("%lld активный купон", 21), "21 active coupons")
        }
    }

    /// Ключи с несколькими аргументами: склоняется только счётный, а остальные
    /// читаются из своих позиций (непозиционный %lld после подстановки читал
    /// первый аргумент — «(+1 в пути)» вместо «(+7 в пути)»).
    func testMultiArgumentPlurals() {
        inLanguage("ru") {
            XCTAssertEqual(LF("%lld бонусов (+%lld в пути)", 5, 7), "5 бонусов (+7 в пути)")
            XCTAssertEqual(LF("%lld бонусов (+%lld в пути)", 1, 7), "1 бонус (+7 в пути)")
            XCTAssertEqual(LF("Линий: %lld → +%lld бонусов", 9, 2), "Линий: 9 → +2 бонуса")
            XCTAssertEqual(LF("Списано %lld баллов (−%lld сом). Остаток: %lld.", 1, 50, 40),
                           "Списан 1 балл (−50 сом). Остаток: 40.")
            XCTAssertEqual(LF("«%@» за %lld бонусов. Купон нельзя вернуть после обмена.", "Кофе", 21),
                           "«Кофе» за 21 бонус. Купон нельзя вернуть после обмена.")
        }
        inLanguage("en") {
            XCTAssertEqual(LF("%lld бонусов (+%lld в пути)", 1, 7), "1 bonus (+7 syncing)")
        }
    }

    func testKyrgyzHasNoNumberInflection() {
        inLanguage("ky") {
            XCTAssertEqual(LF("%lld бонусов", 1), "1 бонус")
            XCTAssertEqual(LF("%lld бонусов", 5), "5 бонус")
        }
    }

    /// Путь SwiftUI: `Text("+\(n) бонусов")` строит ключ «+%lld бонусов» и ищет
    /// его в бандле языка из `\.locale`. Проверяем тем же механизмом
    /// (`String(localized:)` с интерполяцией), что ключ совпадает и форма выбирается.
    func testInterpolatedKeyResolvesPlural() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "ru", ofType: "lproj"),
                                 "ru.lproj должен собираться: в нём plural-формы языка-источника")
        let ru = try XCTUnwrap(Bundle(path: path))
        for (n, expected) in [(1, "+1 бонус"), (3, "+3 бонуса"), (5, "+5 бонусов"), (21, "+21 бонус")] {
            let value = String(localized: "+\(n) бонусов", bundle: ru, locale: Locale(identifier: "ru_RU"))
            XCTAssertEqual(value, expected)
        }
    }

    /// Обычные (не счётные) ключи на русском по-прежнему возвращают сам ключ.
    func testPlainRussianKeyIsUnchanged() {
        inLanguage("ru") {
            XCTAssertEqual(LS("Магазин купонов"), "Магазин купонов")
        }
        inLanguage("en") {
            XCTAssertEqual(LS("Магазин купонов"), "Coupon shop")
        }
    }
}

/// `Font.golos` масштабируется Dynamic Type, а витринные размеры — нет.
@MainActor
final class TypographyTests: XCTestCase {

    private func width(_ font: Font) -> CGFloat {
        let renderer = ImageRenderer(content: Text("Бонусы за игры").font(font).fixedSize())
        renderer.scale = 1
        return renderer.uiImage?.size.width ?? 0
    }

    func testDefaultSettingKeepsDesignSizes() {
        for size: CGFloat in [11, 12, 13, 14, 15, 16, 17, 20, 22, 28, 44] {
            XCTAssertEqual(Font.scaledSize(size, category: .large), size)
        }
    }

    func testTextGrowsAndShrinksWithSetting() {
        XCTAssertGreaterThan(Font.scaledSize(17, category: .accessibilityMedium), 17 * 1.5)
        XCTAssertGreaterThan(Font.scaledSize(13, category: .extraExtraLarge), 13)
        XCTAssertLessThan(Font.scaledSize(17, category: .extraSmall), 17)
    }

    /// Дальше AX2 не растёт — иначе фиксированные рамки карточек разваливаются.
    func testGrowthIsCappedAtAX2() {
        let ax2 = Font.scaledSize(17, category: .accessibilityLarge)
        XCTAssertEqual(Font.scaledSize(17, category: .accessibilityExtraExtraExtraLarge), ax2)
    }

    func testDisplaySizesDoNotScale() {
        XCTAssertEqual(Font.scaledSize(44, category: .accessibilityLarge), 44)
        XCTAssertEqual(Font.scaledSize(30, category: .accessibilityLarge), 30)
    }

    /// Больший макетный размер никогда не даёт меньший экранный: раньше 29 pt шёл
    /// по кривой .title и на AX2 был ~44 pt, а 30-пунктовый заголовок — 30.
    func testScalingIsMonotonicAndCappedBelowDisplayTier() {
        let categories: [UIContentSizeCategory] = [
            .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge,
            .extraExtraExtraLarge, .accessibilityMedium, .accessibilityLarge,
            .accessibilityExtraLarge, .accessibilityExtraExtraExtraLarge,
        ]
        for category in categories {
            var previous: CGFloat = 0
            for step in 16...140 {
                let size = CGFloat(step) / 4   // 4…35 pt шагом 0.25
                let shown = Font.scaledSize(size, category: category)
                XCTAssertGreaterThanOrEqual(shown, previous - 0.001, "\(category.rawValue) @ \(size)")
                if size < Font.displayFloor {
                    XCTAssertLessThanOrEqual(shown, Font.displayFloor, "\(category.rawValue) @ \(size)")
                }
                previous = shown
            }
        }
        XCTAssertLessThanOrEqual(Font.scaledSize(29, category: .accessibilityLarge),
                                 Font.scaledSize(30, category: .accessibilityLarge))
    }

    /// Модификатор `.golos` и `Font.golos` считают одно и то же при одной настройке.
    func testViewModifierMatchesFontAtSameSetting() {
        let viaFont = ImageRenderer(content: Text("Бонусы за игры")
            .font(.system(size: Font.scaledSize(15, category: .large), weight: .semibold)).fixedSize())
        let viaModifier = ImageRenderer(content: Text("Бонусы за игры").golos(15, .semibold)
            .fixedSize().environment(\.dynamicTypeSize, .large))
        viaFont.scale = 1; viaModifier.scale = 1
        XCTAssertEqual(viaFont.uiImage?.size.width ?? 0, viaModifier.uiImage?.size.width ?? -1, accuracy: 0.5)
    }

    /// Это по-прежнему системный SF Pro нужного начертания (а не подмена шрифта:
    /// `Font.custom` с системным именем CoreText отдаёт Times New Roman).
    func testRendersSystemFontWithWeight() {
        let size = Font.scaledSize(15)
        XCTAssertEqual(width(.golos(15, .semibold)), width(.system(size: size, weight: .semibold)), accuracy: 0.5)
        XCTAssertGreaterThan(width(.golos(17, .heavy)), width(.golos(17, .regular)))
    }
}
