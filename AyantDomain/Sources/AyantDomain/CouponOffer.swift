import Foundation

/*
 * Купон, который заведение выпускает, а гость покупает за бонусы.
 *
 * Зачем отдельная сущность. Раньше купон был побочным продуктом акции: гость
 * открывал акцию, получал QR, сотрудник его сканировал. Заведение обязано было
 * держать сканер ради обычной скидки, а сама скидка ничего не стоила — купон
 * выдавался бесплатно всем подряд, и «выгода» ничем не отличалась от рекламы.
 *
 * Теперь роли разведены: акция — объявление («у нас −20% на завтраки»), а
 * купон — товар. Заведение само решает, что отдаёт и во сколько бонусов это
 * ценит; гость копит бонусы в приложении и покупает. Отсюда три поля, которых
 * у награды из каталога не было: ЦЕНА назначается заведением, ОСТАТОК
 * ограничивает раздачу, СРОК не даёт купону жить вечно.
 *
 * Деньгами здесь распоряжается заведение, поэтому `soldCount` и остаток
 * уменьшает только сервер (`buyCoupon`), а не клиент: см. firestore.rules.
 */
public struct CouponOffer: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var venueID: String
    public var venueName: String
    /// Что получает гость: «Бесплатный капучино», «Десерт в подарок».
    public var title: String
    /// Условия: «Только до 12:00», «Один купон на гостя».
    public var details: String
    public var emoji: String
    public var imageURL: String
    /// Цена в бонусах. Назначает заведение — оно и несёт расход.
    public var cost: Int
    /// Сколько всего выпущено. `nil` — без ограничения.
    public var stock: Int?
    /// Сколько уже куплено. Пишет только сервер.
    public var soldCount: Int
    /// Срок купона: после этой даты его нельзя ни купить, ни погасить
    /// (дата переходит на купон гостя при покупке, `scanCoupon` отвечает
    /// `coupon_expired`). Раньше дата закрывала только продажу, а экраны
    /// подписывали её «Действует до» — и проданный купон не сгорал никогда.
    /// `nil` — бессрочно.
    public var expiresAt: Date?
    /// Сколько штук продаётся одному гостю. 0 — без лимита. Без лимита один
    /// игрок с большим балансом выкупал весь остаток; сервер считает покупки
    /// гостя сам (`bonusWallets/{uid}/offerBuys/{offerID}`).
    public var perGuestLimit: Int
    public var statusRaw: String
    /// Временно снят с продажи самим заведением (в отличие от модерации).
    public var isPaused: Bool
    public var citySlug: String

    public init(id: String, venueID: String, venueName: String,
                title: String, details: String = "", emoji: String = "🎁",
                imageURL: String = "", cost: Int, stock: Int? = nil, soldCount: Int = 0,
                expiresAt: Date? = nil,
                perGuestLimit: Int = 0,
                statusRaw: String = ModerationStatus.pending.rawValue,
                isPaused: Bool = false,
                citySlug: String = City.bishkek.id) {
        self.id = id; self.venueID = venueID; self.venueName = venueName
        self.title = title; self.details = details; self.emoji = emoji
        self.imageURL = imageURL; self.cost = cost; self.stock = stock
        self.soldCount = soldCount; self.expiresAt = expiresAt
        self.perGuestLimit = max(0, perGuestLimit)
        self.statusRaw = statusRaw; self.isPaused = isPaused; self.citySlug = citySlug
    }

    /// Терпимое чтение кэша: старые записи без новых полей не должны ронять
    /// весь список (та же причина, что у `HostVenueDTO.init(from:)`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        venueID = try c.decode(String.self, forKey: .venueID)
        title = try c.decode(String.self, forKey: .title)
        cost = try c.decodeIfPresent(Int.self, forKey: .cost) ?? 0
        venueName = try c.decodeIfPresent(String.self, forKey: .venueName) ?? ""
        details = try c.decodeIfPresent(String.self, forKey: .details) ?? ""
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? "🎁"
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL) ?? ""
        stock = try c.decodeIfPresent(Int.self, forKey: .stock)
        soldCount = try c.decodeIfPresent(Int.self, forKey: .soldCount) ?? 0
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        perGuestLimit = try c.decodeIfPresent(Int.self, forKey: .perGuestLimit) ?? 0
        statusRaw = try c.decodeIfPresent(String.self, forKey: .statusRaw)
            ?? ModerationStatus.pending.rawValue
        isPaused = try c.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        citySlug = try c.decodeIfPresent(String.self, forKey: .citySlug) ?? City.bishkek.id
    }

    public var status: ModerationStatus {
        ModerationStatus(rawValue: statusRaw) ?? .pending
    }

    /// Сколько ещё можно купить. `nil` — без ограничения.
    public var remaining: Int? {
        guard let stock else { return nil }
        return max(0, stock - soldCount)
    }

    public var isSoldOut: Bool { remaining == 0 }

    public func isExpired(at now: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt < now
    }

    /// Можно ли КУПИТЬ купон прямо сейчас.
    ///
    /// Четыре независимые причины отказа, и все четыре нужны: модерация
    /// защищает гостя, пауза — заведение, остаток — его карман, срок — обе
    /// стороны. Проверка живёт здесь, а не в экране: её повторяет сервер в
    /// `buyCoupon`, и расходиться они не должны.
    public func isAvailable(at now: Date) -> Bool {
        // Цена и заведение — те же проверки, что у buyCoupon: купон без цены
        // или без стойки, где его гасить, продавать нечем.
        status == .approved && !isPaused && !isSoldOut && !isExpired(at: now)
            && cost > 0 && !venueID.isEmpty
    }
}
