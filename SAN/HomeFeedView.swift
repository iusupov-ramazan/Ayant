import SwiftUI
import UserNotifications
import AyantDomain
import AyantFeatures

/// Главная (SCREENS.md G2) — определяющий экран редизайна.
///
/// Шапка с редакторским «Сегодня», липкий ряд текстовых чипов категорий и лента
/// постов: белая полоса, фото 4:5, весь текст под фотографией (см. `FeedCard.swift`).
/// Кружки-сторис категорий на пенсии: картинку несут сами посты.
struct HomeFeedView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var location: LocationManager
    @ObservedObject private var catStore = CategoryStore.shared
    @State private var category: VenueCategory?
    @State private var path = NavigationPath()
    @State private var visibleCount = 8       // пагинация ленты
    @State private var showGuestAlert = false
    @State private var guestMessage = GuestGate.saveVenue
    @State private var notificationsOff = false
    @State private var shareItem: DealShare?
    private static let pageSize = 8

    private var items: [FeedItem] { feedStore.items(category: category) }
    private var feed: [Deal] { feedStore.deals(category: category) }
    /// Заведения для ряда «Заведения»: ранжированный каталог по категории
    /// (одобренные, не на паузе), первые `venueRailLimit` — ряд, а не список.
    private var railVenues: [Venue] {
        Array(feedStore.venues(category: category).prefix(Self.venueRailLimit))
    }
    private static let venueRailLimit = 12

    /// Якорь самого верха экрана — к нему возвращаемся при смене категории.
    ///
    /// Именно шапка, а не начало ленты: подборка по категории бывает короче
    /// экрана, и тогда единственная допустимая позиция прокрутки — ноль.
    /// Целясь в начало секции, мы просили позицию, которой нет, и лента
    /// оставалась в подвешенном состоянии — с пустым холстом под чипами.
    private static let feedTopID = "feedTop"

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    header.id(Self.feedTopID)
                    Section {
                        // «Сегодня в избранном» — существующая функция, которой нет
                        // в макете. Оставлена над лентой, чтобы редизайн ничего
                        // молча не удалил.
                        if !store.savedTodaySpecials.isEmpty {
                            todaySpecialStrip.padding(.bottom, 18)
                        }
                        // Пока вкладка «Поиск» скрыта (`ReleaseFlags.searchTab`),
                        // это единственный список заведений в приложении —
                        // без него человек видел бы только акции.
                        if showsVenueRail {
                            venueRail.padding(.bottom, 18)
                        }
                        feedContent
                    } header: {
                        categoryRail
                    }
                }
                .padding(.bottom, 26)
            }
            .background(Color.sanCanvas.ignoresSafeArea())
            .sanStatusBarCap()
            .refreshable { await store.load() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Venue.self) { VenueDetailView(venue: $0) }
            .navigationDestination(for: Deal.self) { DealDetailView(deal: $0, isPushed: true) }
            .navigationDestination(for: FeedRoute.self) { route in
                switch route {
                case .saved: SavedView()
                }
            }
            // Смена категории возвращает ленту в начало.
            //
            // Без этого экран уезжал в пустоту: прокрутка остаётся там, где
            // была, а подборка по категории — плитки в две колонки — втрое
            // короче полноэкранной ленты. Позиция оказывалась за концом нового
            // содержимого, и человек видел чистый холст, решая, что всё
            // сломалось. Без анимации: фильтр должен срабатывать мгновенно.
            .onChange(of: category) { _, _ in
                visibleCount = Self.pageSize
                store.logFeedImpression(category: category, userCoord: location.lastLocation)
                // Прокрутка — СЛЕДУЮЩИМ проходом, а не сразу: в момент
                // `onChange` лента ещё старая, и `scrollTo` целился бы по
                //высоте, которой уже нет. Отсюда и оставалась пустота.
                Task { @MainActor in
                    proxy.scrollTo(Self.feedTopID, anchor: .top)
                }
            }
            .onAppear {
                store.logFeedImpression(category: category, userCoord: location.lastLocation)
            }
            .task { await refreshNotificationState() }
            .sheet(item: $shareItem) { item in
                ShareSheet(text: item.text)
            }
            .guestAlert(isPresented: $showGuestAlert, message: guestMessage)
            }
        }
    }

    // MARK: Шапка

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                cityRow
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    NavigationLink(value: FeedRoute.saved) {
                        headerIcon("bookmark")
                    }
                    .buttonStyle(.sanPress(0.90))
                    .accessibilityLabel("Сохранённое")

                    bellButton
                }
            }

            Text("Сегодня")
                .sanEditorialTitle(46)
                .foregroundStyle(Color.sanInk)
                .padding(.top, 16)

            Text("Живые предложения рядом — обновляются каждый день.")
                .sanText(14, .regular, lineHeight: 1.42)
                .foregroundStyle(Color.sanInkSoft)
                .frame(maxWidth: 270, alignment: .leading)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SanMetrics.screenPadding)
        .padding(.top, 12)
        .sanScreenEnter()
    }

    private var cityRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.sanAccentText)
            // Без шеврона: города пока не выбираются, и стрелка обещала бы
            // меню, которого нет. Это подпись, а не кнопка.
            Text(L(store.selectedCity.name))
                .font(.golos(13.5, .bold)).tracking(-0.2)
                .foregroundStyle(Color.sanInk)
        }
    }

    private func headerIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.sanInk)
            .frame(width: 38, height: 38)
            .background(Color.sanSurface,
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    /// Колокольчик. В приложении нет экрана уведомлений, поэтому кнопка ведёт в
    /// системные настройки, а точка горит, когда уведомления НЕ разрешены —
    /// то есть сигналит «включи», а не «есть непрочитанное».
    private var bellButton: some View {
        Button {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        } label: {
            headerIcon("bell")
                .overlay(alignment: .topTrailing) {
                    if notificationsOff {
                        Circle()
                            .fill(Color.sanAccentDeep)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().strokeBorder(Color.sanSurface, lineWidth: 2))
                            .padding(.top, 8).padding(.trailing, 9)
                    }
                }
        }
        .buttonStyle(.sanPress(0.90))
        .accessibilityLabel("Уведомления")
    }

    private func refreshNotificationState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsOff = settings.authorizationStatus != .authorized
    }

    // MARK: Липкий ряд категорий

    private var categoryRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Всё", isOn: category == nil) { category = nil }
                ForEach(catStore.categories) { cat in
                    chip(LocalizedStringKey(cat.rawValue), isOn: category == cat) {
                        category = (category == cat) ? nil : cat
                    }
                }
            }
            .padding(.horizontal, SanMetrics.screenPadding)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        .padding(.top, 18)
        .padding(.bottom, 14)
        // Градиентная маска, из-под которой уезжает крупный заголовок.
        .background(
            LinearGradient(stops: [.init(color: .sanCanvas, location: 0.62),
                                   .init(color: .sanCanvas.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private func chip(_ title: LocalizedStringKey, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            SanHaptics.selection()
            action()
        } label: {
            Text(title)
                .font(.golos(13.5, .bold)).tracking(-0.2)
                .lineLimit(1)
                .foregroundStyle(isOn ? Color.white : Color.sanInkSoft)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background {
                    if isOn {
                        Capsule().fill(LinearGradient.sanAccentGradient)
                            .shadow(color: Color.sanAccent.opacity(0.30), radius: 10, y: 8)
                    } else {
                        Capsule().fill(Color.sanSurface)
                            .shadow(color: .black.opacity(0.05), radius: 1.5, y: 1)
                    }
                }
        }
        .buttonStyle(.sanPress(0.93))
    }

    // MARK: Лента

    @ViewBuilder
    private var feedContent: some View {
        if feedStore.isLoading {
            FeedSkeleton()
        } else if feedStore.loadFailed {
            loadFailure
        } else if !feedStore.hasVenuesInCity {
            emptyCity
        } else if feed.isEmpty {
            emptyCategory
        } else if category != nil {
            // Выбрана категория — это ПОДБОР, а не лента: человек сравнивает
            // варианты, а не залипает. Полноэкранные карточки дают одно
            // предложение на экран, плитки — вчетверо больше.
            categoryGrid
        } else {
            let shown = Array(items.prefix(visibleCount))
            LazyVStack(spacing: 10) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    card(for: item)
                        .sanRise(index, stagger: SanTiming.feedRise.stagger,
                                 duration: SanTiming.feedRise.duration,
                                 cap: SanTiming.feedStaggerCap)
                        .onAppear { loadMoreIfNeeded(item, in: shown) }
                }
                if visibleCount < items.count {
                    ProgressView().padding(.vertical, 16)
                }
            }
        }
    }

    /// Подбор по категории: две колонки, как в «Сохранённом» и на витрине
    /// заведения. Лента «Сегодня» остаётся полноэкранной — она курируемая.
    private var categoryGrid: some View {
        let shown = Array(feed.prefix(visibleCount))
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                   GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, deal in
                Button { path.append(deal) } label: { categoryTile(deal) }
                    .buttonStyle(.sanPress(0.97))
                    .sanRise(index, stagger: SanTiming.gridTileRise.stagger,
                             duration: SanTiming.gridTileRise.duration)
                    .onAppear {
                        if deal.id == shown.last?.id, visibleCount < feed.count {
                            visibleCount = min(visibleCount + Self.pageSize, feed.count)
                        }
                    }
            }
        }
        .padding(.horizontal, SanMetrics.screenPadding)
    }

    private func categoryTile(_ deal: Deal) -> some View {
        let venue = store.venue(for: deal)
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                VenuePhoto(urlString: deal.allImages.first,
                           gradient: venue?.gradientColors ?? [.sanAccent, Color(hex: Palette.orange)])
                    .frame(height: 118)
                    .frame(maxWidth: .infinity)
                    .clipped()
                if let percent = deal.effectiveDiscountPercent {
                    Text("−\(percent)%")
                        .font(.golos(12.5, .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(LinearGradient.sanAccentGradient, in: Capsule())
                        .padding(8)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(deal.title)
                    .sanText(14, .bold, tracking: -0.25, lineHeight: 1.2)
                    .foregroundStyle(Color.sanInk)
                    .lineLimit(2).multilineTextAlignment(.leading)
                if let venue {
                    Text(venue.name)
                        .font(.golos(11.5)).foregroundStyle(Color.sanInkSoft).lineLimit(1)
                }
                if let new = deal.newPrice {
                    Text("\(new) сом")
                        .font(.golos(14, .heavy)).tracking(-0.3)
                        .foregroundStyle(Color.sanAccentText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(Color.sanSurface)
        .clipShape(RoundedRectangle(cornerRadius: SanRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SanRadius.card, style: .continuous)
            .strokeBorder(Color.sanHairline, lineWidth: 0.5))
    }

    @ViewBuilder
    private func card(for item: FeedItem) -> some View {
        switch item {
        case .deal(let deal):
            let venue = store.venue(for: deal)
            FeedDealCard(
                deal: deal,
                venue: venue,
                distanceKm: venue.flatMap { location.distanceKm(to: $0.latitude, $0.longitude) },
                isSaved: store.isFavorite(deal),
                isLiked: store.isLiked(deal),
                onOpen: { path.append(deal) },
                onVenue: { if let venue { path.append(venue) } },
                onSave: { toggleFavorite(deal) },
                onLike: { toggleLike(deal) },
                onShare: { shareItem = DealShare(deal: deal, venue: venue) })

        case .adVenue(let venue):
            FeedAdVenueCard(
                venue: venue,
                distanceKm: location.distanceKm(to: venue.latitude, venue.longitude),
                isSaved: store.isSaved(venue),
                onOpen: { path.append(venue) },
                onSave: { toggleSave(venue) })
        }
    }

    /// Лайк тоже требует аккаунта: он кормит ранжирование и должен переезжать
    /// с пользователем, а не оставаться на устройстве следующему вошедшему.
    private func toggleLike(_ deal: Deal) {
        guard !store.isGuest else { guestMessage = GuestGate.like; showGuestAlert = true; return }
        if !store.isLiked(deal) { SanHaptics.save() }
        store.toggleLike(deal)
    }

    private func toggleFavorite(_ deal: Deal) {
        guard !store.isGuest else { guestMessage = GuestGate.saveDeal; showGuestAlert = true; return }
        if !store.isFavorite(deal) { SanHaptics.save() }
        store.toggleFavorite(deal)
    }

    private func toggleSave(_ venue: Venue) {
        guard !store.isGuest else { guestMessage = GuestGate.saveVenue; showGuestAlert = true; return }
        if !store.isSaved(venue) { SanHaptics.save() }
        store.toggleSave(venue)
    }

    private func loadMoreIfNeeded(_ item: FeedItem, in shown: [FeedItem]) {
        guard item.id == shown.last?.id, visibleCount < items.count else { return }
        visibleCount = min(visibleCount + Self.pageSize, items.count)
    }

    // MARK: Заведения

    /// Ряд есть только у готовой ленты: на скелетоне, ошибке и пустом городе
    /// показывать нечего. Для выбранной категории ряд тоже остаётся — он
    /// полезнее всего, когда акций в категории ещё нет.
    private var showsVenueRail: Bool {
        !feedStore.isLoading && !feedStore.loadFailed && !railVenues.isEmpty
    }

    private var venueRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Заведения")
                .textCase(.uppercase)
                .sanEyebrowText()
                .foregroundStyle(Color.sanInkSoft)
                .padding(.horizontal, SanMetrics.screenPadding)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(railVenues) { venue in
                        // Тот же маршрут, что у рекламной карточки в ленте:
                        // `Venue` в `path` → `VenueDetailView`.
                        Button { path.append(venue) } label: {
                            FeedVenueTile(
                                venue: venue,
                                rating: store.aggregate(for: venue).rating,
                                distanceKm: location.distanceKm(to: venue.latitude, venue.longitude))
                        }
                        .buttonStyle(.sanPress(0.97))
                    }
                }
                .padding(.horizontal, SanMetrics.screenPadding)
            }
            .scrollClipDisabled()
        }
    }

    // MARK: «Сегодня в избранном»

    private var todaySpecialStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Сегодня в избранном")
                .textCase(.uppercase)
                .sanEyebrowText()
                .foregroundStyle(Color.sanInkSoft)
                .padding(.horizontal, SanMetrics.screenPadding)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.savedTodaySpecials) { venue in
                        NavigationLink(value: venue) { specialCard(venue) }
                            .buttonStyle(.sanPress(0.97))
                    }
                }
                .padding(.horizontal, SanMetrics.screenPadding)
            }
            .scrollClipDisabled()
        }
    }

    private func specialCard(_ venue: Venue) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LinearGradient(colors: venue.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 74)
                .overlay(Text(venue.emoji).font(.system(size: 32)))
            VStack(alignment: .leading, spacing: 4) {
                Text(venue.name)
                    .font(.golos(14, .bold)).tracking(-0.25)
                    .foregroundStyle(Color.sanInk).lineLimit(1)
                Text(venue.todaySpecialText ?? "")
                    .font(.golos(11.5)).foregroundStyle(Color.sanInkSoft).lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 200)
        .background(Color.sanSurface,
                    in: RoundedRectangle(cornerRadius: SanRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SanRadius.card, style: .continuous)
            .strokeBorder(Color.sanHairline, lineWidth: 0.5))
        .sanShadow(.card)
    }

    // MARK: Пустые состояния

    /// Каталог не загрузился. Раньше этот случай попадал в «нет заведений в
    /// городе»: пустой экран без объяснения и без кнопки повторить.
    private var loadFailure: some View {
        VStack(spacing: 12) {
            ContentUnavailableView {
                Label("Не удалось загрузить ленту", systemImage: "wifi.exclamationmark")
            } description: {
                Text(feedStore.loadError ?? "Проверьте интернет и попробуйте ещё раз.")
            }
            Button("Повторить") { Task { await store.load() } }
                .buttonStyle(.bordered)
                .tint(.sanAccent)
        }
        .padding(.top, 40)
    }

    private var emptyCity: some View {
        ContentUnavailableView {
            Label("Пока нет заведений в \(store.selectedCity.name)", systemImage: "storefront")
        } description: {
            Text("Знаешь хорошее место? Помоги нам — добавь заведение.")
        }
        .padding(.top, 40)
    }

    private var emptyCategory: some View {
        VStack(spacing: 12) {
            ContentUnavailableView {
                Label("Нет предложений в категории", systemImage: "tray")
            } description: {
                Text("В категории «\(category?.rawValue ?? "")» в городе \(store.selectedCity.name) пока нет акций.")
            }
            Button("Сбросить фильтр") { category = nil }
                .buttonStyle(.bordered)
                .tint(.sanAccent)
        }
        .padding(.top, 40)
    }
}

/// Маршруты ленты, у которых нет собственной модели (в отличие от `Venue`/`Deal`).
enum FeedRoute: Hashable {
    case saved
}

/// Плитка заведения в ряду «Заведения» на главной: обложка, название,
/// категория, рейтинг и расстояние. Нарочно лёгкая — в `LazyHStack` их дюжина.
struct FeedVenueTile: View {
    let venue: Venue
    let rating: Double
    var distanceKm: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VenuePhoto(urlString: venue.imageURL, gradient: venue.gradientColors)
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if venue.isOpenNow {
                        Circle().fill(Color(hex: 0x2FA24C))
                            .frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                            .padding(8)
                            .accessibilityLabel("Открыто")
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(venue.name)
                        .font(.golos(13.5, .bold)).tracking(-0.25)
                        .foregroundStyle(Color.sanInk).lineLimit(1)
                    if venue.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color(hex: 0x4DA3FF))
                    }
                }
                Text(venue.category.locKey)
                    .font(.golos(11.5)).foregroundStyle(Color.sanInkSoft).lineLimit(1)
                HStack(spacing: 6) {
                    if rating > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 9.5))
                                .foregroundStyle(Color(hex: Palette.orange))
                            Text(rating.sanRatingText)
                        }
                    }
                    if let distanceKm {
                        Text(distanceKm.distanceText)
                    }
                }
                .font(.golos(11.5, .semibold)).foregroundStyle(Color.sanInkSoft)
                .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 156)
        .background(Color.sanSurface)
        .clipShape(RoundedRectangle(cornerRadius: SanRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SanRadius.card, style: .continuous)
            .strokeBorder(Color.sanHairline, lineWidth: 0.5))
        .contentShape(Rectangle())
    }
}

#Preview {
    HomeFeedView()
        .environmentObject(AyantStores.app())
        .environmentObject(AyantStores.app().feed)
        .environmentObject(LocationManager())
        .tint(.sanAccent)
}


// MARK: - Поделиться

/// Обёртка для `.sheet(item:)` — что именно отправляем.
struct DealShare: Identifiable {
    let deal: Deal
    let venue: Venue?
    var id: String { deal.id }

    /// Тот же Universal Link, что и в шаринге с экрана предложения
    /// (`DeepLinks.dealURL`): получатель откроет акцию в приложении.
    var text: String {
        var parts = [deal.title]
        if let venue { parts.append(venue.name) }
        if let new = deal.newPrice { parts.append("\(new) сом") }
        return parts.joined(separator: " · ") + "\n" + DeepLinks.dealURL(deal.id).absoluteString
    }
}

/// Системный лист «Поделиться».
struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
