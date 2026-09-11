// swift-tools-version: 5.9
import PackageDescription

/// AyantFeatures — слой фич: сторы (`ObservableObject`), которыми пользуются экраны.
///
/// Зависит **только** от `AyantDomain`. Ни Firebase, ни `AyantData` сюда не
/// подключены, поэтому обращение к Firestore из стора — ошибка компоновки:
/// сторы работают с контрактами домена, а какие реализации за ними стоят,
/// решает композиционный корень приложения (`AppConfig` в цели SAN).
///
/// Зеркалит Gradle-модуль `android/feature`.
let package = Package(
    name: "AyantFeatures",
    // macOS указан только чтобы совпасть с доменом — пакет можно собрать
    // и проверить без симулятора; продукт всё равно едет в iOS-приложение.
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "AyantFeatures", targets: ["AyantFeatures"]),
    ],
    dependencies: [
        .package(path: "../AyantDomain"),
    ],
    targets: [
        .target(
            name: "AyantFeatures",
            dependencies: [.product(name: "AyantDomain", package: "AyantDomain")]
        ),
    ]
)
