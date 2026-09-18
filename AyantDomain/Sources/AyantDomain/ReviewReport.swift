import Foundation

// Жалоба на отзыв.
//
// Требование App Review Guidelines 1.2: у приложения с пользовательским
// контентом должен быть механизм жалоб «and timely responses to concerns».
// Кнопка «Пожаловаться» в карточке заведения была раньше бутафорской — диалог
// с причинами просто закрывался, никуда ничего не уходило. Теперь жалоба
// доезжает до Firestore и видна в админ-панели.
//
// Зеркалит `ReviewReport.kt`.

/// Почему отзыв не должен быть на витрине.
public enum ReviewReportReason: String, CaseIterable, Sendable {
    case fake, spam, offensive

    /// Подпись в интерфейсе. Русская строка — как у `DealStatus.title`
    /// и `ModerationStatus.title`: домен не знает про каталог переводов,
    /// локализует UI-слой.
    public var title: String {
        switch self {
        case .fake:      return "Фейк"
        case .spam:      return "Спам"
        case .offensive: return "Оскорбительное"
        }
    }
}

public struct ReviewReport: Identifiable, Hashable, Sendable {
    public let id: String
    public let reviewID: String
    public let venueID: String
    /// uid пожаловавшегося. Гость тоже вправе пожаловаться: он подписан
    /// анонимно, uid у него есть, а модерация не должна упираться в регистрацию.
    public let reporterID: String
    public let reason: ReviewReportReason
    public let createdAt: Date

    public init(id: String, reviewID: String, venueID: String,
                reporterID: String, reason: ReviewReportReason, createdAt: Date) {
        self.id = id
        self.reviewID = reviewID
        self.venueID = venueID
        self.reporterID = reporterID
        self.reason = reason
        self.createdAt = createdAt
    }

    /// Собирает жалобу с детерминированным id.
    public init(review: Review, reporterID: String, reason: ReviewReportReason, now: Date) {
        self.init(id: Self.id(reviewID: review.id, reporterID: reporterID),
                  reviewID: review.id,
                  venueID: review.venueID,
                  reporterID: reporterID,
                  reason: reason,
                  createdAt: now)
    }

    /// Детерминированный id: один человек — одна жалоба на отзыв.
    ///
    /// Так повторное нажатие перезаписывает свою же запись, а не плодит
    /// дубликаты: иначе один раздражённый человек мог бы накидать сотню жалоб
    /// и очередь модерации стала бы бесполезной. Тот же приём, что у
    /// `logRedemption` (`{userID}_{dealID}`).
    public static func id(reviewID: String, reporterID: String) -> String {
        "\(reviewID)_\(reporterID)"
    }
}

/// Статус разбора. Пишет клиент при создании, меняет только админ-панель.
public enum ReviewReportStatus {
    public static let open = "open"
    public static let reviewed = "reviewed"
}
