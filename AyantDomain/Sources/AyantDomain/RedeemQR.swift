import Foundation

/// QR списания баллов САН, который гость показывает сотруднику:
/// `AYANT-RDM:<userID>:<rewardID>:<points>:<nonce>`.
///
/// `nonce` — один на попытку (открыл экран награды — новый код). Сервер
/// (`redeemVenuePoints`) делает из него ключ идемпотентности `rdm_<nonce>`,
/// поэтому любой повторный скан того же QR — второй сотрудник, второй тап,
/// скриншот — возвращает первый результат, а не списывает баллы ещё раз.
/// Раньше ключ генерировал сканер на каждый скан, и один QR гасился дважды.
///
/// `points` — сколько списать для money-награды; для item-награды `0`.
/// Старые коды из 3–4 частей (без nonce) по-прежнему разбираются.
///
/// **Новый формат (аудит запуска 2026-10-01): `AYANT-RDT:<token>`.** В старом
/// QR стоит uid гостя — а он же стоит в QR начисления, который гость показывает
/// у каждой кассы. Зная чужой uid, можно было собрать QR списания и потратить
/// чужие баллы. Теперь гость просит у сервера (`issueRedeemToken`) одноразовый
/// токен на эту награду в этом заведении; QR несёт только его, живёт он
/// `tokenTTL` и гасится один раз (`redeemVenuePoints`, ключ `rdm_<token>`).
/// Старый формат сканер по-прежнему принимает — для гостей со старой сборкой,
/// пока сервер не включит `REDEEM_REQUIRE_TOKEN`.
public enum RedeemQR {
    public static let prefix = "AYANT-RDM:"
    /// Префикс QR с токеном списания.
    public static let tokenPrefix = "AYANT-RDT:"
    /// Сколько живёт токен (как `REDEEM_TOKEN_TTL_MS` на сервере).
    public static let tokenTTL: TimeInterval = 180
    /// За сколько до истечения экран гостя просит новый токен — чтобы
    /// сотрудник не отсканировал код, который истечёт по дороге на сервер.
    public static let refreshLead: TimeInterval = 20

    /// Что распознал сканер сотрудника.
    public enum Scanned: Equatable {
        /// Новый QR: только токен, всё остальное сервер знает сам.
        case token(String)
        /// Старый QR с uid гостя.
        case legacy(userID: String, rewardID: String, points: Int, nonce: String?)
    }

    public static func tokenCode(_ token: String) -> String { "\(tokenPrefix)\(token)" }

    /// Токен из QR `AYANT-RDT:<token>`; `nil` — не наш код.
    public static func parseToken(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.hasPrefix(tokenPrefix) else { return nil }
        let token = String(code.dropFirst(tokenPrefix.count))
        return isValidToken(token) ? token : nil
    }

    /// Те же правила, что у сервера (`REDEEM_TOKEN_RE`): 20…64 символа [A-Za-z0-9_-].
    public static func isValidToken(_ t: String) -> Bool {
        guard t.count >= 20, t.count <= 64 else { return false }
        return t.unicodeScalars.allSatisfy {
            ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "_" || $0 == "-"
        }
    }

    /// Любой из двух форматов QR списания.
    public static func scan(_ raw: String) -> Scanned? {
        if let t = parseToken(raw) { return .token(t) }
        if let p = parse(raw) { return .legacy(userID: p.userID, rewardID: p.rewardID, points: p.points, nonce: p.nonce) }
        return nil
    }

    /// Через сколько секунд просить новый токен: за `refreshLead` до истечения,
    /// не раньше чем сейчас.
    public static func refreshDelay(expiresAt: Date, now: Date) -> TimeInterval {
        max(0, expiresAt.timeIntervalSince(now) - refreshLead)
    }

    /// Секунд до истечения (для обратного отсчёта на экране), не меньше нуля.
    public static func secondsLeft(expiresAt: Date, now: Date) -> Int {
        max(0, Int(expiresAt.timeIntervalSince(now).rounded(.up)))
    }
    /// Минимальная длина nonce — и на сервере (`REDEEM_NONCE_RE`).
    public static let minNonceLength = 12

    public static func code(userID: String, rewardID: String, points: Int, nonce: String) -> String {
        "\(prefix)\(userID):\(rewardID):\(max(0, points)):\(nonce)"
    }

    /// Свежий nonce: 16 символов [a-z0-9] из UUID — без двоеточий.
    public static func newNonce() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16))
    }

    public static func parse(_ raw: String) -> (userID: String, rewardID: String, points: Int, nonce: String?)? {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.hasPrefix(prefix) else { return nil }
        let parts = code.dropFirst(prefix.count).split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, parts.count <= 4 else { return nil }
        let userID = parts[0], rewardID = parts[1]
        guard !userID.isEmpty, !rewardID.isEmpty else { return nil }
        var points = 0
        if parts.count >= 3 {
            guard let p = Int(parts[2]), p >= 0 else { return nil }
            points = p
        }
        var nonce: String?
        if parts.count == 4 {
            let n = parts[3]
            guard isValidNonce(n) else { return nil }
            nonce = n
        }
        return (userID, rewardID, points, nonce)
    }

    /// Те же правила, что у сервера: 12…64 символа [A-Za-z0-9_-].
    public static func isValidNonce(_ n: String) -> Bool {
        guard n.count >= minNonceLength, n.count <= 64 else { return false }
        return n.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "_" || $0 == "-"
        }
    }
}
