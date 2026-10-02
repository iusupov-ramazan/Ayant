import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

// MARK: - Доставка фото из Cloudinary в нужном размере

/// Cloudinary отдаёт оригинал (до 3600 px и мегабайты), если не попросить
/// иначе. Лента из двадцати таких карточек — сотни мегабайт декодированных
/// битмапов и тормоза скролла. Трансформация в URL (`f_auto,q_auto,w_<px>,c_limit`)
/// заставляет CDN прислать уже уменьшенный WebP/AVIF/JPEG нужной ширины.
///
/// Ссылки не из Cloudinary (эмодзи-галерея, ручные ссылки хозяина, Unsplash
/// в моках) возвращаются как есть.
enum CloudinaryURL {
    /// Потолок ширины: больше этого телефон всё равно не покажет.
    static let maxWidth = 2000

    /// `width` — в ПИКСЕЛЯХ. Для точек используйте `sized(_:points:)`.
    static func sized(_ urlString: String?, width: Int) -> URL? {
        guard let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, let url = URL(string: raw) else { return nil }
        guard url.host?.lowercased() == "res.cloudinary.com",
              let range = raw.range(of: "/upload/") else { return url }
        let tail = raw[range.upperBound...]
        // Уже есть трансформация сразу после /upload/ — не наслаиваем вторую.
        if let first = tail.split(separator: "/", maxSplits: 1).first,
           isTransformation(String(first)) { return url }
        let w = min(max(width, 1), maxWidth)
        let rebuilt = raw[..<range.upperBound] + "f_auto,q_auto,w_\(w),c_limit/" + tail
        return URL(string: String(rebuilt)) ?? url
    }

    /// Ширина в точках → пиксели с запасом на @3x, с потолком `maxWidth`.
    static func sized(_ urlString: String?, points: CGFloat) -> URL? {
        sized(urlString, width: pixels(points))
    }

    static func pixels(_ points: CGFloat) -> Int {
        guard points.isFinite, points > 0 else { return 1 }
        return min(Int((points * 3).rounded(.up)), maxWidth)
    }

    /// `c_fill,w_100`, `f_auto` и т.п.: каждая часть — `<буквы>_<значение>`.
    /// Версия (`v1712345`) и имя файла под это не подходят.
    private static func isTransformation(_ segment: String) -> Bool {
        let parts = segment.split(separator: ",")
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { part in
            guard let us = part.firstIndex(of: "_"), us > part.startIndex else { return false }
            return part[..<us].allSatisfy { $0.isASCII && $0.isLetter }
        }
    }
}

// MARK: - Уменьшение без декодирования оригинала целиком

/// `UIImage(data:)` + перерисовка декодирует снимок 4032×3024 целиком
/// (~48 МБ) на главном потоке — и `UIGraphicsImageRenderer` по умолчанию
/// умножает размер на масштаб экрана, так что «1200 px» становились 3600.
/// ImageIO строит миниатюру прямо из сжатых байт, с учётом EXIF-поворота,
/// и работает на любом потоке.
enum ImageDownsampler {
    /// Миниатюра не больше `maxPixel` по большей стороне (или `nil` для не-картинки).
    static func cgImage(from data: Data, maxPixel: Int) -> CGImage? {
        guard !data.isEmpty else { return nil }
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOpts) else { return nil }
        let opts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts)
    }

    /// JPEG для загрузки: ≤ `maxPixel` по большей стороне, масштаб 1.
    static func jpeg(from data: Data, maxPixel: Int = 1200, quality: Double = 0.8) -> Data? {
        guard let cg = cgImage(from: data, maxPixel: maxPixel) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// То же, но гарантированно вне главного потока.
    static func jpegOffMain(from data: Data, maxPixel: Int = 1200, quality: Double = 0.8) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            jpeg(from: data, maxPixel: maxPixel, quality: quality)
        }.value
    }
}
