import SwiftUI
import PhotosUI
import WebKit
import AyantDomain
import AyantFeatures

// MARK: - Написать / редактировать отзыв (по спецификации)

/// Bottom sheet: что оцениваем, звёзды, текст, до 3 фото. Доступно всем — без визита/покупки.
///
/// Объект отзыва — блюдо/услуга ИЛИ заведение в целом (`nil`): раньше без
/// объектов меню оставить отзыв было нельзя вовсе, а лист, открытый без
/// предвыбора (экран «Начислено → оставить отзыв»), ставил первое блюдо и
/// перезаписывал уже оставленный на него отзыв.
struct WriteReviewView: View {
    let venue: Venue
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var rating: Int
    @State private var text: String
    @State private var photos: [String]   // URL-фото
    @State private var selectedItemID: String?   // nil = о заведении в целом
    /// Отзыв, который сейчас правится (для выбранного объекта). nil — новый.
    @State private var editing: Review?
    @State private var uploadingPhotos = false
    @State private var rejection: String?
    /// Отзыв, переданный снаружи (правка из профиля), — не подменяем прочитанным из кэша.
    private let passedExisting: Review?

    /// Предел правил Firestore (`reviewFieldsValid`).
    private static let maxTextLength = 2000

    init(venue: Venue, existing: Review?, preselectItemID: String? = nil) {
        self.venue = venue
        self.passedExisting = existing
        _rating = State(initialValue: existing?.rating ?? 0)
        _text = State(initialValue: existing?.text ?? "")
        _photos = State(initialValue: existing?.photos ?? [])
        _editing = State(initialValue: existing)
        let initial = ReviewIdentity.normalizedItemID(existing?.itemID ?? preselectItemID)
        // Объект, которого больше нет в меню, — отзыв о заведении в целом.
        _selectedItemID = State(initialValue: venue.items.contains { $0.id == initial } ? initial : nil)
    }

    private var canPublish: Bool { rating > 0 && !uploadingPhotos }

    var body: some View {
        NavigationStack {
            Form {
                if !venue.items.isEmpty {
                    Section("Что оцениваете") {
                        Picker("Объект", selection: $selectedItemID) {
                            Text("Заведение в целом").tag(String?.none)
                            ForEach(venue.items) { item in
                                Text("\(item.emoji) \(item.name)").tag(String?.some(item.id))
                            }
                        }
                        .onChange(of: selectedItemID) { _, _ in prefillFromMyReview() }
                    }
                }
                Section("Оценка") {
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .font(.title)
                                .foregroundStyle(.yellow)
                                .onTapGesture { rating = star }
                                .accessibilityLabel(Text("\(star)"))
                                .accessibilityAddTraits(star == rating ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
                }

                Section {
                    TextField("Расскажи о своём опыте…", text: $text, axis: .vertical)
                        .lineLimit(4...8)
                        .onChange(of: text) { _, new in
                            if new.count > Self.maxTextLength { text = String(new.prefix(Self.maxTextLength)) }
                        }
                } header: {
                    Text("Отзыв")
                } footer: {
                    Text("Без мата, ссылок и номеров телефонов — такие отзывы не публикуются.")
                }

                Section("Фото (до 3)") {
                    ReviewPhotosField(urls: $photos, uploading: $uploadingPhotos, maxCount: 3)
                }
            }
            .navigationTitle(editing == nil ? "Новый отзыв" : "Изменить отзыв")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Опубликовать") { publish() }
                        .disabled(!canPublish)
                }
            }
            .alert("Отзыв не опубликован",
                   isPresented: Binding(get: { rejection != nil }, set: { if !$0 { rejection = nil } })) {
                Button("Понятно", role: .cancel) {}
            } message: {
                Text(L(rejection ?? ""))
            }
            // Свои отзывы могли ещё не загрузиться: без них лист для уже
            // оценённого объекта открывался «новым», и публикация затирала
            // прежний отзыв, не показав его.
            .task {
                await store.loadMyReviews()
                guard passedExisting == nil else { return }
                // Уже начатый черновик не затираем — только отмечаем, что
                // публикация заменит прежний отзыв.
                if rating == 0, text.isEmpty, photos.isEmpty { prefillFromMyReview() }
                else { editing = store.myReview(venueID: venue.id, itemID: selectedItemID) }
            }
        }
    }

    /// Подставляет существующий отзыв пользователя для выбранного объекта.
    private func prefillFromMyReview() {
        let existing = store.myReview(venueID: venue.id, itemID: selectedItemID)
        editing = existing
        rating = existing?.rating ?? 0
        text = existing?.text ?? ""
        photos = existing?.photos ?? []
    }

    private func publish() {
        let item = venue.items.first { $0.id == selectedItemID }
        if let violation = store.saveReview(venueID: venue.id, rating: rating,
                                            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                            photos: photos, itemID: selectedItemID, itemName: item?.name) {
            rejection = violation.message
            return
        }
        dismiss()
    }
}

/// Правка своего отзыва, когда заведения больше нет на витрине (удалено).
/// Раньше лист открывался пустым — без объяснения и без выхода.
struct ReviewVenueUnavailableView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Заведение недоступно",
                                   systemImage: "building.2.crop.circle",
                                   description: Text("Это заведение удалено из каталога — отзыв о нём больше нельзя изменить."))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
                }
        }
    }
}

// MARK: - Фото отзыва

/// Выбор до `maxCount` фото с загрузкой на Cloudinary.
///
/// Отдельно от `MultiImagePickerField`: отзыву нужно знать, что загрузка ещё
/// идёт (иначе «Опубликовать» уходил без фото, которые грузились), и показать
/// ошибку загрузки — раньше упавшая загрузка просто ничего не добавляла.
struct ReviewPhotosField: View {
    @Binding var urls: [String]
    @Binding var uploading: Bool
    var maxCount = 3
    @State private var items: [PhotosPickerItem] = []
    @State private var failed = 0

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
                                .accessibilityLabel(Text("Удалить фото"))
                            }
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                PhotosPicker(selection: $items, maxSelectionCount: max(maxCount - urls.count, 1),
                             matching: .images) {
                    Label(uploading ? "Загрузка…" : "Добавить фото (до \(maxCount))",
                          systemImage: "photo.on.rectangle.angled")
                        .font(.subheadline.weight(.medium))
                }
                .disabled(uploading || urls.count >= maxCount)
                if uploading { ProgressView() }
            }
            if failed > 0 {
                Label("Не удалось загрузить фото. Проверьте соединение и попробуйте ещё раз.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: items) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                uploading = true
                failed = 0
                // По одному: три оригинала по 12 Мп в памяти разом — сотни МБ.
                for it in newItems {
                    if urls.count >= maxCount { break }
                    guard let data = try? await it.loadTransferable(type: Data.self),
                          let jpeg = await ImageDownsampler.jpegOffMain(from: data) else {
                        failed += 1
                        continue
                    }
                    do {
                        urls.append(try await ImageUploader.upload(jpeg))
                    } catch {
                        failed += 1
                    }
                }
                items = []
                uploading = false
            }
        }
    }
}

// MARK: - Скрытые авторы

/// Список авторов, чьи отзывы пользователь скрыл, — с возможностью вернуть.
/// Открывается из профиля («Скрытые авторы»).
struct BlockedAuthorsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        List {
            if store.profile.blockedAuthorIDs.isEmpty {
                Text("Вы никого не скрывали. Скрыть отзывы автора можно в меню «…» у его отзыва.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(store.profile.blockedAuthorIDs.sorted(), id: \.self) { id in
                        HStack {
                            Text(verbatim: store.profile.blockedAuthorNames[id] ?? LS("Автор отзыва"))
                            Spacer()
                            Button("Показывать") { store.unblockAuthor(id: id) }
                                .buttonStyle(.borderless)
                        }
                    }
                } footer: {
                    Text("Отзывы этих авторов не показываются вам ни в одном заведении.")
                }
            }
        }
        .navigationTitle("Скрытые авторы")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Полноэкранный просмотр фото с жалобой

struct PhotoViewerView: View {
    let photos: [String]
    var startIndex: Int = 0
    /// Отправка жалобы на фото (URL, причина). nil — кнопки жалобы нет.
    var onReport: ((String, ReviewReportReason) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var showReport = false
    @State private var reported = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.offset) { i, p in
                    Group {
                        if p.hasPrefix("http"), let url = URL(string: p) {
                            AsyncImage(url: url) { img in
                                img.resizable().scaledToFit()
                            } placeholder: { ProgressView().tint(.white) }
                        } else {
                            Text(p).font(.system(size: 140))
                        }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page)

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").foregroundStyle(.white).padding(12)
                    }
                    .accessibilityLabel(Text("Закрыть"))
                    Spacer()
                    // Жалоба — только на настоящие фото: эмодзи-заглушки не контент.
                    if onReport != nil, photos.indices.contains(index), photos[index].hasPrefix("http") {
                        Button { showReport = true } label: {
                            Image(systemName: "flag").foregroundStyle(.white).padding(12)
                        }
                        .accessibilityLabel(Text("Пожаловаться на фото"))
                    }
                }
                Spacer()
                if reported {
                    Text("Спасибо, жалоба отправлена")
                        .font(.caption).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.white.opacity(0.2), in: Capsule())
                        .padding(.bottom, 30)
                }
            }
        }
        .onAppear { index = startIndex }
        .onChange(of: index) { _, _ in reported = false }
        .confirmationDialog("Пожаловаться на фото", isPresented: $showReport, titleVisibility: .visible) {
            ForEach(ReviewReportReason.allCases, id: \.self) { reason in
                Button(L(reason.title), role: .destructive) { report(reason) }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func report(_ reason: ReviewReportReason) {
        guard photos.indices.contains(index) else { return }
        onReport?(photos[index], reason)
        reported = true
    }
}

// MARK: - In-app PDF-просмотр меню

struct PDFMenuView: View {
    let urlString: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let url = URL(string: urlString) {
                    WebView(url: url)
                } else {
                    ContentUnavailableView("Не удалось открыть меню", systemImage: "doc")
                }
            }
            .navigationTitle("Прайс-лист")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Готово") { dismiss() } }
            }
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView { WKWebView() }
    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.load(URLRequest(url: url))
    }
}

// MARK: - Строка отзыва (с ответом владельца)

struct ReviewRow: View {
    let review: Review

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [.sanAccent, .yellow],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(review.initial).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    // Бейдж «Проверенный визит» снят: отметку ставит только
                    // сервер, а он её пока не выставляет — локальная отметка
                    // была видна одному автору (и подделывалась).
                    Text(review.authorName).font(.subheadline.weight(.semibold))
                    HStack(spacing: 6) {
                        StarRatingView(rating: Double(review.rating), size: 11)
                        Text("· \(review.dateText)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if let itemName = review.itemName, !itemName.isEmpty {
                Text("Отзыв об объекте: \(itemName)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.sanAccent.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.sanAccentText)
            }
            if !review.text.isEmpty {
                Text(review.text).font(.subheadline)
            }
            let reviewPhotos = review.photos + review.photoEmojis
            if !reviewPhotos.isEmpty {
                HStack(spacing: 8) {
                    ForEach(reviewPhotos, id: \.self) { p in
                        GalleryImage(value: p, emojiSize: 24)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            if let reply = review.hostReply {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Ответ заведения", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(.blue)
                    Text(reply.text).font(.caption).foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.vertical, 6)
    }
}
