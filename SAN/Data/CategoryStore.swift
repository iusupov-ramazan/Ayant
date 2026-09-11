import Foundation
import SwiftUI
import AyantDomain
import AyantData

// MARK: - Категории (гибкий список из бэкенда)
//
// Коллекция Firestore `categories` (управляется из админки): slug, name, icon,
// emoji, order, enabled. Приложение читает её и использует в фильтрах и формах.
// Если бэкенд недоступен / пуст — остаёмся на встроенных VenueCategory.allCases.

@MainActor
final class CategoryStore: ObservableObject {
    static let shared = CategoryStore(repository: AppConfig.makeDataRepository())

    /// Категории для UI (встроенные — как фолбэк до загрузки).
    @Published private(set) var categories: [VenueCategory] = VenueCategory.allCases

    private let repository: DataRepository
    /// Репозиторий подставляет композиционный корень; в тестах — свой.
    nonisolated init(repository: DataRepository) {
        self.repository = repository
    }

    func load() async {
        // Категории идут через тот же протокол данных, что и остальной каталог —
        // никаких прямых обращений к Firestore здесь. Пусто/ошибка → встроенные.
        guard let rows = try? await repository.fetchCategories(), !rows.isEmpty else { return }
        VenueCategory.applyRemote(rows)
        categories = rows.filter { $0.enabled }.sorted { $0.order < $1.order }
            .compactMap { VenueCategory(rawValue: $0.name) }
    }
}
