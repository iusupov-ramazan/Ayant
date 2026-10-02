import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import AyantData

// MARK: - Загрузка изображений в Cloudinary

/// Сначала — подписанная загрузка: функция `signCloudinaryUpload` (ID-токен +
/// App Check) выдаёт подпись, и Cloudinary принимает файл только с ней. Пока
/// владелец не завёл секрет на сервере (503 `not_configured`), нет сети до
/// функции или пользователь — гость без токена, грузим по-старому через
/// unsigned-пресет: до настройки сервера ничего не ломается. Когда пресет
/// отключат в Cloudinary, останется только подписанный путь.
enum ImageUploader {
    static let cloudName = "dsb14gwxw"
    static let uploadPreset = "Ayta_ios"
    /// Папки, о которых знает `signCloudinaryUpload` (список — на сервере).
    static let imageFolder = "ayant/images"
    static let documentFolder = "ayant/documents"

    enum UploadError: LocalizedError {
        case badResponse
        var errorDescription: String? { LS("Не удалось загрузить изображение") }
    }

    /// Ответ `signCloudinaryUpload`.
    struct Signature: Decodable {
        let cloudName: String
        let apiKey: String
        let timestamp: Int
        let signature: String
        let folder: String
    }

    /// Грузит файл в Cloudinary и возвращает secure_url.
    static func upload(_ fileData: Data, filename: String = "image.jpg",
                       mime: String = "image/jpeg", resourceType: String = "image",
                       folder: String = imageFolder) async throws -> String {
        if let sig = await signature(folder: folder, resourceType: resourceType) {
            return try await post(fileData, filename: filename, mime: mime,
                                  cloudName: sig.cloudName, resourceType: resourceType,
                                  fields: [("api_key", sig.apiKey),
                                           ("timestamp", String(sig.timestamp)),
                                           ("signature", sig.signature),
                                           ("folder", sig.folder)])
        }
        return try await post(fileData, filename: filename, mime: mime,
                              cloudName: cloudName, resourceType: resourceType,
                              fields: [("upload_preset", uploadPreset)])
    }

    /// Подпись или `nil`, если подписанный путь сейчас недоступен (гость,
    /// сервер не настроен, нет сети) — тогда вызывающий грузит без подписи.
    private static func signature(folder: String, resourceType: String) async -> Signature? {
        guard AppConfig.useFirebase,
              let url = URL(string: AppConfig.functionURL("signCloudinaryUpload")),
              let token = await AppConfig.makeAuthService().idToken(), !token.isEmpty
        else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        await req.attachAppCheck()
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["folder": folder,
                                                                   "resourceType": resourceType])
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let sig = try? JSONDecoder().decode(Signature.self, from: data),
              !sig.signature.isEmpty, !sig.apiKey.isEmpty
        else { return nil }
        return sig
    }

    private static func post(_ fileData: Data, filename: String, mime: String,
                             cloudName: String, resourceType: String,
                             fields: [(String, String)]) async throws -> String {
        guard let url = URL(string: "https://api.cloudinary.com/v1_1/\(cloudName)/\(resourceType)/upload")
        else { throw UploadError.badResponse }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        for (name, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mime)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")

        let (data, resp) = try await URLSession.shared.upload(for: req, from: body)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let secureURL = json["secure_url"] as? String
        else { throw UploadError.badResponse }
        return secureURL
    }

    /// Грузит PDF (прайс-лист / каталог) через /auto/upload.
    static func uploadPDF(_ data: Data) async throws -> String {
        try await upload(data, filename: "catalog.pdf", mime: "application/pdf",
                         resourceType: "auto", folder: documentFolder)
    }
}

// MARK: - Загрузка PDF (прайс-лист / каталог)

struct PDFPickerField: View {
    @Binding var urlString: String
    @State private var showImporter = false
    @State private var uploading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !urlString.isEmpty {
                Label("PDF загружен", systemImage: "doc.fill")
                    .font(.subheadline).foregroundStyle(.green)
            }
            HStack(spacing: 12) {
                Button { showImporter = true } label: {
                    Label(uploading ? "Загрузка…" : (urlString.isEmpty ? "Загрузить PDF" : "Заменить PDF"),
                          systemImage: "doc.badge.plus").font(.subheadline.weight(.medium))
                }
                .disabled(uploading)
                if uploading { ProgressView() }
                if !urlString.isEmpty {
                    Button("Убрать") { urlString = "" }.font(.caption).foregroundStyle(.red)
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            Task {
                uploading = true; error = nil
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    // Чтение файла — не на главном потоке: каталог бывает на десятки МБ.
                    let data = try await Task.detached(priority: .userInitiated) {
                        try Data(contentsOf: url, options: .mappedIfSafe)
                    }.value
                    urlString = try await ImageUploader.uploadPDF(data)
                } catch { self.error = LS("Не удалось загрузить PDF") }
                uploading = false
            }
        }
    }
}

extension UIImage {
    /// Уменьшает до maxDimension ПИКСЕЛЕЙ по большей стороне.
    ///
    /// `format.scale = 1`: формат по умолчанию берёт масштаб экрана, и
    /// «1200» превращались в 3600 px на @3x. Для фото из галереи используйте
    /// `ImageDownsampler` — он не декодирует оригинал целиком.
    func downscaled(maxDimension: CGFloat = 1200) -> UIImage {
        let pixelW = size.width * scale, pixelH = size.height * scale
        let maxSide = max(pixelW, pixelH)
        guard maxSide > maxDimension else { return self }
        let k = maxDimension / maxSide
        let newSize = CGSize(width: (pixelW * k).rounded(), height: (pixelH * k).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}

// MARK: - Поле выбора/загрузки фото (с превью и ручной ссылкой)

struct ImagePickerField: View {
    @Binding var imageURL: String
    @State private var item: PhotosPickerItem?
    @State private var uploading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !imageURL.isEmpty, let url = URL(string: imageURL) {
                AsyncImage(url: CloudinaryURL.sized(imageURL, points: 400) ?? url) { img in
                    Color.clear.overlay { img.resizable().scaledToFill() }
                } placeholder: { Color(.systemGray6) }
                .frame(height: 140).frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 12) {
                PhotosPicker(selection: $item, matching: .images) {
                    Label(uploading ? "Загрузка…" : "Загрузить фото", systemImage: "photo.badge.plus")
                        .font(.subheadline.weight(.medium))
                }
                .disabled(uploading)
                if uploading { ProgressView() }
                if !imageURL.isEmpty {
                    Button("Убрать") { imageURL = "" }
                        .font(.caption).foregroundStyle(.red)
                }
            }

            if let error { Text(error).font(.caption).foregroundStyle(.red) }

            TextField("Или вставьте ссылку", text: $imageURL)
                .keyboardType(.URL).autocapitalization(.none)
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                uploading = true; error = nil
                do {
                    if let data = try await newItem.loadTransferable(type: Data.self),
                       let jpeg = await ImageDownsampler.jpegOffMain(from: data) {
                        imageURL = try await ImageUploader.upload(jpeg)
                    } else {
                        error = LS("Не удалось прочитать фото")
                    }
                } catch {
                    self.error = LS("Ошибка загрузки фото")
                }
                uploading = false
            }
        }
    }
}

// MARK: - Несколько фото (для отзывов / галереи)

struct MultiImagePickerField: View {
    @Binding var urls: [String]
    var maxCount = 3
    @State private var items: [PhotosPickerItem] = []
    @State private var uploading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !urls.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(urls, id: \.self) { u in
                            ZStack(alignment: .topTrailing) {
                                AsyncImage(url: CloudinaryURL.sized(u, points: 72)) { img in
                                    Color.clear.overlay { img.resizable().scaledToFill() }
                                } placeholder: { Color(.systemGray6) }
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                Button { urls.removeAll { $0 == u } } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.5))
                                }
                                .padding(2)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                PhotosPicker(selection: $items, maxSelectionCount: maxCount, matching: .images) {
                    Label(uploading ? "Загрузка…" : "Добавить фото (до \(maxCount))",
                          systemImage: "photo.on.rectangle.angled")
                        .font(.subheadline.weight(.medium))
                }
                .disabled(uploading || urls.count >= maxCount)
                if uploading { ProgressView() }
            }
        }
        .onChange(of: items) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                uploading = true
                // По одному: три оригинала по 12 Мп в памяти разом — сотни МБ.
                // Каждый уменьшается вне главного потока и отпускается до следующего.
                for it in newItems {
                    if urls.count >= maxCount { break }
                    guard let data = try? await it.loadTransferable(type: Data.self) else { continue }
                    if let jpeg = await ImageDownsampler.jpegOffMain(from: data),
                       let url = try? await ImageUploader.upload(jpeg) {
                        urls.append(url)
                    }
                }
                items = []
                uploading = false
            }
        }
    }
}

// MARK: - Ячейка галереи (URL → фото, иначе эмодзи)

struct GalleryImage: View {
    let value: String
    var emojiSize: CGFloat = 40
    /// Ширина ячейки в точках — для размера, запрашиваемого у Cloudinary.
    var points: CGFloat = 200

    var body: some View {
        if value.hasPrefix("http"), let url = URL(string: value) {
            AsyncImage(url: CloudinaryURL.sized(value, points: points) ?? url) { img in
                // Размер — от контейнера, не от снимка (см. `VenuePhoto`).
                Color.clear.overlay { img.resizable().scaledToFill() }
            } placeholder: { Color(.systemGray6) }
            .clipped()
        } else {
            ZStack {
                Color(.systemGray6)
                Text(value).font(.system(size: emojiSize))
            }
        }
    }
}
