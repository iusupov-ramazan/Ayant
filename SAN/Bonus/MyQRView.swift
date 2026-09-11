import SwiftUI
import AyantDomain
import AyantFeatures

/// «Ваш QR» — экран центральной кнопки таб-бара.
///
/// Показывает личный код `AYANT-PTS:<userID>`: сотрудник заведения сканирует его,
/// и Cloud Function `scanCoupon` (ветка C) начисляет баллы. Клиент здесь ничего
/// не считает и не пишет — только рисует код.
struct MyQRView: View {
    @EnvironmentObject private var points: PointsStore
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var location: LocationManager
    @Environment(\.dismiss) private var dismiss
    /// `false`, когда экран показан вкладкой, а не листом.
    var showsDone = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sweep = false
    @State private var shimmer = false
    private var userID: String { points.state.userID }
    private var earnCode: String { "AYANT-PTS:\(userID)" }

    /// Сумма балансов по всем картам. Баллы живут по заведениям — это просто
    /// «сколько у вас всего», разбивка ниже в ленте карточек.
    private var totalBalance: Int {
        (points.state.cards.value ?? []).reduce(0) { $0 + $1.balance }
    }

    /// Заведения с включёнными баллами, ближайшие сверху.
    private var nearby: [Venue] {
        store.venues
            .filter(\.pointsActive)
            .sorted { a, b in
                let da = location.distanceKm(to: a.latitude, a.longitude) ?? .greatestFiniteMagnitude
                let db = location.distanceKm(to: b.latitude, b.longitude) ?? .greatestFiniteMagnitude
                return da < db
            }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Ваш QR").sanEditorialTitle(40)
                        .foregroundStyle(Color.sanInk)

                    Text("Покажите код на кассе — баллы прилетят на карту заведения.")
                        .sanText(14, .regular, lineHeight: 1.45)
                        .foregroundStyle(Color.sanInkSoft)
                        .frame(maxWidth: 280, alignment: .leading)
                        .padding(.top, 9)

                    if userID.isEmpty {
                        signInPrompt.padding(.top, 22)
                    } else {
                        qrCard.padding(.top, 22)
                    }

                    if !nearby.isEmpty {
                        // Капслок — через `textCase`, а не `.uppercased()`:
                        // иначе ключ каталога не совпадёт и перевод отвалится.
                        Text("Рядом с вами")
                            .textCase(.uppercase)
                            .sanEyebrowText()
                            .foregroundStyle(Color.sanInkSoft)
                            .padding(.top, 22)
                        nearbyRail.padding(.top, 12)
                    }
                }
                .padding(.horizontal, SanMetrics.screenPadding)
                .padding(.top, 14)
                .padding(.bottom, 26)
                .sanScreenEnter()
            }
            .sanScreenBackground()
            .navigationTitle("")
            .toolbar {
                // Кнопки закрытия нет, когда экран открыт вкладкой: закрывать
                // нечего, а «Готово» в таб-баре читается как ошибка.
                if showsDone {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Готово") { dismiss() }
                            .font(.golos(16, .semibold))
                    }
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: SanTiming.qrSweep).repeatForever(autoreverses: false)) {
                sweep = true
            }
            withAnimation(.easeInOut(duration: SanTiming.shimmer).repeatForever(autoreverses: false)) {
                shimmer = true
            }
        }
        // Бесконечные анимации не крутятся за закрытым экраном (ANIMATIONS.md §17).
        .onDisappear { withoutAnimation { sweep = false; shimmer = false } }
        // Начисление замечает `PointsStore` (рост баланса в живом потоке), а
        // экран «Начислено» показывает корень приложения — над любой вкладкой
        // и только до тапа гостя. Здесь ничего ловить не нужно.
    }

    // MARK: Карточка с кодом

    private var qrCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.currentUserName)
                        .font(.golos(14.5, .bold)).foregroundStyle(Color.sanInk)
                    Text(L(store.selectedCity.name))
                        .font(.golos(12, .regular)).foregroundStyle(Color.sanInkSoft)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Всего баллов")
                        .font(.golos(11, .semibold)).foregroundStyle(Color.sanInkSoft)
                    Text("\(totalBalance)")
                        .font(.golos(20, .heavy))
                        // Мелкая акцентная цифра на белом — `sanAccentTextStrong`.
                        .foregroundStyle(Color.sanAccentTextStrong)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: totalBalance)
                }
            }

            ZStack {
                QRCodeView(text: earnCode, size: 196)
                // Луч сканирования: бежит сверху вниз по коду.
                if !reduceMotion {
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, .sanAccent, .clear],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: 3)
                        .offset(y: sweep ? 100 : -100)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: 212, height: 212)
            .clipped()
            .padding(.top, 20)

            Text("Покажите сотруднику — он начислит баллы")
                .font(.golos(13.5, .semibold))
                .foregroundStyle(Color.sanInkSoft)
                .multilineTextAlignment(.center)
                .padding(.top, 18)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.sanSurface,
                    in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        // Диагональный блик, пересекающий карточку (ANIMATIONS.md §8) — это
        // «блеск», а не индикатор загрузки: 16% янтаря и ничего больше.
        .overlay {
            if !reduceMotion {
                GeometryReader { geo in
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.clear, Color(hex: Palette.orange).opacity(0.16), .clear],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: 70)
                        .rotationEffect(.degrees(18))
                        .offset(x: shimmer ? geo.size.width + 90 : -90)
                }
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .allowsHitTesting(false)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous)
            .strokeBorder(Color.sanHairline, lineWidth: 0.5))
        .sanShadow(.qrCard)
    }

    private var signInPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.sanInkSoft)
            Text("Войдите в аккаунт, чтобы копить баллы")
                .font(.golos(15, .semibold)).foregroundStyle(Color.sanInk)
            Text("Гостям код не выдаётся — начисление привязано к вашему профилю.")
                .font(.golos(13, .regular)).foregroundStyle(Color.sanInkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .sanCard(padding: 0, radius: 32)
    }

    // MARK: Лента ближайших

    private var nearbyRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(nearby) { venue in
                    VStack(alignment: .leading, spacing: 0) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: venue.gradientColors,
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 36, height: 36)
                        Text(venue.name)
                            .font(.golos(13.5, .bold)).foregroundStyle(Color.sanInk)
                            .lineLimit(2).multilineTextAlignment(.leading)
                            .padding(.top, 10)
                        Text("\(points.state.balance(for: venue.id)) баллов")
                            .font(.golos(12, .regular)).foregroundStyle(Color.sanInkSoft)
                            .padding(.top, 3)
                    }
                    .frame(width: 132, alignment: .leading)
                    .padding(13)
                    .background(Color.sanSurface,
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.sanHairline, lineWidth: 0.5))
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollClipDisabled()
    }
}
