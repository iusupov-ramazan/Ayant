import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

// MARK: - QR-код купона

struct QRCodeView: View {
    let text: String
    var size: CGFloat = 110

    var body: some View {
        Group {
            if let img = Self.generate(text) {
                Image(uiImage: img).interpolation(.none).resizable()
            } else {
                Image(systemName: "qrcode").resizable()
            }
        }
        .frame(width: size, height: size)
        .padding(8)
        .background(.white, in: RoundedRectangle(cornerRadius: 10))
    }

    private static let context = CIContext()
    static func generate(_ string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = context.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Аватар заведения

struct VenueAvatar: View {
    let venue: Venue
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: venue.gradient,
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
            if let urlString = venue.imageURL, !urlString.isEmpty, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Image(systemName: "storefront.fill").font(.system(size: size * 0.42)).foregroundStyle(.white)
                    }
                }
                .clipShape(Circle())
            } else {
                Image(systemName: "storefront.fill").font(.system(size: size * 0.42)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - Обложка заведения (фото или градиент со значком — без эмодзи)

struct VenuePhoto: View {
    let urlString: String?
    var gradient: [Color] = [.sanAccent, .orange]

    var body: some View {
        ZStack {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            if let s = urlString, !s.isEmpty, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .empty: ProgressView().tint(.white)
                    default: Image(systemName: "storefront.fill").font(.largeTitle).foregroundStyle(.white.opacity(0.85))
                    }
                }
            } else {
                Image(systemName: "storefront.fill").font(.largeTitle).foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

// MARK: - Бейдж типа предложения

struct DealTypeBadge: View {
    let type: DealType

    var body: some View {
        Label(type.rawValue, systemImage: type.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(type.color, in: Capsule())
    }
}

// MARK: - Цены

struct PriceLabel: View {
    let deal: Deal

    var body: some View {
        HStack(spacing: 8) {
            if let old = deal.oldPrice {
                Text(old.som)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            if let new = deal.newPrice {
                Text(new.som)
                    .font(.headline)
                    .foregroundStyle(Color.sanAccent)
            }
        }
    }
}

// MARK: - Карточка ленты (инста-формат)

struct DealCard: View {
    let deal: Deal
    var onTap: () -> Void = {}          // тап по картинке/тексту → страница акции
    var onVenueTap: () -> Void = {}     // тап по логотипу/названию → страница заведения
    @EnvironmentObject private var store: AppStore
    @State private var showGuestAlert = false

    private var venue: Venue? { store.venue(for: deal) }
    // Акции показываются «как есть» — рекламой выступают карточки заведений.
    private var isAd: Bool { false }

    private var pad: CGFloat { isAd ? 18 : 14 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isAd { adBanner }
            // Шапка (логотип + название) ведёт на страницу заведения.
            Button(action: onVenueTap) { header }
                .buttonStyle(.plain)
            // Картинка и текст открывают саму акцию.
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 0) {
                    visual
                    caption
                }
            }
            .buttonStyle(.plain)
            actions
        }
        .background(isAd ? Color.sanAccent.opacity(0.06) : Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: isAd ? 22 : 20))
        .overlay(RoundedRectangle(cornerRadius: isAd ? 22 : 20)
            .stroke(isAd ? Color.sanAccent : Color(.systemGray5), lineWidth: isAd ? 2 : 1))
        .shadow(color: isAd ? Color.sanAccent.opacity(0.18) : .black.opacity(0.04),
                radius: isAd ? 12 : 6, y: isAd ? 5 : 3)
        .padding(.vertical, isAd ? 4 : 0)
        .alert("Войдите в аккаунт", isPresented: $showGuestAlert) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Гостям доступен только просмотр. Войдите в профиле, чтобы сохранять.")
        }
    }

    private var adBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "megaphone.fill").font(.caption2)
            Text("Реклама").font(.caption.weight(.heavy))
            Spacer()
            Text("спецпредложение").font(.caption2.weight(.semibold)).opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, pad).padding(.vertical, 8)
        .background(LinearGradient(colors: [Color(hex: 0xFF4D29), Color(hex: 0xFFB300)],
                                   startPoint: .leading, endPoint: .trailing))
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let venue { VenueAvatar(venue: venue, size: 46) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(venue?.name ?? "").font(.subheadline.weight(.bold))
                    if venue?.isVerified == true {
                        Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.blue)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                Text("\(venue?.category.rawValue ?? "") • \(venue?.district ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            DealTypeBadge(type: deal.type)
        }
        .contentShape(Rectangle())
        .padding(.horizontal, pad)
        .padding(.vertical, 12)
    }

    private var visual: some View {
        DealImage(urlString: deal.imageURL, gradient: venue?.gradient ?? [.sanAccent, .orange],
                  emoji: deal.emoji, emojiSize: 90)
            .overlay(alignment: .topLeading) {
                if let percent = deal.discountPercent {
                    Text("−\(percent)%")
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.35), in: Capsule())
                        .padding(12)
                }
            }
    }

    private var actions: some View {
        HStack(spacing: 18) {
            Button {
                if store.isGuest { showGuestAlert = true } else { store.toggleFavorite(deal) }
            } label: {
                Image(systemName: store.isFavorite(deal) ? "bookmark.fill" : "bookmark")
                    .font(.title3)
                    .foregroundStyle(store.isFavorite(deal) ? Color.sanAccent : .primary)
            }
            .buttonStyle(.plain)

            ShareLink(item: DeepLinkRouter.dealURL(deal.id),
                      subject: Text(deal.title),
                      message: Text("\(deal.title) — \(venue?.name ?? ""). Нашёл в Ayta!")) {
                Image(systemName: "square.and.arrow.up").font(.title3).foregroundStyle(.primary)
            }

            Spacer()

            Label("до \(deal.validUntil.sanShort)", systemImage: "clock")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, pad)
        .padding(.vertical, 12)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let urgency = deal.urgencyText {
                Label(urgency, systemImage: "flame.fill")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.red.opacity(0.12), in: Capsule())
                    .foregroundStyle(.red)
            }
            Text(deal.title).font(.title3.weight(.bold)).lineLimit(2)
            Text(deal.details).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            PriceLabel(deal: deal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.horizontal, pad)
        .padding(.top, isAd ? 18 : 16)   // воздух между картинкой и заголовком
        .padding(.bottom, isAd ? 8 : 4)
    }
}

// MARK: - Обложка (картинка по ссылке или градиент + эмодзи)

struct CoverImage: View {
    let urlString: String?
    let gradient: [Color]
    let emoji: String
    var emojiSize: CGFloat = 64

    var body: some View {
        ZStack {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            if let s = urlString, !s.isEmpty, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ProgressView().tint(.white)
                    default:
                        Text(emoji).font(.system(size: emojiSize)).shadow(radius: 6)
                    }
                }
            } else {
                Text(emoji).font(.system(size: emojiSize)).shadow(radius: 6)
            }
        }
    }
}

// MARK: - Картинка акции (как в Instagram: контейнер принимает форму фото)

/// Загружает фото, чтобы узнать его реальные пропорции, и показывает в контейнере
/// с тем же соотношением сторон — обрезанным только до диапазона Instagram
/// (от 1.91:1 ширина к высоте до 4:5). В пределах диапазона картинка видна целиком.
@MainActor
final class DealImageLoader: ObservableObject {
    @Published var ui: UIImage?
    private var loadedURL: URL?

    func load(_ url: URL) async {
        guard loadedURL != url else { return }
        loadedURL = url
        if let (data, _) = try? await URLSession.shared.data(from: url) {
            ui = UIImage(data: data)
        }
    }
}

struct DealImage: View {
    let urlString: String?
    let gradient: [Color]
    let emoji: String
    var emojiSize: CGFloat = 80

    private let maxAR: CGFloat = 1.91   // самый широкий (1.91:1)
    private let minAR: CGFloat = 0.8    // самый высокий (4:5)
    @StateObject private var loader = DealImageLoader()

    private var url: URL? {
        guard let s = urlString, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    /// Соотношение сторон контейнера (ширина/высота), ограниченное диапазоном Instagram.
    private var aspect: CGFloat {
        guard let ui = loader.ui, ui.size.height > 0 else { return 1 }
        return min(maxAR, max(minAR, ui.size.width / ui.size.height))
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            if let ui = loader.ui {
                Image(uiImage: ui).resizable().scaledToFill()
            } else if url != nil {
                ProgressView().tint(.white)
            } else {
                Text(emoji).font(.system(size: emojiSize)).shadow(radius: 6)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipped()
        .task(id: urlString) { if let u = url { await loader.load(u) } }
    }
}

// MARK: - Миниатюра объекта (фото или эмодзи-фолбэк)

struct ItemThumb: View {
    let item: VenueItem
    var size: CGFloat = 70

    var body: some View {
        Group {
            if !item.imageURL.isEmpty, let url = URL(string: item.imageURL) {
                AsyncImage(url: url) { img in
                    img.resizable().scaledToFill()
                } placeholder: { Color(.systemGray6) }
            } else {
                ZStack {
                    Color(.systemGray6)
                    Text(item.emoji).font(.system(size: size * 0.45))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Звёзды рейтинга

struct StarRatingView: View {
    let rating: Double
    var count: Int? = nil
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 1) {
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: symbol(for: i))
                        .font(.system(size: size))
                        .foregroundStyle(.yellow)
                }
            }
            Text(String(format: "%.1f", rating))
                .font(.system(size: size).weight(.semibold))
                .lineLimit(1)
            if let count {
                Text("(\(count))")
                    .font(.system(size: size))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        // Не даём звёздам сжиматься/обрезаться в тесных строках (поиск, карточки).
        .fixedSize(horizontal: true, vertical: false)
    }

    private func symbol(for i: Int) -> String {
        let v = rating - Double(i)
        if v >= 1 { return "star.fill" }
        if v >= 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}

// MARK: - Разбивка рейтинга (5★…1★)

struct RatingBreakdownView: View {
    let breakdown: [Int: Int]   // звезда → количество
    var total: Int { breakdown.values.reduce(0, +) }

    var body: some View {
        VStack(spacing: 5) {
            ForEach((1...5).reversed(), id: \.self) { star in
                HStack(spacing: 8) {
                    Text("\(star)").font(.caption).frame(width: 10)
                    Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.systemGray5))
                            Capsule().fill(Color.sanAccent)
                                .frame(width: geo.size.width * fraction(star))
                        }
                    }
                    .frame(height: 7)
                    Text("\(breakdown[star] ?? 0)")
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
    }

    private func fraction(_ star: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(breakdown[star] ?? 0) / CGFloat(total)
    }
}

// MARK: - Карточка заведения (лента, поиск)

struct VenueCard: View {
    let venue: Venue
    var distanceKm: Double? = nil
    var isSponsored: Bool = false
    @EnvironmentObject private var store: AppStore
    @State private var showGuestAlert = false

    private var agg: (rating: Double, count: Int) { store.aggregate(for: venue) }
    private var dealCount: Int { store.deals(for: venue).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
            info
        }
        .background(isSponsored ? Color.sanAccent.opacity(0.06) : Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(isSponsored ? Color.sanAccent : Color(.systemGray5), lineWidth: isSponsored ? 2 : 1))
        .shadow(color: isSponsored ? Color.sanAccent.opacity(0.18) : .black.opacity(0.05),
                radius: isSponsored ? 10 : 7, y: 3)
        .alert("Войдите в аккаунт", isPresented: $showGuestAlert) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Гостям доступен только просмотр. Войдите в профиле, чтобы сохранять места.")
        }
    }

    private var cover: some View {
        ZStack(alignment: .topLeading) {
            VenuePhoto(urlString: venue.imageURL, gradient: venue.gradient)

            HStack {
                if isSponsored {
                    Text("Реклама")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.4), in: Capsule())
                        .foregroundStyle(.white)
                }
                Spacer()
                Button {
                    if store.isGuest { showGuestAlert = true } else { store.toggleSave(venue) }
                } label: {
                    Image(systemName: store.isSaved(venue) ? "bookmark.fill" : "bookmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.35), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(10)

            if venue.hasTodaySpecial {
                Text("⭐️ Сегодня")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.sanAccent, in: Capsule())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(10)
            }
        }
        .frame(height: 180)
        .clipped()
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text(venue.name).font(.title3.weight(.bold)).lineLimit(1)
                if venue.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.subheadline).foregroundStyle(.blue)
                }
                Spacer()
                Text(venue.isOpenNow ? "Открыто" : "Закрыто")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(venue.isOpenNow ? .green : .secondary)
            }
            HStack(spacing: 6) {
                StarRatingView(rating: agg.rating, count: agg.count)
                Text("·").foregroundStyle(.secondary)
                Text(venue.category.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if let distanceKm {
                    Label(distanceKm.distanceText, systemImage: "location.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if dealCount > 0 {
                    Label("\(dealCount) акц.", systemImage: "tag.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.sanAccent.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.sanAccent)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }
}

// MARK: - Рекламный слот-плейсхолдер (каждая 5-я позиция в ленте)

struct AdPlaceholderCard: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Реклама")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "megaphone.fill")
                .font(.system(size: 30))
                .foregroundStyle(Color.sanAccent.opacity(0.8))
            Text("Здесь может быть\nваша реклама")
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text("Заведения — продвигайтесь в Ayta")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.sanAccent.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(Color.sanAccent.opacity(0.4))
        )
    }
}

// MARK: - Категория-сторис (круглая иконка как в Instagram)

struct CategoryStoryCircle: View {
    let label: String
    let icon: String
    let color: Color
    let isOn: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            isOn
                            ? AnyShapeStyle(LinearGradient(colors: [color, .yellow],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color(.systemGray4)),
                            lineWidth: 2.5)
                        .frame(width: 64, height: 64)
                    Image(systemName: icon).font(.title3).foregroundStyle(color)
                }
                Text(label).font(.caption2).foregroundStyle(isOn ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Компактная строка заведения (Saved, результаты)

struct VenueCompactRow: View {
    let venue: Venue
    var distanceKm: Double? = nil
    @EnvironmentObject private var store: AppStore

    private var agg: (rating: Double, count: Int) { store.aggregate(for: venue) }

    var body: some View {
        HStack(spacing: 14) {
            VenueAvatar(venue: venue, size: 62)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(venue.name).font(.body.weight(.semibold)).lineLimit(1)
                    if venue.isVerified {
                        Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(.blue)
                    }
                }
                StarRatingView(rating: agg.rating, count: agg.count, size: 12)
                HStack(spacing: 6) {
                    Text("\(venue.category.rawValue) · \(venue.district)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let distanceKm {
                        Text("· \(distanceKm.distanceText)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Компактная строка предложения (поиск, избранное, заведение)

struct CompactDealRow: View {
    let deal: Deal
    var showVenue = true
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 14) {
            CoverImage(urlString: deal.imageURL,
                       gradient: store.venue(for: deal)?.gradient ?? [.sanAccent, .orange],
                       emoji: deal.emoji, emojiSize: 28)
                .frame(width: 62, height: 62)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 5) {
                Text(deal.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                if showVenue {
                    Text("\(store.venue(for: deal)?.name ?? "") • до \(deal.validUntil.sanShort)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("до \(deal.validUntil.sanShort)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                store.toggleFavorite(deal)
            } label: {
                Image(systemName: store.isFavorite(deal) ? "heart.fill" : "heart")
                    .font(.title3)
                    .foregroundStyle(store.isFavorite(deal) ? Color.sanAccent : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
