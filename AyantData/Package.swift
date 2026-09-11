// swift-tools-version: 5.9
import PackageDescription

/// AyantData — слой данных: реализации доменных контрактов.
///
/// Единственный модуль, которому разрешён Firebase SDK: зависимости на
/// Firestore / Auth / Messaging / Analytics объявлены здесь и **не** попадают
/// ни в `AyantFeatures`, ни в приложение. Поэтому обращение к Firestore из
/// экрана или стора — ошибка компоновки, а не замечание на ревью.
///
/// Внутри — пары `Mock*` / `Firebase*` для каждого контракта, схема Firestore
/// (`FS`) и мапперы документов. Имена полей живут ровно в одном месте, как и на
/// Android (`data/firestore/FirestoreSchema.kt`).
///
/// Зеркалит Gradle-модуль `android/data`.
let package = Package(
    name: "AyantData",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AyantData", targets: ["AyantData"]),
    ],
    dependencies: [
        .package(path: "../AyantDomain"),
        // Версии совпадают с требованиями самого проекта (см. pbxproj):
        // SwiftPM сводит их к одному разрешению, второй копии SDK не появляется.
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "12.14.0"),
        .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "9.1.0"),
    ],
    targets: [
        .target(
            name: "AyantData",
            dependencies: [
                .product(name: "AyantDomain", package: "AyantDomain"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseCore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseMessaging", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
            ]
        ),
    ]
)
