package kg.ayant.app.domain

/**
 * Проверки полей формы входа/регистрации — чистые, без UI и сети.
 *
 * Зеркалит `AuthValidation.swift`: правило общее, иначе на одной платформе
 * пользователь получает серверную ошибку там, где на другой кнопка выключена.
 */
object AuthValidation {

    /** Минимальная длина пароля у Firebase Auth — короче он отвечает `weak-password`. */
    const val MIN_PASSWORD_LENGTH = 6
    val NAME_LENGTH_RANGE = 2..40

    // ── Почта ────────────────────────────────────────────────────────────────

    /**
     * Ровно одна «собака», непустая локальная часть, домен с точкой и доменной
     * зоной от двух букв. Полный RFC 5322 намеренно не реализуем: задача —
     * отсечь опечатку до похода в сеть, а не доказать существование адреса.
     */
    fun isValidEmail(raw: String): Boolean {
        val email = raw.trim()
        if (email.isEmpty() || email.contains(" ")) return false
        val parts = email.split("@")
        if (parts.size != 2) return false
        val (local, domain) = parts
        if (local.isEmpty() || domain.isEmpty()) return false
        if (local.startsWith(".") || local.endsWith(".")) return false
        val labels = domain.split(".")
        if (labels.size < 2 || labels.any { it.isEmpty() }) return false
        val tld = labels.last()
        return tld.length >= 2 && tld.all { it.isLetter() }
    }

    /**
     * Нормализованная почта: обрезанная и в нижнем регистре. Ею логинимся и её же
     * кладём в аккаунт — иначе « User@Mail.ru » и «user@mail.ru» станут двумя
     * разными пользователями.
     */
    fun normalizedEmail(raw: String): String = raw.trim().lowercase()

    // ── Имя ──────────────────────────────────────────────────────────────────

    /**
     * Буквы (любой алфавит), пробел, дефис и апостроф. Цифры, эмодзи и знаки
     * препинания в имени профиля не нужны, а в отзывах и чеках выглядят мусором.
     */
    fun isValidName(raw: String): Boolean {
        val name = raw.trim()
        if (name.length !in NAME_LENGTH_RANGE) return false
        if (name.none { it.isLetter() }) return false
        return name.all { it.isLetter() || it == ' ' || it == '-' || it == '\'' || it == '’' }
    }

    fun normalizedName(raw: String): String = raw.trim()

    // ── Пароль ───────────────────────────────────────────────────────────────

    fun isValidPassword(raw: String): Boolean = raw.length >= MIN_PASSWORD_LENGTH

    // ── Готовность формы ─────────────────────────────────────────────────────

    fun canSignIn(email: String, password: String): Boolean =
        isValidEmail(email) && isValidPassword(password)

    fun canRegister(name: String, email: String, password: String): Boolean =
        isValidName(name) && canSignIn(email, password)

    // ── Подсказки под полями ─────────────────────────────────────────────────

    /**
     * `null`, пока поле пустое: ошибку показываем только после ввода, чтобы
     * форма не краснела при открытии экрана.
     */
    fun emailHint(raw: String): String? {
        val email = raw.trim()
        if (email.isEmpty()) return null
        return if (isValidEmail(email)) null else "Похоже на опечатку: почта вида name@mail.ru"
    }

    fun nameHint(raw: String): String? {
        val name = raw.trim()
        if (name.isEmpty()) return null
        if (name.length !in NAME_LENGTH_RANGE) return "Имя от 2 до 40 символов"
        return if (isValidName(name)) null else "Только буквы, пробел и дефис"
    }

    fun passwordHint(raw: String): String? {
        if (raw.isEmpty()) return null
        return if (isValidPassword(raw)) null else "Пароль от $MIN_PASSWORD_LENGTH символов"
    }
}
