import SwiftUI
import WebKit

// MARK: - Написать / редактировать отзыв (по спецификации)

/// Bottom sheet: выбор звёзд, текст, до 3 фото. Доступно всем — без визита/покупки.
struct WriteReviewView: View {
    let venue: Venue
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var rating: Int
    @State private var text: String
    @State private var photos: [String]
    @State private var selectedItemID: String?   // nil = о заведении в целом

    private let photoChoices = ["📷", "🍽", "🥗", "☕️", "🍰", "🍜", "🥟", "🍣"]

    init(venue: Venue, existing: Review?, preselectItemID: String? = nil) {
        self.venue = venue
        _rating = State(initialValue: existing?.rating ?? 0)
        _text = State(initialValue: existing?.text ?? "")
        _photos = State(initialValue: existing?.photoEmojis ?? [])
        // Отзыв всегда про конкретный объект: по умолчанию — первый объект заведения.
        _selectedItemID = State(initialValue: existing?.itemID ?? preselectItemID ?? venue.items.first?.id)
    }

    private var canPublish: Bool { rating > 0 && selectedItemID != nil }

    var body: some View {
        NavigationStack {
            Form {
                if venue.items.isEmpty {
                    Section {
                        Text("У заведения пока нет объектов для отзыва. Оценить можно конкретное блюдо или услугу — попросите заведение добавить их.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    Section("Что оцениваете") {
                        Picker("Объект", selection: $selectedItemID) {
                            ForEach(venue.items) { item in
                                Text("\(item.emoji) \(item.name)").tag(String?.some(item.id))
                            }
                        }
                        .onChange(of: selectedItemID) { _, newID in
                            // Подставляем существующий отзыв для выбранного объекта.
                            let existing = store.myReview(venueID: venue.id, itemID: newID)
                            rating = existing?.rating ?? 0
                            text = existing?.text ?? ""
                            photos = existing?.photoEmojis ?? []
                        }
                    }
                }
                Section("Оценка") {
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .font(.title)
                                .foregroundStyle(.yellow)
                                .onTapGesture { rating = star }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
                }

                Section("Отзыв") {
                    TextField("Расскажи о своём опыте…", text: $text, axis: .vertical)
                        .lineLimit(4...8)
                }

                Section("Фото (до 3)") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(photoChoices, id: \.self) { p in
                                let isOn = photos.contains(p)
                                Text(p)
                                    .font(.system(size: 28))
                                    .frame(width: 48, height: 48)
                                    .background(isOn ? Color.sanAccent.opacity(0.2) : Color(.systemGray6),
                                                in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12)
                                        .stroke(isOn ? Color.sanAccent : .clear, lineWidth: 2))
                                    .onTapGesture { togglePhoto(p) }
                            }
                        }
                    }
                    Text("В MVP фото — эмодзи-плейсхолдеры.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(store.myReview(for: venue) == nil ? "Новый отзыв" : "Изменить отзыв")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Опубликовать") {
                        let item = venue.items.first { $0.id == selectedItemID }
                        store.saveReview(venueID: venue.id, rating: rating,
                                         text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                         photos: photos, itemID: selectedItemID, itemName: item?.name)
                        dismiss()
                    }
                    .disabled(!canPublish)
                }
            }
        }
    }

    private func togglePhoto(_ p: String) {
        if let idx = photos.firstIndex(of: p) { photos.remove(at: idx) }
        else if photos.count < 3 { photos.append(p) }
    }
}

// MARK: - Полноэкранный просмотр фото с жалобой

struct PhotoViewerView: View {
    let photos: [String]
    var startIndex: Int = 0
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var showReport = false
    @State private var reported = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.offset) { i, p in
                    Text(p).font(.system(size: 140)).tag(i)
                }
            }
            .tabViewStyle(.page)

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").foregroundStyle(.white).padding(12)
                    }
                    Spacer()
                    Button { showReport = true } label: {
                        Image(systemName: "flag").foregroundStyle(.white).padding(12)
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
        .confirmationDialog("Пожаловаться на фото", isPresented: $showReport, titleVisibility: .visible) {
            Button("Фейк", role: .destructive) { reported = true }
            Button("Спам", role: .destructive) { reported = true }
            Button("Оскорбительное", role: .destructive) { reported = true }
            Button("Отмена", role: .cancel) {}
        }
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
            .navigationTitle("Меню")
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
                    .foregroundStyle(Color.sanAccent)
            }
            if !review.text.isEmpty {
                Text(review.text).font(.subheadline)
            }
            if !review.photoEmojis.isEmpty {
                HStack(spacing: 8) {
                    ForEach(review.photoEmojis, id: \.self) { p in
                        Text(p).font(.title)
                            .frame(width: 48, height: 48)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
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
