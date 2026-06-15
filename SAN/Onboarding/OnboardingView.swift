import SwiftUI

/// 3-шаговый онбординг (по спецификации). Показывается один раз до ленты.
/// Выбор города обязателен — без него лента не работает.
struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var location: LocationManager
    var onFinished: () -> Void

    @State private var step = 0
    @State private var citySearch = ""
    @State private var chosenCity: String?

    // Пока доступен только Бишкек — выбор города отключён.
    private let stepCount = 2

    var body: some View {
        VStack(spacing: 0) {
            progressDots
            TabView(selection: $step) {
                // cityStep.tag(0)   // ⛔️ выбор города отключён — только Бишкек
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

    // MARK: Шаг 1 — Город (обязательно)

    private var cityStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 44)).foregroundStyle(Color.sanAccent)
                Text("Выбери свой город")
                    .font(.title2.weight(.bold))
                Text("Покажем заведения и акции рядом с тобой.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)

            List {
                ForEach(filteredCities) { city in
                    Button {
                        chosenCity = city.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(city.name).foregroundStyle(.primary)
                                Text(city.country).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if chosenCity == city.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.sanAccent)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $citySearch, prompt: "Найти город")

            Button {
                if let chosenCity { store.selectedCitySlug = chosenCity }
                withAnimation { step = 1 }
            } label: {
                Text("Продолжить")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.sanAccent)
            .disabled(chosenCity == nil)
            .padding(16)
        }
    }

    private var filteredCities: [City] {
        guard !citySearch.isEmpty else { return MockData.cities }
        return MockData.cities.filter {
            $0.name.localizedCaseInsensitiveContains(citySearch)
            || $0.country.localizedCaseInsensitiveContains(citySearch)
        }
    }

    // MARK: Шаг 2 — Геолокация

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
