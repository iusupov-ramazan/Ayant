import Foundation
import AyantDomain

/// Удалённые настройки приложения: выключатели функций, начисление за игры и
/// экран «Обновите приложение».
///
/// Всё применяется сразу, как только пришли новые значения: при запуске, при
/// возврате в приложение (`refresh`) и в реальном времени, пока приложение
/// открыто (`listen`). Раньше выключатели функций ждали следующего
/// холодного запуска — для аварийного выключателя это слишком долго:
/// хозяин публикует `false`, а функция видна ещё часами.
@MainActor
public final class RemoteSettingsStore: ObservableObject {
    @Published public private(set) var latest: RemoteSettings
    @Published public private(set) var updateRequired: Bool

    private let service: RemoteConfigService
    private let currentVersion: String

    public init(service: RemoteConfigService, currentVersion: String) {
        self.service = service
        self.currentVersion = currentVersion
        let cached = service.current()
        latest = cached
        updateRequired = cached.requiresUpdate(currentVersion: currentVersion)
    }

    /// Загрузить свежие значения (на старте и при возврате в приложение).
    /// Провал загрузки ничего не меняет — в том числе не снимает уже
    /// показанный экран обновления.
    public func refresh() async {
        guard let fresh = await service.refresh() else { return }
        apply(fresh)
    }

    /// Слушать публикации в реальном времени, пока жива задача.
    public func listen() async {
        for await fresh in service.updates() { apply(fresh) }
    }

    private func apply(_ fresh: RemoteSettings) {
        if latest != fresh { latest = fresh }
        let required = fresh.requiresUpdate(currentVersion: currentVersion)
        if updateRequired != required { updateRequired = required }
    }
}
