import Foundation

/*
 * Instagram: подключение аккаунта заведения и импорт постов в акции.
 *
 * Зачем вообще: у заведений Бишкека контент уже есть — он лежит в их
 * инстаграме. Заставлять хоста перенабирать то же самое в кабинете — верный
 * способ получить пустой каталог. Хост нажимает «Синхронизировать», видит свои
 * посты, выбирает нужный, правит заголовок/описание, выбирает тип («Скидка»,
 * «Акция», «Новинка», «Объявление») — и получает черновик акции.
 *
 * Границы ответственности (важно, их легко перепутать):
 *   — Токен Instagram НИКОГДА не попадает в клиент. Обмен `code` → токен,
 *     хранение и обновление живут в Cloud Functions; клиент ходит за постами
 *     через наши же функции по Firebase ID-токену хоста.
 *   — Ссылки `media_url` у Instagram ПРОТУХАЮТ (часы, не дни). Поэтому при
 *     импорте картинка перезаливается на наш CDN на сервере, и в акцию
 *     попадает уже постоянная ссылка. Класть в акцию ссылку с CDN инстаграма
 *     нельзя: на следующий день у всех импортированных акций пропадут фото.
 *   — Подключиться могут только ПРОФЕССИОНАЛЬНЫЕ аккаунты (Business/Creator):
 *     Basic Display API для личных аккаунтов Meta закрыла в декабре 2024-го.
 */

// MARK: - Пост

public enum InstagramMediaKind: String, Codable, Equatable, Sendable {
    case image, video, carousel

    /// Значения Instagram: IMAGE / VIDEO / CAROUSEL_ALBUM (+ REELS у видео).
    public init(apiValue: String) {
        switch apiValue.uppercased() {
        case "VIDEO", "REELS": self = .video
        case "CAROUSEL_ALBUM": self = .carousel
        default: self = .image
        }
    }
}

/// Пост из инстаграма в том виде, в котором его отдаёт наша функция.
///
/// Ссылок на видеофайл здесь нет намеренно: в акцию идёт обложка, видео мы не
/// храним. `previewURL` — то, что показываем в сетке (для видео это
/// `thumbnail_url`), `imageURLs` — что пойдёт в карусель акции после импорта.
public struct InstagramPost: Identifiable, Equatable, Sendable {
    public let id: String
    public let caption: String
    public let kind: InstagramMediaKind
    public let previewURL: String
    public let imageURLs: [String]
    public let permalink: String
    public let timestamp: Date

    public init(id: String, caption: String, kind: InstagramMediaKind,
                previewURL: String, imageURLs: [String],
                permalink: String, timestamp: Date) {
        self.id = id; self.caption = caption; self.kind = kind
        self.previewURL = previewURL; self.imageURLs = imageURLs
        self.permalink = permalink; self.timestamp = timestamp
    }
}

// MARK: - Подключённый аккаунт

/// Публичная часть подключения — без токена; её и читает клиент.
public struct InstagramConnection: Equatable, Sendable {
    public let username: String
    public let connectedAt: Date
    /// Токен протух и обновиться не смог — нужен повторный вход. Клиент
    /// показывает баннер: молча переставшая работать синхронизация хуже ошибки.
    public let needsReauth: Bool
    public let lastSyncAt: Date?

    public init(username: String, connectedAt: Date,
                needsReauth: Bool = false, lastSyncAt: Date? = nil) {
        self.username = username; self.connectedAt = connectedAt
        self.needsReauth = needsReauth; self.lastSyncAt = lastSyncAt
    }
}

/// Результат импорта: картинки уже перезалиты на наш CDN, ссылки постоянные.
public struct InstagramImport: Equatable, Sendable {
    public let postID: String
    public let imageURLs: [String]
    public let caption: String
    public let permalink: String

    public init(postID: String, imageURLs: [String], caption: String, permalink: String) {
        self.postID = postID; self.imageURLs = imageURLs
        self.caption = caption; self.permalink = permalink
    }
}

// MARK: - Состояние по заведению

/// Instagram одного заведения внутри состояния кабинета.
///
/// Посты не стираются при ошибке синхронизации — это `SyncPhase` поверх уже
/// показанного, как и остальной кабинет: показанный список лучше пустого
/// экрана с ошибкой.
public struct InstagramVenueState: Equatable, Sendable {
    public var connection: InstagramConnection?
    public var posts: [InstagramPost] = []
    public var sync: SyncPhase = .idle
    /// Ссылка входа, которую вью открывает в системном браузере. Гасится по
    /// `instagramConnected` — иначе браузер откроется второй раз при перерисовке.
    public var authURL: URL?
    /// id поста, который прямо сейчас перезаливается на наш CDN.
    public var importing: String?

    public init(connection: InstagramConnection? = nil, posts: [InstagramPost] = [],
                sync: SyncPhase = .idle, authURL: URL? = nil, importing: String? = nil) {
        self.connection = connection; self.posts = posts
        self.sync = sync; self.authURL = authURL; self.importing = importing
    }

    public var isConnected: Bool { connection != nil }
}

// MARK: - Разбор подписи

/// Подпись поста → заголовок и описание акции.
///
/// Чистая функция и единственная настоящая логика фичи — поэтому и вынесена
/// отдельно, и покрыта тестами. Правило: заголовок короткий и без хвоста
/// хэштегов, описание НИЧЕГО не теряет — хост правит текст руками, но не
/// должен восстанавливать то, что мы молча выбросили.
public enum InstagramCaption {
    /// Максимальная длина заголовка. Больше — не влезает в карточку ленты.
    public static let maxTitle = 60

    public struct Parsed: Equatable, Sendable {
        public let title: String
        public let details: String
        /// Хэштеги из хвоста подписи — отдельно: в заголовке они мусор, но
        /// хост может захотеть перенести их в описание сам.
        public let hashtags: [String]

        public init(title: String, details: String, hashtags: [String]) {
            self.title = title; self.details = details; self.hashtags = hashtags
        }
    }

    public static func parse(_ caption: String) -> Parsed {
        let (body, tags) = stripTrailingHashtags(caption)
        guard !body.isEmpty else { return Parsed(title: "", details: "", hashtags: tags) }

        let lines = body.components(separatedBy: .newlines)
        let firstLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let rest = remainder(of: body, after: firstLine)

        // Короткая первая строка — готовый заголовок, остальное в описание.
        if firstLine.count <= maxTitle {
            return Parsed(title: firstLine, details: rest, hashtags: tags)
        }
        // Длинная строка: режем по концу предложения, если он есть в пределах лимита.
        if let cut = sentenceCut(firstLine) {
            let title = String(firstLine[firstLine.startIndex..<cut.end])
                .trimmingCharacters(in: CharacterSet(charactersIn: " .!?…"))
            let tail = String(firstLine[cut.end...]).trimmingCharacters(in: .whitespaces)
            let details = [tail, rest].filter { !$0.isEmpty }.joined(separator: "\n\n")
            return Parsed(title: title, details: details, hashtags: tags)
        }
        // Предложение не кончается — обрезаем по слову, а описанием оставляем
        // ВЕСЬ текст: обрезок — не половина смысла, а только витрина.
        return Parsed(title: wordCut(firstLine) + "…", details: body, hashtags: tags)
    }

    /// Хвост из строк, состоящих только из хэштегов/упоминаний, отрезается.
    /// Хэштеги внутри текста остаются на месте — там они часть фразы.
    private static func stripTrailingHashtags(_ caption: String) -> (String, [String]) {
        var lines = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
        var tags: [String] = []
        while let last = lines.last {
            let trimmed = last.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { lines.removeLast(); continue }
            let words = trimmed.split(separator: " ")
            guard !words.isEmpty, words.allSatisfy({ $0.hasPrefix("#") || $0.hasPrefix("@") }) else { break }
            tags.insert(contentsOf: words.map(String.init), at: 0)
            lines.removeLast()
        }
        let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (body, tags)
    }

    /// Текст после первой строки.
    private static func remainder(of body: String, after firstLine: String) -> String {
        guard let range = body.range(of: firstLine) else { return "" }
        return String(body[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Насколько ЦЕЛАЯ фраза может выйти за лимит и всё равно стать заголовком.
    ///
    /// Настоящая подпись ayant_kg: «Ayant — приводите клиентов и растите бизнес
    /// без лишних затрат!» — 61 символ без знака, ровно на символ больше лимита.
    /// Без запаса заголовок резался по слову («…без лишних…»), а описание
    /// начиналось с той же самой фразы — читается как ошибка, и хост правит это
    /// руками каждый раз. Законченная фраза чуть длиннее лимита выглядит лучше
    /// обрывка: в карточке заголовок и так в две строки. Запас нужен именно
    /// целой фразе — обрубок по слову по-прежнему режется строго по лимиту.
    private static let terminatorGrace = 8

    /// Конец первого предложения, если фраза укладывается в лимит с запасом.
    private static func sentenceCut(_ s: String) -> (end: String.Index, Void)? {
        let terminators: Set<Character> = [".", "!", "?", "…"]
        var index = s.startIndex
        var count = 0
        while index < s.endIndex, count < maxTitle + terminatorGrace {
            if terminators.contains(s[index]) {
                let end = s.index(after: index)
                let candidate = String(s[s.startIndex..<end])
                    .trimmingCharacters(in: CharacterSet(charactersIn: " .!?…"))
                // Односложный огрызок заголовком не делаем, слишком длинный — тоже.
                if count >= 8 && candidate.count <= maxTitle + terminatorGrace { return (end, ()) }
            }
            index = s.index(after: index)
            count += 1
        }
        return nil
    }

    /// Обрезка по границе слова в пределах лимита.
    private static func wordCut(_ s: String) -> String {
        let limit = s.index(s.startIndex, offsetBy: maxTitle)
        let head = String(s[s.startIndex..<limit])
        if let space = head.lastIndex(of: " ") {
            return String(head[head.startIndex..<space])
        }
        return head
    }
}

// MARK: - Контракт сервиса

/// Доступ к инстаграму заведения. Реализации: `MockInstagramService` (офлайн,
/// выдуманные посты) и `FirebaseInstagramService` (HTTP к нашим функциям).
///
/// Всё, что требует секрета приложения Meta, живёт на сервере — здесь только
/// «дай ссылку на вход», «дай посты», «импортируй пост», «отключи».
public protocol InstagramService {
    /// Ссылка авторизации Instagram для заведения. Клиент открывает её в
    /// системном браузере (`ASWebAuthenticationSession`): встроенный WebView
    /// Meta для входа блокирует, да и App Review его не пропустит.
    func authURL(venueID: String) async throws -> URL
    /// Последние посты подключённого аккаунта. Кнопка «Синхронизировать».
    func media(venueID: String, limit: Int) async throws -> [InstagramPost]
    /// Перезаливает фото поста на наш CDN и отдаёт постоянные ссылки.
    func importPost(venueID: String, postID: String) async throws -> InstagramImport
    /// Отключить аккаунт: сервер удаляет токен.
    func disconnect(venueID: String) async throws
    /// Живое состояние подключения. Именно поток, а не разовое чтение: флаг
    /// `needsReauth` ставит СЕРВЕР (не смог продлить токен ночью), и узнать об
    /// этом хост должен на открытом экране, а не при следующем запуске.
    func connection(ownerID: String, venueID: String) -> AsyncStream<InstagramConnection?>
}
