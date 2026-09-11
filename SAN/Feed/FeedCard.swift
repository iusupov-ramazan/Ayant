import SwiftUI
import AyantDomain
import AyantFeatures

// Карточка ленты после редизайна (SCREENS.md G2).
//
// Карточка во всю ширину, без скруглений, между карточками 10pt канваса:
// не «плитка в сетке», а пост. Старый вариант с фото на весь кадр и текстом
// поверх скрима (`SanFeedCard`, `FeedPhoto`, `FeedScrim`, стеклянные чипы)
// удалён — ниже только то, что рисуется сейчас.

// MARK: - Пост ленты (SCREENS.md G2)
//
// Лента переехала с полноэкранной карточки на пост, как в Instagram: белая
// полоса во всю ширину, фото 4:5 и ВЕСЬ текст под фотографией, на белом.
//
// Зачем менять то, что работало. На старой карточке заголовок, цена и чипы
// лежали поверх снимка на четырёхстоповом скриме. Скрим держал контраст, но
// платил за это дважды: он съедал сам кадр (нижняя треть любого блюда уходила
// в темноту) и ограничивал текст двумя строками — на светлой фотографии
// третья строка уже не читалась. На белом ограничение снимается: описание
// разворачивается, цена берёт 27pt, и появляется место под ряд действий.
//
// Ничего, кроме бейджа скидки, на фотографии больше не лежит.

/// Каркас поста: белая полоса без рамок.
///
/// Линий сверху и снизу нет: посты и так разделены полосой канваса, а две
/// границы на каждый пост превращали ленту в таблицу.
private struct FeedPostFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sanSurface)
    }
}

/// Аватар заведения: кольцо градиентом заведения → белый зазор → заливка.
private struct FeedPostAvatar: View {
    let gradient: [Color]
    let imageURL: String?

    var body: some View {
        let brush = LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
        return Circle()
            .fill(brush)
            .frame(width: 38, height: 38)
            .overlay {
                Circle()
                    .fill(brush)
                    .overlay {
                        if let imageURL, !imageURL.isEmpty, let url = URL(string: imageURL) {
                            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                                .clipShape(Circle())
                        }
                    }
                    .padding(1.5)
                    .background(Circle().fill(Color.sanSurface).padding(0.5))
                    .padding(1.5)
            }
    }
}

/// Кнопка ряда действий. Цель нажатия — 44pt, глиф меньше.
private struct FeedActionButton: View {
    let systemName: String
    var size: CGFloat = 23
    var tint: Color = .sanInk
    var isOn: Bool = false
    var label: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: SanMetrics.minHitTarget, height: SanMetrics.minHitTarget)
                .contentShape(Rectangle())
                .sanPop(on: isOn)
        }
        .buttonStyle(.sanPress(0.86))
        .accessibilityLabel(label)
    }
}

/// Фото поста 4:5 с бейджем и двойным тапом.
///
/// Каркас — `Color.clear`: у неё нет своего идеального размера, поэтому высота
/// считается от ширины и пропорции, а не от того, какой кадр подгрузился.
/// Иначе посты разъезжаются по высоте, когда приходят реальные снимки.
private struct FeedPostPhoto<Badge: View>: View {
    let urlString: String?
    let gradient: [Color]
    var onOpen: () -> Void
    var onDoubleTapLike: () -> Void
    @ViewBuilder var badge: Badge

    @State private var burst = false

    var body: some View {
        Color.clear
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .overlay { VenuePhoto(urlString: urlString, gradient: gradient) }
            .clipped()
            .overlay(alignment: .topLeading) {
                badge.padding(.leading, 14).padding(.top, 14)
            }
            .overlay { burstHeart }
            .contentShape(Rectangle())
            // Двойной тап объявляется ПЕРВЫМ: одиночный, объявленный раньше,
            // забирает событие себе и до двойного дело не доходит.
            .onTapGesture(count: 2) {
                onDoubleTapLike()
                SanHaptics.save()
                burst = true
                withAnimation(.sanPop) { burst = false }
            }
            .onTapGesture(count: 1) { onOpen() }
    }

    private var burstHeart: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 92))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .scaleEffect(burst ? 0.7 : 1)
            .opacity(burst ? 1 : 0)
            .allowsHitTesting(false)
    }
}

// MARK: - Карточка предложения

struct FeedDealCard: View {
    let deal: Deal
    let venue: Venue?
    var distanceKm: Double?
    let isSaved: Bool
    var isLiked: Bool = false
    var onOpen: () -> Void = {}
    var onVenue: () -> Void = {}
    var onSave: () -> Void = {}
    var onLike: () -> Void = {}
    var onShare: () -> Void = {}

    @State private var expanded = false
    @State private var clampedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var gradient: [Color] { venue?.gradientColors ?? [.sanAccent, Color(hex: Palette.orange)] }
    /// Фото самой акции; если его нет — обложка заведения.
    private var photoURL: String? { deal.allImages.first ?? venue?.imageURL }
    private var savings: Int? {
        guard let old = deal.oldPrice, let new = deal.newPrice, old > new else { return nil }
        return old - new
    }

    var body: some View {
        FeedPostFrame {
            VStack(alignment: .leading, spacing: 0) {
                header
                FeedPostPhoto(urlString: photoURL, gradient: gradient,
                              onOpen: onOpen, onDoubleTapLike: onLike) { badge }
                actions
                caption
            }
        }
    }

    // MARK: Шапка поста

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onVenue) {
                HStack(spacing: 10) {
                    FeedPostAvatar(gradient: gradient, imageURL: venue?.imageURL)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(venue?.name ?? "")
                                .font(.golos(14, .bold)).tracking(-0.25)
                                .foregroundStyle(Color.sanInk)
                                .lineLimit(1)
                            if venue?.isVerified == true {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(hex: 0x4DA3FF))
                            }
                        }
                        if let sub = subtitle {
                            Text(sub)
                                .font(.golos(11.5, .semibold))
                                .foregroundStyle(Color.sanInkSoft)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.sanPress(0.98))

        }
        .padding(.top, 11).padding(.horizontal, 14).padding(.bottom, 10)
    }

    /// «Центр · 0,4 км» — район всегда, расстояние если геолокация разрешена.
    private var subtitle: String? {
        let district = venue?.district ?? ""
        let distance = distanceKm?.distanceText
        switch (district.isEmpty, distance) {
        case (false, .some(let d)): return "\(district) · \(d)"
        case (false, .none):        return district
        case (true, .some(let d)):  return d
        case (true, .none):         return nil
        }
    }

    // Бейдж: процент скидки, иначе тип предложения.
    @ViewBuilder private var badge: some View {
        // Процент — число, его переводить нечего; тип акции — ключ каталога.
        let percent = deal.effectiveDiscountPercent.map { "−\($0)%" }
        Text(percent.map { LocalizedStringKey($0) } ?? deal.type.locKey)
            // Капслок именно так, а не `.uppercased()`: тот превратил бы ключ
            // каталога в «СКИДКА» и перевод бы не нашёлся.
            .textCase(.uppercase)
            .font(.golos(15, .heavy))
            .tracking(-0.5)
            .foregroundStyle(.white)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(LinearGradient.sanAccentGradient,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .sanShadow(.badge)
            .rotationEffect(.degrees(-3))
    }

    // MARK: Ряд действий
    //
    // Сердечко и закладка — РАЗНЫЕ действия. Сердечко это реакция (живёт на
    // устройстве), закладка кладёт акцию в «Сохранённое». Раньше кнопка была
    // одна и совмещала оба смысла.

    private var actions: some View {
        HStack(spacing: 0) {
            FeedActionButton(systemName: isLiked ? "heart.fill" : "heart",
                             size: 24,
                             tint: isLiked ? Color(hex: 0xFF3B00) : Color.sanInk,
                             isOn: isLiked,
                             label: isLiked ? "Убрать отметку «нравится»" : "Нравится",
                             action: onLike)
            FeedActionButton(systemName: "square.and.arrow.up", label: "Поделиться", action: onShare)
            Spacer(minLength: 0)
            FeedActionButton(systemName: isSaved ? "bookmark.fill" : "bookmark",
                             size: 22,
                             tint: isSaved ? Color.sanAccentText : Color.sanInk,
                             isOn: isSaved,
                             label: isSaved ? "Убрать из сохранённых" : "Сохранить",
                             action: onSave)
        }
        .padding(.top, 4).padding(.horizontal, 8)
    }

    // MARK: Подпись

    /// Вся подпись открывает акцию. Исключение — переключатель «…ещё»: он
    /// раскрывает текст на месте, и уводить с ленты по нему нельзя. Поэтому
    /// тап висит на подписи целиком, а кнопка переключателя перехватывает свой.
    private var caption: some View {
        VStack(alignment: .leading, spacing: 0) {
            priceRow
            Text(deal.title)
                .sanText(19, .heavy, tracking: -0.7, lineHeight: 1.22)
                .foregroundStyle(Color.sanInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            description
            chips.padding(.top, 12)
            if let meta { Text(meta)
                .font(.golos(11.5, .semibold))
                .foregroundStyle(Color(hex: 0x9A9188))
                .padding(.top, 10) }
        }
        .padding(.top, 2).padding(.horizontal, 15).padding(.bottom, 17)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }

    @ViewBuilder private var priceRow: some View {
        if deal.newPrice != nil || deal.oldPrice != nil {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                if let new = deal.newPrice {
                    Text("\(new) сом")
                        .font(.golos(27, .heavy)).tracking(-1.1)
                        .foregroundStyle(Color.sanAccentText)
                }
                if let old = deal.oldPrice {
                    Text("\(old) сом")
                        .font(.golos(14.5))
                        .foregroundStyle(Color(hex: 0x9A9188))
                        .strikethrough()
                }
                if let savings {
                    Text("экономия \(savings) сом")
                        .font(.golos(12.5, .bold))
                        .foregroundStyle(Color(hex: 0x2FA24C))
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Описание в две строки со сворачиванием.
    ///
    /// Обрезаем ОПИСАНИЕ, а не заголовок: заголовок — это само предложение,
    /// оборванный он бесполезен.
    @ViewBuilder private var description: some View {
        let text = deal.details.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                body(text)
                    .lineLimit(expanded ? nil : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Мерим две копии той же строки — с ограничением и без.
                    // Разошлись по высоте, значит текст обрезан. Без этой
                    // проверки «…ещё» висело под любым описанием, в том числе
                    // под однострочным, и ничего не раскрывало.
                    .background(alignment: .topLeading) {
                        ZStack(alignment: .topLeading) {
                            body(text).lineLimit(2)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height }
                                    action: { clampedHeight = $0 }
                            body(text)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height }
                                    action: { fullHeight = $0 }
                        }
                        .hidden()
                    }
                if isTruncated || !deal.terms.isEmpty {
                    Button {
                        withAnimation(.sanStandard(0.28)) { expanded.toggle() }
                    } label: {
                        Text(expanded ? "свернуть" : "…ещё")
                            .font(.golos(13.5, .bold))
                            .foregroundStyle(Color.sanInkSoft)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.sanPress(0.94))
                }
                if expanded { termsPanel }
            }
            .padding(.top, 8)
        }
    }

    private func body(_ text: String) -> some View {
        Text(text)
            .sanText(14, .regular, lineHeight: 1.5)
            // Описание — вторичный текст, а не второй заголовок. Прежний
            // #3D362F почти совпадал с чернилами, и подпись читалась как
            // продолжение названия. `sanInkSoft` — тот же токен, что у всех
            // подписей на белом, и он проходит 4.5:1.
            .foregroundStyle(Color.sanInkSoft)
    }

    private var isTruncated: Bool { fullHeight > clampedHeight + 1 }

    /// Условия акции — панель на канвасе под описанием.
    ///
    /// Показывается только в развёрнутом виде: условия отвечают на вопрос
    /// «а что мелким шрифтом», который возникает уже после того, как человек
    /// заинтересовался. В свёрнутой ленте они бы просто удлиняли каждый пост.
    @ViewBuilder private var termsPanel: some View {
        if !deal.terms.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(deal.terms.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.sanAccentText)
                            .frame(width: 5, height: 5)
                            // Точка на середину первой строки текста, а не на её верх.
                            .padding(.top, 6)
                        Text(line)
                            .sanText(12.5, .regular, lineHeight: 1.45)
                            .foregroundStyle(Color.sanInkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.sanCanvas,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 4)
        }
    }

    private var chips: some View {
        HStack(spacing: 7) {
            if venue?.isOpenNow == true {
                captionChip(fill: Color(hex: 0x2FA24C).opacity(0.12),
                            ink: Color(hex: 0x1F7D3A)) {
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: 0x2FA24C)).frame(width: 5, height: 5)
                        Text("Открыто")
                    }
                }
            }
            if let distanceKm {
                captionChip(fill: Color(hex: 0xF1EEE8), ink: Color.sanInkSoft) {
                    Text(distanceKm.distanceText)
                }
            }
            if let earn = venue?.earnRateLabel {
                captionChip(fill: Color(hex: 0xFFF3EC), ink: Color.sanAccentText) {
                    Text(earn)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func captionChip<C: View>(fill: Color, ink: Color,
                                      @ViewBuilder content: () -> C) -> some View {
        content()
            .font(.golos(11.5, .bold))
            .foregroundStyle(ink)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(fill, in: Capsule())
    }

    /// «12 отзывов · 2 часа назад». Обе половины — реальные данные: счётчик
    /// отзывов заведения и дата старта акции. Нет ни того, ни другого — строки нет.
    private var meta: String? {
        var parts: [String] = []
        if let count = venue?.reviewCount, count > 0 {
            parts.append("\(count) \(Self.reviewPlural(count))")
        }
        if let start = deal.startDate {
            let f = RelativeDateTimeFormatter()
            // Язык приложения, а не системы: приложение русскоязычное и умеет
            // переключаться само (см. `LS`).
            f.locale = Locale(identifier: UserDefaults.standard.string(forKey: "san.language") ?? "ru")
            f.unitsStyle = .full
            parts.append(f.localizedString(for: start, relativeTo: Date()))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func reviewPlural(_ n: Int) -> String {
        let n10 = n % 10, n100 = n % 100
        if n10 == 1 && n100 != 11 { return "отзыв" }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return "отзыва" }
        return "отзывов"
    }
}


// MARK: - Рекламная карточка заведения

/// Заведение, вклеенное в ленту как реклама (`FeedItem.adVenue`). Тот же кадр,
/// но помечен «РЕКЛАМА» — иначе реклама неотличима от органики.
struct FeedAdVenueCard: View {
    let venue: Venue
    var distanceKm: Double?
    let isSaved: Bool
    var onOpen: () -> Void = {}
    var onSave: () -> Void = {}

    var body: some View {
        FeedPostFrame {
            VStack(alignment: .leading, spacing: 0) {
                header
                FeedPostPhoto(urlString: venue.imageURL, gradient: venue.gradientColors,
                              onOpen: onOpen, onDoubleTapLike: {}) {
                    Text("Реклама")
                        .textCase(.uppercase)
                        .font(.golos(10.5, .heavy)).tracking(1.1)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(Color.black.opacity(0.32), in: Capsule())
                }
                actions
                caption
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    FeedPostAvatar(gradient: venue.gradientColors, imageURL: venue.imageURL)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(venue.name)
                                .font(.golos(14, .bold)).tracking(-0.25)
                                .foregroundStyle(Color.sanInk).lineLimit(1)
                            if venue.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(hex: 0x4DA3FF))
                            }
                        }
                        Text(subtitle)
                            .font(.golos(11.5, .semibold))
                            .foregroundStyle(Color.sanInkSoft).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.sanPress(0.98))
        }
        .padding(.top, 11).padding(.horizontal, 14).padding(.bottom, 10)
    }

    private var subtitle: String {
        let distance = distanceKm?.distanceText
        if venue.district.isEmpty { return distance ?? "" }
        return distance.map { "\(venue.district) · \($0)" } ?? venue.district
    }

    // У рекламного поста нет «нравится»: лайкают предложение, а не объявление.
    private var actions: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            FeedActionButton(systemName: isSaved ? "bookmark.fill" : "bookmark",
                             size: 22,
                             tint: isSaved ? Color.sanAccentText : Color.sanInk,
                             isOn: isSaved,
                             label: isSaved ? "Убрать из сохранённых" : "Сохранить",
                             action: onSave)
        }
        .padding(.top, 4).padding(.horizontal, 8)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(venue.name)
                .sanText(19, .heavy, tracking: -0.7, lineHeight: 1.22)
                .foregroundStyle(Color.sanInk)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let special = venue.todaySpecialText, !special.isEmpty {
                Text(special)
                    .sanText(14, .regular, lineHeight: 1.5)
                    .foregroundStyle(Color(hex: 0x3D362F))
                    .lineLimit(2)
                    .padding(.top, 8)
            }
            HStack(spacing: 7) {
                if venue.isOpenNow {
                    chip(fill: Color(hex: 0x2FA24C).opacity(0.12), ink: Color(hex: 0x1F7D3A)) {
                        HStack(spacing: 5) {
                            Circle().fill(Color(hex: 0x2FA24C)).frame(width: 5, height: 5)
                            Text("Открыто")
                        }
                    }
                }
                if let distanceKm {
                    chip(fill: Color(hex: 0xF1EEE8), ink: Color.sanInkSoft) { Text(distanceKm.distanceText) }
                }
                if let earn = venue.earnRateLabel {
                    chip(fill: Color(hex: 0xFFF3EC), ink: Color.sanAccentText) { Text(earn) }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
        }
        .padding(.top, 2).padding(.horizontal, 15).padding(.bottom, 17)
    }

    private func chip<C: View>(fill: Color, ink: Color, @ViewBuilder content: () -> C) -> some View {
        content()
            .font(.golos(11.5, .bold))
            .foregroundStyle(ink)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(fill, in: Capsule())
    }
}

// MARK: - Скелетон загрузки
//
// Не спиннер: он ничего не сообщает о том, что грузится, и посреди ленты
// читается как сломанный экран. Блоки повторяют РЕАЛЬНЫЕ пропорции поста —
// строка шапки, кадр 4:5, полосы подписи, — поэтому появление контента не
// двигает вёрстку.

struct FeedSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        VStack(spacing: 10) {
            post(delay: 0)
            post(delay: 0.3)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: SanTiming.skeletonPulse)
                .repeatForever(autoreverses: true)) { pulsing = true }
        }
        .onDisappear { withoutAnimation { pulsing = false } }
    }

    private func post(delay: Double) -> some View {
        FeedPostFrame {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    bone(width: 38, height: 38, radius: 19)
                    VStack(alignment: .leading, spacing: 5) {
                        bone(width: 120, height: 11)
                        bone(width: 78, height: 9)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 11).padding(.horizontal, 14).padding(.bottom, 10)

                Color.clear
                    .aspectRatio(4.0 / 5.0, contentMode: .fit)
                    .overlay { Color(hex: 0xE9E3DA) }
                    .clipped()

                VStack(alignment: .leading, spacing: 9) {
                    bone(width: 140, height: 22)
                    bone(width: 220, height: 14)
                    bone(width: 180, height: 12)
                }
                .padding(.top, 14).padding(.horizontal, 15).padding(.bottom, 18)
            }
        }
        .opacity(pulsing ? 0.9 : 0.45)
        .animation(.easeInOut(duration: SanTiming.skeletonPulse)
            .repeatForever(autoreverses: true).delay(delay), value: pulsing)
    }

    private func bone(width: CGFloat, height: CGFloat, radius: CGFloat = 5) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color(hex: 0xE9E3DA))
            .frame(width: width, height: height)
    }
}

// MARK: - Мелкие производные для карточки

extension Venue {
    /// Чип «сколько начислим»: читает конфиг баллов, ничего не считает.
    /// Арифметика начисления — только в `PointsMath`.
    var earnRateLabel: String? {
        guard pointsEnabled else { return nil }
        switch pointsMode {
        case "cashback":
            guard cashbackPercent > 0 else { return nil }
            return "+\(cashbackPercent.sanPercentText)% САН"
        case "bands":
            return "Баллы САН"
        default:
            guard pointsFlat > 0 else { return nil }
            return "+\(pointsFlat) баллов"
        }
    }
}

extension Double {
    /// Проценты по-русски: без хвоста у целых, с запятой у дробных.
    var sanPercentText: String {
        self == rounded() ? String(Int(self)) : String(format: "%.1f", self).replacingOccurrences(of: ".", with: ",")
    }

    /// Рейтинг по-русски — с десятичной запятой: «4,8».
    var sanRatingText: String {
        String(format: "%.1f", self).replacingOccurrences(of: ".", with: ",")
    }
}
