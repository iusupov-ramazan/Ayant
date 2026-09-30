import Foundation

// MARK: - Адреса заведения

/// Все адреса заведения одним списком — без «главного» и «филиалов».
///
/// В Firestore адреса по-прежнему лежат двумя частями: первый — в полях
/// заведения (`address`/`latitude`/`longitude`), остальные — в `branches`.
/// Схему не трогаем: Android, админ-панель и уже установленные сборки читают
/// именно её. Но показывать это разделение незачем — для гостя и хозяина
/// «Манаса, 57» ничем не главнее «Токтогула, 93». Здесь обе части сводятся
/// в один список, и экраны работают только с ним.
///
/// У первого адреса нет своего id в данных, поэтому он всегда `firstID`:
/// на него ссылаются акции (`Deal.locationIDs`), и id должен быть стабильным.
public enum VenueLocations {
    /// id первого адреса (того, что хранится в полях самого заведения).
    public static let firstID = "main"

    /// Первый адрес + дополнительные, без пустых.
    public static func all(address: String, latitude: Double, longitude: Double,
                           branches: [Branch]) -> [Branch] {
        let first = Branch(id: firstID, address: address.trimmingCharacters(in: .whitespaces),
                           latitude: latitude, longitude: longitude)
        return ([first] + branches).filter { !$0.address.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Адреса, где действует акция, — или `nil`, если везде.
    ///
    /// «Везде» — это и пустой список, и список, покрывающий все адреса, и
    /// список из одних удалённых адресов: акция, чей единственный адрес
    /// хозяин потом удалил, не должна пропасть или соврать гостю «только
    /// по адресу …», которого больше нет. Порядок — как у адресов заведения.
    public static func restricted(to ids: [String], in locations: [Branch]) -> [Branch]? {
        guard !ids.isEmpty else { return nil }
        let wanted = Set(ids)
        let matched = locations.filter { wanted.contains($0.id) }
        if matched.isEmpty || matched.count == locations.count { return nil }
        return matched
    }
}

extension Venue {
    /// Все адреса заведения (см. `VenueLocations`).
    public var locations: [Branch] {
        VenueLocations.all(address: address, latitude: latitude, longitude: longitude, branches: branches)
    }

    /// Адреса, где действует акция, или `nil` — во всех.
    public func locations(for deal: Deal) -> [Branch]? {
        VenueLocations.restricted(to: deal.locationIDs, in: locations)
    }
}

extension HostVenueDTO {
    /// Все адреса заведения (см. `VenueLocations`).
    public var locations: [Branch] {
        VenueLocations.all(address: address, latitude: latitude, longitude: longitude, branches: branches)
    }
}
