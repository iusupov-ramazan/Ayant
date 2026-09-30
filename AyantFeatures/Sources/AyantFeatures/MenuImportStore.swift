import Foundation
import Combine
import AyantDomain

/// Разбор файла меню: чтение → черновик → правка хозяином.
///
/// Одно состояние и одна точка входа (`state` + `send`). Сохранение в
/// заведение делает не этот стор, а `HostStore` (`.importMenu`): черновик
/// живёт здесь, пока хозяин его правит, и в заведение уходит целиком.
@MainActor
public final class MenuImportStore: ObservableObject {
    @Published public private(set) var state = MenuImportState()

    private let service: MenuParsingService
    private var task: Task<Void, Never>?

    public init(service: MenuParsingService) {
        self.service = service
    }

    deinit { task?.cancel() }

    public var isReading: Bool {
        if case .reading = state.phase { return true }
        return false
    }

    public func send(_ intent: MenuImportIntent) {
        switch intent {
        case .parse(let file, let kind):
            guard !isReading else { return }
            guard file.count <= MenuImport.maxFileBytes else {
                state = MenuImportState(phase: .failed(.server(code: "file_too_large")))
                return
            }
            state = MenuImportState(phase: .reading(progress: 0))
            task = Task { [service, weak self] in
                do {
                    let drafts = try await service.parseMenu(file: file, kind: kind) { value in
                        Task { @MainActor [weak self] in self?.send(.progress(value)) }
                    }
                    guard !Task.isCancelled, let self else { return }
                    self.state = drafts.isEmpty
                        ? MenuImportState(phase: .failed(.server(code: "no_items")))
                        : MenuImportState(phase: .review, drafts: drafts)
                } catch {
                    guard !Task.isCancelled, let self else { return }
                    self.state = MenuImportState(phase: .failed(error as? AppError ?? .unknown))
                }
            }
        case .progress(let value):
            // Прогресс опаздывает к концу разбора — после него не откатываемся.
            guard case .reading(let current) = state.phase, value > current else { return }
            state.phase = .reading(progress: min(value, 1))
        case .update(let item):
            guard let i = state.drafts.firstIndex(where: { $0.id == item.id }) else { return }
            state.drafts[i] = item
        case .toggle(let id):
            guard let i = state.drafts.firstIndex(where: { $0.id == id }) else { return }
            state.drafts[i].include.toggle()
        case .setAll(let include):
            for i in state.drafts.indices { state.drafts[i].include = include }
        case .reset:
            task?.cancel()
            state = MenuImportState()
        }
    }
}
