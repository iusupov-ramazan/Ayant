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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if fixedVenueID == nil, venues.count > 1 { venuePicker }
                scannerArea
                resultBar
            }
            .navigationTitle("Сканер купонов")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .onAppear {
                venueID = fixedVenueID ?? venues.first?.id ?? ""
            }
        }
    }

    // MARK: Выбор заведения

    private var venuePicker: some View {
        Picker("Заведение", selection: $venueID) {
            ForEach(venues) { Text($0.name).tag($0.id) }
        }
        .pickerStyle(.menu)
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    // MARK: Камера / ручной ввод

    @ViewBuilder
    private var scannerArea: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            ZStack {
                CodeScannerView(isPaused: processing || result != nil) { code in
                    handle(code)
                }
                .ignoresSafeArea(edges: .horizontal)
                VStack {
                    Spacer()
                    Text(currentVenue.map { "Заведение: \($0.name)" } ?? "Выберите заведение")
                        .font(.caption).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(.bottom, 16)
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            manualEntry
        }
    }

    private var manualEntry: some View {
        VStack(spacing: 14) {
            Image(systemName: "qrcode.viewfinder").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("Камера недоступна (симулятор). Введите код купона вручную.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            TextField("AYANT-XXXXXX", text: $manualCode)
                .textInputAutocapitalization(.characters)
                .multilineTextAlignment(.center)
                .font(.headline.monospaced())
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 40)
            Button("Проверить купон") {
                handle(manualCode.trimmingCharacters(in: .whitespaces).uppercased())
            }
            .disabled(manualCode.trimmingCharacters(in: .whitespaces).isEmpty || processing)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(Color.sanAccent, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(.white).padding(.horizontal, 40)
            Spacer()
        }
        .padding(.top, 40)
        .frame(maxHeight: .infinity)
    }

    // MARK: Результат

    @ViewBuilder
    private var resultBar: some View {
        if processing {
            HStack { ProgressView(); Text("Проверяем купон…").font(.subheadline) }
                .padding().frame(maxWidth: .infinity)
                .background(Color(.secondarySystemBackground))
        } else if let result {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: result.ok ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .font(.title2).foregroundStyle(result.ok ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.title).font(.subheadline.weight(.bold))
                        if let sub = result.subtitle {
                            Text(sub).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                Button("Сканировать ещё") {
                    self.result = nil
                    lastCode = ""
                    manualCode = ""
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(Color.sanAccent, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .padding(16)
            .background(Color(.systemBackground))
        }
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
