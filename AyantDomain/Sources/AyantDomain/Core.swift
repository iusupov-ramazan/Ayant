import Foundation

// Базовые типы, общие для всех фич: время, ошибки, состояние загрузки.
// Зеркалит `Core.kt` в `android/domain`.

// MARK: - Время

/// Источник «сейчас».
///
/// Ниже слоя UI нельзя вызывать `Date()` напрямую: логика, зависящая от времени
/// (кулдауны, сгорание баллов, свежесть акции), иначе не тестируется без ожидания
/// реального времени. Стор/репозиторий получают `Clock` в конструкторе, тест
/// подставляет фиксированное время.
public protocol Clock: Sendable {
    var now: Date { get }
}

/// Системное время. Единственное место ниже UI, где вызывается `Date()`.
public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

/// Время под контролем теста.
public final class FixedClock: Clock, @unchecked Sendable {
    public var now: Date
    public init(_ now: Date) { self.now = now }
    public func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

// MARK: - Ошибки

/// Доменная ошибка. Слой данных обязан привести к ней всё, что прилетает от
/// Firebase/сети, — выше слоя Data не должно быть ни `NSError`, ни `FirebaseError`.
///
/// `code` совпадает со строкой ошибки сервера там, где она есть
/// (`insufficient`, `below_min`, …), чтобы UI показывал один и тот же текст
/// и на предсказании клиента, и на реальном ответе.
public enum AppError: Error, Equatable, Sendable {
    /// Нет сети / запрос не дошёл. Единственная ошибка, которую есть смысл повторить.
    case network
    /// Гость не авторизован (нет токена или он протух).
    case unauthenticated
    /// Правила Firestore запретили операцию.
    case permissionDenied
    /// Документа нет.
    case notFound
    /// Сервер вернул свой код ошибки (`insufficient`, `key_reused`, …).
    case server(code: String)
    case unknown

    public var code: String {
        switch self {
        case .network:          return "network"
        case .unauthenticated:  return "unauthenticated"
        case .permissionDenied: return "permission_denied"
        case .notFound:         return "not_found"
        case .server(let c):    return c
        case .unknown:          return "unknown"
        }
    }

    /// Имеет ли смысл предлагать «Повторить».
    public var isRetryable: Bool { self == .network }
}

// MARK: - Состояние загрузки

/// Загрузка как ОДНО значение, а не россыпь `isLoading` / `error` / `data`.
///
/// Такие флаги допускают невозможные комбинации (грузим и одновременно ошибка);
/// здесь `switch` обязан разобрать все случаи, поэтому забытое состояние — ошибка
/// компиляции, а не пустой экран.
public enum LoadState<T: Equatable & Sendable>: Equatable, Sendable {
    case idle
    case loading
    case loaded(T)
    case failed(AppError)

    public var value: T? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public var error: AppError? {
        if case .failed(let e) = self { return e }
        return nil
    }
}
