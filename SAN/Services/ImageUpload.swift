import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Загрузка изображений в Cloudinary (unsigned upload)

enum ImageUploader {
    static let cloudName = "dsb14gwxw"
    static let uploadPreset = "Ayta_ios"

    enum UploadError: LocalizedError {
        case badResponse
        var errorDescription: String? { "Не удалось загрузить изображение" }
    }

    /// Грузит файл в Cloudinary и возвращает secure_url.
    static func upload(_ fileData: Data, filename: String = "image.jpg",
                       mime: String = "image/jpeg", resourceType: String = "image") async throws -> String {
        let url = URL(string: "https://api.cloudinary.com/v1_1/\(cloudName)/\(resourceType)/upload")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"upload_preset\"\r\n\r\n")
        append("\(uploadPreset)\r\n")
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
        try await upload(data, filename: "catalog.pdf", mime: "application/pdf", resourceType: "auto")
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
                    let data = try Data(contentsOf: url)
                    urlString = try await ImageUploader.uploadPDF(data)
                } catch { self.error = "Не удалось загрузить PDF" }
                uploading = false
            }
        }
    }
}

extension UIImage {
    /// Уменьшает до maxDimension по большей стороне (экономия трафика/места).
    func downscaled(maxDimension: CGFloat = 1200) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
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
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: { Color(.systemGray6) }
                .frame(height: 140).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
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
                       let ui = UIImage(data: data),
                       let jpeg = ui.downscaled().jpegData(compressionQuality: 0.8) {
                        imageURL = try await ImageUploader.upload(jpeg)
                    } else {
                        error = "Не удалось прочитать фото"
                    }
                } catch {
                    self.error = "Ошибка загрузки фото"
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
                                AsyncImage(url: URL(string: u)) { img in
                                    img.resizable().scaledToFill()
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
                for it in newItems {
                    if urls.count >= maxCount { break }
                    if let data = try? await it.loadTransferable(type: Data.self),
                       let ui = UIImage(data: data),
                       let jpeg = ui.downscaled().jpegData(compressionQuality: 0.8),
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

    var body: some View {
        if value.hasPrefix("http"), let url = URL(string: value) {
            AsyncImage(url: url) { img in
                img.resizable().scaledToFill()
            } placeholder: { Color(.systemGray6) }
        } else {
            ZStack {
                Color(.systemGray6)
                Text(value).font(.system(size: emojiSize))
            }
        }
    }
}
