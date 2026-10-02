import Foundation

/// Один QR гостя на все заведения.
///
/// Раньше у гостя было два кода: «Мой QR» (`AYANT-PTS:<uid>`) — для баллов,
/// и QR карты штампов (`AYANT-CARD:<uid>:<venueID>`) — для штампов. Показать
/// «не тот» значило получить отказ у кассы (`loyalty_is_points`,
/// `points_off`), и гости путались, какой из двух нужен. Механика лояльности
/// у заведения одна — баллы ИЛИ штампы, приоритет у баллов (`LoyaltyKind`), —
/// поэтому любой из двух кодов однозначно ведёт туда, где у этого заведения
/// лояльность. Гостю показываем только `AYANT-PTS`; карточный код остаётся
/// рабочим для старых сборок.
///
/// Зеркало серверного правила в `scanCoupon` (`functions/src/index.ts`): сервер
/// перенаправляет так же, а сканер хоста делает это заранее, чтобы показать
/// правильный экран — ввод суммы чека для баллов, выбор карты для штампов.
public enum GuestQR {
    public static let earnPrefix = "AYANT-PTS:"
    public static let cardPrefix = "AYANT-CARD:"

    /// Код, который гость показывает в любом заведении.
    public static func code(userID: String) -> String { earnPrefix + userID }

    /// Куда направить отсканированный код в этом заведении. Чужие коды
    /// (купоны, списания, карта другого заведения) возвращаются как есть.
    public static func route(_ code: String, venueID: String,
                             pointsEnabled: Bool, loyaltyEnabled: Bool) -> String {
        let parts = code.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, !parts[1].isEmpty else { return code }
        let user = parts[1]
        if code.hasPrefix(earnPrefix), !pointsEnabled, loyaltyEnabled {
            return "\(cardPrefix)\(user):\(venueID)"
        }
        if code.hasPrefix(cardPrefix), pointsEnabled, parts.count >= 3, parts[2] == venueID {
            return earnPrefix + user
        }
        return code
    }
}
