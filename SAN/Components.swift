import SwiftUI

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
            if let urlString = venue.imageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Text(venue.emoji).font(.system(size: size * 0.5))
                    }
                }
                .clipShape(Circle())
            } else {
                Text(venue.emoji).font(.system(size: size * 0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
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
    var onTap: () -> Void = {}
    @EnvironmentObject private var store: AppStore

    private var venue: Venue? { store.venue(for: deal) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            visual
            actions
            caption
        }
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let venue { VenueAvatar(venue: venue) }
            VStack(alignment: .leading, spacing: 1) {
                Text(venue?.name ?? "")
                    .font(.subheadline.weight(.semibold))
                Text("\(venue?.category.rawValue ?? "") • \(venue?.district ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            DealTypeBadge(type: deal.type)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var visual: some View {
        ZStack {
            LinearGradient(colors: venue?.gradient ?? [.sanAccent, .orange],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            Text(deal.emoji)
                .font(.system(size: 90))
                .shadow(radius: 8)

            if let percent = deal.discountPercent {
                Text("−\(percent)%")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.35), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topLeading)
                    .padding(12)
            }
        }
        .frame(height: 280)
        .clipped()
    }

    private var actions: some View {
        HStack(spacing: 18) {
            Button {
                store.toggleFavorite(deal)
            } label: {
                Image(systemName: store.isFavorite(deal) ? "heart.fill" : "heart")
                    .font(.title2)
                    .foregroundStyle(store.isFavorite(deal) ? Color.sanAccent : .primary)
            }
            .buttonStyle(.plain)

            ShareLink(item: "\(deal.title) — \(venue?.name ?? ""), \(venue?.address ?? ""). Нашёл в САН!") {
                Image(systemName: "paperplane")
                    .font(.title2)
                    .foregroundStyle(.primary)
            }

            Spacer()

            Label("до \(deal.validUntil.sanShort)", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(deal.title)
                .font(.headline)
            Text(deal.details)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            PriceLabel(deal: deal)
        }
        .padding(.horizontal, 16)
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
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(.systemGray5), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
        .alert("Войдите в аккаунт", isPresented: $showGuestAlert) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Гостям доступен только просмотр. Войдите в профиле, чтобы сохранять места.")
        }
    }

    private var cover: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: venue.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(venue.emoji).font(.system(size: 64)).shadow(radius: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

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
        .frame(height: 150)
        .clipped()
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(venue.name).font(.headline).lineLimit(1)
                if venue.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption).foregroundStyle(.blue)
                }
                Spacer()
                Text(venue.isOpenNow ? "Открыто" : "Закрыто")
                    .font(.caption2.weight(.semibold))
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
                    Label("\(dealCount) САН", systemImage: "tag.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.sanAccent.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.sanAccent)
                }
            }
        }
        .padding(12)
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
            Text("Заведения — продвигайтесь в САН")
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
        HStack(spacing: 12) {
            VenueAvatar(venue: venue, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(venue.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if venue.isVerified {
                        Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.blue)
                    }
                }
                StarRatingView(rating: agg.rating, count: agg.count, size: 11)
                HStack(spacing: 6) {
                    Text("\(venue.category.rawValue) · \(venue.district)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let distanceKm {
                        Text("· \(distanceKm.distanceText)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Компактная строка предложения (поиск, избранное, заведение)

struct CompactDealRow: View {
    let deal: Deal
    var showVenue = true
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: store.venue(for: deal)?.gradient ?? [.sanAccent, .orange],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                Text(deal.emoji).font(.title2)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(deal.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
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
                    .foregroundStyle(store.isFavorite(deal) ? Color.sanAccent : .secondary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
    }
}
