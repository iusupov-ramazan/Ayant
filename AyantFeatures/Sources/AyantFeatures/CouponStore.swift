import Foundation
import Combine
import AyantDomain

// MARK: - Хранилище купонов

@MainActor
public final class CouponStore: ObservableObject {
    /// Награды, которые реально можно предъявить: каталог из `config/globalRewards`,
    /// где у каждой проставлено заведение-партнёр.
    ///
    /// Пусто, пока партнёров не завели, — и это правильное поведение: награда
    /// без заведения выдаёт купон, который сотрудник не погасит
    /// (`scanCoupon` → `wrong_venue`).
    @Published public private(set) var rewards: [Reward] = []

    @Published public private(set) var coupons: [Coupon] = []
    private let key = "san.coupons"
    private let backend: CouponService
    private let clock: Clock
    public private(set) var userID = ""

    public init(backend: CouponService, clock: Clock = SystemClock()) {
        self.backend = backend
        self.clock = clock
        load()
    }

    public var activeCount: Int { coupons.filter { !$0.used }.count }

    /// Синк с Firestore: подтягивает used-статус и новые купоны-награды лояльности.
    /// Бэкенд — источник правды для купонов, привязанных к заведению.
    public func sync(userID: String) async {
        self.userID = userID
        guard !userID.isEmpty, let fetched = try? await backend.fetchCoupons(userID: userID) else { return }
        var map: [String: Coupon] = [:]
        for c in coupons { map[c.code] = c }        // локальные (в т.ч. общие бонус-купоны)
        for c in fetched { map[c.code] = c }         // бэкенд перекрывает по коду
        coupons = map.values.sorted { $0.createdAt > $1.createdAt }
        save()
    }

    /// Загружает каталог наград. Ошибка сети → каталог остаётся пустым, и
    /// раздел наград показывает пустое состояние вместо нерабочих карточек.
    public func loadRewards() async {
        rewards = (try? await backend.fetchGlobalRewards()) ?? []
    }

    /// Списывает бонусы и выдаёт купон. Возвращает купон или nil (не хватило
    /// бонусов либо у награды нет партнёра).
    ///
    /// Купон уходит в бэкенд — иначе сотрудник его не найдёт: `scanCoupon`
    /// ищет купон по коду в Firestore и сверяет `venueID`. Раньше награда
    /// глобального кошелька оставалась только на устройстве, и предъявить её
    /// было невозможно.
    public func redeem(_ reward: Reward, bonus: BonusEngine) -> Coupon? {
        guard reward.isRedeemable else { return nil }
        guard bonus.spend(reward.cost) else { return nil }
        let c = Coupon(id: "cp_\(UUID().uuidString.prefix(8))",
                       title: reward.title,
                       code: "AYANT-\(UUID().uuidString.prefix(6).uppercased())",
                       createdAt: clock.now, used: false,
                       venueID: reward.venueID, venueName: reward.venueName,
                       kind: "reward")
        coupons.insert(c, at: 0)
        save()
        AnalyticsLog.log(.couponClaim, ["reward_id": reward.id, "cost": reward.cost])
        let uid = userID
        Task { try? await backend.saveCoupon(c, userID: uid) }
        return c
    }

    /// Создаёт купон за акцию заведения (сканируется сотрудником → штамп лояльности).
    /// Пишется в бэкенд, чтобы заведение могло его отсканировать. Возвращает купон.
    @discardableResult
    public func createDealCoupon(dealID: String, title: String, venueID: String, venueName: String) -> Coupon {
        // Уже есть непогашенный купон на эту акцию — переиспользуем.
        if let existing = coupons.first(where: { $0.dealID == dealID && !$0.used }) { return existing }
        let c = Coupon(id: "cp_\(UUID().uuidString.prefix(8))",
                       title: title,
                       code: "AYANT-\(UUID().uuidString.prefix(6).uppercased())",
                       createdAt: clock.now, used: false,
                       venueID: venueID, venueName: venueName, kind: "deal", dealID: dealID)
        coupons.insert(c, at: 0)
        save()
        let uid = userID
        Task { try? await backend.saveCoupon(c, userID: uid) }
        return c
    }

    /// Кладёт полученный в подарок купон в кошелёк.
    public func addGifted(title: String, code: String) {
        guard !coupons.contains(where: { $0.code == code }) else { return }
        coupons.insert(Coupon(id: "cp_\(UUID().uuidString.prefix(8))",
                              title: title, code: code, createdAt: clock.now), at: 0)
        save()
    }

    public func markUsed(_ coupon: Coupon) {
        guard let i = coupons.firstIndex(where: { $0.id == coupon.id }) else { return }
        coupons[i].used = true
        save()
    }

    /// Очищает кошелёк купонов при смене пользователя.
    /// Купоны лежат в `UserDefaults` по ключу устройства — после выхода их
    /// увидел бы следующий вошедший.
    public func resetForNewUser() {
        coupons = []
        userID = ""
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func save() {
        if let d = try? JSONEncoder().encode(coupons) { UserDefaults.standard.set(d, forKey: key) }
    }
    private func load() {
        if let d = UserDefaults.standard.data(forKey: key),
           let c = try? JSONDecoder().decode([Coupon].self, from: d) { coupons = c }
    }
}
