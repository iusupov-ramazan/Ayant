import SwiftUI
import UIKit

// MARK: - Модели

/// Награда из каталога (что можно купить за бонусы).
struct Reward: Identifiable, Hashable {
    let id: String
    let title: String
    let cost: Int
    let emoji: String
}

/// Купон, полученный пользователем за бонусы (показывается сотруднику).
struct Coupon: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var code: String
    var createdAt: Date
    var used: Bool = false
}

// MARK: - Хранилище купонов

@MainActor
final class CouponStore: ObservableObject {
    /// Каталог наград. Позже можно вынести в Firestore.
    static let catalog: [Reward] = [
        Reward(id: "disc10", title: "−10% к любой акции", cost: 100, emoji: "🏷️"),
        Reward(id: "coffee", title: "Бесплатный кофе у партнёра", cost: 300, emoji: "☕️"),
        Reward(id: "dessert", title: "Десерт в подарок", cost: 400, emoji: "🍰"),
        Reward(id: "vip", title: "VIP-доступ к новинкам", cost: 500, emoji: "⭐️"),
    ]

    @Published private(set) var coupons: [Coupon] = []
    private let key = "san.coupons"

    init() { load() }

    var activeCount: Int { coupons.filter { !$0.used }.count }

    /// Списывает бонусы и выдаёт купон. Возвращает купон или nil (не хватило бонусов).
    func redeem(_ reward: Reward, bonus: BonusEngine) -> Coupon? {
        guard bonus.spend(reward.cost) else { return nil }
        let c = Coupon(id: "cp_\(UUID().uuidString.prefix(8))",
                       title: reward.title,
                       code: "AYTA-\(UUID().uuidString.prefix(6).uppercased())",
                       createdAt: .now)
        coupons.insert(c, at: 0)
        save()
        AnalyticsLog.log(.couponClaim, ["reward_id": reward.id, "cost": reward.cost])
        return c
    }

    /// Кладёт полученный в подарок купон в кошелёк.
    func addGifted(title: String, code: String) {
        guard !coupons.contains(where: { $0.code == code }) else { return }
        coupons.insert(Coupon(id: "cp_\(UUID().uuidString.prefix(8))",
                              title: title, code: code, createdAt: .now), at: 0)
        save()
    }

    func markUsed(_ coupon: Coupon) {
        guard let i = coupons.firstIndex(where: { $0.id == coupon.id }) else { return }
        coupons[i].used = true
        save()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(coupons) { UserDefaults.standard.set(d, forKey: key) }
    }
    private func load() {
        if let d = UserDefaults.standard.data(forKey: key),
           let c = try? JSONDecoder().decode([Coupon].self, from: d) { coupons = c }
    }
}

// MARK: - Мои купоны

struct MyCouponsView: View {
    @EnvironmentObject private var coupons: CouponStore

    var body: some View {
        Group {
            if coupons.coupons.isEmpty {
                ContentUnavailableView("Нет купонов",
                    systemImage: "ticket",
                    description: Text("Обменяй бонусы на купоны во вкладке «Бонусы»."))
            } else {
                List {
                    ForEach(coupons.coupons) { c in
                        NavigationLink { CouponDetailView(coupon: c) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: c.used ? "ticket" : "ticket.fill")
                                    .font(.title2)
                                    .foregroundStyle(c.used ? Color.secondary : Color.sanAccent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.title).font(.subheadline.weight(.semibold))
                                    Text(c.used ? "Использован" : "Активен")
                                        .font(.caption)
                                        .foregroundStyle(c.used ? Color.secondary : Color.green)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Мои купоны")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Подарок готов (картинка купона + текст для шаринга)

/// Картинка-купон для шаринга (рендерится в UIImage).
struct GiftCardImage: View {
    let title: String
    var body: some View {
        VStack(spacing: 14) {
            Text("🎁").font(.system(size: 72))
            Text("ПОДАРОК · AYTA").font(.headline.weight(.heavy)).tracking(2)
            Text(title).font(.title.weight(.bold)).multilineTextAlignment(.center)
            Text("Открой ссылку в приложении Ayta\nи забери купон").font(.subheadline)
                .multilineTextAlignment(.center).opacity(0.95)
        }
        .padding(40)
        .frame(width: 640, height: 460)
        .background(LinearGradient(colors: [Color(hex: 0xFF4D29), Color(hex: 0xFFB300)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .foregroundStyle(.white)
    }
}

@MainActor
func renderGiftImage(title: String) -> UIImage? {
    let renderer = ImageRenderer(content: GiftCardImage(title: title))
    renderer.scale = 3
    return renderer.uiImage
}

/// Обёртка над UIActivityViewController — шарит текст + картинку + ссылку.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct GiftShareSheet: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var showActivity = false

    private var caption: String {
        "🎁 Тебе подарок — купон «\(title)» в Ayta! Забери по ссылке: \(url.absoluteString)"
    }

    var body: some View {
        VStack(spacing: 16) {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            }
            Text("Подарок готов!").font(.title2.weight(.bold))
            Text("Отправь другу картинку со ссылкой — он заберёт купон в приложении.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            Button { showActivity = true } label: {
                Label("Поделиться", systemImage: "square.and.arrow.up")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.sanAccent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)
            Button("Готово") { dismiss() }.padding(.top, 2)
            Spacer()
        }
        .padding(.top, 30)
        .onAppear { image = renderGiftImage(title: title) }
        .sheet(isPresented: $showActivity) {
            ActivityShareSheet(items: image != nil ? [caption, image!] : [caption])
        }
        .presentationDetents([.large])
    }
}

// MARK: - Купон (показать сотруднику)

struct CouponDetailView: View {
    let coupon: Coupon
    @EnvironmentObject private var coupons: CouponStore
    @State private var showUseConfirm = false

    private var isUsed: Bool {
        coupons.coupons.first(where: { $0.id == coupon.id })?.used ?? coupon.used
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ticket
                if isUsed {
                    Label("Купон использован", systemImage: "checkmark.seal.fill")
                        .font(.headline).foregroundStyle(.green)
                } else {
                    Text("Покажи этот экран сотруднику заведения перед оплатой.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal)
                    Button { showUseConfirm = true } label: {
                        Text("Использовать купон")
                            .font(.headline)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color.sanAccent, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain).padding(.horizontal)
                }
            }
            .padding(20)
        }
        .navigationTitle("Купон")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Использовать купон?", isPresented: $showUseConfirm) {
            Button("Да, применить", role: .destructive) { coupons.markUsed(coupon) }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Подтверждай только при сотруднике — купон одноразовый.")
        }
    }

    // Красивый билет-купон.
    private var ticket: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("AYTA · КУПОН").font(.caption.weight(.heavy)).foregroundStyle(.white.opacity(0.9))
                Text(coupon.title)
                    .font(.title.weight(.heavy)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 26).padding(.horizontal, 16)
            .background(
                LinearGradient(colors: isUsed ? [.gray, .gray.opacity(0.7)]
                                              : [Color(hex: 0xFF4D29), Color(hex: 0xFFB300)],
                               startPoint: .topLeading, endPoint: .bottomTrailing))

            // Перфорация
            ZStack {
                Rectangle().fill(Color(.systemBackground)).frame(height: 1)
                HStack { Circle().fill(Color(.systemGroupedBackground)).frame(width: 24, height: 24).offset(x: -12)
                    Spacer()
                    Circle().fill(Color(.systemGroupedBackground)).frame(width: 24, height: 24).offset(x: 12) }
            }

            VStack(spacing: 12) {
                QRCodeView(text: coupon.code, size: 180).opacity(isUsed ? 0.4 : 1)
                Text(coupon.code).font(.headline.monospaced()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 22)
            .background(Color(.secondarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(.systemGray5), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}
