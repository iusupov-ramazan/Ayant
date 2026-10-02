import Foundation

/// Сборка DTO хоста из полей формы — чистая часть бизнес-кабинета.
///
/// Раньше это жило внутри `HostStore.saveVenueForm` / `saveDealForm` вперемешку
/// с сохранением в кэш и отправкой в Firestore, поэтому правила «что при правке
/// сохраняется, а что перезаписывается» нигде не проверялись. Здесь они —
/// чистые функции: на вход поля формы, на выход DTO.
///
/// Правила, которые легко нарушить и трудно заметить:
///  • при **правке** сохраняются `id`, `status` (модерация) и `todaySpecial` —
///    иначе одобренное заведение молча уедет обратно на модерацию;
///  • при **правке акции** сохраняется `startDate` — иначе «свежесть» в ленте
///    обнулится и акция подпрыгнет наверх;
///  • ссылки и соцсети тримятся: пробел в конце ломает переход по ссылке.
///
/// Зеркалит `HostForms.kt` в `android/domain`.
public enum HostForms {

    /// Поля формы заведения. Отдельная структура, чтобы не передавать 20 аргументов.
    public struct VenueFields: Equatable {
        public var name: String
        public var category: VenueCategory
        public var district: String
        public var address: String
        public var phone: String
        public var emoji: String
        public var latitude: Double
        public var longitude: Double
        public var openHour: Int
        public var closeHour: Int
        public var imageURL: String
        public var weekHours: [DayHours]
        public var pdfMenuURL: String
        public var whatsapp: String
        public var instagram: String
        public var telegram: String
        public var branches: [Branch]
        public var loyaltyEnabled: Bool
        public var loyaltyGoal: Int
        public var loyaltyReward: String
        public var couponsEnabled: Bool
        /// Имя первой карты штампов. `nil` — «не трогать»: общая форма
        /// заведения карт не показывает и не должна их затирать.
        public var loyaltyTitle: String?
        /// Дополнительные карты штампов. `nil` — «не трогать», как и выше;
        /// пустой массив — «удалить все дополнительные».
        public var extraStampCards: [StampCard]?

        public init(name: String, category: VenueCategory, district: String, address: String,
                    phone: String, emoji: String, latitude: Double, longitude: Double,
                    openHour: Int, closeHour: Int, imageURL: String, weekHours: [DayHours],
                    pdfMenuURL: String, whatsapp: String, instagram: String, telegram: String,
                    branches: [Branch], loyaltyEnabled: Bool, loyaltyGoal: Int,
                    loyaltyReward: String, couponsEnabled: Bool,
                    loyaltyTitle: String? = nil, extraStampCards: [StampCard]? = nil) {
            self.loyaltyTitle = loyaltyTitle; self.extraStampCards = extraStampCards
            self.name = name; self.category = category; self.district = district
            self.address = address; self.phone = phone; self.emoji = emoji
            self.latitude = latitude; self.longitude = longitude
            self.openHour = openHour; self.closeHour = closeHour
            self.imageURL = imageURL; self.weekHours = weekHours; self.pdfMenuURL = pdfMenuURL
            self.whatsapp = whatsapp; self.instagram = instagram; self.telegram = telegram
            self.branches = branches
            self.loyaltyEnabled = loyaltyEnabled; self.loyaltyGoal = loyaltyGoal
            self.loyaltyReward = loyaltyReward; self.couponsEnabled = couponsEnabled
        }
    }

    /// Поля формы из уже существующего заведения.
    ///
    /// Нужна, когда экран правит ОДНУ настройку (например карту лояльности с
    /// вкладки «Лояльность»), а `saveVenue` принимает форму целиком: собирать её
    /// по полю в UI — верный способ незаметно затереть остальные. Здесь всё
    /// переносится из DTO один раз и в одном месте.
    public static func fields(from dto: HostVenueDTO) -> VenueFields {
        VenueFields(
            name: dto.name, category: dto.category, district: dto.district,
            address: dto.address, phone: dto.phone, emoji: dto.emoji,
            latitude: dto.latitude, longitude: dto.longitude,
            openHour: dto.openHour, closeHour: dto.closeHour,
            imageURL: dto.imageURL, weekHours: dto.weekHours,
            pdfMenuURL: dto.pdfMenuURL, whatsapp: dto.whatsapp,
            instagram: dto.instagram, telegram: dto.telegram,
            branches: dto.branches,
            loyaltyEnabled: dto.loyaltyEnabled, loyaltyGoal: dto.loyaltyGoal,
            loyaltyReward: dto.loyaltyReward, couponsEnabled: dto.couponsEnabled,
            loyaltyTitle: dto.loyaltyTitle, extraStampCards: dto.extraStampCards)
    }

    /// Поля формы акции.
    public struct DealFields: Equatable {
        public var venueID: String
        public var type: DealType
        public var title: String
        public var details: String
        public var emoji: String
        public var newPrice: Int?
        public var discountPercent: Int?
        public var endDate: Date?
        public var isDraft: Bool
        public var imageURLs: [String]
        public var terms: [String]
        /// id поста инстаграма, если акцию создают импортом.
        public var sourcePostID: String?
        /// Адреса, где действует акция. Пусто — во всех.
        public var locationIDs: [String]

        public init(venueID: String, type: DealType, title: String, details: String,
                    emoji: String, newPrice: Int?, discountPercent: Int?,
                    endDate: Date?, isDraft: Bool, imageURLs: [String],
                    terms: [String] = [], sourcePostID: String? = nil,
                    locationIDs: [String] = []) {
            self.venueID = venueID; self.type = type; self.title = title
            self.details = details; self.emoji = emoji
            self.newPrice = newPrice; self.discountPercent = discountPercent
            self.endDate = endDate; self.isDraft = isDraft; self.imageURLs = imageURLs
            self.terms = terms; self.sourcePostID = sourcePostID
            self.locationIDs = locationIDs
        }
    }

    private static func trim(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
    }

    /// Заведение из формы. `existing == nil` — создание (статус «на модерации»),
    /// иначе правка поверх существующего DTO.
    /// - Parameter newID: генератор id для нового заведения (в тесте — фиксированный).
    public static func venue(existing: HostVenueDTO?,
                             fields: VenueFields,
                             newID: @autoclosure () -> String) -> HostVenueDTO {
        var dto = existing ?? HostVenueDTO(
            id: newID(), name: fields.name, categoryRaw: fields.category.rawValue,
            district: fields.district, address: fields.address, phone: fields.phone,
            emoji: fields.emoji, latitude: fields.latitude, longitude: fields.longitude,
            openHour: fields.openHour, closeHour: fields.closeHour,
            todaySpecial: nil, isPaused: false, isVerified: false)

        dto.name = trim(fields.name)
        dto.categoryRaw = fields.category.rawValue
        dto.district = trim(fields.district)
        dto.address = trim(fields.address)
        dto.phone = trim(fields.phone)
        dto.emoji = fields.emoji
        dto.latitude = fields.latitude
        dto.longitude = fields.longitude
        dto.openHour = min(max(fields.openHour, 0), 24)
        dto.closeHour = min(max(fields.closeHour, 0), 24)
        dto.imageURL = trim(fields.imageURL)
        dto.weekHours = fields.weekHours
        dto.pdfMenuURL = trim(fields.pdfMenuURL)
        dto.whatsapp = trim(fields.whatsapp)
        dto.instagram = trim(fields.instagram)
        dto.telegram = trim(fields.telegram)
        dto.branches = fields.branches
        dto.loyaltyEnabled = fields.loyaltyEnabled
        dto.loyaltyGoal = fields.loyaltyGoal
        dto.loyaltyReward = trim(fields.loyaltyReward)
        dto.couponsEnabled = fields.couponsEnabled
        if let title = fields.loyaltyTitle {
            dto.loyaltyTitle = StampCards.clip(trim(title), StampCards.titleLimit)
        }
        if let extras = fields.extraStampCards {
            dto.extraStampCards = StampCards.sanitizedExtras(extras)
            dto.stampCardsLoaded = true
        }
        // id / status / todaySpecial у существующего DTO намеренно не трогаем;
        // карты штампов — тоже, если форма их не передала (`nil`).
        return dto
    }

    // MARK: Купоны заведения

    /// Поля редактора купона. Остаток и счётчик продаж сюда не входят
    /// намеренно: `soldCount` пишет только сервер, а `stock` заведение задаёт,
    /// но уменьшать его вручную ниже проданного нельзя — см. `couponOffer`.
    public struct CouponFields: Equatable {
        public var venueID: String
        public var venueName: String
        public var title: String
        public var details: String
        public var emoji: String
        public var imageURL: String
        public var cost: Int
        /// `nil` — выпуск без ограничения.
        public var stock: Int?
        public var expiresAt: Date?
        /// Лимит в одни руки; 0 — без лимита.
        public var perGuestLimit: Int
        public var isPaused: Bool

        public init(venueID: String, venueName: String, title: String, details: String = "",
                    emoji: String = "🎁", imageURL: String = "", cost: Int,
                    stock: Int? = nil, expiresAt: Date? = nil, perGuestLimit: Int = 0,
                    isPaused: Bool = false) {
            self.venueID = venueID; self.venueName = venueName
            self.title = title; self.details = details; self.emoji = emoji
            self.imageURL = imageURL; self.cost = cost; self.stock = stock
            self.expiresAt = expiresAt; self.perGuestLimit = perGuestLimit; self.isPaused = isPaused
        }
    }

    /// Минимальная цена купона в бонусах.
    ///
    /// Не ноль: бесплатный купон — это снова раздача всем подряд, от которой и
    /// уходили, убирая купон у акции. Цена — единственное, что отличает купон
    /// от объявления.
    public static let minCouponCost = 1

    /// Верх лимита в одни руки в форме: больше — это уже «без лимита».
    public static let maxPerGuestLimit = 99

    /// Купон из формы. Правки поверх существующего не трогают то, чем
    /// распоряжается не заведение.
    ///
    /// Три правила, которые легко нарушить и трудно заметить:
    ///
    /// 1. `status` сохраняется — кроме одного случая: у ОДОБРЕННОГО купона
    ///    изменилось то, что проверяла модерация (цена, название, условия,
    ///    эмодзи, фото). Тогда он возвращается на модерацию (`pending`) — то же
    ///    требует `firestore.rules`, и запись с прежним `approved` сервер
    ///    отклонил бы. Остаток, срок, лимит в одни руки и пауза модерацию не
    ///    трогают: это решения заведения, а не содержание купона.
    /// 2. `soldCount` сохраняется: его считает сервер при покупке, и запись с
    ///    клиента затёрла бы чужие покупки.
    /// 3. Остаток нельзя опустить НИЖЕ проданного. Иначе у купленных купонов
    ///    «отрицательный» остаток, а `remaining` и отчётность разъезжаются.
    public static func couponOffer(existing: CouponOffer?,
                                   fields: CouponFields,
                                   newID: @autoclosure () -> String) -> CouponOffer {
        let sold = existing?.soldCount ?? 0
        var offer = CouponOffer(
            id: existing?.id ?? newID(),
            venueID: fields.venueID,
            venueName: trim(fields.venueName),
            title: trim(fields.title),
            details: trim(fields.details),
            emoji: fields.emoji,
            imageURL: trim(fields.imageURL),
            cost: max(minCouponCost, fields.cost),
            stock: fields.stock.map { max($0, sold) },
            soldCount: sold,
            expiresAt: fields.expiresAt,
            perGuestLimit: min(max(0, fields.perGuestLimit), maxPerGuestLimit),
            statusRaw: existing?.statusRaw ?? ModerationStatus.pending.rawValue,
            isPaused: fields.isPaused,
            citySlug: existing?.citySlug ?? City.bishkek.id)
        if let existing, existing.status == .approved,
           couponNeedsReview(old: existing, new: offer) {
            offer.statusRaw = ModerationStatus.pending.rawValue
        }
        return offer
    }

    /// Какой `status` отправить вместе с записью купона; `nil` — не отправлять
    /// (merge оставит серверное значение).
    ///
    /// `server` — документ, каким он лежит на сервере СЕЙЧАС (`nil` — его нет).
    /// Решаем по нему, а не по кэшу кабинета: `couponOffer` берёт статус из
    /// кэша, и кэшированный `pending` у купона, который админ одобрил после
    /// последней синхронизации, при каждом сохранении (даже паузы или остатка)
    /// молча снимал одобрение. Поэтому статус уходит только в двух случаях:
    /// купона ещё нет (создание — всегда `pending`) или одобренный на сервере
    /// купон изменён в том, что видела модерация (возврат на `pending`, как
    /// требует `firestore.rules`).
    public static func couponStatusToWrite(server: CouponOffer?, edited: CouponOffer) -> String? {
        guard let server else { return ModerationStatus.pending.rawValue }
        if server.status == .approved, couponNeedsReview(old: server, new: edited) {
            return ModerationStatus.pending.rawValue
        }
        return nil
    }

    /// Изменилось ли то, что проверяет модерация. Тот же список полей, что в
    /// правиле `couponOffers` в `firestore.rules`: cost, title, details, emoji,
    /// imageURL. Разойдутся списки — сервер начнёт отклонять сохранения.
    public static func couponNeedsReview(old: CouponOffer, new: CouponOffer) -> Bool {
        old.cost != new.cost || old.title != new.title || old.details != new.details
            || old.emoji != new.emoji || old.imageURL != new.imageURL
    }

    // MARK: Баллы САН

    /// Поля редактора баллов САН (вкладка «Лояльность»). Отдельная структура:
    /// заведение правится целиком через `VenueFields`, а конфиг баллов — своей
    /// формой, чтобы обычное сохранение заведения его не задевало.
    public struct PointsFields: Equatable {
        public var pointsEnabled: Bool
        public var pointsMode: String            // "flat" | "bands" | "cashback"
        public var pointsFlat: Int
        public var pointsBands: [PointsBand]
        public var cashbackPercent: Double
        public var pointsRewards: [PointsReward]
        public var pointsExpiryMonths: Int
        public var redeemMode: String            // "staffScan" | "customerInitiated"
        public var earnCooldownMinutes: Int

        public init(pointsEnabled: Bool, pointsMode: String, pointsFlat: Int,
                    pointsBands: [PointsBand], cashbackPercent: Double,
                    pointsRewards: [PointsReward], pointsExpiryMonths: Int,
                    redeemMode: String, earnCooldownMinutes: Int) {
            self.pointsEnabled = pointsEnabled; self.pointsMode = pointsMode
            self.pointsFlat = pointsFlat; self.pointsBands = pointsBands
            self.cashbackPercent = cashbackPercent; self.pointsRewards = pointsRewards
            self.pointsExpiryMonths = pointsExpiryMonths; self.redeemMode = redeemMode
            self.earnCooldownMinutes = earnCooldownMinutes
        }
    }

    /// Поля редактора баллов из существующего заведения — см. `fields(from:)`.
    public static func pointsFields(from dto: HostVenueDTO) -> PointsFields {
        PointsFields(pointsEnabled: dto.pointsEnabled, pointsMode: dto.pointsMode,
                     pointsFlat: dto.pointsFlat, pointsBands: dto.pointsBands,
                     cashbackPercent: dto.cashbackPercent, pointsRewards: dto.pointsRewards,
                     pointsExpiryMonths: dto.pointsExpiryMonths, redeemMode: dto.redeemMode,
                     earnCooldownMinutes: dto.earnCooldownMinutes)
    }

    /// Допустимые значения конфига баллов — те же ограничения, что у сервера
    /// (`functions/src/index.ts`) и админ-панели. Клиент режет их до записи,
    /// чтобы «50% кэшбэка» не уехали в Firestore и не сработал ночной алерт.
    public enum PointsLimits {
        public static let modes = ["flat", "bands", "cashback"]
        public static let redeemModes = ["staffScan", "customerInitiated"]
        public static let maxPoints = PointsMath.maxPointsPerEarn          // 10 000
        public static let maxCashbackPercent = PointsMath.maxCashbackPercent // 20
        public static let expiryMonths = 1...24
        /// 0 — без паузы (начисление на каждом скане), см. CLAUDE.md.
        public static let cooldownMinutes = 0...1440
    }

    /// Накладывает конфиг баллов на DTO заведения, приводя значения к серверным
    /// ограничениям. Всё остальное в DTO (id, статус модерации, карта штампов,
    /// контакты…) не трогается — это правка одной группы полей, а не заведения.
    ///
    /// Правила:
    ///  • неизвестный режим → `flat`, неизвестный способ списания → `staffScan`;
    ///  • `pointsFlat`, баллы диапазонов — 0…10 000; кэшбэк — 0…20 %;
    ///  • диапазоны сортируются по `maxAmount`, дубли по сумме отбрасываются
    ///    (остаётся первый) — сервер выбирает диапазон по индексу, порядок важен;
    ///  • названия наград тримятся, безымянные награды удаляются, стоимость ≥ 1,
    ///    для «money» коэффициент ≥ 1 (иначе балл стоил бы дешевле сома), а в
    ///    режиме cashback — не выше `20 / процент` (`PointsMath.effectiveRatio`):
    ///    иначе «20% баллами + 1 балл = 5 сом» давали бы скидку 100%;
    ///  • срок сгорания 1…24 мес, пауза 0…1440 мин.
    public static func applyPoints(to dto: HostVenueDTO, fields: PointsFields) -> HostVenueDTO {
        var out = dto
        out.pointsEnabled = fields.pointsEnabled
        out.pointsMode = PointsLimits.modes.contains(fields.pointsMode) ? fields.pointsMode : "flat"
        out.redeemMode = PointsLimits.redeemModes.contains(fields.redeemMode) ? fields.redeemMode : "staffScan"
        out.pointsFlat = clamp(fields.pointsFlat, 0...PointsLimits.maxPoints)
        out.cashbackPercent = fields.cashbackPercent.isFinite
            ? min(max(fields.cashbackPercent, 0), PointsLimits.maxCashbackPercent)
            : 0
        out.pointsExpiryMonths = clamp(fields.pointsExpiryMonths, PointsLimits.expiryMonths)
        out.earnCooldownMinutes = clamp(fields.earnCooldownMinutes, PointsLimits.cooldownMinutes)

        // Диапазоны: стабильная сортировка + дедупликация по верхней границе.
        var seenAmounts = Set<Int>()
        out.pointsBands = fields.pointsBands
            .map { PointsBand(maxAmount: max($0.maxAmount, 0),
                              points: clamp($0.points, 0...PointsLimits.maxPoints)) }
            .filter { seenAmounts.insert($0.maxAmount).inserted }
            .sorted { $0.maxAmount < $1.maxAmount }

        out.pointsRewards = fields.pointsRewards.compactMap { r in
            let title = trim(r.title)
            guard !title.isEmpty else { return nil }
            var reward = r
            reward.title = title
            reward.type = r.type == "money" ? "money" : "item"
            reward.cost = max(r.cost, 1)
            if reward.type == "money" {
                let ratio = r.ratio.isFinite ? max(r.ratio, 1) : 1
                reward.ratio = PointsMath.effectiveRatio(ratio, pointsMode: out.pointsMode,
                                                         cashbackPercent: out.cashbackPercent)
            }
            return reward
        }
        return out
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Акция из формы. При правке сохраняется `id` и исходный `startDate`.
    ///
    /// - Parameters:
    ///   - pickerCalendar: календарь, в котором хозяин выбрал дату окончания
    ///     (`DatePicker` показывает день в поясе телефона). В тесте — фиксированный.
    ///   - citySlug: город заведения — дата окончания закрывается в ЕГО поясе.
    public static func deal(existing: HostDealDTO?,
                            fields: DealFields,
                            now: Date,
                            pickerCalendar: Calendar = .current,
                            citySlug: String = City.bishkek.id,
                            newID: @autoclosure () -> String) -> HostDealDTO {
        HostDealDTO(
            id: existing?.id ?? newID(),
            venueID: fields.venueID,
            typeRaw: fields.type.rawValue,
            title: trim(fields.title),
            details: trim(fields.details),
            emoji: fields.emoji,
            newPrice: fields.newPrice,
            discountPercent: fields.discountPercent,
            startDate: existing?.startDate ?? now,
            // Нетронутую при правке дату не пересчитываем: иначе на телефоне в
            // поясе восточнее города каждое сохранение сдвигало бы её на день.
            endDate: fields.endDate.map { end in
                end == existing?.endDate ? end : endOfDay(end, pickedIn: pickerCalendar, citySlug: citySlug)
            },
            statusRaw: dealStatus(existing: existing, isDraft: fields.isDraft).rawValue,
            imageURL: trim(fields.imageURLs.first ?? ""),
            imageURLs: fields.imageURLs,
            // Пустые строки не сохраняем: пустой пункт условий — это буллет
            // в никуда.
            terms: fields.terms.map(trim).filter { !$0.isEmpty },
            // Связь с постом, как и `startDate`, переживает правку: потеряв её,
            // кабинет перестанет помечать пост добавленным и предложит
            // импортировать его второй раз.
            sourcePostID: existing?.sourcePostID ?? fields.sourcePostID,
            // Без повторов и в порядке выбора; пусто — «во всех адресах».
            locationIDs: fields.locationIDs.reduce(into: [String]()) { ids, id in
                if !id.isEmpty && !ids.contains(id) { ids.append(id) }
            })
    }

    /// Статус акции после сохранения формы.
    ///
    /// Форма знает только переключатель «черновик». Раньше любое сохранение без
    /// него ставило `active` — правка опечатки в акции на паузе молча
    /// запускала её снова. Теперь:
    ///  • «черновик» включён → `draft`;
    ///  • был черновик, переключатель выключили → `active` (публикация);
    ///  • иначе статус прежний (`paused` остаётся паузой); `expired` и новая
    ///    акция → `active` — продлённая акция снова идёт.
    public static func dealStatus(existing: HostDealDTO?, isDraft: Bool) -> DealStatus {
        if isDraft { return .draft }
        switch existing?.status {
        case .paused?: return .paused
        default: return .active
        }
    }

    /// Конец выбранного дня (23:59:59) в поясе города.
    ///
    /// `DatePicker(displayedComponents: .date)` отдаёт выбранный день со
    /// ВРЕМЕНЕМ открытия формы: акция «до 5 октября», созданная в 14:20,
    /// заканчивалась 5-го в 14:20 — посреди дня, на котором гость её видел.
    /// День берём в календаре выбора (телефон), а закрываем в поясе города.
    public static func endOfDay(_ date: Date, pickedIn picker: Calendar, citySlug: String) -> Date {
        let day = picker.dateComponents([.year, .month, .day], from: date)
        var end = DateComponents()
        end.year = day.year; end.month = day.month; end.day = day.day
        end.hour = 23; end.minute = 59; end.second = 59
        return City.calendar(forSlug: citySlug).date(from: end) ?? date
    }
}
