import Foundation

/// Чистое наложение контента хоста поверх данных репозитория.
///
/// Хост-сторона редактирует заведения/предложения, которые должны появляться и в
/// пользовательской ленте, перекрывая одноимённые из репозитория (правки хоста
/// «выигрывают»). Раньше это жило в `AppStore.recombine()` через словарь; вынесено
/// сюда как чистая функция, чтобы протестировать семантику слияния без стора.
///
/// Firebase- и UI-независимо. Зеркаль на Android (`AppViewModel.setHostContent`).
public enum FeedAssembly {

    /// Накладывает `overrides` на `base` по `id`: элемент из `overrides` заменяет
    /// одноимённый из `base` на его месте; отсутствующие в `base` — добавляются в хвост.
    ///
    /// Порядок `base` сохраняется. Это детерминированнее прежнего словаря, но
    /// на выдачу не влияет: потребители всё равно фильтруют/сортируют по скору.
    public static func overlay<T: Identifiable>(_ base: [T], with overrides: [T]) -> [T] {
        guard !overrides.isEmpty else { return base }
        let overrideByID = Dictionary(overrides.map { ($0.id, $0) },
                                      uniquingKeysWith: { _, last in last })
        var result = base.map { overrideByID[$0.id] ?? $0 }   // замена на месте
        let baseIDs = Set(base.map(\.id))
        result.append(contentsOf: overrides.filter { !baseIDs.contains($0.id) })
        return result
    }
}
