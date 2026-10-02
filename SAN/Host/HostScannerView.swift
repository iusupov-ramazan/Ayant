import SwiftUI
import VisionKit
import AVFoundation
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
    /// Доступ к камере. Без него окно сканера было бы просто чёрным квадратом —
    /// сотрудник не понял бы, почему ничего не сканируется.
    @State private var cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
    /// Повтор ПОСЛЕДНЕГО запроса после сетевой ошибки — с тем же `scanKey`:
    /// сервер вернёт первый результат, а не начислит второй раз. `resetScan()`
    /// здесь не вызывается намеренно — он минтит новый ключ.
    @State private var retryAction: (() -> Void)?
    /// Распознанная карта лояльности ждёт выбора: у заведения несколько карт
    /// штампов («Кофе», «Пицца»), и какую засчитать, знает только сотрудник.
    @State private var pendingCardPick: String?

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
                } else if let code = pendingCardPick, let venue = currentVenue {
                    Color.black.opacity(0.35).ignoresSafeArea()
                        .onTapGesture { resetScan() }
                    cardPicker(code: code, cards: venue.stampCards)
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
            // Свежие настройки лояльности перед сканами: режим баллов, карты
            // штампов и их вкл/выкл правятся и из админ-панели, а маршрут скана
            // (экран суммы, выбор карты) строится по кэшу кабинета. Один синк
            // на открытие сканера — дёшево, а устаревший кэш иначе вёл бы к
            // лишнему вводу суммы или отказу сервера.
            .task { await host.sync() }
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
                Text("Сканер QR гостя")
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
                    switch cameraAuth {
                    case .authorized:
                        CodeScannerView(isPaused: processing || result != nil || pendingEarn != nil || pendingCardPick != nil) {
                            handle($0)
                        }
                    case .denied, .restricted:
                        cameraDenied
                    case .notDetermined:
                        // Спрашиваем сразу, как только окно на экране.
                        Color.clear.task { await requestCamera() }
                    @unknown default:
                        cameraDenied
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

    /// Доступ к камере запрещён: объясняем и ведём в Настройки. Ручной ввод
    /// кода ниже продолжает работать.
    private var cameraDenied: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text("Нет доступа к камере")
                .font(.golos(15, .bold)).foregroundStyle(.white)
            Text("Разрешите доступ в Настройках, чтобы сканировать QR гостей.")
                .font(.golos(12.5)).foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Открыть настройки")
                    .font(.golos(13.5, .bold)).foregroundStyle(Color.sanAccentDeep)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(.sanPress(0.95))
        }
        .padding(20)
    }

    @MainActor private func requestCamera() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraAuth = granted ? .authorized : AVCaptureDevice.authorizationStatus(for: .video)
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
                Text(currentVenue?.name ?? LS("Выберите заведение"))
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
                .textInputAutocapitalization(.never)   // uid в QR гостя чувствителен к регистру; код купона поднимет normalizedManualCode
                .autocorrectionDisabled()
                .multilineTextAlignment(.center)
                .font(.golos(15, .semibold))
                .tracking(3)
                .foregroundStyle(.white)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Button {
                handle(Self.normalizedManualCode(manualCode))
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
                    // Сумма и клавиатура прокручиваются, кнопка закреплена снизу:
                    // на маленьком экране с крупным шрифтом она уходила за край,
                    // и начислить было нечем.
                    GeometryReader { geo in
                        ScrollView {
                            VStack(spacing: 0) {
                                Spacer(minLength: 8)
                                VStack(spacing: 6) {
                                    Text(amount > 0 ? amount.sanThousands : "0")
                                        .sanText(64, .heavy, tracking: -3.2, lineHeight: 1)
                                        .foregroundStyle(.white)
                                        .contentTransition(.numericText())
                                        .animation(.snappy, value: amount)
                                        .lineLimit(1).minimumScaleFactor(0.5)
                                    Text("сом").font(.golos(14)).foregroundStyle(.white.opacity(0.8))
                                }
                                earnPreview(preview).padding(.top, 16)
                                Spacer(minLength: 12)
                                HostAmountKeypad(text: $billText).padding(.horizontal, 20)
                            }
                            .frame(minHeight: geo.size.height)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
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
                                Text("Диапазоны не настроены — задайте их во вкладке «Лояльность».")
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
                // «QR распознан» уже написано на бейдже справа — не повторяем.
                if !pending.userID.isEmpty {
                    Text("ID \(pending.userID.prefix(8))")
                        .font(.golos(11.5)).foregroundStyle(.white.opacity(0.8))
                }
            }
            Spacer(minLength: 8)
            // Сервер код ещё не проверял — распознан, а не «верный».
            Text("QR распознан")
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
                Image(systemName: result.isWarning ? "exclamationmark.triangle.fill"
                                      : result.ok ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(result.isWarning ? Color(hex: 0xE0A100)
                                     : result.ok ? Color.sanOpen : Color(hex: 0xE8556B))
                Text(result.title).font(.golos(18, .bold)).foregroundStyle(Color.sanInk)
                    .multilineTextAlignment(.center)
                if let sub = result.subtitle {
                    Text(sub).font(.golos(14)).foregroundStyle(Color.sanInkSoft)
                        .multilineTextAlignment(.center)
                }
                if let retryAction {
                    // Сетевая ошибка: повторяем с тем же ключом идемпотентности.
                    Button { retryAction() } label: { Text("Повторить") }
                        .buttonStyle(SanPrimaryButton())
                        .padding(.top, 4)
                    Button { resetScan() } label: { Text("Сканировать ещё") }
                        .buttonStyle(SanPillButton())
                } else {
                    Button { resetScan() } label: { Text("Сканировать ещё") }
                        .buttonStyle(SanPrimaryButton())
                        .padding(.top, 4)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 340)
        .background(Color.sanSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 28)
    }

    private func resetScan() {
        result = nil
        retryAction = nil
        lastCode = ""
        manualCode = ""
        scanKey = ""
        pendingCardPick = nil
    }

    // MARK: Логика

    private func handle(_ raw: String) {
        let raw = raw.trimmingCharacters(in: .whitespaces)
        guard !processing, result == nil, pendingEarn == nil, pendingCardPick == nil,
              !raw.isEmpty, raw != lastCode else { return }
        guard !venueID.isEmpty else { result = .error(LS("Выберите заведение")); return }

        // Ключ на распознанный QR — один, и он переживёт переход на экран суммы
        // и повторные тапы по кнопке начисления.
        lastCode = raw
        scanKey = UUID().uuidString

        // Один QR гостя: «Мой QR» у заведения со штампами — это штамп, QR карты
        // у заведения с баллами — баллы. Так же решает сервер; здесь — чтобы
        // сразу показать нужный экран (сумма чека или выбор карты).
        let code = GuestQR.route(raw, venueID: venueID,
                                 pointsEnabled: currentVenue?.pointsEnabled ?? false,
                                 loyaltyEnabled: currentVenue?.loyaltyEnabled ?? false)

        if code.hasPrefix("AYANT-PTS:") {
            // `pointsMode` значим только при включённых баллах: у заведения,
            // которое их выключило, в документе остаётся старый режим, и сканер
            // просил бы сумму чека за начисление, которое сервер всё равно
            // отклонит (`points_off`). Тогда код уходит на сервер как есть —
            // ответ скажет, что включить.
            let pointsOn = currentVenue?.pointsEnabled == true
            let mode = pointsOn ? (currentVenue?.pointsMode ?? "flat") : "flat"
            if mode == "cashback" || mode == "bands" {
                let userID = code.split(separator: ":").dropFirst().first.map(String.init) ?? ""
                pendingEarn = PendingEarn(code: code, mode: mode, userID: userID)
                return
            }
            submitScan(code: code, billAmount: nil, bandIndex: nil, billForReceipt: nil)
            return
        }
        if code.hasPrefix(RedeemQR.prefix) || code.hasPrefix(RedeemQR.tokenPrefix) {
            submitRedeem(code: code)
            return
        }
        // Несколько карт штампов — сначала выбор. С одной картой выбирать
        // нечего: штамп уходит сразу, как раньше.
        if code.hasPrefix("AYANT-CARD:"), let cards = currentVenue?.stampCards, cards.count > 1 {
            SanHaptics.selection()
            pendingCardPick = code
            return
        }
        submitScan(code: code, billAmount: nil, bandIndex: nil, billForReceipt: nil)
    }

    /// Выбор карты штампов после скана.
    private func cardPicker(code: String, cards: [StampCard]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Какой карте штамп?")
                .font(.golos(18, .bold)).foregroundStyle(Color.sanInk)
            Text("У заведения несколько карт — выберите, за что гость платит сейчас.")
                .font(.golos(13)).foregroundStyle(Color.sanInkSoft)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(cards) { card in
                Button {
                    // Ключ — на пару «QR + карта»: повтор того же выбора после
                    // сбоя сети пойдёт с тем же ключом (`retryAction`), а штамп
                    // на другую карту — законный отдельный скан, со своим.
                    scanKey = UUID().uuidString
                    pendingCardPick = nil
                    submitScan(code: code, billAmount: nil, bandIndex: nil,
                               billForReceipt: nil, cardID: card.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "seal.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.sanAccentText)
                            .frame(width: 38, height: 38)
                            .background(Color.sanAccent.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.title.isEmpty ? LS("Карта лояльности") : card.title)
                                .font(.golos(15.5, .bold)).foregroundStyle(Color.sanInk)
                            Text("\(card.goal) визитов → «\(card.reward)»")
                                .font(.golos(12.5)).foregroundStyle(Color.sanInkSoft)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x9A9188))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.sanSurfaceMuted, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.sanPress(0.97))
            }
            Button { resetScan() } label: { Text("Отмена") }
                .buttonStyle(SanPillButton())
                .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: 360)
        .background(Color.sanSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 24)
    }

    /// Начисление баллов / штамп / погашение купона через scanCoupon.
    private func submitScan(code: String, billAmount: Int?, bandIndex: Int?, billForReceipt: Int?,
                            cardID: String? = nil) {
        processing = true
        result = nil
        retryAction = nil
        let key = scanKey.isEmpty ? UUID().uuidString : scanKey
        let vID = venueID
        let modeLabel = currentVenue.flatMap(Self.modeLabel)
        Task {
            let token = await authService.idToken() ?? ""
            do {
                let out = try await couponService.scanCoupon(code: code, venueID: vID, idToken: token,
                                                             billAmount: billAmount, bandIndex: bandIndex,
                                                             idempotencyKey: key, cardID: cardID)
                await MainActor.run {
                    processing = false
                    if out.ok && out.points {
                        // Баллы → полноэкранная квитанция (H15).
                        receipt = EarnReceipt(awarded: out.awarded, balance: out.balance,
                                              guestLabel: LS("Гость"),
                                              billAmount: billForReceipt,
                                              modeLabel: modeLabel,
                                              replayed: out.replayed)
                        host.send(.noteScanSucceeded)
                    } else {
                        result = out.ok ? .success(out)
                            : .error(Self.message(for: out.errorCode, retryAfterSec: out.retryAfterSec))
                        if out.ok { host.send(.noteScanSucceeded) }
                        // Отказ из-за устаревших настроек в кэше — подтягиваем
                        // свежие, чтобы следующий скан пошёл верным путём.
                        if !out.ok, Self.isStaleConfig(out.errorCode) { host.send(.sync) }
                    }
                }
            } catch {
                await MainActor.run {
                    processing = false
                    result = .error(LS("Ошибка сети. Попробуйте ещё раз."))
                    retryAction = {
                        submitScan(code: code, billAmount: billAmount, bandIndex: bandIndex,
                                   billForReceipt: billForReceipt, cardID: cardID)
                    }
                }
            }
        }
    }

    /// Списание баллов на награду. Новый QR — `AYANT-RDT:<token>` (только
    /// одноразовый токен), старый — `AYANT-RDM:userID:rewardId[:points[:nonce]]`.
    /// Оба разбирает `RedeemQR` (домен), здесь своего парсера нет.
    private func submitRedeem(code: String) {
        guard let scanned = RedeemQR.scan(code) else { result = .error(LS("Неверный код награды.")); return }
        if case .token(let redeemToken) = scanned {
            submitTokenRedeem(code: code, token: redeemToken)
            return
        }
        guard let qr = RedeemQR.parse(code) else { result = .error(LS("Неверный код награды.")); return }
        let userID = qr.userID, rewardId = qr.rewardID
        let pts = qr.points    // для money-награды; у item-награды 0
        processing = true
        result = nil
        retryAction = nil
        let vID = venueID
        let key = scanKey.isEmpty ? UUID().uuidString : scanKey
        Task {
            let token = await authService.idToken() ?? ""
            let outcome: ScanResultUI
            var networkFailed = false
            do {
                // Ключ идемпотентности: `nonce` из QR гостя — сервер делает
                // из него `rdm_<nonce>`, и ПОВТОРНЫЙ скан того же QR (второй
                // сотрудник, второй тап, скриншот) воспроизводит первое
                // списание, а не списывает ещё раз. Ключ на скан (`key`) —
                // запасной для старых QR без nonce: он спасает только от
                // ретрая после таймаута.
                let out = try await couponService.redeemVenuePoints(venueID: vID, userID: userID,
                                                                    rewardId: rewardId, pointsToSpend: pts,
                                                                    idToken: token,
                                                                    idempotencyKey: key,
                                                                    nonce: qr.nonce)
                outcome = out.ok ? .redeemed(out) : .error(Self.message(for: out.errorCode))
                if out.ok { host.send(.noteScanSucceeded) }
            } catch {
                outcome = .error(LS("Ошибка сети. Попробуйте ещё раз."))
                networkFailed = true
            }
            await MainActor.run {
                processing = false
                result = outcome
                if networkFailed { retryAction = { submitRedeem(code: code) } }
            }
        }
    }

    /// Списание по токену: чья карта и какая награда — знает только сервер.
    /// Повтор (сеть, второй сотрудник, тот же QR) сервер воспроизводит по
    /// `rdm_<token>` — ответ придёт с `replayed`, баллы дважды не спишутся.
    private func submitTokenRedeem(code: String, token redeemToken: String) {
        processing = true
        result = nil
        retryAction = nil
        let vID = venueID
        Task {
            let idToken = await authService.idToken() ?? ""
            let outcome: ScanResultUI
            var networkFailed = false
            do {
                let out = try await couponService.redeemVenuePoints(venueID: vID, token: redeemToken, idToken: idToken)
                outcome = out.ok ? .redeemed(out) : .error(Self.message(for: out.errorCode))
                if out.ok { host.send(.noteScanSucceeded) }
            } catch {
                outcome = .error(LS("Ошибка сети. Попробуйте ещё раз."))
                networkFailed = true
            }
            await MainActor.run {
                processing = false
                result = outcome
                if networkFailed { retryAction = { submitRedeem(code: code) } }
            }
        }
    }

    /// «Кэшбэк 5%» / «30 за визит» — для строки квитанции.
    private static func modeLabel(_ v: HostVenueDTO) -> String? {
        switch v.pointsMode {
        case "cashback":
            guard v.cashbackPercent > 0 else { return nil }
            return LF("Кэшбэк %@%%", v.cashbackPercent.sanPercentText)
        case "bands": return LS("По сумме чека")
        default:
            guard v.pointsFlat > 0 else { return nil }
            return LF("%lld за визит", v.pointsFlat)
        }
    }

    // Тексты — через `LS`, а не литералами: функция возвращает `String`, и
    // `Text(String)` каталог не смотрит. Ключи добавлены в каталог руками.
    /// Отказ сервера человеческим языком. Для `cooldown` — сколько ждать:
    /// сервер присылает `retryAfterSec`, и «попробуйте позже» без срока
    /// заставляло сотрудника сканировать наугад.
    private static func message(for code: String?, retryAfterSec: Int?) -> String {
        if code == "cooldown", let sec = retryAfterSec, sec > 0 {
            let minutes = max(1, Int((Double(sec) / 60).rounded(.up)))
            return LF("Этому гостю уже начисляли недавно. Следующее начисление — через %lld мин.", minutes)
        }
        return message(for: code)
    }

    private static func message(for code: String?) -> String {
        switch code {
        case "coupon_not_found": return LS("Купон не найден.")
        case "wrong_venue":      return LS("Этот код — для другого заведения.")
        case "loyalty_off":      return LS("Карта штампов выключена — включите её во вкладке «Лояльность».")
        case "card_not_found":   return LS("Эта карта штампов выключена или удалена. Настройки обновлены — отсканируйте QR гостя ещё раз.")
        case "loyalty_is_points": return LS("Настройки лояльности изменились — мы их обновили. Отсканируйте QR гостя ещё раз.")
        case "already_used":     return LS("Купон уже был использован.")
        case "coupon_expired":   return LS("Срок купона истёк — погасить его нельзя.")
        case "not_owner":        return LS("У вас нет прав на это заведение.")
        case "venue_not_found":  return LS("Заведение не найдено.")
        case "no_token", "bad_token": return LS("Требуется вход в аккаунт заведения.")
        case "missing_params":   return LS("Пустой код купона.")
        // Баллы САН
        // Тот же код приходит на «Мой QR» у заведения без лояльности вовсе.
        case "points_off":       return LS("У заведения не включены ни баллы, ни карта штампов. Включите их во вкладке «Лояльность».")
        // Один код и для штампов, и для баллов — формулировка общая. Если
        // сервер прислал `retryAfterSec`, срок добавляет перегрузка выше.
        case "cooldown":         return LS("Этому гостю уже начисляли недавно, попробуйте позже.")
        // Сканер не спросил сумму/диапазон, а сервер их ждёт (или диапазонов
        // теперь меньше) — значит, кэш настроек устарел; его подтягивает
        // `isStaleConfig`, и повторный скан пойдёт верным путём.
        case "missing_amount", "bad_band":
            return LS("Настройки лояльности изменились — мы их обновили. Отсканируйте QR гостя ещё раз.")
        case "no_points":        return LS("Начислять нечего (0 баллов).")
        case "bad_code":         return LS("Неверный QR-код.")
        case "insufficient":     return LS("У гостя недостаточно баллов.")
        case "reward_not_found": return LS("Награда не найдена или отключена.")
        case "redeem_not_allowed": return LS("Списание баллов недоступно для этого заведения.")
        case "below_min":        return LS("Слишком мало баллов для этой награды.")
        case "missing_user":     return LS("Не удалось определить гостя.")
        case "key_reused":       return LS("Этот код уже обрабатывался с другим запросом. Отсканируйте QR заново.")
        case "bad_reward":       return LS("Награда указана неверно. Попросите гостя обновить QR.")
        // Токен списания (QR AYANT-RDT)
        case "token_not_found":  return LS("QR не найден. Попросите гостя открыть награду заново.")
        case "token_expired":    return LS("QR устарел. Попросите гостя открыть награду заново — код обновится.")
        case "token_used":       return LS("Этот QR уже погашен.")
        case "token_required":   return LS("Старый QR больше не принимается. Попросите гостя обновить приложение.")
        case "internal":         return LS("Ошибка на сервере. Попробуйте ещё раз через минуту.")
        case "app_check_failed": return LS("Приложение не прошло проверку. Обновите его из App Store.")
        default:                 return LS("Не удалось отсканировать код.")
        }
    }

    /// Отказы, которые означают «кэш настроек заведения устарел»: после них
    /// сканер подтягивает свежие настройки (`host.send(.sync)`).
    static func isStaleConfig(_ code: String?) -> Bool {
        ["loyalty_is_points", "card_not_found", "missing_amount", "bad_band"].contains(code ?? "")
    }

    /// Ручной ввод. Код купона (`AYANT-XXXXXX`) регистронезависим — его
    /// приводим к верхнему регистру, чтобы набрать с телефона было проще. А в
    /// QR гостя (`AYANT-PTS:` / `AYANT-CARD:` / `AYANT-RDM:`) стоят uid и nonce,
    /// где регистр значим: прежний `uppercased()` портил их, и сервер не
    /// находил гостя.
    static func normalizedManualCode(_ raw: String) -> String {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = code.firstIndex(of: ":") else { return code.uppercased() }
        return code[..<colon].uppercased() + code[colon...]
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

    /// Повторный скан уже погашенного QR награды (тот же nonce → сервер
    /// воспроизвёл прежнее списание). Баллы второй раз не списаны, но
    /// «Награда выдана ✓» здесь — приглашение выдать её ещё раз по
    /// скриншоту. Поэтому — предупреждение, а не успех.
    var isWarning: Bool {
        if case .redeemed(let r) = self { return r.replayed }
        return false
    }

    var title: String {
        switch self {
        case .success(let o):
            if o.points { return o.awarded > 0 ? LF("+%lld баллов ✓", o.awarded) : LS("Готово ✓") }
            // Штамп: крупно — что начислено ЗА ЭТОТ скан. Прежний заголовок
            // с итогом («2 из 6») после первого скана читался как двойной штамп.
            if o.loyalty && !o.rewardIssued {
                return o.cardTitle.isEmpty ? LS("+1 штамп ✓") : LF("+1 штамп · %@ ✓", o.cardTitle)
            }
            return o.title.isEmpty ? LS("Купон погашен ✓") : "«\(o.title)» ✓"
        case .redeemed(let r):
            if r.replayed { return LS("Эта награда уже выдана") }
            return r.rewardTitle.isEmpty ? LS("Награда выдана ✓") : "«\(r.rewardTitle)» ✓"
        case .error(let m): return m
        }
    }
    var subtitle: String? {
        switch self {
        case .success(let o):
            if o.points { return LF("Начислено %lld. Баланс гостя: %lld баллов.", o.awarded, o.balance) }
            // Купон: заголовок уже сказал «погашен» — здесь то, что делать
            // сотруднику. Повтор того же скана (сеть) списанием не был.
            guard o.loyalty else {
                return o.replayed ? LS("Этот скан уже был засчитан — повторно купон не погашен.")
                                  : LS("Выдайте гостю то, что указано в купоне.")
            }
            if o.rewardIssued { return LF("🎉 Карта заполнена! Гостю выдан купон «%@» — он уже в «Мои купоны»; погасить можно сразу или в следующий визит.", o.rewardTitle) }
            // Итог — второй строкой: «2 из 6» — это всего на карте, не за скан.
            let total = LF("Всего на карте: %lld из %lld.", o.stamps, o.goal)
            return o.title.isEmpty ? total : LF("Купон «%@» погашен. %@", o.title, total)
        case .redeemed(let r):
            if r.replayed { return Self.replayedRedeemSubtitle(r) }
            if let som = r.somOff { return LF("Списано %lld баллов (−%lld сом). Остаток: %lld.", r.redeemed, som, r.balance) }
            return LF("Списано %lld баллов. Остаток: %lld. Выдайте награду гостю.", r.redeemed, r.balance)
        case .error: return nil
        }
    }

    /// «Списано 14:05 · чек K7Q2M9. Не выдавайте награду повторно.» —
    /// время и код чека из ПЕРВОГО списания, которое сервер воспроизвёл:
    /// по ним сотрудник сверится с тем, кто выдал награду.
    static func replayedRedeemSubtitle(_ r: RedeemOutcome) -> String {
        var parts: [String] = []
        if !r.rewardTitle.isEmpty { parts.append("«\(r.rewardTitle)»") }
        let when = r.redeemedAt.map {
            $0.formatted(Date.FormatStyle(locale: AppLanguage.locale).day().month(.abbreviated).hour().minute())
        }
        switch (when, r.receiptCode.isEmpty ? nil : r.receiptCode) {
        case let (w?, code?): parts.append(LF("Списано %@ · чек %@", w, code))
        case let (w?, nil):   parts.append(LF("Списано %@", w))
        case let (nil, code?): parts.append(LF("Чек %@", code))
        case (nil, nil): break
        }
        parts.append(LS("Не выдавайте награду повторно."))
        return parts.joined(separator: "\n")
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
