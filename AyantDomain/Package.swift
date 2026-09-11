// swift-tools-version: 5.9
import PackageDescription

/// AyantDomain — чистое ядро приложения: модели, чистые функции (Ranking,
/// PointsMath, FeedAssembly, ReviewStats) и контракты репозиториев.
///
/// Модуль намеренно не зависит НИ ОТ ЧЕГО, кроме Foundation: ни SwiftUI, ни
/// FirebaseFirestore сюда не подключены, поэтому попытка их импортировать —
/// ошибка компиляции, а не замечание на ревью. Граница слоёв держится сборкой.
///
/// Тесты гоняются на macOS без симулятора (`swift test --package-path AyantDomain`),
/// поэтому весь код здесь обязан быть платформонезависимым.
///
/// Зеркалит Gradle-модуль `android/domain`.
let package = Package(
    name: "AyantDomain",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "AyantDomain", targets: ["AyantDomain"]),
    ],
    targets: [
        .target(name: "AyantDomain"),
        .testTarget(name: "AyantDomainTests", dependencies: ["AyantDomain"]),
    ]
)
