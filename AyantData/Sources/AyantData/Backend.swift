import Foundation

/// Адреса вызываемых Cloud Functions.
///
/// Живут в слое данных: это часть контракта с бэкендом, а не настройка сборки.
/// `AppConfig.functionURL` остался тонкой обёрткой, чтобы вызовы в приложении
/// не пришлось править.
public enum AyantBackend {
    public static let functionsBaseURL = "https://us-central1-san-25d32.cloudfunctions.net"
    public static func functionURL(_ name: String) -> String { "\(functionsBaseURL)/\(name)" }
}
