import SwiftUI
import AyantDomain
import AyantFeatures

/// Полный список заведений города — продолжение ряда «Заведения» на главной
/// («Все · N» в шапке ряда и хвостовая плитка «Все заведения →»).
///
/// Живёт в `NavigationStack` главной (`FeedRoute.allVenues`), поэтому своего
/// стека нет, а `NavigationLink(value: venue)` уходит в уже объявленный там
/// `VenueDetailView`. Открывается на той же категории, что выбрана на главной.
struct AllVenuesView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var feedStore: FeedStore
    @EnvironmentObject private var location: LocationManager
    @ObservedObject private var catStore = CategoryStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var category: VenueCategory?
    @State private var query = ""
    @State private var sort: Sort = .rating

    enum Sort { case rating, distance }

    init(initialCategory: VenueCategory? = nil) {
        _category = State(initialValue: initialCategory)
    }

    /// Каталог категории в порядке ранжирования (`FeedStore.venues(category:)`),
    /// сверху — локальный поиск и, если есть геопозиция, сортировка «Ближе».
    private var results: [Venue] {
        var list = feedStore.venues(category: category)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty {
            list = list.filter { venue in
                [venue.name, venue.category.rawValue, venue.district, venue.address]
                    .contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            }
        }
        if sort == .distance, canSortByDistance {
            // Без координат — в хвост, а не в голову: «ближе» обещает известное расстояние.
            list.sort { (distance(to: $0) ?? .infinity) < (distance(to: $1) ?? .infinity) }
        }
        return list
    }

    private var canSortByDistance: Bool { location.lastLocation != nil }
    private var totalCount: Int { feedStore.venues(category: category).count }

    private func distance(to venue: Venue) -> Double? {
        location.distanceKm(to: venue.latitude, venue.longitude)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                titleBlock
                searchField
                    .padding(.horizontal, SanMetrics.screenPadding)
                    .padding(.top, 16)
                categoryRail
                    .padding(.top, 12)
                if canSortByDistance {
                    sortRow
                        .padding(.horizontal, SanMetrics.screenPadding)
                        .padding(.top, 4)
                }
                content
                    .padding(.top, 8)
            }
            .padding(.bottom, 28)
        }
        .background(Color.sanCanvas.ignoresSafeArea())
        .sanStatusBarCap()
        // Экран открывается пушем: системную панель прячем ради крупного
        // заголовка, но «назад» оставляем — как в «Сохранённом».
        .sanNavBar { dismiss() }
        .toolbar(.hidden, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            // Геопозиция могла появиться позже, чем человек выбрал «Ближе».
            if sort == .distance, !canSortByDistance { sort = .rating }
        }
    }

    // MARK: Заголовок

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Заведения")
                .sanEditorialTitle(44)
                .foregroundStyle(Color.sanInk)
            Text(Self.countText(totalCount, city: store.selectedCity.name))
                .sanText(14, .regular, lineHeight: 1.42)
                .foregroundStyle(Color.sanInkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SanMetrics.screenPadding)
        .padding(.top, 8)
        .sanScreenEnter()
    }

    /// «41 заведение · Бишкек» — склонение существительного по последним
    /// цифрам; город через точку, чтобы не склонять его самого.
    static func countText(_ n: Int, city: String) -> String {
        let mod10 = n % 10, mod100 = n % 100
        let noun: String
        if mod10 == 1 && mod100 != 11 { noun = "заведение" }
        else if (2...4).contains(mod10) && !(12...14).contains(mod100) { noun = "заведения" }
        else { noun = "заведений" }
        return "\(n) \(noun) · \(city)"
    }

    // MARK: Поиск

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x9A9188))
            TextField("", text: $query,
                      prompt: Text("Название, категория или район")
                        .foregroundColor(Color(hex: 0x9A9188)))
                .font(.golos(14.5, .medium))
                .foregroundStyle(Color.sanInk)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15)).foregroundStyle(Color(hex: 0x9A9188))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.sanSurface)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.sanHairline, lineWidth: 0.5))
    }

    // MARK: Категории (те же чипы, что на главной)

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
            .padding(.vertical, 8)
        }
        .scrollClipDisabled()
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

    // MARK: Сортировка

    private var sortRow: some View {
        HStack(spacing: 8) {
            sortChip("По рейтингу", systemName: "star", value: .rating)
            sortChip("Ближе", systemName: "location", value: .distance)
            Spacer(minLength: 0)
        }
    }

    private func sortChip(_ title: LocalizedStringKey, systemName: String, value: Sort) -> some View {
        let isOn = sort == value
        return Button {
            SanHaptics.selection()
            sort = value
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isOn ? "\(systemName).fill" : systemName)
                    .font(.system(size: 10.5, weight: .bold))
                Text(title)
                    .font(.golos(12.5, .bold)).tracking(-0.2)
                    .lineLimit(1)
            }
            .foregroundStyle(isOn ? Color.sanCanvas : Color.sanInkSoft)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(isOn ? Color.sanInk : Color.sanSurfaceMuted, in: Capsule())
        }
        .buttonStyle(.sanPress(0.93))
    }

    // MARK: Список

    @ViewBuilder
    private var content: some View {
        let list = results
        if list.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, venue in
                    NavigationLink(value: venue) {
                        VenueCompactRow(venue: venue, distanceKm: distance(to: venue))
                            .padding(.horizontal, SanMetrics.screenPadding)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.sanPress(0.98))
                    if index < list.count - 1 {
                        Rectangle()
                            .fill(Color.sanHairline)
                            .frame(height: 0.5)
                            .padding(.leading, SanMetrics.screenPadding + 62 + 14)
                    }
                }
            }
        }
    }

    // MARK: Пустое состояние

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView {
                    Label("Ничего не нашлось", systemImage: "magnifyingglass")
                } description: {
                    Text("Попробуйте другое название, категорию или район.")
                }
                Button("Очистить поиск") { query = "" }
                    .buttonStyle(.bordered)
                    .tint(.sanAccent)
            } else {
                ContentUnavailableView {
                    Label("Нет заведений в категории", systemImage: "storefront")
                } description: {
                    Text("В категории «\(category?.rawValue ?? "")» в городе \(store.selectedCity.name) пока нет заведений.")
                }
                Button("Сбросить фильтр") { category = nil }
                    .buttonStyle(.bordered)
                    .tint(.sanAccent)
            }
        }
        .padding(.top, 40)
    }
}

#Preview {
    NavigationStack {
        AllVenuesView()
    }
    .environmentObject(AyantStores.app())
    .environmentObject(AyantStores.app().feed)
    .environmentObject(LocationManager())
    .tint(.sanAccent)
}
