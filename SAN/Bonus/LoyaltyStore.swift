import SwiftUI
import PassKit

// MARK: - Модель карты лояльности

struct LoyaltyCard: Identifiable, Codable, Hashable {
    var id: String { venueID }
    var venueID: String
    var venueName: String
    var stamps: Int = 0            // штампы в текущем круге
    var completedRounds: Int = 0   // сколько наград уже получено
    var goal: Int = 6              // штампов до награды (задаёт заведение)
    var reward: String = "Награда за лояльность"  // что получает гость
}

// MARK: - Хранилище

@MainActor
final class LoyaltyStore: ObservableObject {
    static let defaultGoal = 6   // фолбэк, если заведение не задало

    @Published private(set) var cards: [LoyaltyCard] = []
    private(set) var userID = ""
    private let key = "san.loyalty"
    private let backend = AppConfig.makeCouponService()

    init() { load() }

    func card(for venueID: String) -> LoyaltyCard? { cards.first { $0.venueID == venueID } }

    /// Карта для заведения — существующая (с синхронизированными штампами) или
    /// новая на 0 штампов (чтобы можно было добавить в Wallet до первого штампа).
    func cardOrNew(venueID: String, venueName: String, goal: Int, reward: String) -> LoyaltyCard {
        card(for: venueID) ?? LoyaltyCard(venueID: venueID, venueName: venueName,
                                          goal: max(goal, 2), reward: reward)
    }

    /// Синк карт лояльности из Firestore. Штампы начисляет сканер заведения
    /// (Cloud Function по QR карты), клиент их отображает.
    func sync(userID: String) async {
        self.userID = userID
        guard !userID.isEmpty, let fetched = try? await backend.fetchLoyaltyCards(userID: userID) else { return }
        var map: [String: LoyaltyCard] = [:]
        for c in cards { map[c.venueID] = c }
        for c in fetched { map[c.venueID] = c }   // бэкенд — источник правды
        cards = map.values.sorted { $0.stamps > $1.stamps }
        save()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(cards) { UserDefaults.standard.set(d, forKey: key) }
    }
    private func load() {
        if let d = UserDefaults.standard.data(forKey: key),
           let c = try? JSONDecoder().decode([LoyaltyCard].self, from: d) { cards = c }
    }
}

// MARK: - Экран «Карты лояльности»

struct LoyaltyView: View {
    @EnvironmentObject private var loyalty: LoyaltyStore

    var body: some View {
        Group {
            if loyalty.cards.isEmpty {
                ContentUnavailableView(
                    "Пока нет карт лояльности",
                    systemImage: "creditcard",
                    description: Text("Откройте страницу заведения с картой лояльности и покажите её QR сотруднику — за каждый визит штамп, а на финише награда."))
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(loyalty.cards) { LoyaltyCardView(card: $0, userID: loyalty.userID) }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Карты лояльности")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Карта лояльности заведения: сетка штампов, QR (его сканирует заведение,
/// чтобы начислить штамп) и кнопка добавления в Apple Wallet.
struct LoyaltyCardView: View {
    let card: LoyaltyCard
    let userID: String
    @State private var walletError: String?
    @State private var showQR = false

    private var loyaltyCode: String { "AYANT-CARD:\(userID):\(card.venueID)" }
    private var canScan: Bool { !userID.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.venueName).font(.headline).foregroundStyle(.white)
                    Text("Награда: \(card.reward)")
                        .font(.caption).foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Text("\(card.stamps)/\(card.goal)")
                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(.white.opacity(0.25), in: Capsule())
            }
            stampGrid
            if card.completedRounds > 0 {
                Label("Наград получено: \(card.completedRounds)", systemImage: "gift.fill")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.white)
            }
            if showQR && canScan {
                VStack(spacing: 8) {
                    QRCodeView(text: loyaltyCode, size: 168)
                        .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 14))
                    Text("Покажите сотруднику — он отсканирует для штампа")
                        .font(.caption2).foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 10) {
                Button { showQR.toggle() } label: {
                    Label(showQR ? "Скрыть QR" : "Показать QR", systemImage: "qrcode")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain).disabled(!canScan)
                Button {
                    WalletService.addLoyaltyPass(card, userID: userID) { walletError = $0 }
                } label: {
                    Label("Wallet", systemImage: "wallet.pass")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(.black, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain).disabled(!canScan)
            }
            if !canScan {
                Text("Войдите в аккаунт, чтобы копить штампы.")
                    .font(.caption2).foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Color(hex: 0xFF4D29), Color(hex: 0xFFB300)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20))
        .alert("Apple Wallet", isPresented: Binding(
            get: { walletError != nil }, set: { if !$0 { walletError = nil } })) {
            Button("Понятно", role: .cancel) {}
        } message: { Text(walletError ?? "") }
    }

    private var stampGrid: some View {
        let cols = min(max(card.goal, 1), 6)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: cols), spacing: 8) {
            ForEach(0..<card.goal, id: \.self) { i in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(i < card.stamps ? Color.white : Color.white.opacity(0.18))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if i < card.stamps {
                            Image(systemName: "checkmark").font(.headline.weight(.black))
                                .foregroundStyle(Color(hex: 0xE8531F))
                        } else {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(.white.opacity(0.55), lineWidth: 1.5)
                        }
                    }
            }
        }
    }
}

/// Экран карты лояльности конкретного заведения (со страницы заведения).
struct VenueLoyaltyScreen: View {
    let venue: Venue
    @EnvironmentObject private var loyalty: LoyaltyStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let card = loyalty.cardOrNew(venueID: venue.id, venueName: venue.name,
                                             goal: venue.loyaltyGoal, reward: venue.loyaltyReward)
                LoyaltyCardView(card: card, userID: loyalty.userID)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Как это работает", systemImage: "info.circle").font(.subheadline.weight(.semibold))
                    Text("Показывайте QR карты сотруднику при каждом визите — он сканирует его, и вам засчитывается штамп. Соберите \(venue.loyaltyGoal) штампов и получите «\(venue.loyaltyReward)».")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(16)
        }
        .navigationTitle("Карта лояльности")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Apple Wallet (PassKit)

enum WalletService {
    /// URL Cloud Function, которая подписывает .pkpass (после деплоя и настройки сертификата).
    static let passEndpoint = "https://us-central1-san-25d32.cloudfunctions.net/generateLoyaltyPass"

    static func addLoyaltyPass(_ card: LoyaltyCard, userID: String, onError: @escaping (String) -> Void) {
        guard var comps = URLComponents(string: passEndpoint) else { return }
        comps.queryItems = [
            .init(name: "venue", value: card.venueID),
            .init(name: "user", value: userID),
            .init(name: "name", value: card.venueName),
            .init(name: "stamps", value: String(card.stamps)),
            .init(name: "goal", value: String(card.goal)),
            .init(name: "reward", value: card.reward),
        ]
        guard let url = comps.url else { return }
        URLSession.shared.dataTask(with: url) { data, _, err in
            DispatchQueue.main.async {
                guard let data, err == nil, let pass = try? PKPass(data: data),
                      let vc = PKAddPassesViewController(pass: pass), let top = Self.topVC() else {
                    onError("Apple Wallet скоро — карта ещё настраивается на сервере.")
                    return
                }
                top.present(vc, animated: true)
            }
        }.resume()
    }

    static let couponPassEndpoint = "https://us-central1-san-25d32.cloudfunctions.net/generateCouponPass"

    /// Кладёт купон в Apple Wallet (.pkpass со сканируемым QR = code).
    static func addCouponPass(_ coupon: Coupon, onError: @escaping (String) -> Void) {
        guard var comps = URLComponents(string: couponPassEndpoint) else { return }
        comps.queryItems = [
            .init(name: "code", value: coupon.code),
            .init(name: "title", value: coupon.title),
            .init(name: "venue", value: coupon.venueName),
        ]
        guard let url = comps.url else { return }
        URLSession.shared.dataTask(with: url) { data, _, err in
            DispatchQueue.main.async {
                guard let data, err == nil, let pass = try? PKPass(data: data),
                      let vc = PKAddPassesViewController(pass: pass), let top = Self.topVC() else {
                    onError("Apple Wallet скоро — купоны ещё настраиваются на сервере.")
                    return
                }
                top.present(vc, animated: true)
            }
        }.resume()
    }

    static func topVC() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController
        var top = root
        while let p = top?.presentedViewController { top = p }
        return top
    }
}
