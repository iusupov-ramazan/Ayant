import Foundation
import CoreLocation
import UIKit

/// Управляет «while using» геолокацией. Публикует только последнюю позицию —
/// история не хранится (по спецификации). Если доступ не выдан — расстояния скрыты.
@MainActor
final class LocationManager: NSObject, ObservableObject {

    @Published private(set) var lastLocation: CLLocationCoordinate2D?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Доступ выдан (while using или always).
    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// Запрос «при использовании». Безопасно вызывать повторно.
    func request() {
        manager.requestWhenInUseAuthorization()
    }

    /// Обновить позицию при открытии приложения.
    func refresh() {
        guard isAuthorized else { return }
        manager.requestLocation()
    }

    // MARK: - Расстояние (Haversine, км)

    /// Расстояние от пользователя до точки. nil — если позиция неизвестна.
    func distanceKm(to lat: Double, _ lng: Double) -> Double? {
        guard let me = lastLocation else { return nil }
        return Self.haversine(me.latitude, me.longitude, lat, lng)
    }

    static func haversine(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6371.0 // радиус Земли, км
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if self.isAuthorized { manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        Task { @MainActor in self.lastLocation = coord }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Тихо игнорируем — расстояния просто останутся скрытыми.
    }
}

// MARK: - Форматирование расстояния

extension Double {
    /// «0.8 км» / «1.2 км» / «350 м».
    var distanceText: String {
        if self < 1 { return "\(Int((self * 1000).rounded())) м" }
        return String(format: "%.1f км", self)
    }
}

// MARK: - Deep-link маршрутов (2GIS → Google Maps фолбэк)

enum Directions {
    /// URL для построения маршрута. 2GIS если установлен, иначе Google Maps.
    static func url(lat: Double, lng: Double) -> URL {
        let dgis = URL(string: "dgis://2gis.ru/routeSearch/to/\(lng),\(lat)/go")
        if let dgis, UIApplicationOpenChecker.canOpen(dgis) { return dgis }
        return URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lng)")!
    }

    /// Прямая ссылка на 2GIS (кнопка «2GIS»).
    static func dgis(lat: Double, lng: Double) -> URL {
        URL(string: "dgis://2gis.ru/routeSearch/to/\(lng),\(lat)/go")
            ?? URL(string: "https://2gis.ru")!
    }

    /// Прямая ссылка на Google Maps (кнопка «Google Maps»).
    static func google(lat: Double, lng: Double) -> URL {
        URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lng)")!
    }
}

enum UIApplicationOpenChecker {
    static func canOpen(_ url: URL) -> Bool {
        UIApplication.shared.canOpenURL(url)
    }
}
