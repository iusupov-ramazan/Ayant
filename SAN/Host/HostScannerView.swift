import SwiftUI
import VisionKit
import AyantDomain
import AyantFeatures

// MARK: - Сканер купонов (сторона бизнеса)
//
// Сотрудник сканирует QR купона гостя. Cloud Function `scanCoupon` атомарно
// гасит купон и начисляет 1 штамп в карту лояльности гостя. Работает только
// на реальном устройстве с камерой (VisionKit). На симуляторе — ручной ввод кода.

/// H13 Сканер → H14 Сумма чека → H15 Начислено.
///
/// Экран — акцентная поверхность, а не тёмная: единственный тёмный элемент во
/// всём хост-приложении это окно камеры. Ветку выбирает префикс QR, как и на
/// сервере: `AYANT-CARD:` → штамп, `AYANT-PTS:` → баллы, `AYANT-RDM:` → списание,
/// иначе купон.
struct HostScannerView: View {
    /// Если задан — сканируем для конкретного заведения (без выбора).
    var fixedVenueID: String? = nil
    /// `false`, когда сканер открыт вкладкой: закрывать нечего.
    var showsBack = true

    @EnvironmentObject private var host: HostStore
    @Environment(\.dismiss) private var dismiss

    @State private var venueID = ""
    @State private var processing = false
    @State private var result: ScanResultUI?
    @State private var lastCode = ""
    @State private var manualCode = ""
    @State private var pendingEarn: PendingEarn?   // ждём сумму/диапазон для баллов САН
    @State private var billText = ""               // ввод суммы чека (mode=cashback)
    /// Ключ идемпотентности МИНТИТСЯ ОДИН РАЗ на распознанный QR и переживает
    /// повторные тапы по кнопке: иначе ретрай ушёл бы с новым ключом и сервер
    /// начислил бы второй раз (CLAUDE.md, «Key reuse is a collision»).
    @State private var scanKey = ""
    /// Что показать на экране «Начислено» — заполняется из ответа сервера.
    @State private var receipt: EarnReceipt?

    private let couponService = AppConfig.makeCouponService()
    private let authService = AppConfig.makeAuthService()

    private var venues: [HostVenueDTO] { host.state.venues }
    private var currentVenue: HostVenueDTO? { venues.first { $0.id == venueID } }

    var body: some View {
        NavigationStack {
            ZStack {
                HostScanSurface()
                scannerScreen
                if processing || result != nil {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    resultCard
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $pendingEarn) { billScreen($0) }
            .fullScreenCover(item: $receipt) { r in
                HostScanReceiptView(
                    awarded: r.awarded, balance: r.balance, guestLabel: r.guestLabel,
                    billAmount: r.billAmount, modeLabel: r.modeLabel, replayed: r.replayed,
                    onScanMore: { receipt = nil; resetScan() },
                    onDone: { receipt = nil; if showsBack { dismiss() } else { resetScan() } })
            }
            .onAppear { venueID = fixedVenueID ?? venues.first?.id ?? "" }
        }
    }

    // MARK: H13 — сканер

    private var scannerScreen: some View {
        VStack(spacing: 0) {
            HStack {
                if showsBack {
                    HostScanIconButton(systemName: "chevron.left", label: "Назад") { dismiss() }
                } else {
                    Color.clear.frame(width: 40, height: 40)
                }
                Spacer()
                Text("Сканер купонов")
                    .font(.golos(16, .bold)).foregroundStyle(.white)
                Spacer()
                Color.clear.frame(width: 40, height: 40)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            if fixedVenueID == nil, venues.count > 1 {
                venuePicker.padding(.horizontal, 20).padding(.top, 14)
            }

            Spacer(minLength: 12)

            HostScanReticle {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    CodeScannerView(isPaused: processing || result != nil || pendingEarn != nil) {
                        handle($0)
                    }
                } else {
                    // Симулятор: камеры нет — работает ручной ввод ниже.
                    Color.clear
                }
            }

            kindChips.padding(.top, 22)

            Text("Наведите камеру на QR гостя — баллы, штамп или купон определятся сами")
                .font(.golos(14, .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
                .padding(.top, 16)

            Spacer(minLength: 12)

            codeEntry.padding(.horizontal, 20).padding(.bottom, 18)
        }
    }

    /// Информационные чипы: тип определяет префикс QR, поэтому это не
    /// переключатели, а «что принимает это заведение».
    private var kindChips: some View {
        HStack(spacing: 8) {
            HostScanKindChip(title: "Баллы", enabled: currentVenue?.asVenue.pointsActive == true)
            HostScanKindChip(title: "Штамп", enabled: currentVenue?.asVenue.stampsActive == true)
            HostScanKindChip(title: "Купон", enabled: true)
        }
    }

    private var venuePicker: some View {
        Menu {
            ForEach(venues) { v in Button(v.name) { venueID = v.id } }
        } label: {
            HStack {
                Text(currentVenue?.name ?? "Выберите заведение")
                    .font(.golos(15, .semibold)).foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var codeEntry: some View {
        VStack(spacing: 12) {
            Text("Или введите код")
                .textCase(.uppercase)
                .font(.golos(11.5, .heavy)).tracking(1.2)
                .foregroundStyle(.white.opacity(0.75))
            TextField("", text: $manualCode,
                      prompt: Text("AYANT-XXXXXX").foregroundColor(.white.opacity(0.55)))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.golos(15, .semibold))
                .tracking(3)
                .foregroundStyle(.white)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Button {
                handle(manualCode.trimmingCharacters(in: .whitespaces).uppercased())
            } label: {
                Text("Проверить код")
                    .font(.golos(16, .bold))
                    .foregroundStyle(Color.sanAccentDeep)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.sanPress(0.97))
            .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty || processing)
            .opacity(manualCode.trimmingCharacters(in: .whitespaces).isEmpty ? 0.6 : 1)
        }
    }

    // MARK: H14 — сумма чека

    @ViewBuilder
    private func billScreen(_ pending: PendingEarn) -> some View {
        let bands = currentVenue?.pointsBands ?? []
        let amount = Int(billText) ?? 0
        // Предпросмотр считает домен — своей формулы здесь нет.
        let preview = (try? PointsMath.award(config: PointsConfig(venue: previewConfigVenue),
                                             billAmount: amount, bandIndex: nil).get()) ?? 0
        ZStack {
            HostScanSurface()
            VStack(spacing: 0) {
                HStack {
                    HostScanIconButton(systemName: "chevron.left", label: "Назад") {
                        pendingEarn = nil; resetScan()
                    }
                    Spacer()
                    Text("Сумма чека")
                        .font(.golos(16, .bold)).foregroundStyle(.white)
                        .lineLimit(1).fixedSize()
                    Spacer()
                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.horizontal, 18).padding(.top, 8)

                guestRow(pending).padding(.horizontal, 20).padding(.top, 16)

                if pending.mode == "cashback" {
                    Spacer(minLength: 8)
                    VStack(spacing: 6) {
                        Text(amount > 0 ? amount.sanThousands : "0")
                            .sanText(64, .heavy, tracking: -3.2, lineHeight: 1)
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: amount)
                        Text("сом").font(.golos(14)).foregroundStyle(.white.opacity(0.8))
                    }
                    earnPreview(preview).padding(.top, 16)
                    Spacer(minLength: 12)
                    HostAmountKeypad(text: $billText).padding(.horizontal, 20)
                    Button {
                        pendingEarn = nil
                        submitScan(code: pending.code, billAmount: amount, bandIndex: nil,
                                   billForReceipt: amount)
                    } label: {
                        Text("Начислить баллы")
                            .font(.golos(16, .bold)).foregroundStyle(Color.sanAccentDeep)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.sanPress(0.97))
                    .disabled(amount <= 0)
                    .opacity(amount <= 0 ? 0.6 : 1)
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 18)
                } else {
                    // Диапазоны: сумму не вводим, выбираем полосу.
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(Array(bands.enumerated()), id: \.offset) { idx, band in
                                Button {
                                    pendingEarn = nil
                                    submitScan(code: pending.code, billAmount: nil, bandIndex: idx,
                                               billForReceipt: nil)
                                } label: {
                                    HStack {
                                        Text(idx == bands.count - 1 ? "\(band.maxAmount)+ сом"
                                                                    : "до \(band.maxAmount) сом")
                                        Spacer()
                                        Text("+\(band.points)").font(.golos(17, .heavy))
                                    }
                                    .font(.golos(16, .semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, 18).padding(.vertical, 16)
                                    .frame(maxWidth: .infinity)
                                    .background(.white.opacity(0.2),
                                                in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                                }
                                .buttonStyle(.sanPress(0.97))
                            }
                            if bands.isEmpty {
                                Text("Диапазоны не настроены в админ-панели.")
                                    .font(.golos(14)).foregroundStyle(.white.opacity(0.85))
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 20)
                            }
                        }
                        .padding(20)
                    }
                }
            }
        }
        .onAppear { billText = "" }
    }

    private func guestRow(_ pending: PendingEarn) -> some View {
        HStack(spacing: 12) {
            Circle().fill(.white.opacity(0.28)).frame(width: 38, height: 38)
                .overlay(Image(systemName: "person.fill")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text("Гость").font(.golos(14, .bold)).foregroundStyle(.white)
                Text(pending.userID.isEmpty ? "QR распознан" : "ID \(pending.userID.prefix(8))")
                    .font(.golos(11.5)).foregroundStyle(.white.opacity(0.8))
            }
            Spacer(minLength: 8)
            Text("QR верный")
                .font(.golos(12, .bold)).foregroundStyle(Color.sanOpen)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Color.white, in: Capsule())
        }
        .padding(14)
        .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func earnPreview(_ points: Int) -> some View {
        HStack(spacing: 8) {
            Circle().fill(Color(hex: Palette.orange)).frame(width: 7, height: 7)
            Text("+\(points) баллов гостю")
                .font(.golos(13.5, .heavy)).foregroundStyle(Color.sanAccentDeep)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Color.white, in: Capsule())
        .animation(.snappy, value: points)
    }

    /// Доменный `Venue` только ради `PointsConfig` — предпросмотр обязан считать
    /// той же математикой, что и сервер.
    private var previewConfigVenue: Venue {
        var v = Venue(id: "", name: "", category: .cafe, district: "", address: "",
                      phone: "", emoji: "", gradient: Venue.defaultGradient)
        v.pointsEnabled = true
        v.pointsMode = currentVenue?.pointsMode ?? "flat"
        v.pointsFlat = currentVenue?.pointsFlat ?? 0
        v.cashbackPercent = currentVenue?.cashbackPercent ?? 0
        v.pointsBands = currentVenue?.pointsBands ?? []
        return v
    }

    // MARK: Результат (ошибки и не-балльные ветки)

    private var resultCard: some View {
        VStack(spacing: 14) {
            if processing {
                ProgressView().tint(Color.sanAccent)
                Text("Проверяем код…").font(.golos(16, .semibold)).foregroundStyle(Color.sanInk)
            } else if let result {
                Image(systemName: result.ok ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .font(.system(size: 44)).foregroundStyle(result.ok ? Color.sanOpen : Color(hex: 0xE8556B))
                Text(result.title).font(.golos(18, .bold)).foregroundStyle(Color.sanInk)
                    .multilineTextAlignment(.center)
                if let sub = result.subtitle {
                    Text(sub).font(.golos(14)).foregroundStyle(Color.sanInkSoft)
                        .multilineTextAlignment(.center)
                }
                Button { resetScan() } label: { Text("Сканировать ещё") }
                    .buttonStyle(SanPrimaryButton())
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: 340)
        .background(Color.sanSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 28)
    }

    private func resetScan() {
        result = nil
        lastCode = ""
        manualCode = ""
        scanKey = ""
    }

    // MARK: Логика

    private func handle(_ code: String) {
        let code = code.trimmingCharacters(in: .whitespaces)
        guard !processing, result == nil, pendingEarn == nil, !code.isEmpty, code != lastCode else { return }
        guard !venueID.isEmpty else { result = .error("Выберите заведение"); return }

        // Ключ на распознанный QR — один, и он переживёт переход на экран суммы
        // и повторные тапы по кнопке начисления.
        lastCode = code
        scanKey = UUID().uuidString

        if code.hasPrefix("AYANT-PTS:") {
            let mode = currentVenue?.pointsMode ?? "flat"
            if mode == "cashback" || mode == "bands" {
                let userID = code.split(separator: ":").dropFirst().first.map(String.init) ?? ""
                pendingEarn = PendingEarn(code: code, mode: mode, userID: userID)
                return
            }
            submitScan(code: code, billAmount: nil, bandIndex: nil, billForReceipt: nil)
            return
        }
        if code.hasPrefix("AYANT-RDM:") {
            submitRedeem(code: code)
            return
        }
        submitScan(code: code, billAmount: nil, bandIndex: nil, billForReceipt: nil)
    }

    /// Начисление баллов / штамп / погашение купона через scanCoupon.
    private func submitScan(code: String, billAmount: Int?, bandIndex: Int?, billForReceipt: Int?) {
        processing = true
        let key = scanKey.isEmpty ? UUID().uuidString : scanKey
        let vID = venueID
        let modeLabel = currentVenue.flatMap(Self.modeLabel)
        Task {
            let token = await authService.idToken() ?? ""
            do {
                let out = try await couponService.scanCoupon(code: code, venueID: vID, idToken: token,
                                                             billAmount: billAmount, bandIndex: bandIndex,
                                                             idempotencyKey: key)
                await MainActor.run {
                    processing = false
                    if out.ok && out.points {
                        // Баллы → полноэкранная квитанция (H15).
                        receipt = EarnReceipt(awarded: out.awarded, balance: out.balance,
                                              guestLabel: "Гость",
                                              billAmount: billForReceipt,
                                              modeLabel: modeLabel,
                                              replayed: out.replayed)
                    } else {
                        result = out.ok ? .success(out) : .error(Self.message(for: out.errorCode))
                    }
                }
            } catch {
                await MainActor.run { processing = false; result = .error("Ошибка сети. Попробуйте ещё раз.") }
            }
        }
    }

    /// Списание баллов на награду. Код: AYANT-RDM:userID:rewardId[:points].
    private func submitRedeem(code: String) {
        let parts = code.split(separator: ":").map(String.init)
        guard parts.count >= 3 else { result = .error("Неверный код награды."); return }
        let userID = parts[1], rewardId = parts[2]
        let pts = parts.count >= 4 ? (Int(parts[3]) ?? 0) : 0    // для money-награды
        processing = true
        let vID = venueID
        let key = scanKey.isEmpty ? UUID().uuidString : scanKey
        Task {
            let token = await authService.idToken() ?? ""
            let outcome: ScanResultUI
            do {
                // Ключ идемпотентности на один разобранный QR: если запрос
                // придётся повторить (таймаут), сервер вернёт первый результат,
                // а не спишет баллы второй раз.
                let out = try await couponService.redeemVenuePoints(venueID: vID, userID: userID,
                                                                    rewardId: rewardId, pointsToSpend: pts,
                                                                    idToken: token,
                                                                    idempotencyKey: key)
                outcome = out.ok ? .redeemed(out) : .error(Self.message(for: out.errorCode))
            } catch {
                outcome = .error("Ошибка сети. Попробуйте ещё раз.")
            }
            await MainActor.run { processing = false; result = outcome }
        }
    }

    /// «Кэшбэк 5%» / «30 за визит» — для строки квитанции.
    private static func modeLabel(_ v: HostVenueDTO) -> String? {
        switch v.pointsMode {
        case "cashback":
            guard v.cashbackPercent > 0 else { return nil }
            return "Кэшбэк \(v.cashbackPercent.sanPercentText)%"
        case "bands": return "По сумме чека"
        default:
            guard v.pointsFlat > 0 else { return nil }
            return "\(v.pointsFlat) за визит"
        }
    }

    private static func message(for code: String?) -> String {
        switch code {
        case "coupon_not_found": return "Купон не найден."
        case "wrong_venue":      return "Этот код — для другого заведения."
        case "loyalty_off":      return "Карта лояльности у заведения выключена."
        case "already_used":     return "Купон уже был использован."
        case "not_owner":        return "У вас нет прав на это заведение."
        case "venue_not_found":  return "Заведение не найдено."
        case "no_token", "bad_token": return "Требуется вход в аккаунт заведения."
        case "missing_params":   return "Пустой код купона."
        // Баллы САН
        case "points_off":       return "Баллы САН у заведения выключены."
        case "cooldown":         return "Баллы этому гостю уже начислены недавно."
        case "missing_amount":   return "Введите сумму чека."
        case "bad_band":         return "Выберите диапазон суммы."
        case "no_points":        return "Начислять нечего (0 баллов)."
        case "bad_code":         return "Неверный QR-код."
        case "insufficient":     return "У гостя недостаточно баллов."
        case "reward_not_found": return "Награда не найдена или отключена."
        case "redeem_not_allowed": return "Списание баллов недоступно для этого заведения."
        case "below_min":        return "Слишком мало баллов для этой награды."
        case "missing_user":     return "Не удалось определить гостя."
        default:                 return "Не удалось отсканировать код."
        }
    }
}

/// Данные экрана «Начислено» — всё из ответа сервера.
struct EarnReceipt: Identifiable {
    let id = UUID()
    let awarded: Int
    let balance: Int
    let guestLabel: String
    let billAmount: Int?
    let modeLabel: String?
    let replayed: Bool
}

/// Ожидание суммы/диапазона перед начислением баллов САН.
struct PendingEarn: Identifiable {
    let id = UUID()
    let code: String
    let mode: String   // "cashback" | "bands"
    var userID: String = ""
}

/// Модель результата для UI.
enum ScanResultUI {
    case success(ScanOutcome)
    case redeemed(RedeemOutcome)
    case error(String)

    var ok: Bool { if case .error = self { return false }; return true }

    var title: String {
        switch self {
        case .success(let o):
            if o.points { return o.awarded > 0 ? "+\(o.awarded) баллов ✓" : "Готово ✓" }
            return o.title.isEmpty ? "Купон погашен ✓" : "«\(o.title)» ✓"
        case .redeemed(let r):
            return r.rewardTitle.isEmpty ? "Награда выдана ✓" : "«\(r.rewardTitle)» ✓"
        case .error(let m): return m
        }
    }
    var subtitle: String? {
        switch self {
        case .success(let o):
            if o.points { return "Начислено \(o.awarded). Баланс гостя: \(o.balance) баллов." }
            guard o.loyalty else { return "Купон погашен." }
            if o.rewardIssued { return "🎉 Карта заполнена! Сегодня награда: «\(o.rewardTitle)» — выдайте гостю." }
            return "Штамп начислен: \(o.stamps) из \(o.goal)."
        case .redeemed(let r):
            if let som = r.somOff { return "Списано \(r.redeemed) баллов (−\(som) сом). Остаток: \(r.balance)." }
            return "Списано \(r.redeemed) баллов. Остаток: \(r.balance). Выдайте награду гостю."
        case .error: return nil
        }
    }
}

// MARK: - Уголки рамки сканера

struct CornerBrackets: Shape {
    var len: CGFloat = 28
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // Верхний-левый
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + len))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + len, y: rect.minY))
        // Верхний-правый
        p.move(to: CGPoint(x: rect.maxX - len, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + len))
        // Нижний-правый
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - len))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - len, y: rect.maxY))
        // Нижний-левый
        p.move(to: CGPoint(x: rect.minX + len, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - len))
        return p
    }
}

// MARK: - VisionKit-обёртка

struct CodeScannerView: UIViewControllerRepresentable {
    var isPaused: Bool
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        if isPaused {
            vc.stopScanning()
        } else {
            try? vc.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                if case let .barcode(barcode) = item, let s = barcode.payloadStringValue {
                    onScan(s)
                    break
                }
            }
        }
    }
}
