package kg.ayant.app.domain.model

import java.util.Date

// Жалоба на отзыв. Зеркалит `ReviewReport.swift`.
//
// Требование App Review Guidelines 1.2: у приложения с пользовательским
// контентом должен быть механизм жалоб «and timely responses to concerns».
// Диалог «Пожаловаться» был раньше бутафорским — он просто показывал
// «Спасибо», никуда ничего не уходило. Теперь жалоба доезжает до Firestore
// и видна в админ-панели.

/** Почему отзыв не должен быть на витрине. */
enum class ReviewReportReason(val slug: String) {
    FAKE("fake"),
    SPAM("spam"),
    OFFENSIVE("offensive");

    companion object {
        fun fromSlug(slug: String): ReviewReportReason =
            entries.firstOrNull { it.slug == slug } ?: SPAM
    }
}

data class ReviewReport(
    val id: String,
    val reviewID: String,
    val venueID: String,
    /**
     * uid пожаловавшегося. Гость тоже вправе пожаловаться: он подписан
     * анонимно, uid у него есть, а модерация не должна упираться в регистрацию.
     */
    val reporterID: String,
    val reason: ReviewReportReason,
    val createdAt: Date,
) {
    companion object {
        /**
         * Детерминированный id: один человек — одна жалоба на отзыв.
         *
         * Так повторное нажатие перезаписывает свою же запись, а не плодит
         * дубликаты: иначе один раздражённый человек мог бы накидать сотню
         * жалоб и очередь модерации стала бы бесполезной.
         */
        fun id(reviewID: String, reporterID: String): String = "${reviewID}_$reporterID"

        fun of(review: Review, reporterID: String, reason: ReviewReportReason, now: Date) =
            ReviewReport(
                id = id(review.id, reporterID),
                reviewID = review.id,
                venueID = review.venueID,
                reporterID = reporterID,
                reason = reason,
                createdAt = now,
            )
    }
}

/** Статус разбора. Пишет клиент при создании, меняет только админ-панель. */
object ReviewReportStatus {
    const val OPEN = "open"
    const val REVIEWED = "reviewed"
}
