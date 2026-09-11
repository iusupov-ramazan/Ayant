package kg.ayant.app.domain

/*
 * Базовые типы, общие для всех фич: время, ошибки, состояние загрузки.
 * Зеркалит `Core.swift` в пакете AyantDomain.
 */

// ── Время ────────────────────────────────────────────────────────────────────

/**
 * Источник «сейчас».
 *
 * Ниже слоя UI нельзя вызывать `System.currentTimeMillis()` напрямую: логика,
 * зависящая от времени (кулдауны, сгорание баллов, свежесть акции), иначе не
 * тестируется без ожидания реального времени. ViewModel/репозиторий получают
 * [Clock] в конструкторе, тест подставляет фиксированное время.
 */
interface Clock {
    val nowMs: Long
}

/** Системное время. Единственное место ниже UI, где берётся реальное время. */
object SystemClock : Clock {
    override val nowMs: Long get() = System.currentTimeMillis()
}

/** Время под контролем теста. */
class FixedClock(override var nowMs: Long) : Clock {
    fun advance(ms: Long) { nowMs += ms }
}

// ── Ошибки ───────────────────────────────────────────────────────────────────

/**
 * Доменная ошибка. Слой данных обязан привести к ней всё, что прилетает от
 * Firebase/сети, — выше слоя Data не должно быть ни `FirebaseFirestoreException`,
 * ни `IOException`.
 *
 * [code] совпадает со строкой ошибки сервера там, где она есть
 * (`insufficient`, `below_min`, …), чтобы UI показывал один и тот же текст
 * и на предсказании клиента, и на реальном ответе.
 */
sealed class AppError(val code: String) {
    /** Нет сети / запрос не дошёл. Единственная ошибка, которую есть смысл повторить. */
    data object Network : AppError("network")
    /** Гость не авторизован (нет токена или он протух). */
    data object Unauthenticated : AppError("unauthenticated")
    /** Правила Firestore запретили операцию. */
    data object PermissionDenied : AppError("permission_denied")
    /** Документа нет. */
    data object NotFound : AppError("not_found")
    /** Сервер вернул свой код ошибки (`insufficient`, `key_reused`, …). */
    data class Server(val serverCode: String) : AppError(serverCode)
    data object Unknown : AppError("unknown")

    /** Имеет ли смысл предлагать «Повторить». */
    val isRetryable: Boolean get() = this is Network
}

// ── Состояние загрузки ───────────────────────────────────────────────────────

/**
 * Загрузка как ОДНО значение, а не россыпь `isLoading` / `error` / `data`.
 *
 * Такие флаги допускают невозможные комбинации (грузим и одновременно ошибка);
 * здесь `when` обязан разобрать все случаи, поэтому забытое состояние — ошибка
 * компиляции, а не пустой экран.
 */
sealed interface LoadState<out T> {
    data object Idle : LoadState<Nothing>
    data object Loading : LoadState<Nothing>
    data class Loaded<T>(val value: T) : LoadState<T>
    data class Failed(val error: AppError) : LoadState<Nothing>

    fun valueOrNull(): T? = (this as? Loaded)?.value
    val isLoading: Boolean get() = this is Loading
    fun errorOrNull(): AppError? = (this as? Failed)?.error
}

/**
 * Обёртка, чтобы доменная [AppError] пролезала через `kotlin.Result`
 * (он умеет носить только `Throwable`). Слой данных заворачивает ошибки сюда,
 * фича достаёт их через [asAppError] — и про Firebase при этом не знает.
 */
class AppErrorException(val error: AppError) : Exception(error.code)

/** Достать доменную ошибку из `Result.failure`. Неизвестное → [AppError.Unknown]. */
fun Throwable.asAppError(): AppError =
    (this as? AppErrorException)?.error ?: AppError.Unknown
