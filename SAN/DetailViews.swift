import SwiftUI

// MARK: - Детали предложения

struct DealDetailView: View {
    let deal: Deal
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private var venue: Venue? { store.venue(for: deal) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    VStack(alignment: .leading, spacing: 10) {
                        DealTypeBadge(type: deal.type)
                        Text(deal.title).font(.title2.weight(.bold))
                        Text(deal.details).font(.body).foregroundStyle(.secondary)
                        PriceLabel(deal: deal)
                        Label("Действует до \(deal.validUntil.sanShort)", systemImage: "clock")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    showAtVenue
                    if venue != nil { venueSection }
                }
                .padding(.bottom, 24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button { store.toggleFavorite(deal) } label: {
                        Image(systemName: store.isFavorite(deal) ? "bookmark.fill" : "bookmark")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: DeepLinkRouter.dealURL(deal.id),
                              subject: Text(deal.title),
                              message: Text("\(deal.title) — \(venue?.name ?? ""). Нашёл в САН!")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private var hero: some View {
        ZStack {
            LinearGradient(colors: venue?.gradient ?? [.sanAccent, .orange],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(deal.emoji).font(.system(size: 100)).shadow(radius: 10)
            if let percent = deal.discountPercent {
                Text("−\(percent)%")
                    .font(.title.weight(.heavy)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.black.opacity(0.35), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
            }
        }
        .frame(height: 260)
        .clipped()
    }

    private var showAtVenue: some View {
        HStack(spacing: 12) {
            Image(systemName: "qrcode.viewfinder").font(.title).foregroundStyle(Color.sanAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Покажи этот экран сотруднику").font(.subheadline.weight(.semibold))
                Text("Код: САН-\(deal.id.uppercased())").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sanAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var venueSection: some View {
        if let venue {
            VStack(alignment: .leading, spacing: 12) {
                Text("Заведение").font(.headline)
                HStack(spacing: 12) {
                    VenueAvatar(venue: venue, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(venue.name).font(.subheadline.weight(.semibold))
                        Text("\(venue.category.rawValue) • \(venue.district)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Label(venue.address, systemImage: "mappin.and.ellipse").font(.subheadline)
                if let url = URL(string: "tel:\(venue.phone.filter { !$0.isWhitespace })") {
                    Link(destination: url) {
                        Label(venue.phone, systemImage: "phone.fill").font(.subheadline)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Страница заведения (полная, по спецификации)

struct VenueDetailView: View {
    let venue: Venue
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var session: SessionStore
    @Environment(\.openURL) private var openURL

    @State private var activeSheet: VenueSheet?
    @State private var hoursExpanded = false
    @State private var photoViewerIndex: Int?
    @State private var reportingReview: Review?
    @State private var showGuestPrompt = false

    private var deals: [Deal] { store.deals(for: venue) }
    private var agg: (rating: Double, count: Int) { store.aggregate(for: venue) }
    private var venueReviews: [Review] { store.reviews(for: venue) }

    /// Фото заведения + фото из отзывов.
    private var galleryPhotos: [String] {
        venue.photoEmojis + venueReviews.flatMap(\.photoEmojis)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actionRow
                if venue.hasTodaySpecial { todaySpecialBanner }
                infoSection
                mapTile
                if !deals.isEmpty { dealsGrid }
                if !galleryPhotos.isEmpty { photosGallery }
                if !venue.items.isEmpty { itemsSection }
                reviewsSection
            }
            .padding(.bottom, 32)
        }
        .navigationTitle(venue.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.log(AnalyticsMetric.views, for: venue.id) }
        .alert("Войдите в аккаунт", isPresented: $showGuestPrompt) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Гостям доступен только просмотр. Войдите в профиле, чтобы сохранять и оставлять отзывы.")
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .deal(let deal): DealDetailView(deal: deal)
            case .writeReview(let itemID):
                WriteReviewView(venue: venue,
                                existing: store.myReview(venueID: venue.id, itemID: itemID),
                                preselectItemID: itemID)
            case .pdf: if let pdf = venue.pdfMenuURL { PDFMenuView(urlString: pdf) }
            }
        }
        .fullScreenCover(item: Binding(
            get: { photoViewerIndex.map { IndexBox(value: $0) } },
            set: { photoViewerIndex = $0?.value }
        )) { box in
            PhotoViewerView(photos: galleryPhotos, startIndex: box.value)
        }
    }

    // MARK: Шапка

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: venue.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 190)
                Text(venue.emoji).font(.system(size: 70))
                    .frame(maxWidth: .infinity).frame(height: 190)
                VenueAvatar(venue: venue, size: 64)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
                    .offset(x: 16, y: 32)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(venue.name).font(.title2.weight(.bold))
                    if venue.isVerified {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue)
                    }
                }
                HStack(spacing: 8) {
                    Text(venue.category.rawValue)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color(.systemGray6), in: Capsule())
                    StarRatingView(rating: agg.rating, count: agg.count)
                }
                if venue.savedByCount > 0 {
                    Label("Сохранили \(venue.savedByCount) человек", systemImage: "bookmark.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 40)
        }
    }

    // MARK: Действия

    private var actionRow: some View {
        HStack(spacing: 10) {
            actionButton("Позвонить", "phone.fill") {
                store.log(AnalyticsMetric.calls, for: venue.id)
                if let url = URL(string: "tel:\(venue.phone.filter { !$0.isWhitespace })") { openURL(url) }
            }
            actionButton("Маршрут", "location.fill") {
                store.log(AnalyticsMetric.maps, for: venue.id)
                openURL(Directions.url(lat: venue.latitude, lng: venue.longitude))
            }
            actionButton(store.isSaved(venue) ? "Сохранено" : "Сохранить",
                         store.isSaved(venue) ? "bookmark.fill" : "bookmark") {
                if session.isGuest { showGuestPrompt = true }
                else { store.toggleSave(venue); store.log(AnalyticsMetric.saves, for: venue.id) }
            }
            ShareLink(item: DeepLinkRouter.venueURL(venue.id),
                      subject: Text(venue.name),
                      message: Text("\(venue.name), \(venue.address). Нашёл в САН!")) {
                actionLabel("Поделиться", "square.and.arrow.up")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private func actionButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(title, icon) }.buttonStyle(.plain)
    }

    private func actionLabel(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.subheadline)
            Text(title).font(.caption2)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(Color.sanAccent)
    }

    // MARK: Сегодняшний специал

    private var todaySpecialBanner: some View {
        HStack(spacing: 10) {
            Text("⭐️").font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Сегодня").font(.caption.weight(.bold)).foregroundStyle(Color.sanAccent)
                Text(venue.todaySpecialText ?? "").font(.subheadline.weight(.medium))
            }
            Spacer()
        }
        .padding(14)
        .background(Color.sanAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    // MARK: Инфо

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Label(venue.address, systemImage: "mappin.and.ellipse").font(.subheadline)
                HStack(spacing: 10) {
                    mapLinkButton("2GIS") { openURL(Directions.dgis(lat: venue.latitude, lng: venue.longitude)) }
                    mapLinkButton("Google Maps") { openURL(Directions.google(lat: venue.latitude, lng: venue.longitude)) }
                }
            }
            if let url = URL(string: "tel:\(venue.phone.filter { !$0.isWhitespace })") {
                Link(destination: url) { Label(venue.phone, systemImage: "phone.fill").font(.subheadline) }
            }
            Button { withAnimation { hoursExpanded.toggle() } } label: {
                HStack {
                    Label(venue.hoursStatusText, systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(venue.isOpenNow ? .green : .secondary)
                    Spacer()
                    Image(systemName: hoursExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            if hoursExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(weekdays, id: \.self) { day in
                        HStack {
                            Text(day).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%02d:00 – %02d:00", venue.openHour, venue.closeHour))
                                .font(.caption)
                        }
                    }
                }
                .padding(.leading, 28)
            }
            if venue.pdfMenuURL != nil {
                Button { activeSheet = .pdf } label: {
                    Label("Меню (PDF)", systemImage: "doc.text").font(.subheadline)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private var weekdays: [String] {
        ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"]
    }

    private func mapLinkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.sanAccent.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.sanAccent)
        }
        .buttonStyle(.plain)
    }

    // MARK: Карта (статичный тайл → маршрут)

    private var mapTile: some View {
        Button { openURL(Directions.url(lat: venue.latitude, lng: venue.longitude)) } label: {
            ZStack {
                LinearGradient(colors: [Color(.systemGray5), Color(.systemGray4)],
                               startPoint: .top, endPoint: .bottom)
                VStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill").font(.system(size: 38)).foregroundStyle(Color.sanAccent)
                    Text("Открыть маршрут").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: Сетка предложений (3 колонки)

    private var dealsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Предложения").font(.headline).padding(.horizontal, 16)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(deals) { deal in
                    Button { store.log(AnalyticsMetric.dealTaps, for: venue.id); activeSheet = .deal(deal) } label: {
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(colors: venue.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                            Text(deal.emoji).font(.system(size: 34))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            if let pct = deal.discountPercent {
                                Text("−\(pct)%")
                                    .font(.caption2.weight(.bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(.black.opacity(0.4), in: Capsule())
                                    .padding(6)
                            }
                        }
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: Галерея фото

    private var photosGallery: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Фото").font(.headline).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(galleryPhotos.enumerated()), id: \.offset) { i, p in
                        Button { photoViewerIndex = i } label: {
                            Text(p).font(.system(size: 40))
                                .frame(width: 90, height: 90)
                                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: Объекты для отзывов (блюда/услуги)

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Оценить блюдо или услугу").font(.headline).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(venue.items) { item in
                        Button {
                            if session.isGuest { showGuestPrompt = true }
                            else { activeSheet = .writeReview(item.id) }
                        } label: {
                            VStack(spacing: 6) {
                                Text(item.emoji).font(.system(size: 34))
                                    .frame(width: 70, height: 70)
                                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
                                Text(item.name).font(.caption).lineLimit(1)
                                    .frame(maxWidth: 80)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: Отзывы

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Отзывы").font(.headline).padding(.horizontal, 16)

            HStack(alignment: .center, spacing: 20) {
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", agg.rating)).font(.system(size: 40, weight: .bold))
                    StarRatingView(rating: agg.rating, size: 12)
                    Text("\(agg.count) отзывов").font(.caption2).foregroundStyle(.secondary)
                }
                RatingBreakdownView(breakdown: store.ratingBreakdown(for: venue))
            }
            .padding(.horizontal, 16)

            if venue.items.isEmpty {
                Text("Отзывы оставляются на конкретные блюда и услуги. Заведение пока не добавило объекты для оценки.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else {
                Button {
                    if session.isGuest { showGuestPrompt = true } else { activeSheet = .writeReview(nil) }
                } label: {
                    Label("Оценить блюдо или услугу", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.sanAccent, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }

            if venueReviews.isEmpty {
                Text("Пока нет отзывов. Будь первым!")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(venueReviews) { review in
                        ReviewRow(review: review)
                            .contextMenu {
                                if review.authorID != store.currentUserID {
                                    Button(role: .destructive) { reportingReview = review } label: {
                                        Label("Пожаловаться", systemImage: "flag")
                                    }
                                }
                            }
                        Divider()
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .confirmationDialog("Пожаловаться на отзыв", isPresented: Binding(
            get: { reportingReview != nil }, set: { if !$0 { reportingReview = nil } }
        ), titleVisibility: .visible) {
            Button("Фейк", role: .destructive) { reportingReview = nil }
            Button("Спам", role: .destructive) { reportingReview = nil }
            Button("Оскорбительное", role: .destructive) { reportingReview = nil }
            Button("Отмена", role: .cancel) { reportingReview = nil }
        }
    }
}

/// Обёртка Int для item-based fullScreenCover.
private struct IndexBox: Identifiable {
    let value: Int
    var id: Int { value }
}

/// Единый источник для всех модальных листов страницы заведения.
private enum VenueSheet: Identifiable {
    case deal(Deal)
    case writeReview(String?)   // itemID или nil (о заведении в целом)
    case pdf

    var id: String {
        switch self {
        case .deal(let d): return "deal_\(d.id)"
        case .writeReview(let item): return "writeReview_\(item ?? "venue")"
        case .pdf: return "pdf"
        }
    }
}

#Preview {
    NavigationStack {
        VenueDetailView(venue: MockData.venues[0])
            .environmentObject(AppStore())
            .environmentObject(LocationManager())
            .environmentObject(SessionStore())
    }
    .tint(.sanAccent)
}
