import SwiftUI
import AyantDomain
import AyantFeatures

// Поверхности сканера (SCREENS.md H13–H15).
//
// Главный ход редизайна здесь: экран сканера — АКЦЕНТНЫЙ градиент, а не тёмный.
// Единственный тёмный элемент во всём хост-приложении — само окно камеры.

// MARK: - Акцентная поверхность

/// Фон сканера и экрана суммы: градиент 160°, белое радиальное свечение и
/// riso-штриховка поверх.
struct HostScanSurface: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.sanAccent, Color(hex: Palette.orange)],
                           startPoint: UnitPoint(x: 0.329, y: 0.030),
                           endPoint: UnitPoint(x: 0.671, y: 0.970))
            RadialGradient(colors: [.white.opacity(0.22), .clear],
                           center: UnitPoint(x: 0.5, y: 0.38),
                           startRadius: 0, endRadius: 320)
            SanRisoHatch(opacity: 0.10)
        }
        .ignoresSafeArea()
    }
}

/// Круглая полупрозрачная кнопка на акцентной поверхности.
struct HostScanIconButton: View {
    let systemName: String
    var label: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.24), in: Circle())
        }
        .buttonStyle(.sanPress(0.90))
        .accessibilityLabel(label)
    }
}

// MARK: - Окно камеры (H13)

/// Рамка сканера: тёмное окно + белые уголки + бегущий луч.
struct HostScanReticle<Camera: View>: View {
    @ViewBuilder var camera: Camera
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    private let side: CGFloat = 238

    var body: some View {
        ZStack {
            // Единственный тёмный элемент хост-приложения.
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color(hex: 0x241C16))
                .overlay {
                    camera.clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                }
                .overlay {
                    // Внутренняя тень — «глубина» окна.
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.black.opacity(0.55), lineWidth: 30)
                        .blur(radius: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                        .allowsHitTesting(false)
                }
                .shadow(color: Color(hex: 0x782D00).opacity(0.35), radius: 25, y: 20)

            CornerBrackets(len: 50)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .padding(10)

            if !reduceMotion {
                Rectangle()
                    .fill(Color.white)
                    .frame(height: 2)
                    .shadow(color: Color(hex: 0xFFD9A8).opacity(0.6), radius: 11)
                    .padding(.horizontal, 14)
                    .offset(y: sweep ? side / 2 - 20 : -side / 2 + 20)
            }
        }
        .frame(width: side, height: side)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: SanTiming.scannerSweep).repeatForever(autoreverses: true)) {
                sweep = true
            }
        }
        .onDisappear { withoutAnimation { sweep = false } }
    }
}

/// Чип типа кода. Показывает, что это заведение принимает, — сам тип определяет
/// префикс QR, поэтому чипы информационные, а не переключатели.
struct HostScanKindChip: View {
    let title: LocalizedStringKey
    let enabled: Bool

    var body: some View {
        Text(title)
            .font(.golos(13, .bold))
            .foregroundStyle(enabled ? Color.sanAccentDeep : Color.white)
            .padding(.horizontal, 15).padding(.vertical, 9)
            .background(enabled ? AnyShapeStyle(Color.white)
                                : AnyShapeStyle(Color.white.opacity(0.24)),
                        in: Capsule())
    }
}

// MARK: - Клавиатура суммы (H14)

/// 3×4 цифровая клавиатура. Сумма ограничена 7 цифрами.
struct HostAmountKeypad: View {
    @Binding var text: String
    static let maxDigits = 7

    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["00", "0", "⌫"],
    ]

    var body: some View {
        VStack(spacing: 9) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 9) {
                    ForEach(row, id: \.self) { key in
                        Button { press(key) } label: {
                            Group {
                                if key == "⌫" {
                                    Image(systemName: "delete.left")
                                        .font(.system(size: 21, weight: .semibold))
                                } else {
                                    Text(key).font(.golos(22, .semibold))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(.white.opacity(0.2),
                                        in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        }
                        .buttonStyle(.sanPress(0.93))
                    }
                }
            }
        }
    }

    private func press(_ key: String) {
        SanHaptics.selection()
        switch key {
        case "⌫":
            if !text.isEmpty { text.removeLast() }
        default:
            let next = text + key
            // Ведущие нули не копим и длину ограничиваем.
            let trimmed = String(next.drop { $0 == "0" && next.count > 1 })
            guard trimmed.count <= Self.maxDigits else { return }
            text = trimmed.isEmpty ? "" : trimmed
        }
    }
}

// MARK: - Начислено (H15)

/// Экран-квитанция после начисления. Хост работает, а не празднует, — конфетти
/// здесь нет, только кольца и галочка.
struct HostScanReceiptView: View {
    let awarded: Int
    let balance: Int
    let guestLabel: String
    /// Сумма чека — только если её вводили (cashback/bands).
    let billAmount: Int?
    /// Подпись режима начисления («Кэшбэк 5%» и т. п.), если есть.
    let modeLabel: String?
    /// `true` — сервер вернул повторный ответ по тому же ключу.
    let replayed: Bool
    var onScanMore: () -> Void
    var onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ringsRunning = false
    @State private var discShown = false
    @State private var shownAwarded = 0

    var body: some View {
        ZStack {
            Color.sanCanvas.ignoresSafeArea()
            VStack(spacing: 0) {
                burst
                Text("+\(shownAwarded)")
                    .sanText(58, .heavy, tracking: -3, lineHeight: 1)
                    .foregroundStyle(LinearGradient.sanAccentGradient)
                    .contentTransition(.numericText())
                    .padding(.top, 24)

                Text("Баллы начислены")
                    .sanText(22, .heavy, tracking: -0.9)
                    .foregroundStyle(Color.sanInk)
                    .padding(.top, 10)

                if replayed {
                    // Повтор по тому же ключу: баллы НЕ начислены второй раз.
                    Text("Повторный ответ — баллы уже были начислены.")
                        .font(.golos(12.5, .semibold))
                        .foregroundStyle(Color.sanInkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }

                receipt.padding(.top, 24)

                Button("Сканировать ещё", action: onScanMore)
                    .buttonStyle(SanPrimaryButton())
                    .frame(maxWidth: 300)
                    .padding(.top, 24)

                Button("Готово", action: onDone)
                    .font(.golos(15, .semibold))
                    .foregroundStyle(Color.sanInkSoft)
                    .padding(.top, 14)
            }
            .padding(30)
        }
        .onAppear(perform: start)
        .onDisappear { withoutAnimation { ringsRunning = false } }
    }

    private var burst: some View {
        ZStack {
            if !reduceMotion {
                ring(color: .sanAccent, delay: 0)
                ring(color: Color(hex: Palette.orange), delay: 0.6)
            }
            Circle()
                .fill(LinearGradient.sanAccentGradient)
                .frame(width: 100, height: 100)
                .overlay(Image(systemName: "checkmark")
                    .font(.system(size: 44, weight: .heavy)).foregroundStyle(.white))
                .shadow(color: Color.sanAccent.opacity(0.4), radius: 20, y: 18)
                .scaleEffect(discShown ? 1 : 0.6)
                .opacity(discShown ? 1 : 0)
        }
        .frame(width: 116, height: 116)
    }

    private func ring(color: Color, delay: Double) -> some View {
        Circle()
            .strokeBorder(color, lineWidth: 2)
            .frame(width: 116, height: 116)
            .scaleEffect(ringsRunning ? 2.6 : 0.35)
            .opacity(ringsRunning ? 0 : 0.55)
            .animation(.easeOut(duration: 1.9).repeatForever(autoreverses: false).delay(delay),
                       value: ringsRunning)
    }

    private var receipt: some View {
        VStack(spacing: 0) {
            receiptRow("Гость", guestLabel)
            if let billAmount {
                SanHairline()
                receiptRow("Сумма чека", "\(billAmount.sanThousands) сом")
            }
            if let modeLabel {
                SanHairline()
                receiptRow("Начисление", modeLabel)
            }
            SanHairline()
            receiptRow("Новый баланс гостя", "\(balance)", accent: true)
        }
        .padding(.horizontal, 18).padding(.vertical, 4)
        .frame(maxWidth: 300)
        .background(Color.sanSurface,
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.sanHairline, lineWidth: 0.5))
        .sanShadow(.elevated)
    }

    private func receiptRow(_ title: LocalizedStringKey, _ value: String,
                            accent: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.golos(13.5)).foregroundStyle(Color.sanInkSoft)
            Spacer(minLength: 8)
            Text(value)
                .font(.golos(14.5, .bold))
                .foregroundStyle(accent ? Color.sanAccentText : Color.sanInk)
                .lineLimit(1)
        }
        .padding(.vertical, 13)
    }

    private func start() {
        SanHaptics.success()
        guard !reduceMotion else { discShown = true; shownAwarded = awarded; return }
        withAnimation(.sanPop) { discShown = true }
        ringsRunning = true
        // Счётчик идёт К значению, которое вернул сервер.
        withAnimation(.sanCounter) { shownAwarded = awarded }
    }
}
