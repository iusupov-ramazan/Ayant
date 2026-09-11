import Foundation

/// Генерация крипто-стойких кодов купонов/подарков.
///
/// Раньше коды были `AYANT-` + 6 hex из префикса UUID (~24 бита) — их можно было
/// перебрать/угадать (важно для подарочных купонов: их забирает любой, кто знает
/// код). Теперь код — 12 символов из безошибочного алфавита (без 0/O/1/I) на базе
/// системного CSPRNG (`SystemRandomNumberGenerator`), ~60 бит энтропии.
///
/// Формат кода не завязан на длину нигде на сервере (сравнение по строгому равенству
/// строки), поэтому старые коды в базе продолжают работать без миграции.
enum CodeGen {
    /// Алфавит Crockford-подобный: без визуально похожих 0/O/1/I.
    private static let alphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")

    /// Крипто-случайный код заданной длины (по умолчанию 12 символов ≈ 60 бит).
    static func secureCode(_ length: Int = 12) -> String {
        var rng = SystemRandomNumberGenerator()   // CSPRNG на платформах Apple
        return String((0..<length).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &rng)] })
    }

    /// Код купона акции (сканируется заведением). Префикс `AYANT-` сохраняет
    /// совместимость с ветвлением сканера (в коде нет двоеточия → это не
    /// `AYANT-CARD:`/`AYANT-PTS:`).
    static func couponCode() -> String { "AYANT-\(secureCode())" }

    /// Код подарочного купона (передаётся по ссылке, забирается один раз).
    static func giftCode() -> String { "GIFT-\(secureCode())" }
}
