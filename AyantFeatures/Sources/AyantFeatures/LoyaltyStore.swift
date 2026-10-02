import Foundation
import Combine
import AyantDomain

// MARK: - Хранилище

@MainActor
public final class LoyaltyStore: ObservableObject {
    public static let defaultGoal = 6   // фолбэк, если заведение не задало

    @Published public private(set) var cards: [LoyaltyCard] = []
    /// Непоказанный штамп (см. `PointsState.pendingEarn` у баллов). Живёт до
    /// `dismissStamp()`, не до перерисовки экрана.
    @Published public private(set) var pendingStamp: LoyaltyStampEvent?
    /// Был ли уже первый снимок: первая загрузка — не «начисление».
    private var hasBaseline = false
    public private(set) var userID = ""
    private let key = "san.loyalty"
    private let backend: CouponService
    private var observation: Task<Void, Never>?

    deinit { observation?.cancel() }

    public init(backend: CouponService) {
        self.backend = backend
        load()
    }

    /// Первая карта заведения (та, что была единственной до нескольких карт).
    public func card(for venueID: String) -> LoyaltyCard? {
        card(venueID: venueID, cardID: StampCard.defaultID)
    }

    public func card(venueID: String, cardID: String) -> LoyaltyCard? {
        let id = LoyaltyCard.id(venueID: venueID, cardID: cardID)
        return cards.first { $0.id == id }
    }

    /// Карта для заведения — существующая (с синхронизированными штампами) или
    /// новая на 0 штампов (чтобы можно было добавить в Wallet до первого штампа).
    public func cardOrNew(venueID: String, venueName: String, goal: Int, reward: String) -> LoyaltyCard {
        card(for: venueID) ?? LoyaltyCard(venueID: venueID, venueName: venueName,
                                          goal: max(goal, 2), reward: reward)
    }

    /// То же для конкретной карты заведения: прогресс гостя, если он есть, а
    /// цель, награда и имя — всегда текущие из настроек заведения.
    public func cardOrNew(venueID: String, venueName: String, stampCard: StampCard) -> LoyaltyCard {
        var card = card(venueID: venueID, cardID: stampCard.id)
            ?? LoyaltyCard(venueID: venueID, venueName: venueName, cardID: stampCard.id)
        card.goal = max(stampCard.goal, 2)
        card.reward = stampCard.reward
        card.title = stampCard.title
        return card
    }

    /// Подписка на живой поток карт лояльности.
    ///
    /// Штампы начисляет сканер заведения (Cloud Function по QR карты). Раньше
    /// экран опрашивал бэкенд раз в 4 секунды, пока был открыт; теперь Firestore
    /// сам присылает изменение snapshot-листенером — тот же приём, что у баллов
    /// (`FirebasePointsRepository`). Листенер снимается вместе с задачей.
    public func observe(userID: String) {
        guard self.userID != userID || observation == nil else { return }
        observation?.cancel()
        self.userID = userID
        guard !userID.isEmpty else { return }
        observation = Task { [backend] in
            for await snapshot in backend.liveLoyaltyCards(userID: userID) {
                if Task.isCancelled || self.userID != userID { return }
                apply(snapshot.value, fromCache: snapshot.isFromCache)
            }
        }
    }

    /// Снимок с сервера поверх известных карт; рост штампов или собранный круг
    /// у уже известной карты — событие для экрана «Начислено».
    ///
    /// Точка отсчёта (`hasBaseline`) — только с серверного снимка: первый
    /// снимок из пустого/неполного кэша SDK, взятый за «было», превращал
    /// следующий серверный в ложное «+1 штамп» (или «карта заполнена»).
    private func apply(_ fetched: [LoyaltyCard], fromCache: Bool = false) {
        // Ключ — id карты, а не заведение: у заведения их может быть несколько,
        // и по `venueID` вторая карта затирала бы первую.
        let before = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var map = before
        for c in fetched { map[c.id] = c }   // бэкенд — источник правды
        if hasBaseline, pendingStamp == nil {
            for c in fetched {
                // Новой карты в прошлом снимке нет — первый штамп: «было» = 0.
                let wasStamps = before[c.id]?.stamps ?? 0
                let wasRounds = before[c.id]?.completedRounds ?? 0
                let completed = c.completedRounds > wasRounds
                guard completed || c.stamps > wasStamps else { continue }
                PointsStore.logFirstOnce("san.analytics.firstStampLogged", .firstStamp)
                pendingStamp = LoyaltyStampEvent(
                    id: "\(c.id)-\(c.completedRounds)-\(c.stamps)",
                    venueID: c.venueID, venueName: c.venueName,
                    stamps: c.stamps, goal: max(c.goal, 1),
                    rewardIssued: completed, reward: c.reward, cardTitle: c.title)
                break
            }
        }
        if !fromCache { hasBaseline = true }
        cards = map.values.sorted { $0.stamps > $1.stamps }
        save()
    }

    public func dismissStamp() { pendingStamp = nil }

    public func stopObserving() {
        observation?.cancel()
        observation = nil
    }

    /// Разовый синк — оставлен для мест, где живой поток избыточен (запуск приложения).
    public func sync(userID: String) async {
        self.userID = userID
        guard !userID.isEmpty, let fetched = try? await backend.fetchLoyaltyCards(userID: userID) else { return }
        // Пока шёл запрос, гость мог выйти или смениться — чужие карты не кладём.
        guard self.userID == userID else { return }
        apply(fetched)
    }

    /// Очищает карты штампов при смене пользователя (см. `CouponStore.resetForNewUser`).
    public func resetForNewUser() {
        stopObserving()
        cards = []
        pendingStamp = nil
        hasBaseline = false
        userID = ""
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func save() {
        if let d = try? JSONEncoder().encode(cards) { UserDefaults.standard.set(d, forKey: key) }
    }
    private func load() {
        if let d = UserDefaults.standard.data(forKey: key),
           let c = try? JSONDecoder().decode([LoyaltyCard].self, from: d) { cards = c }
    }
}
