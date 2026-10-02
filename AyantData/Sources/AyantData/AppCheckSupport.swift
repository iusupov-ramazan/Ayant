import Foundation
import FirebaseCore
import FirebaseAppCheck

/// App Check для денежных путей.
///
/// Наши функции — `onRequest`, а не callable: автоматический App Check Firebase
/// их не покрывает, и сервер разбирает заголовок `X-Firebase-AppCheck` сам
/// (`checkAppCheck` в `functions/src/index.ts`, режим — env `APPCHECK_MODE`).
/// Пока клиент заголовок не слал, `enforce` нельзя было включить вовсе: он
/// отрезал бы всех настоящих пользователей. Теперь — порядок раскатки
/// off → monitor → enforce одним env-флагом на сервере.
///
/// Без App Check потолки `earnBonus` — единственное, что отделяет скрипт с
/// настоящим аккаунтом от бонусов, на которые заведения отдают товар.
public enum AyantAppCheck {
    /// Заголовок, который читает сервер.
    public static let header = "X-Firebase-AppCheck"

    /// Провайдер — СТРОГО до `FirebaseApp.configure()`, иначе SDK возьмёт
    /// провайдер по умолчанию.
    ///
    /// DeviceCheck, а не App Attest: ему не нужен entitlement и отдельная
    /// возможность в профиле подписи — сборка не сломается из-за профиля.
    /// В Firebase Console → App Check для iOS-приложения нужно зарегистрировать
    /// DeviceCheck-ключ (.p8). В отладке — debug-провайдер: токен печатается в
    /// консоль Xcode при первом запуске, его регистрируют там же, иначе
    /// симулятор в режиме `enforce` получит 401.
    public static func install() {
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(DeviceCheckProviderFactory())
        #endif
    }

    /// Текущий токен или `nil` (мок-режим без Firebase, провайдер недоступен).
    ///
    /// Без токена запрос всё равно уходит: при `APPCHECK_MODE=off|monitor`
    /// сервер его пропустит, а при `enforce` ответит понятным 401
    /// `app_check_failed` — так же, как ответил бы на запрос скрипта.
    public static func token() async -> String? {
        guard FirebaseApp.app() != nil else { return nil }
        return try? await AppCheck.appCheck().token(forcingRefresh: false).token
    }
}

public extension URLRequest {
    /// Прикладывает App Check к запросу в Cloud Function.
    mutating func attachAppCheck() async {
        if let token = await AyantAppCheck.token() {
            setValue(token, forHTTPHeaderField: AyantAppCheck.header)
        }
    }
}
