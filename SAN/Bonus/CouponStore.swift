import SwiftUI
import UIKit
import AyantDomain
import AyantFeatures

// MARK: - Линия перфорации (пунктир) для билета-купона

struct DashedLine: Shape {
    var vertical = false
    func path(in rect: CGRect) -> Path {
        var p = Path()
        if vertical {
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        } else {
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        return p
    }
}

// MARK: - Мои купоны

struct MyCouponsView: View {
    @EnvironmentObject private var coupons: CouponStore

    var body: some View {
        let available = coupons.coupons.filter { !$0.used }
        let used = coupons.coupons.filter { $0.used }
        Group {
            if coupons.coupons.isEmpty {
                ContentUnavailableView("Нет купонов",
                    systemImage: "ticket",
                    description: Text("Получи купон на акции заведений или обменяй бонусы во вкладке «Бонусы»."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if !available.isEmpty { couponSection("Доступные", available) }
                        if !used.isEmpty { couponSection("Использованные", used) }
                    }
                    .padding(16)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle("Мои купоны")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func couponSection(_ title: String, _ items: [Coupon]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(title) · \(items.count)")
                .font(.footnote.weight(.semibold)).textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            ForEach(items) { couponCard($0) }
        }
    }

    private func couponCard(_ c: Coupon) -> some View {
        NavigationLink { CouponDetailView(coupon: c) } label: {
            HStack(spacing: 0) {
                ZStack {
                    LinearGradient(colors: c.used ? [Color(.systemGray3), Color(.systemGray4)]
                                                   : [Color(hex: 0xFF4D29), Color(hex: 0xFFB300)],
                                   startPoint: .top, endPoint: .bottom)
                    Image(systemName: "ticket.fill").font(.title2).foregroundStyle(.white)
                }
                .frame(width: 62)
                .overlay(alignment: .trailing) {
                    DashedLine(vertical: true)
                        .stroke(Color.white.opacity(0.65), style: StrokeStyle(lineWidth: 1.4, dash: [4, 4]))
                        .frame(width: 1)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(c.title).font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary).lineLimit(2)
                    if !c.venueName.isEmpty {
                        Label(c.venueName, systemImage: "mappin.circle.fill")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    CouponStatusPill(used: c.used)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary).padding(.trailing, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.systemGray5), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

/// Пилюля статуса купона (активен / использован).
struct CouponStatusPill: View {
    let used: Bool
    var body: some View {
        Label(used ? "Использован" : "Активен",
              systemImage: used ? "checkmark.seal.fill" : "checkmark.circle.fill")
            .font(.caption2.weight(.bold))
            .foregroundStyle(used ? Color.secondary : Color.green)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background((used ? Color.secondary : Color.green).opacity(0.14), in: Capsule())
    }
}

// MARK: - Подарок готов (картинка купона + текст для шаринга)

/// Картинка-купон для шаринга (рендерится в UIImage).
struct GiftCardImage: View {
    let title: String
    var body: some View {
        VStack(spacing: 14) {
            Text("🎁").font(.system(size: 72))
            Text("ПОДАРОК · AYANT").font(.headline.weight(.heavy)).tracking(2)
            Text(title).font(.title.weight(.bold)).multilineTextAlignment(.center)
            Text("Открой ссылку в приложении Ayant\nи забери купон").font(.subheadline)
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
        "🎁 Тебе подарок — купон «\(title)» в Ayant! Забери по ссылке: \(url.absoluteString)"
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
    @State private var copied = false
    @State private var prevBrightness = UIScreen.main.brightness

    private var isUsed: Bool {
        coupons.coupons.first(where: { $0.id == coupon.id })?.used ?? coupon.used
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ticket
                actions
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Купон")
        // QR не должен перекрываться FAB — на листе-детали таб-бар прячем.
        .toolbar(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            prevBrightness = UIScreen.main.brightness
            if !isUsed { UIScreen.main.brightness = 1.0 }   // ярче — легче сканировать
        }
        .onDisappear { UIScreen.main.brightness = prevBrightness }
        .alert("Использовать купон?", isPresented: $showUseConfirm) {
            Button("Да, применить", role: .destructive) { coupons.markUsed(coupon) }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Подтверждай только при сотруднике — купон одноразовый.")
        }
    }

    // MARK: Действия под билетом

    @ViewBuilder private var actions: some View {
        if isUsed {
            Label("Купон использован", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
        } else if coupon.isVenueBound {
            infoRow("qrcode.viewfinder",
                    "Покажите QR сотруднику — он отсканирует его, и предложение применится.")
        } else {
            VStack(spacing: 12) {
                infoRow("info.circle", "Покажите этот экран сотруднику заведения перед оплатой.")
                Button { showUseConfirm = true } label: {
                    Text("Использовать купон").font(.headline)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Color.sanAccent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func infoRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color.sanAccentText)
            Text(text).font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Билет-купон

    private var ticket: some View {
        VStack(spacing: 0) {
            // Шапка
            VStack(spacing: 12) {
                HStack {
                    Text("AYANT").font(.caption2.weight(.black)).tracking(3)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(.white.opacity(0.22), in: Capsule())
                    Spacer()
                    Label(isUsed ? "Использован" : "Активен",
                          systemImage: isUsed ? "checkmark.seal.fill" : "checkmark.circle.fill")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(.white.opacity(0.22), in: Capsule())
                }
                Text(coupon.title)
                    .font(.title2.weight(.heavy)).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                if !coupon.venueName.isEmpty {
                    Label(coupon.venueName, systemImage: "mappin.circle.fill")
                        .font(.footnote.weight(.medium))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20).padding(.vertical, 22)
            .frame(maxWidth: .infinity)
            .background(headerGradient)

            perforation

            // Тело: QR + код. QR только у купона заведения — он записан в
            // Firestore и его сканирует сотрудник. У бонус-купона документа
            // на сервере нет, показывать сканируемый код нельзя: остаётся
            // код текстом и кнопка «Использовать купон» ниже.
            VStack(spacing: 16) {
                if coupon.isVenueBound {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.white)
                            .frame(width: 224, height: 224)
                            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                        QRCodeView(text: coupon.code, size: 188).opacity(isUsed ? 0.35 : 1)
                        if isUsed { usedStamp }
                    }
                } else if isUsed {
                    usedStamp.padding(.vertical, 12)
                }
                VStack(spacing: 6) {
                    Text("КОД КУПОНА").font(.caption2.weight(.semibold))
                        .tracking(1.5).foregroundStyle(.secondary)
                    Button {
                        UIPasteboard.general.string = coupon.code
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { copied = false }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(coupon.code).font(.title3.weight(.bold).monospaced()).tracking(1)
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.caption).foregroundStyle(copied ? .green : .secondary)
                        }
                    }
                    .buttonStyle(.plain).foregroundStyle(.primary)
                }
            }
            .padding(.vertical, 24).padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 10)
    }

    private var headerGradient: LinearGradient {
        LinearGradient(colors: isUsed ? [Color(.systemGray2), Color(.systemGray3)]
                                      : [Color(hex: 0xFF4D29), Color(hex: 0xFFB300)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // Полоса перфорации: настоящие вырезы-полукруги по краям (маска), а не
    // крашеные кружки — выглядит одинаково в любой теме и на любом фоне.
    private var perforation: some View {
        DashedLine()
            .stroke(Color(.systemGray3), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            .frame(height: 1)
            .padding(.horizontal, 24)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .mask { notchMask }
    }

    private var notchMask: some View {
        ZStack {
            Rectangle().fill(.white)
            HStack {
                Circle().fill(.white).frame(width: 30, height: 30).offset(x: -15)
                Spacer()
                Circle().fill(.white).frame(width: 30, height: 30).offset(x: 15)
            }
            .blendMode(.destinationOut)
        }
        .compositingGroup()
    }

    private var usedStamp: some View {
        Text("ПОГАШЕНО")
            .font(.title3.weight(.black)).tracking(2)
            .foregroundStyle(Color.red.opacity(0.8))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.8), lineWidth: 3))
            .rotationEffect(.degrees(-15))
    }
}
