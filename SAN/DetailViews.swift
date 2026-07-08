import SwiftUI
import StoreKit

// MARK: - Детали предложения

struct DealDetailView: View {
    let deal: Deal
    var isPushed: Bool = false   // true — экран в навигационном стеке (push), без «Готово»
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var coupons: CouponStore
    @EnvironmentObject private var loyalty: LoyaltyStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @AppStorage("san.redeemCount") private var redeemCount = 0
    @State private var showMapOptions = false
    @State private var presentedCoupon: Coupon?

    private var venue: Venue? { store.venue(for: deal) }

    var body: some View {
        if isPushed {
            content
        } else {
            NavigationStack {
                content
                    .navigationDestination(for: Venue.self) { VenueDetailView(venue: $0) }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                VStack(alignment: .leading, spacing: 10) {
                    DealTypeBadge(type: deal.type)
                    Text(deal.title).font(.title2.weight(.bold))
                    Text(deal.details).font(.body).foregroundStyle(.secondary)
                    PriceLabel(deal: deal)
                    if let urgency = deal.urgencyText {
                        Label(urgency, systemImage: "flame.fill")
                            .font(.subheadline.weight(.bold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.red.opacity(0.12), in: Capsule())
                            .foregroundStyle(.red)
                    }
                    Label("Действует до \(deal.validUntil.sanShort)", systemImage: "clock")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                showAtVenue
                if venue != nil { venueSection }
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(venue?.name ?? "Предложение")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.log(AnalyticsMetric.dealTaps, for: deal.venueID)
            AnalyticsLog.log(.dealView, ["deal_id": deal.id, "venue_id": deal.venueID])
        }
        .toolbar {
            if !isPushed {
                ToolbarItem(placement: .topBarLeading) { Button("Готово") { dismiss() } }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.toggleFavorite(deal) } label: {
                    Image(systemName: store.isFavorite(deal) ? "bookmark.fill" : "bookmark")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: DeepLinkRouter.dealURL(deal.id),
                          subject: Text(deal.title),
                          message: Text("\(deal.title) — \(venue?.name ?? ""). Нашёл в Ayant!")) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    private var hero: some View {
        ImageCarousel(urls: deal.allImages, gradient: venue?.gradient ?? [.sanAccent, .orange],
                      emoji: deal.emoji, height: 300)
            .overlay(alignment: .topLeading) {
                if let percent = deal.discountPercent {
                    Text("−\(percent)%")
                        .font(.title.weight(.heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(.black.opacity(0.35), in: Capsule())
                        .padding(16)
                }
            }
    }

    @ViewBuilder
    private var showAtVenue: some View {
        // Купон есть только у скидок и акций, и только если заведение принимает купоны.
        // У новинок и объявлений показывать нечего.
        if deal.isRedeemable && (venue?.couponsEnabled ?? true) {
            let dealCoupon = coupons.coupons.first { $0.dealID == deal.id }
            let used = dealCoupon?.used ?? false
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    QRCodeView(text: dealCoupon?.code ?? "AYANT-\(deal.id.uppercased())", size: 92)
                        .opacity(used ? 0.4 : 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(used ? "Купон использован" : "Купон на предложение")
                            .font(.subheadline.weight(.semibold))
                        Text("Сотрудник сканирует QR и применяет предложение перед оплатой.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let c = dealCoupon {
                            Text(c.code).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if used {
                    Label("Купон использован", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity)
                } else if store.isGuest {
                    Text("Войдите в аккаунт, чтобы получить купон.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Button {
                        let vID = venue?.id ?? deal.venueID
                        let vName = venue?.name ?? ""
                        let c = coupons.createDealCoupon(dealID: deal.id, title: deal.title,
                                                         venueID: vID, venueName: vName)
                        presentedCoupon = c
                        bumpRatingPrompt()
                    } label: {
                        Text(dealCoupon == nil ? "Получить купон" : "Показать купон")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(Color.sanAccent, in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sanAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 16)
            .sheet(item: $presentedCoupon) { c in
                NavigationStack { CouponDetailView(coupon: c) }
                    .environmentObject(coupons)
            }
        }
    }

    /// Просим оценить приложение после 1-го и каждого 5-го полученного купона.
    private func bumpRatingPrompt() {
        redeemCount += 1
        if redeemCount == 1 || redeemCount % 5 == 0 {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                requestReview()
            }
        }
    }

    @ViewBuilder
    private var venueSection: some View {
        if let venue {
            VStack(alignment: .leading, spacing: 12) {
                Text("Заведение").font(.headline)
                NavigationLink(value: venue) {
                    HStack(spacing: 12) {
                        VenueAvatar(venue: venue, size: 48)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(venue.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Text("\(venue.category.rawValue) • \(venue.district)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                if !venue.address.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        store.log(AnalyticsMetric.maps, for: venue.id)
                        showMapOptions = true
                    } label: {
                        HStack {
                            Label(venue.address, systemImage: "mappin.and.ellipse").font(.subheadline)
                            Spacer()
                            Image(systemName: "map.fill").foregroundStyle(Color.sanAccent)
                        }
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Открыть на карте", isPresented: $showMapOptions, titleVisibility: .visible) {
                        Button("2GIS") { openURL(Directions.dgis(lat: venue.latitude, lng: venue.longitude)) }
                        Button("Google Maps") { openURL(Directions.google(lat: venue.latitude, lng: venue.longitude)) }
                        Button("Отмена", role: .cancel) {}
                    }
                }
                if !venue.phone.trimmingCharacters(in: .whitespaces).isEmpty,
                   let url = URL(string: "tel:\(venue.phone.filter { !$0.isWhitespace })") {
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
    @EnvironmentObject private var loyalty: LoyaltyStore
    @Environment(\.openURL) private var openURL

    @State private var activeSheet: VenueSheet?
    @State private var hoursExpanded = false
    @State private var photoViewerIndex: Int?
    @State private var reportingReview: Review?
    @State private var showGuestPrompt = false
    @State private var showMapOptions = false

    private var deals: [Deal] { store.deals(for: venue) }
    private var agg: (rating: Double, count: Int) { store.aggregate(for: venue) }
    private var venueReviews: [Review] { store.reviews(for: venue) }

    /// Реальные фото (обложка, объекты, фото из отзывов) + легаси-эмодзи как фолбэк.
    private var galleryPhotos: [String] {
        var out: [String] = []
        if let cover = venue.imageURL, !cover.isEmpty { out.append(cover) }
        out += venue.items.compactMap { $0.imageURL.isEmpty ? nil : $0.imageURL }
        out += venueReviews.flatMap(\.photos)
        out += venue.photoEmojis
        out += venueReviews.flatMap(\.photoEmojis)
        return out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actionRow
                if venue.hasTodaySpecial { todaySpecialBanner }
                if venue.loyaltyEnabled { loyaltyBanner }
                infoSection
                if !deals.isEmpty { dealsGrid }
                if !galleryPhotos.isEmpty { photosGallery }
                if !venue.items.isEmpty { itemsSection }
                reviewsSection
            }
            .padding(.bottom, 32)
        }
        .navigationTitle(venue.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            store.log(AnalyticsMetric.views, for: venue.id)
            AnalyticsLog.log(.venueView, ["venue_id": venue.id])
        }
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
            case .pdf: if let pdf = venue.pdfMenuURL, !pdf.isEmpty { PDFMenuView(urlString: pdf) }
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
                Group {
                    let photos = galleryPhotos.filter { $0.hasPrefix("http") }
                    if photos.count > 1 {
                        ImageCarousel(urls: photos, gradient: venue.gradient, emoji: venue.emoji, height: 190)
                    } else {
                        VenuePhoto(urlString: venue.imageURL, gradient: venue.gradient)
                    }
                }
                .frame(height: 190).clipped()
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
                    Text(venue.category.locKey)
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

    private var hasPhone: Bool {
        !venue.phone.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var hasLocation: Bool {
        !venue.address.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if hasPhone {
                actionButton("Позвонить", "phone.fill") {
                    store.log(AnalyticsMetric.calls, for: venue.id)
                    if let url = URL(string: "tel:\(venue.phone.filter { !$0.isWhitespace })") { openURL(url) }
                }
            }
            if hasLocation {
                actionButton("Маршрут", "location.fill") {
                    store.log(AnalyticsMetric.maps, for: venue.id)
                    openURL(Directions.url(lat: venue.latitude, lng: venue.longitude))
                }
            }
            actionButton(store.isSaved(venue) ? "Сохранено" : "Сохранить",
                         store.isSaved(venue) ? "bookmark.fill" : "bookmark") {
                if session.isGuest { showGuestPrompt = true }
                else { store.toggleSave(venue); store.log(AnalyticsMetric.saves, for: venue.id) }
            }
            ShareLink(item: DeepLinkRouter.venueURL(venue.id),
                      subject: Text(venue.name),
                      message: Text("\(venue.name), \(venue.address). Нашёл в Ayant!")) {
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

    // MARK: Карта лояльности

    private var loyaltyBanner: some View {
        let card = loyalty.card(for: venue.id)
        let stamps = card?.stamps ?? 0
        let goal = venue.loyaltyGoal
        let rounds = card?.completedRounds ?? 0
        return NavigationLink {
            VenueLoyaltyScreen(venue: venue)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "creditcard.fill").foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Карта лояльности").font(.subheadline.weight(.bold)).foregroundStyle(.white)
                        Text("\(goal) визитов → \(venue.loyaltyReward)")
                            .font(.caption).foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                    Text("\(stamps)/\(goal)")
                        .font(.caption.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.25), in: Capsule())
                }
                HStack(spacing: 6) {
                    ForEach(0..<goal, id: \.self) { i in
                        Image(systemName: i < stamps ? "checkmark.seal.fill" : "seal")
                            .font(.footnote)
                            .foregroundStyle(i < stamps ? .white : .white.opacity(0.45))
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill").font(.caption2)
                    Text(rounds > 0
                         ? "Наград получено: \(rounds). Штамп — за каждый использованный купон здесь."
                         : "Штамп начисляется за каждый использованный купон в этом заведении.")
                        .font(.caption2)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .foregroundStyle(.white.opacity(0.9))
            }
            .padding(14)
            .background(
                LinearGradient(colors: [Color(hex: 0xFF4D29), Color(hex: 0xFFB300)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    // MARK: Инфо

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !venue.address.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    store.log(AnalyticsMetric.maps, for: venue.id)
                    showMapOptions = true
                } label: {
                    HStack {
                        Label(venue.address, systemImage: "mappin.and.ellipse").font(.subheadline)
                        Spacer()
                        Image(systemName: "map.fill").foregroundStyle(Color.sanAccent)
                    }
                }
                .buttonStyle(.plain)
                .confirmationDialog("Открыть на карте", isPresented: $showMapOptions, titleVisibility: .visible) {
                    Button("2GIS") { openURL(Directions.dgis(lat: venue.latitude, lng: venue.longitude)) }
                    Button("Google Maps") { openURL(Directions.google(lat: venue.latitude, lng: venue.longitude)) }
                    Button("Отмена", role: .cancel) {}
                }
            }
            // Дополнительные адреса (филиалы)
            ForEach(venue.branches) { b in
                Button { openURL(Directions.dgis(lat: b.latitude, lng: b.longitude)) } label: {
                    HStack {
                        Label(b.address, systemImage: "mappin.and.ellipse").font(.subheadline)
                        Spacer()
                        Image(systemName: "map").foregroundStyle(Color.sanAccent)
                    }
                }
                .buttonStyle(.plain)
            }
            if !venue.phone.trimmingCharacters(in: .whitespaces).isEmpty,
               let url = URL(string: "tel:\(venue.phone.filter { !$0.isWhitespace })") {
                Link(destination: url) { Label(venue.phone, systemImage: "phone.fill").font(.subheadline) }
            }
            if venue.whatsappURL != nil || venue.instagramURL != nil || venue.telegramURL != nil {
                HStack(spacing: 12) {
                    if let wa = venue.whatsappURL {
                        socialIcon("message.fill", .green, wa)
                    }
                    if let tg = venue.telegramURL {
                        socialIcon("paperplane.fill", Color(hex: 0x29A9EB), tg)
                    }
                    if let ig = venue.instagramURL {
                        socialIcon("camera.fill", Color(hex: 0xC13584), ig)
                    }
                }
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
                    ForEach(0..<7, id: \.self) { i in
                        let isToday = i == Venue.todayIndex
                        HStack {
                            Text(Venue.weekdayLong[i])
                                .font(.caption)
                                .fontWeight(isToday ? .semibold : .regular)
                                .foregroundStyle(isToday ? .primary : .secondary)
                            Spacer()
                            Text(venue.hours(for: i).label)
                                .font(.caption)
                                .foregroundStyle(venue.hours(for: i).closed ? .secondary : .primary)
                        }
                    }
                }
                .padding(.leading, 28)
            }
            if let pdf = venue.pdfMenuURL, !pdf.isEmpty {
                Button { activeSheet = .pdf } label: {
                    Label("Прайс-лист / каталог (PDF)", systemImage: "doc.text").font(.subheadline)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private func socialIcon(_ icon: String, _ color: Color, _ url: URL) -> some View {
        Link(destination: url) {
            Image(systemName: icon)
                .font(.headline).foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(color, in: Circle())
        }
    }


    // MARK: Публикации заведения (последние 3 + «смотреть все»)

    // Показываем первые 6 публикаций; если их больше — кнопка ведёт на
    // отдельный экран с подгрузкой (пагинацией).
    private var shownDeals: [Deal] { Array(deals.prefix(6)) }

    private var dealsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Публикации").font(.headline)
                Spacer()
                if deals.count > 6 {
                    NavigationLink {
                        VenueDealsView(venue: venue)
                    } label: {
                        Text("Смотреть все (\(deals.count))")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .padding(.horizontal, 16)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(shownDeals) { deal in
                    Button { activeSheet = .deal(deal) } label: {
                        DealGridCell(deal: deal, gradient: venue.gradient)
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
                            GalleryImage(value: p, emojiSize: 40)
                                .frame(width: 90, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
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
                                ItemThumb(item: item, size: 70)
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

/// Ячейка публикации в сетке (квадрат с обложкой и бейджем скидки).
struct DealGridCell: View {
    let deal: Deal
    let gradient: [Color]

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                CoverImage(urlString: deal.imageURL, gradient: gradient,
                           emoji: deal.emoji, emojiSize: 34)
            }
            .overlay(alignment: .bottomLeading) {
                if let pct = deal.discountPercent {
                    Text("−\(pct)%")
                        .font(.caption2.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.black.opacity(0.4), in: Capsule())
                        .padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Все публикации заведения с постраничной подгрузкой (по 12 за раз).
struct VenueDealsView: View {
    let venue: Venue
    @EnvironmentObject private var store: AppStore
    @State private var visibleCount = 12
    @State private var selectedDeal: Deal?

    private static let pageSize = 12
    private var deals: [Deal] { store.deals(for: venue) }
    private var shown: [Deal] { Array(deals.prefix(visibleCount)) }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(shown) { deal in
                    Button { selectedDeal = deal } label: {
                        DealGridCell(deal: deal, gradient: venue.gradient)
                    }
                    .buttonStyle(.plain)
                    .onAppear { loadMoreIfNeeded(deal) }
                }
            }
            .padding(16)
            if visibleCount < deals.count {
                ProgressView().padding(.bottom, 20)
            }
        }
        .navigationTitle("Публикации")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedDeal) { deal in
            DealDetailView(deal: deal)
        }
    }

    private func loadMoreIfNeeded(_ deal: Deal) {
        guard deal.id == shown.last?.id, visibleCount < deals.count else { return }
        visibleCount = min(visibleCount + Self.pageSize, deals.count)
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
            .environmentObject(LoyaltyStore())
    }
    .tint(.sanAccent)
}
