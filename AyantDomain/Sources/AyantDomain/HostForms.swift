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

        public init(name: String, category: VenueCategory, district: String, address: String,
                    phone: String, emoji: String, latitude: Double, longitude: Double,
                    openHour: Int, closeHour: Int, imageURL: String, weekHours: [DayHours],
                    pdfMenuURL: String, whatsapp: String, instagram: String, telegram: String,
                    branches: [Branch], loyaltyEnabled: Bool, loyaltyGoal: Int,
                    loyaltyReward: String, couponsEnabled: Bool) {
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
            loyaltyReward: dto.loyaltyReward, couponsEnabled: dto.couponsEnabled)
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

        public init(venueID: String, type: DealType, title: String, details: String,
                    emoji: String, newPrice: Int?, discountPercent: Int?,
                    endDate: Date?, isDraft: Bool, imageURLs: [String],
                    terms: [String] = []) {
            self.venueID = venueID; self.type = type; self.title = title
            self.details = details; self.emoji = emoji
            self.newPrice = newPrice; self.discountPercent = discountPercent
            self.endDate = endDate; self.isDraft = isDraft; self.imageURLs = imageURLs
            self.terms = terms
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
        // id / status / todaySpecial у существующего DTO намеренно не трогаем.
        return dto
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
    ///    для «money» коэффициент ≥ 1 (иначе балл стоил бы дешевле сома);
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
                reward.ratio = r.ratio.isFinite ? max(r.ratio, 1) : 1
            }
            return reward
        }
        return out
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Акция из формы. При правке сохраняется `id` и исходный `startDate`.
    public static func deal(existing: HostDealDTO?,
                            fields: DealFields,
                            now: Date,
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
            endDate: fields.endDate,
            statusRaw: (fields.isDraft ? DealStatus.draft : .active).rawValue,
            imageURL: trim(fields.imageURLs.first ?? ""),
            imageURLs: fields.imageURLs,
            // Пустые строки не сохраняем: пустой пункт условий — это буллет
            // в никуда.
            terms: fields.terms.map(trim).filter { !$0.isEmpty })
    }
}
