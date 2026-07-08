import SwiftUI
import VisionKit

// MARK: - Сканер купонов (сторона бизнеса)
//
// Сотрудник сканирует QR купона гостя. Cloud Function `scanCoupon` атомарно
// гасит купон и начисляет 1 штамп в карту лояльности гостя. Работает только
// на реальном устройстве с камерой (VisionKit). На симуляторе — ручной ввод кода.

struct HostScannerView: View {
    /// Если задан — сканируем для конкретного заведения (без выбора).
    var fixedVenueID: String? = nil

    @EnvironmentObject private var host: HostStore
    @Environment(\.dismiss) private var dismiss

    @State private var venueID = ""
    @State private var processing = false
    @State private var result: ScanResultUI?
    @State private var lastCode = ""
    @State private var manualCode = ""

    private let couponService = AppConfig.makeCouponService()
    private let authService = AppConfig.makeAuthService()

    private var venues: [HostVenueDTO] { host.venueDTOs }
    private var currentVenue: HostVenueDTO? { venues.first { $0.id == venueID } }

    private let darkBG = Color(hex: 0x0E0D0C)
    private let panel = Color(hex: 0x1A1917)
    private let field = Color(hex: 0x201E1C)

    var body: some View {
        NavigationStack {
            ZStack {
                darkBG.ignoresSafeArea()
                VStack(spacing: 20) {
                    header
                    if fixedVenueID == nil, venues.count > 1 { venuePicker }
                    scannerArea
                    Text("Наведите камеру на QR купона гостя")
                        .font(.golos(15, .medium)).foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    codeEntry
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20).padding(.top, 8)

                if processing || result != nil {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    resultCard
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { venueID = fixedVenueID ?? venues.first?.id ?? "" }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Шапка

    private var header: some View {
        ZStack {
            Text("Сканер купонов").font(.golos(20, .bold)).foregroundStyle(.white)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
    }

    // MARK: Выбор заведения

    private var venuePicker: some View {
        Menu {
            ForEach(venues) { v in Button(v.name) { venueID = v.id } }
        } label: {
            HStack {
                Text(currentVenue?.name ?? "Выберите заведение")
                    .font(.golos(15, .semibold)).foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Камера / плейсхолдер

    @ViewBuilder
    private var scannerArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(panel)
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                CodeScannerView(isPaused: processing || result != nil) { code in handle(code) }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white)
                            .frame(width: 150, height: 150)
                        Image(systemName: "qrcode").font(.system(size: 92)).foregroundStyle(.black)
                        Rectangle().fill(Color.sanAccent).frame(height: 2).frame(width: 150)
                            .shadow(color: Color.sanAccent, radius: 6)
                    }
                    Text("AYANT-XXXXXX").font(.golos(15, .bold)).foregroundStyle(.white.opacity(0.5))
                        .tracking(1)
                }
            }
            CornerBrackets(len: 30)
                .stroke(Color.sanAccent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .padding(22)
        }
        .frame(height: 320)
    }

    // MARK: Ввод кода

    private var codeEntry: some View {
        VStack(spacing: 14) {
            Text("ИЛИ ВВЕДИТЕ КОД").font(.golos(12, .bold)).tracking(1.2)
                .foregroundStyle(.white.opacity(0.45))
            TextField("", text: $manualCode, prompt: Text("AYANT-XXXXXX").foregroundColor(.white.opacity(0.4)))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.golos(17, .bold))
                .foregroundStyle(.white)
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity)
                .background(field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Button {
                handle(manualCode.trimmingCharacters(in: .whitespaces).uppercased())
            } label: { Text("Проверить купон") }
            .buttonStyle(SanPrimaryButton())
            .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty || processing)
        }
    }

    // MARK: Результат

    private var resultCard: some View {
        VStack(spacing: 14) {
            if processing {
                ProgressView().tint(.white)
                Text("Проверяем купон…").font(.golos(16, .semibold)).foregroundStyle(.white)
            } else if let result {
                Image(systemName: result.ok ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .font(.system(size: 44)).foregroundStyle(result.ok ? Color.sanOpen : .red)
                Text(result.title).font(.golos(18, .bold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                if let sub = result.subtitle {
                    Text(sub).font(.golos(14, .regular)).foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
                Button {
                    self.result = nil; lastCode = ""; manualCode = ""
                } label: { Text("Сканировать ещё") }
                .buttonStyle(SanPrimaryButton())
                .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: 340)
        .background(panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 28)
    }

    // MARK: Логика

    private func handle(_ code: String) {
        let code = code.trimmingCharacters(in: .whitespaces)
        guard !processing, result == nil, !code.isEmpty, code != lastCode else { return }
        guard !venueID.isEmpty else { result = .error("Выберите заведение"); return }
        lastCode = code
        processing = true
        let vID = venueID
        Task {
            let token = await authService.idToken() ?? ""
            let outcome: ScanResultUI
            do {
                let out = try await couponService.scanCoupon(code: code, venueID: vID, idToken: token)
                outcome = out.ok ? .success(out) : .error(Self.message(for: out.errorCode))
            } catch {
                outcome = .error("Ошибка сети. Попробуйте ещё раз.")
            }
            await MainActor.run {
                processing = false
                result = outcome
            }
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
        default:                 return "Не удалось отсканировать купон."
        }
    }
}

/// Модель результата для UI.
enum ScanResultUI {
    case success(ScanOutcome)
    case error(String)

    var ok: Bool { if case .success = self { return true }; return false }

    var title: String {
        switch self {
        case .success(let o): return o.title.isEmpty ? "Купон погашен ✓" : "«\(o.title)» ✓"
        case .error(let m): return m
        }
    }
    var subtitle: String? {
        switch self {
        case .success(let o):
            guard o.loyalty else { return "Купон погашен." }
            if o.rewardIssued { return "🎉 Карта заполнена! Сегодня награда: «\(o.rewardTitle)» — выдайте гостю." }
            return "Штамп начислен: \(o.stamps) из \(o.goal)."
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
