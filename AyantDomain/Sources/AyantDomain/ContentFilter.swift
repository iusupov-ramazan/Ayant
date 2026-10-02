import Foundation

// Фильтр пользовательского текста (отзывы) перед публикацией.
//
// App Review Guidelines 1.2: у приложения с пользовательским контентом должен
// быть «a method for filtering objectionable material». Жалобы и скрытие
// автора разбирают то, что уже опубликовано; этот фильтр не даёт опубликовать
// очевидное — мат (русский, кыргызский, английский), ссылки и телефоны (спам
// «пишите в WhatsApp» / «заходите на сайт»).
//
// Список НАМЕРЕННО скромный: корни, которые почти не дают ложных срабатываний
// на обычных словах («хлеб», «небо», «мудрый», «употреблять» проходят — это
// закреплено тестами `ContentFilterTests`). Полную модерацию делает человек по
// жалобам, а не словарь.

public enum ContentFilter {

    /// Почему текст нельзя опубликовать.
    public enum Violation: String, Equatable, Sendable {
        case profanity
        case link
        case phone

        /// Ключ каталога строк (UI локализует).
        public var message: String {
            switch self {
            case .profanity: return "Отзыв содержит недопустимые слова"
            case .link, .phone: return "Ссылки и номера телефонов в отзывах не допускаются"
            }
        }
    }

    /// `nil` — текст можно публиковать.
    public static func check(_ text: String) -> Violation? {
        let lower = text.lowercased()
        if containsProfanity(lower) { return .profanity }
        if containsLink(lower) { return .link }
        if containsPhone(text) { return .phone }
        return nil
    }

    // MARK: - Мат

    /// Корни, которые ищутся как ПОДСТРОКА слова (с приставками: «заеб…», «распизд…»).
    private static let containsRoots: [String] = [
        "пизд", "хуй", "хуе", "хуё", "хуя", "хуил", "ебан", "ебат", "ебал", "ебуч", "ебло",
        "еблан", "ёбан", "ёбну", "ебну", "долбоеб", "долбоёб", "бляд", "залуп", "пидор",
        "пидар", "гандон", "гондон", "мудак", "мудил", "мудач", "шлюх",
        // кыргызский
        "сигейин", "сикейин", "сиктир", "сигип", "амыңды", "амынды", "жалап",
        // английский
        "fuck", "motherf", "cunt", "asshole", "bullshit",
    ]

    /// Слова, которые запрещены ТОЛЬКО целиком: как подстрока они встречаются
    /// в обычных словах («сукно», «дикий», «shitake»).
    private static let wholeWords: Set<String> = [
        "бля", "блять", "блядь", "сука", "суки", "сучка", "сучара", "ебу", "ебёт", "ебет",
        "пидр", "хер", "нахер", "похер", "кутак",
        "shit", "shitty", "bitch", "bitches", "dick", "dickhead", "fucker", "whore", "slut",
    ]

    /// Обычные основы, внутри которых корни выше встречаются случайно:
    /// «колебаться», «хлебать», «погребальный», «учебный», «застрахуйте».
    /// Слово с такой основой проверяется только по `wholeWords`.
    private static let innocentStems: [String] = [
        "колеб", "хлеб", "греб", "скреб", "учеб", "требл", "страх",
    ]

    /// Латинские «двойники» кириллицы: «xyй», «cyka» пишут, чтобы обойти фильтр.
    private static let homoglyphs: [Character: Character] = [
        "a": "а", "e": "е", "o": "о", "p": "р", "c": "с", "x": "х", "y": "у",
        "k": "к", "m": "м", "t": "т", "b": "в", "h": "н", "3": "з", "0": "о", "@": "а",
    ]

    static func containsProfanity(_ lower: String) -> Bool {
        let normalized = lower.replacingOccurrences(of: "ё", with: "е")
        let latinWords = words(in: normalized)
        // Тот же текст, где латинские двойники заменены кириллицей.
        let cyrillicWords = latinWords.map { word in
            String(word.map { homoglyphs[$0] ?? $0 })
        }
        let roots = containsRoots.map { $0.replacingOccurrences(of: "ё", with: "е") }
        for group in [latinWords, cyrillicWords] {
            for word in group {
                if wholeWords.contains(word) { return true }
                if innocentStems.contains(where: { word.contains($0) }) { continue }
                if roots.contains(where: { word.contains($0) }) { return true }
            }
        }
        return false
    }

    /// Слова из букв (и цифр-двойников): разделители — всё остальное, включая
    /// звёздочки и точки, которыми мат «разбивают» («х.у.й» склеится обратно).
    private static func words(in text: String) -> [String] {
        // Одиночные точки/дефисы/звёздочки между буквами — маскировка, склеиваем.
        let glued = text.replacingOccurrences(
            of: #"(?<=\p{L})[\.\*\-_](?=\p{L})"#, with: "", options: .regularExpression)
        return glued
            .split { !($0.isLetter || $0 == "@" || $0 == "0" || $0 == "3") }
            .map(String.init)
    }

    // MARK: - Ссылки

    private static let linkPatterns: [String] = [
        #"https?://"#,
        #"\bwww\."#,
        #"\b(t\.me|wa\.me|instagram\.com|vk\.com|tiktok\.com|bit\.ly|telegram\.me)/"#,
        #"\b[a-z0-9-]{2,}\.(com|ru|kg|net|org|io|me|info|xyz|site|online|shop|store|app|link|biz|club|pro|top)\b"#,
    ]

    static func containsLink(_ lower: String) -> Bool {
        linkPatterns.contains { lower.range(of: $0, options: .regularExpression) != nil }
    }

    // MARK: - Телефоны

    /// Девять и больше цифр подряд (с пробелами, дефисами, скобками, «+») —
    /// номер телефона. Цены («1 200 сом», «350 г») короче и проходят.
    static func containsPhone(_ text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: #"\+?\d[\d\s\-\(\)]{7,}\d"#) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            if text[r].filter(\.isNumber).count >= 9 { return true }
        }
        return false
    }
}

// MARK: - Жалоба на фото

/// Жалоба на фото из галереи заведения (Guidelines 1.2). Ложится в ту же
/// очередь `reviewReports`, что и жалобы на отзывы, с `reason = "photo"`:
/// модератор видит её в той же админ-странице.
public struct PhotoReport: Equatable, Sendable {
    /// Причина в документе — отличает жалобу на фото от жалобы на текст.
    public static let reason = "photo"
    /// `reviewID` жалобы на фото самого заведения (обложка, меню): правила
    /// требуют непустой id из `[A-Za-z0-9_-]`, а отзыва у такого фото нет.
    public static let venuePhotoReviewID = "venuePhoto"

    public let id: String
    /// Отзыв, к которому прикреплено фото; `venuePhotoReviewID` — фото заведения.
    public let reviewID: String
    public let venueID: String
    public let photoURL: String
    public let reporterID: String
    /// Что не так с фото (фейк / спам / оскорбительное).
    public let photoReason: ReviewReportReason
    public let createdAt: Date

    public init(reviewID: String, venueID: String, photoURL: String,
                reporterID: String, reason: ReviewReportReason, now: Date) {
        self.reviewID = reviewID.isEmpty ? Self.venuePhotoReviewID : reviewID
        self.venueID = venueID
        self.photoURL = photoURL
        self.reporterID = reporterID
        self.photoReason = reason
        self.createdAt = now
        self.id = Self.id(photoURL: photoURL, reporterID: reporterID)
    }

    /// Детерминированный id: одна жалоба человека на одно фото (повтор
    /// перезаписывает свою же запись, как у `ReviewReport`). Хэш URL —
    /// стабильный FNV-1a, а не `hashValue` (тот меняется между запусками).
    public static func id(photoURL: String, reporterID: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in photoURL.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return "photo_\(String(hash, radix: 16))_\(reporterID)"
    }
}
