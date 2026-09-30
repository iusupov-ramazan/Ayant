import UIKit

// MARK: - Свайп назад на экранах со своей шапкой
//
// Почти все экраны приложения прячут системную навигационную панель
// (`.toolbar(.hidden, for: .navigationBar)`) и рисуют свою кнопку «назад».
// UIKit при скрытой панели перестаёт запускать жест возврата от края экрана:
// делегат `interactivePopGestureRecognizer` смотрит на панель и отказывает.
// Так на странице заведения не работал свайп назад — и на «Заведениях»,
// в «Сохранённом», в поиске, в профиле тоже.
//
// Делегат жеста подменяется на сам навигационный контроллер, который
// разрешает жест, когда есть куда возвращаться. Одно место на всё
// приложение: новому экрану со своей шапкой ничего добавлять не нужно.

extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == interactivePopGestureRecognizer else { return true }
        // Корень стека: возвращаться некуда, а начатый жест «заморозил» бы
        // экран. Во время перехода — тоже нет, иначе стек ломается.
        return viewControllers.count > 1 && transitionCoordinator == nil
    }
}
