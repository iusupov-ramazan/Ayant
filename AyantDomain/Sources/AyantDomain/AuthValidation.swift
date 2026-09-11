import Foundation

/// Проверки полей формы входа/регистрации — чистые, без UI и сети.
///
/// Живут в домене, потому что это ОБЩЕЕ правило: экран на iOS и `AuthScreen.kt`
/// на Android обязаны блокировать одно и то же, иначе на одной платформе
/// пользователь получает серверную ошибку там, где на другой кнопка выключена.
/// Зеркалит `AuthValidation.kt`.
public enum AuthValidation {

    /// Минимальная длина пароля у Firebase Auth — короче он отвечает `weak-password`.
    public static let minPasswordLength = 6
    public static let nameLengthRange = 2...40

    // MARK: Почта

    /// Ровно одна «собака», непустая локальная часть, домен с точкой и доменной
    /// зоной от двух букв. Полный RFC 5322 намеренно не реализуем: задача —
    /// отсечь опечатку до похода в сеть, а не доказать существование адреса.
    public static func isValidEmail(_ raw: String) -> Bool {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !email.contains(" ") else { return false }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let local = parts[0], domain = parts[1]
        guard !local.isEmpty, !domain.isEmpty else { return false }
        guard !local.hasPrefix("."), !local.hasSuffix(".") else { return false }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return false }
        guard let tld = labels.last, tld.count >= 2,
              tld.allSatisfy({ $0.isLetter }) else { return false }
        return true
    }

    /// Нормализованная почта: обрезанная и в нижнем регистре.
    /// Ею логинимся и её же кладём в аккаунт — иначе « User@Mail.ru » и
    /// «user@mail.ru» станут двумя разными пользователями.
    public static func normalizedEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: Имя

    /// Буквы (любой алфавит), пробел, дефис и апостроф. Цифры, эмодзи и знаки
    /// препинания в имени профиля не нужны, а в отзывах и чеках выглядят мусором.
    public static func isValidName(_ raw: String) -> Bool {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard nameLengthRange.contains(name.count) else { return false }
        guard name.contains(where: { $0.isLetter }) else { return false }
        return name.allSatisfy { ch in
            ch.isLetter || ch == " " || ch == "-" || ch == "'" || ch == "’"
        }
    }

    /// Имя без двойных пробелов по краям — то, что уходит в `displayName`.
    public static func normalizedName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Пароль

    public static func isValidPassword(_ raw: String) -> Bool {
        raw.count >= minPasswordLength
    }

    // MARK: Готовность формы

    /// Можно ли отправлять форму входа.
    public static func canSignIn(email: String, password: String) -> Bool {
        isValidEmail(email) && isValidPassword(password)
    }

    /// Можно ли отправлять форму регистрации.
    public static func canRegister(name: String, email: String, password: String) -> Bool {
        isValidName(name) && canSignIn(email: email, password: password)
    }

    // MARK: Подсказки под полями (русские — как и остальные строки домена)

    /// `nil`, пока поле пустое: ошибку показываем только после ввода, чтобы
    /// форма не краснела при открытии экрана.
    public static func emailHint(_ raw: String) -> String? {
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.isEmpty { return nil }
        return isValidEmail(email) ? nil : "Похоже на опечатку: почта вида name@mail.ru"
    }

    public static func nameHint(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return nil }
        if !nameLengthRange.contains(name.count) { return "Имя от 2 до 40 символов" }
        return isValidName(name) ? nil : "Только буквы, пробел и дефис"
    }

    public static func passwordHint(_ raw: String) -> String? {
        if raw.isEmpty { return nil }
        return isValidPassword(raw) ? nil : "Пароль от \(minPasswordLength) символов"
    }
}
