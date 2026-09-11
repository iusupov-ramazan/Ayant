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

// MARK: - Форма билета: скруглённый прямоугольник с вырезами на перфорации
//
// Два полукруглых выреза лежат на линии перфорации. `vertical` — линия
// вертикальная (x = cut), вырезы сверху и снизу (карточка в списке);
// иначе линия горизонтальная (y = cut), вырезы слева и справа (билет на
// экране купона). Круги наполовину торчат за край, поэтому рисовать надо с
// `FillStyle(eoFill: true)` — тогда пересечение с прямоугольником вычитается,
// а вырез выглядит одинаково в любой теме и на любом фоне.

struct TicketShape: Shape {
    var cut: CGFloat
    var vertical: Bool
    var notchRadius: CGFloat = 9
    var cornerRadius: CGFloat = SanRadius.card

    func path(in rect: CGRect) -> Path {
        var p = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        let r = notchRadius
        let d = r * 2
        if vertical {
            let x = rect.minX + cut
            p.addEllipse(in: CGRect(x: x - r, y: rect.minY - r, width: d, height: d))
            p.addEllipse(in: CGRect(x: x - r, y: rect.maxY - r, width: d, height: d))
        } else {
            let y = rect.minY + cut
            p.addEllipse(in: CGRect(x: rect.minX - r, y: y - r, width: d, height: d))
            p.addEllipse(in: CGRect(x: rect.maxX - r, y: y - r, width: d, height: d))
        }
        return p
    }
}

// MARK: - Общий вид купона (подписи вида, глиф, «погашенный» градиент)

private enum CouponLook {
    /// Подпись под названием: откуда взялся купон.
    static func kindLabel(_ kind: String) -> LocalizedStringKey {
        switch kind {
        case "loyalty": return "Награда за карту лояльности"
        case "deal":    return "Купон на акцию"
        case "gift":    return "Подарок от друга"
        default:        return "Бонусный купон"
        }
    }

    /// Что показать на корешке: эмодзи по виду или инициал заведения.
    static func glyph(for coupon: Coupon) -> String {
        switch coupon.kind {
        case "loyalty": return "🎁"
        case "deal":    return "🎟"
        default:
            if let first = coupon.venueName.trimmingCharacters(in: .whitespaces).first {
                return String(first).uppercased()
            }
            return "🎟"
        }
    }

    /// Приглушённый тёплый серый — для использованных купонов.
    static var usedGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xB5ADA4), Color(hex: 0x8E867E)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @ViewBuilder
    static func gradient(used: Bool) -> some View {
        if used { usedGradient } else { LinearGradient.sanAccentGradient }
    }

    /// «3 активных купона» — склонение по последним цифрам.
    static func activeText(_ n: Int) -> String {
        if n == 0 { return "Активных купонов нет" }
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "\(n) активный купон" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "\(n) активных купона" }
        return "\(n) активных купонов"
    }
}

// MARK: - Мои купоны

/// Список купонов. Открывается пушем из профиля и с экрана бонусов, поэтому
/// своего стека нет: системную панель прячем ради редакторского заголовка,
/// «назад» даёт `sanNavBar`.
struct MyCouponsView: View {
    @EnvironmentObject private var coupons: CouponStore
    @Environment(\.dismiss) private var dismiss

    private var available: [Coupon] { coupons.coupons.filter { !$0.used } }
    private var used: [Coupon] { coupons.coupons.filter { $0.used } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                titleBlock
                if coupons.coupons.isEmpty {
                    emptyState
                        .padding(.horizontal, SanMetrics.screenPadding)
                } else {
                    if !available.isEmpty {
                        couponSection("Активные", available, startIndex: 0)
                    }
                    if !used.isEmpty {
                        couponSection("Использованные", used, startIndex: available.count)
                    }
                }
            }
            .padding(.bottom, 28)
        }
        .background(Color.sanCanvas.ignoresSafeArea())
        .sanStatusBarCap()
        .sanNavBar { dismiss() }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Заголовок

    private var subtitle: String {
        var text = CouponLook.activeText(available.count)
        if !used.isEmpty { text += " · использованных: \(used.count)" }
        return text
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Купоны")
                .sanEditorialTitle(44)
                .foregroundStyle(Color.sanInk)
            Text(subtitle)
                .sanText(14, .regular, lineHeight: 1.42)
                .foregroundStyle(Color.sanInkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SanMetrics.screenPadding)
        .padding(.top, 8)
        .sanScreenEnter()
    }

    // MARK: Секции

    private func couponSection(_ title: LocalizedStringKey, _ items: [Coupon],
                               startIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title)
                Text("· \(items.count)")
            }
            .textCase(.uppercase)
            .sanEyebrowText()
            .foregroundStyle(Color.sanInkSoft)
            .padding(.leading, 4)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, coupon in
                NavigationLink { CouponDetailView(coupon: coupon) } label: {
                    CouponTicketCard(coupon: coupon)
                }
                .buttonStyle(.sanPress(0.98))
                .opacity(coupon.used ? 0.6 : 1)
                .sanRise(startIndex + index,
                         stagger: SanTiming.dealRowRise.stagger,
                         duration: SanTiming.dealRowRise.duration)
            }
        }
        .padding(.horizontal, SanMetrics.screenPadding)
    }

    // MARK: Пустое состояние

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🎟").font(.system(size: 52))
            Text("Купонов пока нет")
                .font(.golos(20, .bold))
                .foregroundStyle(Color.sanInk)
            Text("Купоны появляются с акций — нажмите «Получить купон» на странице предложения — и за заполненную карту штампов в заведении.")
                .sanText(14, .regular, lineHeight: 1.42)
                .foregroundStyle(Color.sanInkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .sanCard(padding: 24, radius: SanRadius.hero)
    }
}

// MARK: - Карточка-билет в списке

/// Корешок слева (градиент + глиф), перфорация, справа — название, заведение,
/// вид купона, код и статус.
struct CouponTicketCard: View {
    let coupon: Coupon

    private static let stubWidth: CGFloat = 76
    private var shape: TicketShape {
        TicketShape(cut: Self.stubWidth, vertical: true, notchRadius: 9, cornerRadius: SanRadius.card)
    }

    var body: some View {
        HStack(spacing: 0) {
            stub
            VStack(alignment: .leading, spacing: 4) {
                Text(coupon.title)
                    .font(.golos(15, .bold)).tracking(-0.2)
                    .foregroundStyle(Color.sanInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !coupon.venueName.isEmpty {
                    Text(coupon.venueName)
                        .font(.golos(12.5, .medium))
                        .foregroundStyle(Color.sanInkSoft)
                        .lineLimit(1)
                }
                Text(CouponLook.kindLabel(coupon.kind))
                    .font(.golos(11.5, .semibold))
                    .foregroundStyle(Color.sanAccentText)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(coupon.code)
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.sanInkSoft)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    CouponStatusPill(used: coupon.used)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Сначала маска содержимого, потом подложка с тенью: иначе маска
        // обрежет и тень.
        .mask { shape.fill(style: FillStyle(eoFill: true)) }
        .background {
            shape.fill(Color.sanSurface, style: FillStyle(eoFill: true))
                .shadow(color: .black.opacity(0.05), radius: 7, y: 3)
        }
        // Обводка обрезается по рамке карточки, чтобы внешние половины
        // кругов-вырезов не рисовались за краем.
        .overlay { shape.stroke(Color.sanHairline, lineWidth: 0.5).clipped() }
    }

    private var stub: some View {
        ZStack {
            CouponLook.gradient(used: coupon.used)
            SanRisoHatch(opacity: 0.14)
            // Эмодзи цвет игнорируют, инициал становится белым — один стиль на оба.
            Text(CouponLook.glyph(for: coupon))
                .font(.golos(26, .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: Self.stubWidth)
        .overlay(alignment: .trailing) {
            DashedLine(vertical: true)
                .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .frame(width: 1.5)
                .padding(.vertical, 12)
        }
    }
}

/// Пилюля статуса купона (активен / использован).
struct CouponStatusPill: View {
    let used: Bool
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: used ? "checkmark.seal.fill" : "checkmark.circle.fill")
                .font(.system(size: 9.5, weight: .bold))
            Text(used ? "Использован" : "Активен")
                .font(.golos(10.5, .heavy)).tracking(0.2)
        }
        .foregroundStyle(used ? Color.sanInkSoft : Color.sanOpen)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(used ? Color.sanSurfaceMuted : Color.sanOpen.opacity(0.12), in: Capsule())
        .fixedSize()
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

/// Билет: градиентная шапка, перфорация с вырезами, белое тело с QR и кодом.
/// Открывается и пушем из списка, и в листе со страницы акции
/// (`DetailViews`) — в обоих случаях `dismiss()` закрывает то, что нужно.
struct CouponDetailView: View {
    let coupon: Coupon
    @EnvironmentObject private var coupons: CouponStore
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var showUseConfirm = false
    @State private var copied = false
    @State private var prevBrightness = UIScreen.main.brightness
    /// Высота шапки — по ней ставятся вырезы перфорации.
    @State private var headerHeight: CGFloat = 132

    private static let perforationHeight: CGFloat = 30

    private var isUsed: Bool {
        coupons.coupons.first(where: { $0.id == coupon.id })?.used ?? coupon.used
    }

    /// «11 сентября» — родительный падеж даёт сам формат `d MMMM` в ru_RU.
    private var receivedText: String {
        coupon.createdAt.formatted(
            Date.FormatStyle(locale: Locale(identifier: "ru_RU")).day().month(.wide))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ticket
                actions
            }
            .padding(.horizontal, SanMetrics.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color.sanCanvas.ignoresSafeArea())
        .sanNavBar("Купон") { dismiss() }
        .toolbar(.hidden, for: .navigationBar)
        // QR не должен перекрываться FAB — на листе-детали таб-бар прячем.
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            prevBrightness = UIScreen.main.brightness
            if !isUsed { UIScreen.main.brightness = 1.0 }   // ярче — легче сканировать
        }
        .onDisappear { UIScreen.main.brightness = prevBrightness }
        .alert("Использовать купон?", isPresented: $showUseConfirm) {
            Button("Да, применить", role: .destructive) {
                coupons.markUsed(coupon)
                // Иначе заведение не увидит погашение в аналитике.
                store.redeemCoupon(coupon)
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Подтверждай только при сотруднике — купон одноразовый.")
        }
    }

    // MARK: Действия под билетом

    @ViewBuilder private var actions: some View {
        if isUsed {
            usedState
        } else if coupon.isVenueBound {
            infoRow("qrcode.viewfinder",
                    "Покажите QR сотруднику — он отсканирует его, и предложение применится.")
        } else {
            VStack(spacing: 12) {
                infoRow("info.circle", "Покажите этот экран сотруднику заведения перед оплатой.")
                Button { showUseConfirm = true } label: {
                    Text("Использовать купон")
                }
                .buttonStyle(SanPrimaryButton())
            }
        }
    }

    private var usedState: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.sanOpen)
            VStack(alignment: .leading, spacing: 3) {
                Text("Купон использован")
                    .font(.golos(17, .bold))
                    .foregroundStyle(Color.sanOpen)
                Text("Повторно применить его нельзя.")
                    .font(.golos(13, .medium))
                    .foregroundStyle(Color.sanInkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color.sanOpen.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: SanRadius.card, style: .continuous))
    }

    private func infoRow(_ icon: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            SanIconTile(systemName: icon, size: 36)
            Text(text)
                .sanText(14, .regular, lineHeight: 1.42)
                .foregroundStyle(Color.sanInkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sanCard(padding: 14, radius: SanRadius.card)
    }

    // MARK: Билет-купон

    private var ticketShape: TicketShape {
        TicketShape(cut: headerHeight + Self.perforationHeight / 2,
                    vertical: false,
                    notchRadius: Self.perforationHeight / 2,
                    cornerRadius: SanRadius.hero)
    }

    private var ticket: some View {
        VStack(spacing: 0) {
            header
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { headerHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, h in headerHeight = h }
                })
            perforation
            ticketBody
        }
        // Маска — на содержимое, подложка с тенью — отдельно, иначе тень
        // обрезается по маске.
        .mask { ticketShape.fill(style: FillStyle(eoFill: true)) }
        .background {
            ticketShape.fill(Color.sanSurface, style: FillStyle(eoFill: true))
                .shadow(color: .black.opacity(0.10), radius: 14, y: 8)
        }
        .overlay { ticketShape.stroke(Color.sanHairline, lineWidth: 0.5).clipped() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(coupon.venueName.isEmpty ? "Купон" : coupon.venueName)
                    .textCase(.uppercase)
                    .sanEyebrowText()
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("AYANT")
                    .font(.golos(10.5, .black)).tracking(2.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.white.opacity(0.2), in: Capsule())
            }
            Text(coupon.title)
                .font(.golos(26, .heavy)).tracking(-0.8)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(CouponLook.kindLabel(coupon.kind))
                .font(.golos(13, .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                CouponLook.gradient(used: isUsed)
                SanRisoHatch(opacity: 0.12)
            }
        }
    }

    // Полоса перфорации: сами вырезы делает `TicketShape` на уровне билета,
    // здесь — только пунктир между ними.
    private var perforation: some View {
        DashedLine()
            .stroke(Color.sanInkSoft.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            .frame(height: 2)
            .padding(.horizontal, Self.perforationHeight / 2 + 12)
            .frame(height: Self.perforationHeight)
            .frame(maxWidth: .infinity)
    }

    // Тело: QR + код. QR только у купона заведения — он записан в
    // Firestore и его сканирует сотрудник. У бонус-купона документа
    // на сервере нет, показывать сканируемый код нельзя: остаётся
    // код текстом и кнопка «Использовать купон» ниже.
    private var ticketBody: some View {
        VStack(spacing: 18) {
            if coupon.isVenueBound {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.white)
                        .frame(width: 236, height: 236)
                        .sanShadow(.qrCard)
                    QRCodeView(text: coupon.code, size: 200).opacity(isUsed ? 0.35 : 1)
                    if isUsed { usedStamp }
                }
                .padding(.top, 6)
            } else if isUsed {
                usedStamp.padding(.vertical, 8)
            }

            VStack(spacing: 10) {
                Text("Код купона")
                    .textCase(.uppercase)
                    .sanEyebrowText()
                    .foregroundStyle(Color.sanInkSoft)
                Text(coupon.code)
                    .font(.system(size: 24, weight: .heavy, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(Color.sanInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                copyButton
            }

            SanHairline()

            HStack {
                Text("Получен \(receivedText)")
                    .font(.golos(12.5, .medium))
                    .foregroundStyle(Color.sanInkSoft)
                Spacer(minLength: 8)
                CouponStatusPill(used: isUsed)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = coupon.code
            SanHaptics.selection()
            withAnimation(.sanStandard) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.sanStandard) { copied = false }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .bold))
                Text(copied ? "Скопировано" : "Скопировать")
                    .font(.golos(13.5, .bold))
            }
            .foregroundStyle(copied ? Color.sanOpen : Color.sanInk)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(copied ? Color.sanOpen.opacity(0.12) : Color.sanSurfaceMuted, in: Capsule())
        }
        .buttonStyle(.sanPress(0.94))
        .accessibilityLabel("Скопировать код купона")
    }

    private var usedStamp: some View {
        Text("ПОГАШЕНО")
            .font(.golos(20, .black)).tracking(2)
            .foregroundStyle(Color(hex: Palette.red).opacity(0.85))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: Palette.red).opacity(0.85), lineWidth: 3))
            .rotationEffect(.degrees(-15))
    }
}
