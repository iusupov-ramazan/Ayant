package kg.ayant.app.domain

import java.security.SecureRandom

/**
 * Генерация крипто-стойких кодов купонов/подарков. Зеркалит iOS `CodeGen.swift`.
 *
 * Раньше коды были `AYANT-`/`GIFT-` + 6–8 hex из префикса UUID (~24–32 бита) — их
 * можно перебрать/угадать (критично для подарочных купонов: их забирает любой, кто
 * знает код). Теперь код — 12 символов из безошибочного алфавита (без 0/O/1/I) на
 * базе [SecureRandom] (CSPRNG), ~60 бит энтропии.
 *
 * Сервер сравнивает код по строгому равенству строки, длина нигде не зашита —
 * старые коды в базе продолжают работать без миграции.
 */
object CodeGen {
    // Алфавит Crockford-подобный: без визуально похожих 0/O/1/I.
    private const val ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
    private val rng = SecureRandom()

    /** Крипто-случайный код заданной длины (по умолчанию 12 символов ≈ 60 бит). */
    fun secureCode(length: Int = 12): String =
        buildString { repeat(length) { append(ALPHABET[rng.nextInt(ALPHABET.length)]) } }

    /** Код купона акции. Префикс `AYANT-` (без двоеточия → не путается с картой/баллами). */
    fun couponCode(): String = "AYANT-${secureCode()}"

    /** Код подарочного купона (передаётся по ссылке, забирается один раз). */
    fun giftCode(): String = "GIFT-${secureCode()}"
}
