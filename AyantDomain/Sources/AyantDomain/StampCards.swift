import Foundation

// Несколько карт штампов у одного заведения («Пармезан»: кофе отдельно,
// пицца отдельно).
//
// Совместимость важнее красоты: у заведения уже есть ОДНА карта в скалярных
// полях (`loyaltyEnabled` / `loyaltyGoal` / `loyaltyReward`), её читают
// Android, админ-панель и старые сборки iOS, и по ней уже накоплены штампы в
// `loyaltyCards/{userID}_{venueID}`. Поэтому:
//
// • первая карта — это и есть скалярные поля (id `default`), плюс
//   необязательное имя `loyaltyTitle`; её документ штампов не меняется;
// • остальные карты лежат в массиве `stampCards` и копят штампы в ОТДЕЛЬНОЙ
//   коллекции `extraLoyaltyCards/{userID}_{venueID}_{cardID}` — Android и
//   старые iOS читают `loyaltyCards` по userID и склеивают по заведению, так
//   что документ второй карты там затёр бы им первую;
// • `loyaltyEnabled` включает программу штампов целиком.
//
// Клиент, который не знает о картах, шлёт скан без `cardID` — сервер
// ставит штамп на первую карту, как раньше. Правила повторены в
// `functions/src/index.ts` (`activeStampCards`, `stampCardDocID`) и прогоняются
// на обеих сторонах одним фикстуром `specs/fixtures/stamp-cards-fixtures.json`.

/// Одна карта штампов заведения.
public struct StampCard: Identifiable, Hashable, Codable, Sendable {
    /// id первой карты — той, что живёт в скалярных полях заведения.
    public static let defaultID = "default"

    public var id: String
    /// Имя карты для гостя и сотрудника («Кофе», «Пицца»). Пустое — у первой
    /// карты, пока заведение не дало ей имя.
    public var title: String
    public var goal: Int
    public var reward: String
    /// Выключенная карта не показывается гостю и не принимает штампы, но её
    /// накопленные штампы не пропадают — карту можно включить обратно.
    public var active: Bool

    public var isDefault: Bool { id == Self.defaultID }

    public init(id: String, title: String, goal: Int, reward: String, active: Bool = true) {
        self.id = id; self.title = title; self.goal = goal; self.reward = reward; self.active = active
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        goal = try c.decodeIfPresent(Int.self, forKey: .goal) ?? StampCards.defaultGoal
        reward = try c.decodeIfPresent(String.self, forKey: .reward) ?? ""
        active = try c.decodeIfPresent(Bool.self, forKey: .active) ?? true
    }
}

/// Правила карт штампов — чистые, без хранилища и без часов.
public enum StampCards {
    public static let defaultGoal = 6
    /// Те же границы, что у степпера и у сервера: карта на 1 штамп — не карта,
    /// на 13+ — гость не доживёт до награды.
    public static let goalRange = 2...12
    /// Предел карт на заведение, включая первую. Больше — и сотрудник на кассе
    /// выбирает дольше, чем гость ждёт.
    public static let maxCards = 5
    public static let titleLimit = 30
    public static let rewardLimit = 60
    public static let defaultReward = "Награда за лояльность"

    /// Все карты заведения, которые сейчас принимают штампы, — первая
    /// впереди. Пусто, если программа штампов выключена.
    public static func active(enabled: Bool, title: String, goal: Int, reward: String,
                              extras: [StampCard]) -> [StampCard] {
        guard enabled else { return [] }
        let trimmedReward = reward.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = StampCard(
            id: StampCard.defaultID,
            title: clip(title.trimmingCharacters(in: .whitespacesAndNewlines), titleLimit),
            goal: firstGoal(goal),
            reward: trimmedReward.isEmpty ? defaultReward : trimmedReward)
        // Отбор повторяется и здесь: карты могли прийти в обход `parse`.
        return [first] + sanitizedExtras(extras).filter(\.active)
    }

    /// id документа штампов гостя. Первая карта — прежний документ без
    /// суффикса: на нём уже накоплены штампы, и его читают клиенты, которые
    /// о картах не знают.
    /// Первая ли это карта — её штампы в прежней коллекции `loyaltyCards`,
    /// у остальных — в `extraLoyaltyCards` (имена — `FS.Collection`).
    public static func isFirstCard(_ cardID: String) -> Bool {
        cardID.isEmpty || cardID == StampCard.defaultID
    }

    public static func ledgerDocID(userID: String, venueID: String, cardID: String) -> String {
        cardID.isEmpty || cardID == StampCard.defaultID
            ? "\(userID)_\(venueID)"
            : "\(userID)_\(venueID)_\(cardID)"
    }

    /// Цель дополнительной карты: ноль и отрицательное — «не задано» (6),
    /// иначе 2…12.
    /// Обрезка по скалярам Unicode — так же считает сервер (`Array.from`):
    /// с эмодзи символы Swift и единицы UTF-16 в JS разошлись бы.
    static func clip(_ s: String, _ limit: Int) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: s.unicodeScalars.prefix(limit))
        return String(view)
    }

    public static func clampGoal(_ goal: Int) -> Int {
        goal > 0 ? min(max(goal, goalRange.lowerBound), goalRange.upperBound) : defaultGoal
    }

    /// Цель первой карты — как до нескольких карт: ноль и отрицательное — 6,
    /// минимум 2, **сверху не зажимается** (Android пишет цель свободным числом,
    /// и сервер её никогда не ограничивал).
    public static func firstGoal(_ goal: Int) -> Int {
        goal > 0 ? max(goal, goalRange.lowerBound) : defaultGoal
    }

    /// Приводит дополнительные карты к правилам перед сохранением: обрезает
    /// текст, зажимает цель, выбрасывает карты без награды и дубли id, не
    /// пускает чужой `default` и держит общий предел карт.
    public static func sanitizedExtras(_ cards: [StampCard]) -> [StampCard] {
        var seen: Set<String> = [StampCard.defaultID]
        var out: [StampCard] = []
        for card in cards {
            // id не обрезаем: сервер и админ-панель принимают его как есть,
            // и « pizza» здесь, но не там, разъехался бы.
            let id = card.id
            guard isValidID(id), !seen.contains(id) else { continue }
            let reward = clip(card.reward.trimmingCharacters(in: .whitespacesAndNewlines), rewardLimit)
            guard !reward.isEmpty else { continue }
            seen.insert(id)
            out.append(StampCard(
                id: id,
                title: clip(card.title.trimmingCharacters(in: .whitespacesAndNewlines), titleLimit),
                goal: clampGoal(card.goal),
                reward: reward,
                active: card.active))
            if out.count == maxCards - 1 { break }
        }
        return out
    }

    /// id карты идёт в имя документа Firestore — только латиница, цифры и
    /// дефис, без `/` и `_` (подчёркивание разделяет части id документа).
    public static func isValidID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 32 else { return false }
        return id.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "-"
        }
    }

    /// Новый id дополнительной карты. Источник случайности передаётся снаружи,
    /// чтобы тесты были детерминированными.
    public static func newID(random: () -> UInt32 = { UInt32.random(in: 0...UInt32.max) }) -> String {
        "card-" + String(random(), radix: 36)
    }
}
