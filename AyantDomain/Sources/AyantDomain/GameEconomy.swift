import Foundation

/// Курс мини-игр: сколько игрового времени стоит один бонус.
///
/// Одно число на все игры. До этого цена бонуса жила отдельной константой в
/// каждой игре, и пока действовал дневной потолок, расхождение ничего не
/// решало — до потолка доходили все. Потолка больше нет, и цена внутри игры
/// стала всей экономикой сразу: при прежних числах «Змейка» приносила бонус
/// за секунды, а «Три в ряд» — за минуту, то есть выгодно было играть только
/// в одну игру, а остальные превращались в украшение.
///
/// Настраивается ровно одной строкой — `minutesPerBonus`. Всё остальное здесь
/// это ЗАМЕРЫ темпа игры, а не ручки: их меняют, когда меняется сама игра
/// (скорость падения в тетрисе, размер поля, длительность каскада).
public enum GameEconomy {

    /// Минут нормальной игры за один бонус.
    ///
    /// При единице купон за 300 бонусов стоит примерно пять часов игры —
    /// это и есть та цифра, которую стоит обсуждать с заведениями, а не
    /// «яблоки» и «линии» по отдельности.
    public static let minutesPerBonus: Double = 1

    /// Потолок бонусов за день в БЕСКОНЕЧНЫХ играх («Три в ряд»).
    ///
    /// У остальных игр партия кончается сама (змейка врезалась, стакан тетриса
    /// переполнился), а бесконечная не кончается никогда — без потолка она
    /// превращается в станок: включил и копишь, сколько хватит терпения. Цена
    /// бонуса при этом прежняя (`minutesPerBonus`), потолок ограничивает только
    /// сколько оплачиваемых минут в день: при 30 это полчаса. Дальше играть
    /// можно, бонусы просто не идут, и экран говорит об этом прямо.
    ///
    /// Купон за 300 бонусов только из «Три в ряд» — не меньше десяти дней.
    public static let endlessDailyBonusCap = 30

    // MARK: Темп игр (прикидка по живой игре, а не теория)

    /// Яблок в минуту в «Змейке»: шаг 0,16 с, поле 15×20, к середине партии
    /// змея длинная и путь до яблока растёт.
    public static let applesPerMinute: Double = 12

    /// Линий в минуту в «Тетрисе» при игре с быстрым сбросом.
    public static let linesPerMinute: Double = 5

    /// Совпадений в минуту в «Три в ряд» с учётом каскадов и анимации хода.
    public static let matchesPerMinute: Double = 15

    // MARK: Цена бонуса в единицах каждой игры

    public static var applesPerBonus: Int { price(applesPerMinute) }
    public static var linesPerBonus: Int { price(linesPerMinute) }
    public static var matchesPerBonus: Int { price(matchesPerMinute) }

    /// «2048» в этот расчёт не входит намеренно: там цена не константа, а
    /// ступенька — каждая следующая плитка вдвое дороже предыдущей
    /// (`Game2048.bonusFromValue`). Первый бонус там стоит примерно минуты,
    /// то есть попадает в общий курс, а дальше игра дорожает сама. Это её
    /// анти-фарм, и подгонять его под линейный курс нельзя.
    private static func price(_ perMinute: Double) -> Int {
        max(1, Int((perMinute * minutesPerBonus).rounded()))
    }
}

// MARK: - Курс из Remote Config

/// Действующий курс игр — то, что реально платят игры и время в приложении.
///
/// Значения по умолчанию — `GameEconomy` выше (замеры темпа + якорь); консоль
/// Firebase Remote Config может поменять любое из них без релиза
/// (`RemoteSettings.gameRates`, ключи — `GameRates.Key`). Правило одно для
/// всех ключей: 0, отрицательное, мусор или отсутствие ключа — значение по
/// умолчанию; значение вне разумных границ прижимается к ним. Опечатка в
/// консоли не должна ни раздать бонусы даром, ни обнулить заработок.
///
/// Сервер режет независимо (`earnBonus`: `BONUS_DAILY_EARN_CAP`, потолки
/// источников) — поднять заработок выше серверного потолка отсюда нельзя.
///
/// Игра берёт снимок курса в начале партии: смена курса посреди партии иначе
/// пересчитала бы уже набранное (тетрис начисляет разницу `bonuses`).
public struct GameRates: Equatable, Sendable {
    /// Минут игры за бонус — якорь, из которого выводятся цены игр ниже,
    /// если их не задали в консоли напрямую.
    public var minutesPerBonus: Double
    /// Яблок «Змейки» за бонус.
    public var applesPerBonus: Int
    /// Линий «Тетриса» за бонус.
    public var linesPerBonus: Int
    /// Совпадений «Diamond» за бонус.
    public var matchesPerBonus: Int
    /// С какой плитки «2048» начинаются бонусы (степень двойки). Дальше —
    /// по бонусу за каждое удвоение, это её анти-фарм.
    public var game2048FirstTile: Int
    /// Время в приложении: минут активности за цикл, бонусов за цикл, циклов в день.
    public var timeGoalMinutes: Int
    public var timeRewardPerGoal: Int
    public var timeGoalsPerDay: Int

    public init(minutesPerBonus: Double = GameEconomy.minutesPerBonus,
                applesPerBonus: Int = GameEconomy.applesPerBonus,
                linesPerBonus: Int = GameEconomy.linesPerBonus,
                matchesPerBonus: Int = GameEconomy.matchesPerBonus,
                game2048FirstTile: Int = Game2048.bonusFromValue,
                timeGoalMinutes: Int = 30,
                timeRewardPerGoal: Int = 1,
                timeGoalsPerDay: Int = 4) {
        self.minutesPerBonus = minutesPerBonus
        self.applesPerBonus = applesPerBonus
        self.linesPerBonus = linesPerBonus
        self.matchesPerBonus = matchesPerBonus
        self.game2048FirstTile = game2048FirstTile
        self.timeGoalMinutes = timeGoalMinutes
        self.timeRewardPerGoal = timeRewardPerGoal
        self.timeGoalsPerDay = timeGoalsPerDay
    }

    public static let defaults = GameRates()

    public var timeGoalSeconds: Int { timeGoalMinutes * 60 }
    /// Сколько время в приложении может принести за день.
    public var timeDailyMax: Int { timeRewardPerGoal * timeGoalsPerDay }

    /// Ключи Remote Config. Данные установленных приложений — не переименовывать.
    public enum Key {
        public static let minutesPerBonus = "ios_bonus_minutes_per_bonus"
        public static let applesPerBonus = "ios_bonus_snake_apples_per_bonus"
        public static let linesPerBonus = "ios_bonus_tetris_lines_per_bonus"
        public static let matchesPerBonus = "ios_bonus_diamond_matches_per_bonus"
        public static let game2048FirstTile = "ios_bonus_2048_first_tile"
        public static let timeGoalMinutes = "ios_bonus_time_goal_minutes"
        public static let timeRewardPerGoal = "ios_bonus_time_reward"
        public static let timeGoalsPerDay = "ios_bonus_time_goals_per_day"
        public static let all = [minutesPerBonus, applesPerBonus, linesPerBonus, matchesPerBonus,
                                 game2048FirstTile, timeGoalMinutes, timeRewardPerGoal, timeGoalsPerDay]
    }

    /// Курс из значений консоли (`nil` — ключ не задан).
    ///
    /// Цена игры, не заданная напрямую, выводится из якоря по замеренному
    /// темпу (`GameEconomy.applesPerMinute` …) — поэтому одна правка
    /// `ios_bonus_minutes_per_bonus` двигает все три игры разом, как и задумано.
    public static func resolve(_ remote: [String: Double]) -> GameRates {
        func positive(_ key: String) -> Double? {
            guard let v = remote[key], v.isFinite, v > 0 else { return nil }
            return v
        }
        // Прижимаем ещё В Double и только потом переводим в Int: `Int(1e30)`
        // роняет приложение, а активированный конфиг лежит на диске — падение
        // на каждом запуске до переустановки.
        func int(_ key: String, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
            guard let v = positive(key) else { return fallback }
            return Int(min(max(v.rounded(), Double(range.lowerBound)), Double(range.upperBound)))
        }
        // Якорь не ниже четверти минуты: 0.1 превращал опечатку в консоли в
        // десятикратную раздачу по всем играм сразу.
        let minutes = positive(Key.minutesPerBonus).map { min(max($0, 0.25), 60) }
            ?? GameEconomy.minutesPerBonus
        func price(_ perMinute: Double) -> Int { max(1, Int((perMinute * minutes).rounded())) }

        var firstTile = Game2048.bonusFromValue
        if let v = positive(Key.game2048FirstTile) {
            // Сначала граница в Double (см. `int` выше), потом Int.
            let tile = v <= 2048 ? Int(v.rounded()) : 0
            // Только степень двойки из тех, что игра реально строит, и не ниже
            // 64: лестница — единственный анти-фарм «2048», а с 8/16/32 первые
            // бонусы падают за секунды, и перезапуск партии становится фермой.
            if tile >= 64, tile <= 2048, tile & (tile - 1) == 0 { firstTile = tile }
        }
        return GameRates(
            minutesPerBonus: minutes,
            applesPerBonus: int(Key.applesPerBonus, price(GameEconomy.applesPerMinute), 1...1000),
            linesPerBonus: int(Key.linesPerBonus, price(GameEconomy.linesPerMinute), 1...1000),
            matchesPerBonus: int(Key.matchesPerBonus, price(GameEconomy.matchesPerMinute), 1...1000),
            game2048FirstTile: firstTile,
            timeGoalMinutes: int(Key.timeGoalMinutes, 30, 1...240),
            timeRewardPerGoal: int(Key.timeRewardPerGoal, 1, 1...100),
            timeGoalsPerDay: int(Key.timeGoalsPerDay, 4, 1...24))
    }
}

// MARK: - Начисление «пакетами» по ходу партии

/// Сколько бонусов предъявить сейчас, если игра платит за полные «пакеты»
/// единиц (яблок «Змейки»): полных пакетов по `unitsPerBonus` минус уже
/// предъявленные за партию. Неполный пакет ждёт; уменьшившийся счёт (новая
/// партия без сброса) ничего не забирает и не платит.
///
/// Вынесено из экрана, чтобы правило было проверяемым: раньше эта арифметика
/// жила во вью, и ошибка в ней (деление на ноль, двойная выплата при
/// одинаковом счёте) проявилась бы только в живой игре.
public enum BatchPayout {
    public static func newBonuses(units: Int, unitsPerBonus: Int, alreadyCredited: Int) -> Int {
        let earned = max(0, units) / max(1, unitsPerBonus)
        return max(0, earned - max(0, alreadyCredited))
    }

    /// Всего полных пакетов в счёте — то, что после выплаты становится `alreadyCredited`.
    public static func fullBatches(units: Int, unitsPerBonus: Int) -> Int {
        max(0, units) / max(1, unitsPerBonus)
    }
}
