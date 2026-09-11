import SwiftUI
import AyantDomain
import AyantFeatures

// Оболочка приложения заведения после редизайна (SCREENS.md, раздел HOST APP).
//
// Идентичность хоста — тёплые песочные riso-панели и кремовый таб-бар. Никакого
// тёмного хрома: единственный тёмный элемент во всём хост-приложении — окно
// камеры на сканере.
//
// Вкладки: Заведения · Лояльность · Сканер · Аналитика · Отзывы · Профиль.
// «Продвижение» отдало слот «Лояльности» и живёт в действиях заведения (за
// `ReleaseFlags.promote`); «Профиль» — своя вкладка: на аватаре в шапке его
// не находили, а вместе с ним не находили и выход в режим гостя.

enum HostTab: Hashable {
    case venues, loyalty, scanner, analytics, reviews, profile
}

// MARK: - Песочная шапка

/// Riso-панель со скруглёнными нижними углами — общая шапка хост-экранов.
struct HostSandHeader<Content: View>: View {
    /// Плоский вариант: кремовая заливка, без riso-текстуры и без скруглений снизу.
    ///
    /// Нужен «Заведениям»: там под шапкой идёт сетка встык, во всю ширину и без
    /// скруглений. Панель с текстурой и радиусом 34 обрывалась над ней ребром —
    /// экран читался как карточка, положенная на сетку, а не как одна витрина.
    /// Остальные хост-экраны — списки на канвасе, им панель по-прежнему нужна.
    var flat = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SanMetrics.screenPadding)
            .padding(.top, 14)
            .padding(.bottom, flat ? 18 : 26)
            .background {
                if flat {
                    Color.sanHostHeader
                } else {
                    let shape = UnevenRoundedRectangle(bottomLeadingRadius: SanRadius.panel,
                                                       bottomTrailingRadius: SanRadius.panel,
                                                       style: .continuous)
                    shape.fill(LinearGradient.sanSandGradient)
                        .overlay(SanRisoHatch().clipShape(shape))
                }
            }
    }
}

/// Чип «РЕЖИМ ЗАВЕДЕНИЯ» с пульсирующей точкой.
struct HostModeChip: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color(hex: Palette.orange))
                .frame(width: 6, height: 6)
                .opacity(dim ? 0.35 : 1)
            Text("Режим заведения")
                .textCase(.uppercase)
                .font(.golos(10.5, .heavy)).tracking(1.1)
        }
        .foregroundStyle(Color.sanHostEyebrow)
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Color.sanAccent.opacity(0.15), in: Capsule())
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) { dim = true }
        }
        .onDisappear { withoutAnimation { dim = false } }
    }
}

/// Пилюля «Я гость» — возврат в гостевое приложение.
struct HostGuestPill: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("Я гость")
                .font(.golos(12.5, .bold))
                .foregroundStyle(Color.sanSandInkStrong)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Color.white.opacity(0.82), in: Capsule())
        }
        .buttonStyle(.sanPress(0.94))
    }
}

// MARK: - Корень хост-навигации

struct HostRootView: View {
    @EnvironmentObject private var host: HostStore
    @EnvironmentObject private var store: AppStore

    @State private var tab: HostTab = .venues

    private var pendingReviews: Int {
        store.reviews(forVenueIDs: host.state.ownedVenueIDs).filter { $0.hostReply == nil }.count
    }

    var body: some View {
        // Панель СИСТЕМНАЯ, как и в гостевом приложении: на iOS 26 она приходит
        // со стеклом. Кремовая панель из хендоффа и FAB-сканер уехали — сканер
        // стал центральной вкладкой, то есть остался на том же месте и в один
        // тап, но без ручной отрисовки и вечной пульсации.
        TabView(selection: $tab) {
            // «Сканер» и «Лояльность» — соседние вкладки этого же таб-бара,
            // поэтому экрану больше не нужны колбэки для перехода в них.
            HostVenuesView()
                .tabItem { Label("Заведения", systemImage: "storefront.fill") }
                .tag(HostTab.venues)
            HostLoyaltyView()
                .tabItem { Label("Лояльность", systemImage: "star.circle.fill") }
                .tag(HostTab.loyalty)
            HostScannerView(showsBack: false)
                .tabItem { Label("Сканер", systemImage: "viewfinder") }
                .tag(HostTab.scanner)
            HostAnalyticsView()
                .tabItem { Label("Аналитика", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(HostTab.analytics)
            HostReviewsView()
                .tabItem { Label("Отзывы", systemImage: "star.bubble.fill") }
                .badge(pendingReviews)
                .tag(HostTab.reviews)
                // Отзывы по заведениям владельца грузятся здесь — и бейдж, и сам
                // инбокс читают один кэш.
                .task(id: host.state.ownedVenueIDs) {
                    await store.loadReviews(forVenueIDs: host.state.ownedVenueIDs)
                }
            HostProfileView()
                .tabItem { Label("Профиль", systemImage: "person.crop.circle") }
                .tag(HostTab.profile)
        }
        .tint(Color.sanAccentText)
    }
}
