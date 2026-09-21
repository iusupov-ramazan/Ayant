import Foundation
import FirebaseFirestore
import AyantDomain

// MARK: - Офлайн-режим

/// Заглушка для режима без Firebase (`AppConfig.useFirebase == false`,
/// в том числе витринные скриншоты).
///
/// Постов НЕ выдумывает. Пара `Mock*`/`Firebase*` обязательна по архитектуре —
/// без неё офлайн-сборка не соберётся, — но придуманный контент в этой фиче
/// вреден: это чужие фотографии под именем заведения. Пусть лучше экран честно
/// показывает «аккаунт не подключён», чем красивую неправду.
public final class MockInstagramService: InstagramService {
    public init() {}

    public func authURL(venueID: String) async throws -> URL {
        throw AppError.server(code: "not_configured")
    }

    public func media(venueID: String, limit: Int) async throws -> [InstagramPost] { [] }

    public func importPost(venueID: String, postID: String) async throws -> InstagramImport {
        throw AppError.server(code: "not_connected")
    }

    public func disconnect(venueID: String) async throws {}

    public func connection(ownerID: String, venueID: String) -> AsyncStream<InstagramConnection?> {
        AsyncStream { continuation in
            continuation.yield(nil)
            continuation.finish()
        }
    }
}

// MARK: - Живой сервис

/// HTTP к нашим Cloud Functions + снапшот подключения из Firestore.
///
/// Токена инстаграма здесь нет и быть не может: функции его не отдают, а
/// `igAccounts` закрыта правилами. Всё, что видит клиент, — обезличенные посты
/// и публичная часть подключения (`igConnections`).
public final class FirebaseInstagramService: InstagramService {
    private let db = Firestore.firestore()
    private let auth: AuthService
    private let session: URLSession

    public init(auth: AuthService, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    // MARK: Запросы

    public func authURL(venueID: String) async throws -> URL {
        let json = try await post("instagramAuthStart", body: ["venueID": venueID])
        guard let raw = json["authURL"] as? String, let url = URL(string: raw) else {
            throw AppError.server(code: "bad_response")
        }
        return url
    }

    public func media(venueID: String, limit: Int) async throws -> [InstagramPost] {
        let json = try await post("instagramMedia", body: ["venueID": venueID, "limit": limit])
        let raw = json["posts"] as? [[String: Any]] ?? []
        return raw.compactMap(Self.post(from:))
    }

    public func importPost(venueID: String, postID: String) async throws -> InstagramImport {
        let json = try await post("instagramImportMedia",
                                  body: ["venueID": venueID, "postID": postID])
        let urls = json["imageURLs"] as? [String] ?? []
        guard !urls.isEmpty else { throw AppError.server(code: "no_image") }
        return InstagramImport(postID: json["postID"] as? String ?? postID,
                               imageURLs: urls,
                               caption: json["caption"] as? String ?? "",
                               permalink: json["permalink"] as? String ?? "")
    }

    public func disconnect(venueID: String) async throws {
        _ = try await post("instagramDisconnect", body: ["venueID": venueID])
    }

    public func connection(ownerID: String, venueID: String) -> AsyncStream<InstagramConnection?> {
        let docID = FS.IgConnectionDoc.id(ownerID: ownerID, venueID: venueID)
        return AsyncStream { continuation in
            guard !ownerID.isEmpty, !venueID.isEmpty else {
                continuation.yield(nil); continuation.finish(); return
            }
            let registration = db.collection(FS.IgConnectionDoc.collection).document(docID)
                .addSnapshotListener { snapshot, error in
                    // Ошибка слушателя (чаще всего — недеплоенные правила) НЕ
                    // равна «аккаунт не подключён». Выдать здесь nil значит
                    // показать «Подключить Instagram» поверх рабочего
                    // подключения и не сказать ни слова о причине.
                    if let error {
                        print("⚠️ igConnections listener failed: \(error.localizedDescription)")
                        return
                    }
                    guard let data = snapshot?.data() else { continuation.yield(nil); return }
                    continuation.yield(InstagramConnection(
                        username: data.string(FS.IgConnectionDoc.username) ?? "",
                        connectedAt: (data[FS.IgConnectionDoc.connectedAt] as? Timestamp)?.dateValue() ?? .now,
                        needsReauth: data[FS.IgConnectionDoc.needsReauth] as? Bool ?? false,
                        lastSyncAt: (data[FS.IgConnectionDoc.lastSyncAt] as? Timestamp)?.dateValue()))
                }
            continuation.onTermination = { _ in registration.remove() }
        }
    }

    // MARK: Транспорт

    private func post(_ function: String, body: [String: Any]) async throws -> [String: Any] {
        guard let token = await auth.idToken(), !token.isEmpty else { throw AppError.unauthenticated }
        var req = URLRequest(url: URL(string: AyantBackend.functionURL(function))!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) }
        catch { throw AppError.network }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            // Коды сервера (`not_connected`, `reauth_required`, …) доходят до
            // экрана как есть — по ним рисуется подсказка, а не «что-то пошло не так».
            throw AppError.server(code: json["error"] as? String ?? "http_\(code)")
        }
        return json
    }

    /// Разбор поста. Время приходит строкой ISO-8601 от Graph API.
    private static func post(from d: [String: Any]) -> InstagramPost? {
        guard let id = d["id"] as? String, !id.isEmpty else { return nil }
        let images = d["imageURLs"] as? [String] ?? []
        let preview = d["previewURL"] as? String ?? images.first ?? ""
        guard !preview.isEmpty else { return nil }   // без картинки пост в акцию не годится
        return InstagramPost(
            id: id,
            caption: d["caption"] as? String ?? "",
            kind: InstagramMediaKind(apiValue: d["mediaType"] as? String ?? "IMAGE"),
            previewURL: preview,
            imageURLs: images.isEmpty ? [preview] : images,
            permalink: d["permalink"] as? String ?? "",
            timestamp: Self.isoFormatter.date(from: d["timestamp"] as? String ?? "") ?? .distantPast)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        // Graph API отдаёт «2026-09-01T10:00:00+0000» — без двоеточия в зоне.
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
