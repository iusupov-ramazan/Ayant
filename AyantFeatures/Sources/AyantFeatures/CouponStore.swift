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
    /// Серверный кошелёк: есть — покупки идут через `buyCoupon`, нет (мок,
    /// тесты) — бонусы списываются на устройстве, как раньше.
    private let wallet: BonusWalletService?
    /// Ключ идемпотентности на покупку (по `BonusPurchase.ref`): живёт, пока
    /// сервер не дал окончательный ответ. Обрыв сети → повтор с тем же ключом,
    /// и сервер вернёт уже выданный купон, а не продаст второй.
    private var purchaseKeys: [String: String] = [:]
    public private(set) var userID = ""

    public init(backend: CouponService, clock: Clock = SystemClock(), wallet: BonusWalletService? = nil) {
        self.backend = backend
        self.clock = clock
        self.wallet = wallet
        load()
    }

    public var usesServerWallet: Bool { wallet != nil }

    /// Итог покупки за бонусы. `failed` несёт код сервера (`insufficient`,
    /// `sold_out`, `unavailable`, …) или `network` — тогда повтор безопасен.
    public enum PurchaseResult: Equatable {
        case coupon(Coupon)
        case gift(code: String)
        case failed(String)
    }

    public var activeCount: Int { coupons.filter { !$0.used }.count }

    /// Синк с Firestore: подтягивает used-статус и новые купоны-награды лояльности.
    /// Бэкенд — источник правды для купонов, привязанных к заведению.
    public func sync(userID: String) async {
        self.userID = userID
        guard !userID.isEmpty, let fetched = try? await backend.fetchCoupons(userID: userID) else { return }
        merge(fetched)
    }

    /// Слушает купоны пользователя на сервере. Купон гасит сотрудник —
    /// сканом или вводом кода, — и `used` приходит сюда сразу: раньше купон
    /// оставался «активным» у гостя до перезапуска приложения, потому что
    /// синк был разовым (при входе).
    public func observe(userID: String) {
        guard !userID.isEmpty else { return }
        if userID == observedUserID, observeTask != nil { return }
        observeTask?.cancel()
        self.userID = userID
        observedUserID = userID
        observeTask = Task { [weak self, backend] in
            for await list in backend.coupons(userID: userID) {
                guard let self, !Task.isCancelled else { return }
                self.merge(list)
            }
        }
    }

    public func stopObserving() {
        observeTask?.cancel()
        observeTask = nil
        observedUserID = ""
    }

    private var observeTask: Task<Void, Never>?
    private var observedUserID = ""

    /// Сервер — источник правды для купонов, которые он знает (по коду);
    /// локальные купоны, которых на сервере нет (подарки, мок-режим), остаются.
    private func merge(_ fetched: [Coupon]) {
        var map: [String: Coupon] = [:]
        for c in coupons { map[c.code] = c }        // локальные (в т.ч. общие бонус-купоны)
        for c in fetched { map[c.code] = c }         // бэкенд перекрывает по коду
        let merged = map.values.sorted { $0.createdAt > $1.createdAt }
        guard merged != coupons else { return }     // снапшот без изменений — не перерисовываем
        coupons = merged
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
    public func redeem(_ reward: Reward, bonus: BonusEngine) async -> PurchaseResult {
        guard reward.isRedeemable else { return .failed("not_found") }
        if wallet != nil { return await purchase(.reward(id: reward.id, asGift: false, fromName: ""), bonus: bonus) }
        return redeemLocally(reward, bonus: bonus).map(PurchaseResult.coupon) ?? .failed("insufficient")
    }

    /// Подарок другу: списываются бонусы, сервер создаёт `giftCoupons/{code}`.
    /// Без серверного кошелька — `failed("local")`: тогда подарок делает
    /// `AppStore.createGift`, как раньше.
    public func gift(_ reward: Reward, fromName: String, bonus: BonusEngine) async -> PurchaseResult {
        guard wallet != nil else { return .failed("local") }
        return await purchase(.reward(id: reward.id, asGift: true, fromName: fromName), bonus: bonus)
    }

    /// Одна покупка через `buyCoupon`. Цена, остаток и модерация проверяются
    /// на сервере; клиент только показывает итог и кладёт купон в кошелёк.
    private func purchase(_ item: BonusPurchase, bonus: BonusEngine) async -> PurchaseResult {
        guard let wallet else { return .failed("local") }
        let key = purchaseKeys[item.ref] ?? UUID().uuidString
        purchaseKeys[item.ref] = key
        guard let r = try? await wallet.buy(item, idempotencyKey: key) else {
            return .failed("network")          // ключ остаётся — повтор безопасен
        }
        purchaseKeys[item.ref] = nil           // ответ окончательный: следующая покупка — новый ключ
        guard r.ok else { return .failed(r.errorCode ?? "buy_failed") }
        bonus.applyServerBalance(r.balance)
        if let code = r.giftCode {
            AnalyticsLog.log(.couponClaim, ["ref": item.ref, "gift": true])
            return .gift(code: code)
        }
        guard let c = r.coupon else { return .failed("buy_failed") }
        if !coupons.contains(where: { $0.code == c.code }) {
            coupons.insert(c, at: 0)
            save()
        }
        AnalyticsLog.log(.couponClaim, ["ref": item.ref])
        return .coupon(c)
    }

    private func redeemLocally(_ reward: Reward, bonus: BonusEngine) -> Coupon? {
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

    // MARK: Купоны заведения за бонусы

    /// Купоны, которые продаёт заведение, — по id заведения. Только доступные
    /// к покупке (`CouponOffer.isAvailable`): снятое с продажи, разобранное и
    /// не прошедшее модерацию гостю показывать незачем.
    @Published public private(set) var offersByVenue: [String: [CouponOffer]] = [:]

    public func offers(venueID: String) -> [CouponOffer] { offersByVenue[venueID] ?? [] }

    /// Витрина «Купоны заведений» во вкладке «Бонусы»: всё, что можно купить
    /// прямо сейчас, по всем заведениям, от дешёвого к дорогому.
    @Published public private(set) var shopOffers: [CouponOffer] = []

    /// Загружает витрину. Ошибка сети — прежний список остаётся.
    public func loadShopOffers() async {
        guard let all = try? await backend.fetchApprovedCouponOffers() else { return }
        let now = clock.now
        shopOffers = all.filter { $0.isAvailable(at: now) }
            .sorted { ($0.cost, $0.venueName, $0.title) < ($1.cost, $1.venueName, $1.title) }
    }

    /// Загружает купоны заведения. Ошибка сети — прежний список остаётся.
    public func loadOffers(venueID: String) async {
        guard let all = try? await backend.fetchCouponOffers(venueID: venueID) else { return }
        let now = clock.now
        offersByVenue[venueID] = all.filter { $0.isAvailable(at: now) }.sorted { $0.cost < $1.cost }
    }

    /// Обмен бонусов на купон заведения. Возвращает купон или nil (купон
    /// недоступен или не хватило бонусов).
    ///
    /// С серверным кошельком — `buyCoupon`: списание, остаток (`soldCount`) и
    /// сам купон в одной серверной транзакции. Без него (мок-режим) — на
    /// устройстве: для оффлайн-демо, в продакшене этого пути нет.
    public func buy(_ offer: CouponOffer, bonus: BonusEngine) async -> PurchaseResult {
        guard offer.isAvailable(at: clock.now) else { return .failed("unavailable") }
        if wallet != nil { return await purchase(.offer(id: offer.id), bonus: bonus) }
        return buyLocally(offer, bonus: bonus).map(PurchaseResult.coupon) ?? .failed("insufficient")
    }

    private func buyLocally(_ offer: CouponOffer, bonus: BonusEngine) -> Coupon? {
        guard bonus.spend(offer.cost) else { return nil }
        let c = Coupon(id: "cp_\(UUID().uuidString.prefix(8))",
                       title: offer.title,
                       code: "AYANT-\(UUID().uuidString.prefix(6).uppercased())",
                       createdAt: clock.now, used: false,
                       venueID: offer.venueID, venueName: offer.venueName,
                       kind: "offer")
        coupons.insert(c, at: 0)
        save()
        AnalyticsLog.log(.couponClaim, ["offer_id": offer.id, "cost": offer.cost])
        let uid = userID
        Task { try? await backend.saveCoupon(c, userID: uid) }
        return c
    }

    // `createDealCoupon` удалён вместе с купоном у акции: акция теперь
    // объявление. Уже выданные купоны с `kind: "deal"` остаются в кошельках и
    // гасятся как раньше — `scanCoupon` их по-прежнему понимает, и отнимать у
    // людей то, что они успели получить, нельзя.

    /// Забирает подарок через сервер (`claimGift`): купон приходит с
    /// заведением и гасится у стойки. `nil` — без серверного кошелька
    /// (тогда подарок забирает `AppStore.claimGift` по-старому).
    public func claimGift(code: String) async -> PurchaseResult? {
        guard let wallet else { return nil }
        guard let r = try? await wallet.claimGift(code: code) else { return .failed("network") }
        guard r.ok, let c = r.coupon else { return .failed(r.errorCode ?? "claim_failed") }
        if !coupons.contains(where: { $0.code == c.code }) {
            coupons.insert(c, at: 0)
            save()
        }
        return .coupon(c)
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
        // Слушатель прежнего пользователя снимаем — иначе его купоны
        // вернулись бы в кошелёк следующего.
        stopObserving()
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
        purgeLegacyOnce()
    }

    /// Купоны до серверного кошелька (их создавал клиент, часть из них не
    /// гасится) убираются с устройства один раз. С сервера их убирает
    /// `scripts/purge-legacy-coupons.js` — иначе синк вернул бы их обратно.
    /// Отсечка та же, что у переноса баланса в кошелёк.
    public static let legacyCutoff = Date(timeIntervalSince1970: 1_790_791_200)   // 2026-10-01 00:00 Бишкек
    private static let legacyPurgeKey = "san.coupons.legacyPurged.v1"

    private func purgeLegacyOnce() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: Self.legacyPurgeKey) else { return }
        d.set(true, forKey: Self.legacyPurgeKey)
        let kept = coupons.filter { $0.createdAt >= Self.legacyCutoff }
        guard kept.count != coupons.count else { return }
        coupons = kept
        save()
    }
}
