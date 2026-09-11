import SwiftUI
import AyantDomain
import AyantFeatures

// История баллов заведения: журнал `venuePoints/{card}/ledger`, который пишет
// только сервер. Экран — чистая функция от `points.state.history(for:)`;
// строки и скелет отсюда же использует `VenuePointsScreen` (пять последних).

// MARK: - Полный экран истории

struct PointsHistoryView: View {
    let venue: Venue
    @EnvironmentObject private var points: PointsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch points.state.history(for: venue.id) {
                case .idle, .loading:
                    PointsHistorySkeleton(rows: 6)

                case .failed(let error):
                    PointsHistoryFailed(error: error) { reload() }

                case .loaded(let entries) where entries.isEmpty:
                    PointsHistoryEmpty()

                case .loaded(let entries):
                    PointsHistorySummary(entries: entries)
                    ForEach(PointsLedgerMonth.group(entries)) { month in
                        VStack(alignment: .leading, spacing: 10) {
                            // Не `SanSectionHeader`: он капслочит, а месяц читается
                            // как заголовок — «Сентябрь 2026».
                            Text(month.title)
                                .font(.golos(15, .bold)).foregroundStyle(Color.sanInk)
                                .padding(.leading, 4)
                            PointsLedgerCard(entries: month.entries, venue: venue)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .refreshable { await reloadAndSettle() }
        .sanNavBar("История баллов") { dismiss() }
        .sanScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { reload() }
    }

    private func reload() { points.send(.loadHistory(venueID: venue.id)) }

    /// Стор не сообщает, когда журнал приехал (уже показанный список он не
    /// стирает на время загрузки), поэтому индикатор держим короткую паузу —
    /// иначе он схлопывается в тот же кадр и читается как «ничего не произошло».
    private func reloadAndSettle() async {
        reload()
        try? await Task.sleep(for: .milliseconds(600))
    }
}

// MARK: - Итог за загруженный период

/// «Начислено N · Списано M» — только по тем записям, что пришли (не больше
/// `PointsStore.historyLimit`), поэтому это не lifetime-счётчики карты.
struct PointsHistorySummary: View {
    let entries: [PointsLedgerEntry]

    private var earned: Int   { entries.filter { $0.kind == .earn }.map(\.points).reduce(0, +) }
    private var redeemed: Int { -entries.filter { $0.kind == .redeem }.map(\.points).reduce(0, +) }
    private var expired: Int  { -entries.filter { $0.kind == .expire }.map(\.points).reduce(0, +) }

    private var rangeCaption: String {
        guard let newest = entries.first?.at, let oldest = entries.last?.at else { return "" }
        let a = PointsLedgerFormat.day(oldest), b = PointsLedgerFormat.day(newest)
        return a == b ? a : "\(a) — \(b)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Начислено \(earned) · Списано \(redeemed)")
                    .font(.golos(15, .bold)).foregroundStyle(Color.sanInk)
                Spacer(minLength: 8)
                Text(rangeCaption)
                    .font(.golos(11.5, .medium)).foregroundStyle(Color.sanInkSoft)
                    .lineLimit(1)
            }
            HStack(spacing: 10) {
                tile(label: "Начислено", value: "+\(earned)", tint: .sanOpen)
                tile(label: "Списано", value: "−\(redeemed)", tint: .sanInk)
                if expired > 0 {
                    tile(label: "Сгорело", value: "−\(expired)", tint: .sanInkSoft)
                }
            }
        }
        .sanCard(padding: 16, radius: SanRadius.card)
    }

    private func tile(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .textCase(.uppercase)
                .font(.golos(10.5, .heavy)).tracking(0.8)
                .foregroundStyle(Color.sanInkSoft)
            Text(value)
                .font(.golos(20, .heavy)).tracking(-0.6)
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.sanSurfaceMuted,
                    in: RoundedRectangle(cornerRadius: SanRadius.tile, style: .continuous))
    }
}

// MARK: - Группировка по месяцам

/// Записи одного месяца в порядке, в котором они пришли (новые сверху).
struct PointsLedgerMonth: Identifiable {
    let id: String          // "2026-09"
    let title: String       // «Сентябрь 2026»
    let entries: [PointsLedgerEntry]

    /// Сохраняет порядок входа: первая запись задаёт первый месяц.
    static func group(_ entries: [PointsLedgerEntry]) -> [PointsLedgerMonth] {
        var order: [String] = []
        var buckets: [String: [PointsLedgerEntry]] = [:]
        for entry in entries {
            let key = PointsLedgerFormat.monthKey(entry.at)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(entry)
        }
        return order.map { key in
            PointsLedgerMonth(id: key,
                              title: PointsLedgerFormat.monthTitle(buckets[key]!.first!.at),
                              entries: buckets[key]!)
        }
    }
}

// MARK: - Карточка со строками

/// Группа строк журнала с волосяными разделителями.
struct PointsLedgerCard: View {
    let entries: [PointsLedgerEntry]
    let venue: Venue

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { SanHairline(leading: 66) }
                PointsLedgerRow(entry: entry, venue: venue)
            }
        }
        .sanGroupCard(radius: SanRadius.card)
    }
}

/// Одна операция: плитка-иконка, название, дата (+ чек), сумма со знаком.
struct PointsLedgerRow: View {
    let entry: PointsLedgerEntry
    let venue: Venue

    var body: some View {
        HStack(spacing: 12) {
            SanIconTile(systemName: entry.sanIcon, tint: entry.sanTint, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.sanTitle(venue: venue))
                    .font(.golos(15, .semibold)).foregroundStyle(Color.sanInk)
                    .lineLimit(1)
                Text(entry.sanSubtitle)
                    .font(.golos(12.5, .medium)).foregroundStyle(Color.sanInkSoft)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(entry.sanAmount)
                .font(.golos(15, .bold))
                .foregroundStyle(entry.points > 0 ? Color.sanOpen : Color.sanInk)
                .monospacedDigit()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Пустое / ошибка / скелет

struct PointsHistoryEmpty: View {
    var body: some View {
        HStack(spacing: 12) {
            SanIconTile(systemName: "clock.arrow.circlepath", tint: .sanInkSoft, size: 40)
            Text("Пока нет операций. Покажите QR при оплате — первое начисление появится здесь.")
                .font(.golos(13.5, .medium)).foregroundStyle(Color.sanInkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sanCard(padding: 14, radius: SanRadius.card)
    }
}

struct PointsHistoryFailed: View {
    let error: AppError
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SanIconTile(systemName: "exclamationmark.triangle.fill", tint: .red, size: 40)
                Text(PointsMessages.historyText(for: error))
                    .font(.golos(13.5, .medium)).foregroundStyle(Color.sanInk)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            Button("Повторить", action: retry)
                .buttonStyle(SanPillButton(accent: true))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sanCard(padding: 14, radius: SanRadius.card)
    }
}

/// Скелет строк журнала: те же пропорции, что у `PointsLedgerRow`, чтобы
/// появление данных не двигало вёрстку.
struct PointsHistorySkeleton: View {
    var rows: Int = 3
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { index in
                if index > 0 { SanHairline(leading: 66) }
                HStack(spacing: 12) {
                    bone(width: 40, height: 40, radius: 40 * 0.34)
                    VStack(alignment: .leading, spacing: 6) {
                        bone(width: 150, height: 12)
                        bone(width: 100, height: 10)
                    }
                    Spacer(minLength: 8)
                    bone(width: 38, height: 14)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
        }
        .sanGroupCard(radius: SanRadius.card)
        .opacity(pulsing ? 0.9 : 0.5)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: SanTiming.skeletonPulse)
                .repeatForever(autoreverses: true)) { pulsing = true }
        }
        .onDisappear { withoutAnimation { pulsing = false } }
        .accessibilityLabel("Загрузка истории")
    }

    private func bone(width: CGFloat, height: CGFloat, radius: CGFloat = 5) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.sanTileEmpty)
            .frame(width: width, height: height)
    }
}

// MARK: - Представление записи

extension PointsLedgerEntry {
    var sanIcon: String {
        switch kind {
        case .earn:    return "arrow.down.circle.fill"
        case .redeem:  return "gift.fill"
        case .expire:  return "clock.badge.xmark"
        case .unknown: return "circle.dashed"
        }
    }

    var sanTint: Color {
        switch kind {
        case .earn:    return .sanOpen
        case .redeem:  return .sanAccent
        case .expire, .unknown: return .sanInkSoft
        }
    }

    func sanTitle(venue: Venue) -> String {
        switch kind {
        case .earn:   return "Начислено за визит"
        case .redeem:
            let title = venue.pointsRewards.first { $0.id == rewardID }?.title ?? "Награда"
            return "Списано: \(title)"
        case .expire:  return "Баллы сгорели"
        case .unknown: return "Операция"
        }
    }

    /// «11 сентября, 14:32 · чек 1 200 сом»
    var sanSubtitle: String {
        var text = PointsLedgerFormat.moment(at)
        if kind == .earn, let bill = billAmount, bill > 0 {
            text += " · чек \(bill.sanThousands) сом"
        }
        return text
    }

    /// «+50» / «−300» — минус типографский, чтобы не путался с дефисом.
    var sanAmount: String {
        if points > 0 { return "+\(points)" }
        if points < 0 { return "−\(-points)" }
        return "0"
    }
}

// MARK: - Форматтеры (русская локаль)

/// Форматтеры дорогие в создании — держим по одному экземпляру на формат.
enum PointsLedgerFormat {
    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = format
        return f
    }

    private static let momentFormatter = make("d MMMM, HH:mm")
    private static let dayFormatter    = make("d MMM")
    private static let monthKeyFormatter = make("yyyy-MM")
    /// `LLLL` — именительный падеж («Сентябрь»), `MMMM` дал бы «сентября».
    private static let monthTitleFormatter = make("LLLL yyyy")

    /// «11 сентября, 14:32»
    static func moment(_ date: Date) -> String { momentFormatter.string(from: date) }
    /// «11 сент.»
    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }
    /// Ключ группировки — «2026-09».
    static func monthKey(_ date: Date) -> String { monthKeyFormatter.string(from: date) }
    /// «Сентябрь 2026» — с заглавной, как заголовок раздела.
    static func monthTitle(_ date: Date) -> String {
        let raw = monthTitleFormatter.string(from: date)
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }
}
