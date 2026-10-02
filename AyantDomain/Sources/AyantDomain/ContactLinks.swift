import Foundation

/// Ссылки на мессенджеры и соцсети заведения из того, что ввёл хозяин.
///
/// Хозяева пишут контакты как попало: «0555 123 456», «+996 (555) 12-34-56»,
/// «@navat», «instagram.com/navat», «https://t.me/navat». Раньше
/// `instagramURL` для «instagram.com/navat» давал
/// `https://instagram.com/instagram.com/navat`, а местный номер «0555…»
/// уходил в wa.me без кода страны — WhatsApp такой номер не находит.
public enum ContactLinks {

    /// Код страны по умолчанию — каталог пока только в Кыргызстане.
    public static let defaultCountryCode = "996"

    /// wa.me принимает только международный номер цифрами, без «+» и нулей.
    public static func whatsapp(_ raw: String, countryCode: String = defaultCountryCode) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Уже ссылка (wa.me/…, api.whatsapp.com/…) — открываем как есть.
        if let url = webURL(trimmed, hosts: ["wa.me", "api.whatsapp.com", "whatsapp.com"]) { return url }
        var digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        if digits.hasPrefix("00") { digits.removeFirst(2) }              // 00996… → 996…
        else if trimmed.hasPrefix("+") { /* уже международный */ }
        else if digits.hasPrefix(countryCode) && digits.count > 9 { /* 996… без «+» */ }
        else if digits.hasPrefix("0") { digits = countryCode + digits.dropFirst() }  // 0555… → 996555…
        else if digits.count == 9 { digits = countryCode + digits }      // 555123456 → 996555123456
        guard digits.count >= 10 else { return nil }
        return URL(string: "https://wa.me/\(digits)")
    }

    public static func instagram(_ raw: String) -> URL? {
        profile(raw, host: "instagram.com", knownHosts: ["instagram.com", "www.instagram.com", "instagr.am"])
    }

    public static func telegram(_ raw: String) -> URL? {
        profile(raw, host: "t.me", knownHosts: ["t.me", "telegram.me", "www.t.me"])
    }

    // MARK: - Внутреннее

    /// «@name», «name», «instagram.com/name», «https://instagram.com/name».
    private static func profile(_ raw: String, host: String, knownHosts: [String]) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = webURL(trimmed, hosts: knownHosts) { return url }
        // Чужая полная ссылка (linktr.ee/…) — тоже открываем как есть.
        if trimmed.lowercased().hasPrefix("http") { return URL(string: trimmed) }
        var handle = trimmed
        while handle.hasPrefix("@") { handle.removeFirst() }
        handle = handle.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !handle.isEmpty,
              handle.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }),
              let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        else { return nil }
        return URL(string: "https://\(host)/\(encoded)")
    }

    /// Ввод, который уже содержит один из `hosts` (со схемой или без), → https-ссылка.
    private static func webURL(_ text: String, hosts: [String]) -> URL? {
        var rest = text
        let lower = rest.lowercased()
        if lower.hasPrefix("https://") { rest.removeFirst(8) }
        else if lower.hasPrefix("http://") { rest.removeFirst(7) }
        let restLower = rest.lowercased()
        guard hosts.contains(where: { restLower == $0 || restLower.hasPrefix($0 + "/") }) else {
            return nil
        }
        return URL(string: "https://\(rest)")
    }
}
