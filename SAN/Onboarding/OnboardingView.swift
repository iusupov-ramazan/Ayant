import SwiftUI
import AyantDomain
import AyantFeatures

/// Онбординг: бонусы и баллы, геолокация, уведомления. Показывается один раз до ленты.
/// Выбор города обязателен — без него лента не работает.
struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var location: LocationManager
    var onFinished: () -> Void

    @State private var step = 0
    /// Ждём ответа на системный запрос геолокации, чтобы уйти на следующий шаг
    /// не раньше, чем диалог закроется.
    @State private var awaitingLocationAnswer = false

    // Пока доступен только Бишкек — выбор города отключён. Шаги: бонусы и
    // баллы (0), геолокация (1), уведомления (2).
    private let stepCount = 3

    var body: some View {
        VStack(spacing: 0) {
            progressDots
            TabView(selection: $step) {
                walletsStep.tag(0)
                locationStep.tag(1)
                notificationStep.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: step)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            // Город зафиксирован на Бишкеке до запуска в других городах.
            store.selectedCitySlug = City.bishkek.id
        }
        .onChange(of: location.authorizationStatus) { _, _ in
            guard awaitingLocationAnswer else { return }
            awaitingLocationAnswer = false
            withAnimation { step = 2 }
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

    // MARK: Шаг 0 — Бонусы и баллы
    //
    // В приложении два разных кошелька, и путают их постоянно: бонусы (общие,
    // за игры, тратятся на купоны) и баллы САН (у каждого заведения свои).
    // Одна фраза до первого экрана снимает половину вопросов в поддержку.

    private var walletsStep: some View {
        prePrompt(
            icon: "star.circle.fill",
            title: "Бонусы и баллы",
            subtitle: "Бонусы — общие: их приносят игры в приложении, а тратятся они на купоны заведений. Баллы у каждого заведения свои: покажите на кассе «Мой QR», и заведение начислит баллы, которые тратятся только у него.",
            primary: "Понятно",
            secondary: nil
        ) {
            withAnimation { step = 1 }
        }
    }

    // MARK: Шаг 1 — Геолокация
    //
    // Кнопка названа нейтрально, и мимо системного запроса пути нет — это
    // требование App Review (5.1.1(iv), отклонение 15.09.2026). Было
    // «Разрешить геолокацию» и «Не сейчас»: первое подсказывало ответ, второе
    // позволяло вообще не дойти до системного диалога. Сам экран-объяснение
    // разрешён и полезен — нельзя только подменять им выбор пользователя.

    private var locationStep: some View {
        prePrompt(
            icon: "location.circle.fill",
            title: "Включите геолокацию",
            subtitle: "Разрешите доступ к локации, чтобы видеть, как далеко заведения от вас. Без неё всё работает — просто без расстояний.",
            primary: "Продолжить",
            secondary: nil
        ) {
            // Системный диалог показывается ровно один раз за установку. Если
            // ответ уже дан (или геолокация запрещена родительским контролем),
            // он не появится и делегат промолчит — тогда уходим дальше сами,
            // иначе шаг стал бы тупиком без единственной кнопки.
            guard location.authorizationStatus == .notDetermined else {
                withAnimation { step = 2 }
                return
            }
            awaitingLocationAnswer = true
            location.request()
        }
    }

    // MARK: Шаг 2 — Уведомления
    //
    // Та же правка, что у геолокации (5.1.1(iv), отклонение 15.09.2026): одна
    // нейтральная кнопка «Продолжить», и она ВСЕГДА ведёт в системный диалог.
    // Было «Включить уведомления» + «Позже» — «Позже» позволяло обойти
    // системный запрос, за что сборку и отклонили. Решает сам пользователь —
    // в системном окне.

    private var notificationStep: some View {
        prePrompt(
            icon: "bell.badge.fill",
            title: "Не пропустите новые акции",
            // Обещаем только то, что приложение действительно присылает: напоминания
            // про бонусы (`NotificationManager`) и новости заведений.
            subtitle: "Напомним про бонусы и расскажем о новых акциях заведений. Отключить можно в настройках.",
            primary: "Продолжить",
            secondary: nil
        ) {
            Task {
                // Если ответ уже дан, система диалог не покажет и вызов вернётся
                // сразу — шаг не становится тупиком.
                await NotificationManager.requestAuthorization()
                // Рекламные топики — только при выданном разрешении и включённой
                // настройке «Новости и акции заведений» (по умолчанию включена).
                await MarketingPush.sync()
                AnalyticsLog.log(.onboardingComplete)
                onFinished()
            }
        }
    }

    // MARK: Переиспользуемый pre-prompt

    /// `secondary`/`onSkip` — опциональные: у шагов-разрешений (геолокация,
    /// уведомления) кнопки «мимо» быть не должно (см. `locationStep`).
    ///
    /// Ключи каталога, а не `String`: `Text(String)` ничего не переводит, и
    /// онбординг оставался русским даже в английской сборке.
    private func prePrompt(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey,
                           primary: LocalizedStringKey, secondary: LocalizedStringKey?,
                           onPrimary: @escaping () -> Void,
                           onSkip: (() -> Void)? = nil) -> some View {
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
                if let secondary, let onSkip {
                    Button(action: onSkip) {
                        Text(secondary).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}
