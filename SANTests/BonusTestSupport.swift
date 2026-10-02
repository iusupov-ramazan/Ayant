import Foundation

/// Стирает всё, что `BonusEngine` кладёт в UserDefaults по пользователю
/// (очереди `san.bonus.pendingEarns.<uid>`, снимки дневных счётчиков,
/// отметки серверных потолков). `resetForNewUser` их намеренно НЕ стирает —
/// очередь должна пережить выход, — поэтому тесты чистят сами, иначе
/// неотправленное из одного теста «дошло» бы в другом.
func purgeBonusUserDefaults() {
    let d = UserDefaults.standard
    for key in d.dictionaryRepresentation().keys where
        key.hasPrefix("san.bonus.pendingEarns") ||
        key.hasPrefix("san.bonus.dayCounters.") ||
        key.hasPrefix("san.bonus.serverCappedSources") ||
        key == "san.bonus.serverGlobalCapDay" {
        d.removeObject(forKey: key)
    }
}
