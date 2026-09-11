package kg.ayant.app.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Зеркало `DomainAuthValidationTests.swift` — те же случаи, тот же результат. */
class AuthValidationTest {

    @Test fun `accepts ordinary addresses`() {
        listOf("user@mail.ru", "a.b-c@sub.domain.kg", "ЮЗЕР@почта.рф", " User@Mail.RU ")
            .forEach { assertTrue(it, AuthValidation.isValidEmail(it)) }
    }

    @Test fun `rejects address without at or dot`() {
        listOf("", "abc", "a@", "@mail.ru", "a@b", "a b@mail.ru", "a@@mail.ru",
               "a@mail.", "a@.ru", "a@mail.r")
            .forEach { assertFalse(it, AuthValidation.isValidEmail(it)) }
    }

    @Test fun `normalized email trims and lowercases`() {
        assertEquals("user@mail.ru", AuthValidation.normalizedEmail("  User@Mail.RU "))
    }

    @Test fun `accepts human names`() {
        listOf("Аяна", "Иван Петров", "Жийде-Айым", "O'Brian", "Ai")
            .forEach { assertTrue(it, AuthValidation.isValidName(it)) }
    }

    @Test fun `rejects digits symbols and emoji`() {
        listOf("", "A", "Иван228", "user_name", "🙂🙂", "<script>", "Иван!", "а".repeat(41))
            .forEach { assertFalse(it, AuthValidation.isValidName(it)) }
    }

    @Test fun `password needs six characters`() {
        assertFalse(AuthValidation.isValidPassword("12345"))
        assertTrue(AuthValidation.isValidPassword("123456"))
    }

    @Test fun `empty form cannot be submitted`() {
        assertFalse(AuthValidation.canSignIn("", ""))
        assertFalse(AuthValidation.canSignIn("user@mail.ru", ""))
        assertFalse(AuthValidation.canSignIn("", "123456"))
        assertTrue(AuthValidation.canSignIn("user@mail.ru", "123456"))
    }

    @Test fun `registration also needs valid name`() {
        assertFalse(AuthValidation.canRegister("", "user@mail.ru", "123456"))
        assertFalse(AuthValidation.canRegister("Иван1", "user@mail.ru", "123456"))
        assertTrue(AuthValidation.canRegister("Иван", "user@mail.ru", "123456"))
    }

    @Test fun `hints stay silent until something is typed`() {
        assertNull(AuthValidation.emailHint(""))
        assertNull(AuthValidation.nameHint("  "))
        assertNull(AuthValidation.passwordHint(""))
        assertNotNull(AuthValidation.emailHint("abc"))
        assertNotNull(AuthValidation.nameHint("Иван228"))
        assertNotNull(AuthValidation.passwordHint("123"))
    }
}
