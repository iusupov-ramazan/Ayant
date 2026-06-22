import SwiftUI

/// 3-шаговый онбординг (по спецификации). Показывается один раз до ленты.
/// Выбор города обязателен — без него лента не работает.
struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var location: LocationManager
    var onFinished: () -> Void

    @State private var step = 0

    // Пока доступен только Бишкек — выбор города отключён (2 шага).
    private let stepCount = 2

    var body: some View {
        VStack(spacing: 0) {
            progressDots
            TabView(selection: $step) {
                locationStep.tag(0)
                notificationStep.tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: step)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            // Город зафиксирован на Бишкеке до запуска в других городах.
            store.selectedCitySlug = City.bishkek.id
        }
    }

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<stepCount, id: \.self) { i in
                Capsule()
                    .fill(i == step ? Color.sanAccent : Color(.systemGray4))
                    .frame(width: i == step ? 22 : 8, height: 8)
            }
        }
        .padding(.top, 16)
    }

    // MARK: Шаг 1 — Геолокация

    private var locationStep: some View {
        prePrompt(
            icon: "location.circle.fill",
            title: "Включи геолокацию",
            subtitle: "Разреши доступ к локации, чтобы видеть, как далеко заведения от тебя. Без неё всё работает — просто без расстояний.",
            primary: "Разрешить геолокацию",
            secondary: "Не сейчас"
        ) {
            location.request()
            withAnimation { step = 2 }
        } onSkip: {
            withAnimation { step = 2 }
        }
    }

    // MARK: Шаг 3 — Уведомления

    private var notificationStep: some View {
        prePrompt(
            icon: "bell.badge.fill",
            title: "Не пропусти новые акции",
            subtitle: "Уведомим, когда сохранённые заведения опубликуют новое предложение. Включить можно позже в настройках.",
            primary: "Включить уведомления",
            secondary: "Позже"
        ) {
            Task {
                await NotificationManager.requestAuthorization()
                onFinished()
            }
        } onSkip: {
            onFinished()
        }
    }

    // MARK: Переиспользуемый pre-prompt

    private func prePrompt(icon: String, title: String, subtitle: String,
                           primary: String, secondary: String,
                           onPrimary: @escaping () -> Void,
                           onSkip: @escaping () -> Void) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundStyle(Color.sanAccent)
            Text(title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 10) {
                Button(action: onPrimary) {
                    Text(primary).font(.headline)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.sanAccent)
                Button(action: onSkip) {
                    Text(secondary).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}
