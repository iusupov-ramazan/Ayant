package kg.ayant.app.core

import android.content.Context
import android.icu.text.RelativeDateTimeFormatter
import android.icu.util.ULocale
import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import kg.ayant.app.R
import kg.ayant.app.domain.AuthValidation
import kg.ayant.app.ui.vm.SessionViewModel
import kg.ayant.app.domain.model.AdCampaign
import kg.ayant.app.domain.model.City
import kg.ayant.app.domain.model.DayHours
import kg.ayant.app.domain.model.Deal
import kg.ayant.app.domain.model.DealType
import kg.ayant.app.domain.model.Venue
import kg.ayant.app.domain.model.VenueCategory
import kg.ayant.app.domain.model.VenueItem
import kg.ayant.app.domain.model.VerificationStatus
import kg.ayant.app.ui.vm.AppTheme
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Язык интерфейса (Профиль → Язык): `ru` | `en` | `ky`. Зеркалит `AppLanguage`
 * из `SAN/L10n.swift`.
 *
 * Локаль для дат и чисел — язык ПРИЛОЖЕНИЯ, а не системы: кыргызский раньше
 * выпадал из этой ветки и форматировался по-русски (`Format.kt` жёстко держал
 * `ru_RU`). Код языка сюда кладёт [LocaleUtil] при оборачивании контекста
 * Activity, так что к моменту первой композиции он уже актуален.
 */
object AppLanguage {
    const val DEFAULT = "ru"

    @Volatile var current: String = DEFAULT
        internal set

    val locale: Locale get() = localeFor(current)

    fun localeFor(code: String): Locale = when (code) {
        "en" -> Locale("en", "US")
        "ky" -> Locale("ky", "KG")
        else -> Locale("ru", "RU")
    }

    /**
     * Контекст с ресурсами на языке приложения — для строк вне композиции
     * (форматтеры, уведомления, `Intent.createChooser`). `Application` сам по
     * себе живёт в системной локали, поэтому оборачиваем его так же, как
     * Activity в [LocaleUtil.wrap].
     */
    val context: Context get() = LocaleUtil.wrap(AppConfig.applicationContext)
}

/**
 * Строка каталога на языке приложения для мест, где `stringResource` не годится
 * (не-Composable хелперы, форматирование, `share`). Аналог `LS`/`LF` на iOS.
 */
fun LS(@StringRes id: Int, vararg args: Any): String =
    if (args.isEmpty()) AppLanguage.context.getString(id)
    else AppLanguage.context.getString(id, *args)

/** «2 часа назад» / «2 hours ago» / «2 саат мурун» — в локали приложения. */
fun Date.relativeText(nowMs: Long = System.currentTimeMillis()): String {
    val fmt = RelativeDateTimeFormatter.getInstance(ULocale.forLocale(AppLanguage.locale))
    val diffMs = nowMs - time
    val minutes = diffMs / 60_000
    val hours = minutes / 60
    val days = hours / 24
    return when {
        minutes < 1 -> fmt.format(RelativeDateTimeFormatter.Direction.PLAIN, RelativeDateTimeFormatter.AbsoluteUnit.NOW)
        hours < 1 -> fmt.format(minutes.toDouble(), RelativeDateTimeFormatter.Direction.LAST, RelativeDateTimeFormatter.RelativeUnit.MINUTES)
        days < 1 -> fmt.format(hours.toDouble(), RelativeDateTimeFormatter.Direction.LAST, RelativeDateTimeFormatter.RelativeUnit.HOURS)
        days < 7 -> fmt.format(days.toDouble(), RelativeDateTimeFormatter.Direction.LAST, RelativeDateTimeFormatter.RelativeUnit.DAYS)
        days < 31 -> fmt.format((days / 7).toDouble(), RelativeDateTimeFormatter.Direction.LAST, RelativeDateTimeFormatter.RelativeUnit.WEEKS)
        days < 365 -> fmt.format((days / 30).toDouble(), RelativeDateTimeFormatter.Direction.LAST, RelativeDateTimeFormatter.RelativeUnit.MONTHS)
        else -> fmt.format((days / 365).toDouble(), RelativeDateTimeFormatter.Direction.LAST, RelativeDateTimeFormatter.RelativeUnit.YEARS)
    }
}

// MARK: - Доменные подписи → каталог строк.
//
// Домен (`:domain`) не знает про Android-ресурсы и держит русские `title`;
// показываем их через каталог здесь, на месте отображения — как `L(...)` /
// `locKey` на iOS. Неизвестное значение (категория из Firestore, которой нет в
// списке) остаётся как есть.

@StringRes fun DealType.titleRes(): Int = when (this) {
    DealType.DISCOUNT -> R.string.deal_type_discount
    DealType.PROMO -> R.string.deal_type_promo
    DealType.NOVELTY -> R.string.deal_type_novelty
    DealType.ANNOUNCEMENT -> R.string.deal_type_announcement
}

@Composable fun DealType.localizedTitle(): String = stringResource(titleRes())

/** Бейдж без процента скидки: «СКИДКА» / «ПРОМО» / … Mirrors `DealType.badgeLabel`. */
@StringRes fun DealType.badgeRes(): Int = when (this) {
    DealType.DISCOUNT -> R.string.deal_badge_discount
    DealType.PROMO -> R.string.deal_badge_promo
    DealType.NOVELTY -> R.string.deal_badge_novelty
    DealType.ANNOUNCEMENT -> R.string.deal_badge_announcement
}

fun DealType.badgeLabel(context: Context): String = context.getString(badgeRes())

@Composable fun DealType.badgeLabel(): String = stringResource(badgeRes())

/** Категория заведения: известные — из каталога, прочие — как записаны в Firestore. */
@StringRes fun VenueCategory.titleResOrNull(): Int? = when (rawValue) {
    "Кафе" -> R.string.category_cafe
    "Кофейня" -> R.string.category_coffee
    "Фастфуд" -> R.string.category_fastfood
    "Ресторан" -> R.string.category_restaurant
    "Чайхана" -> R.string.category_teahouse
    "Пекарня" -> R.string.category_bakery
    else -> null
}

fun VenueCategory.localizedName(context: Context): String =
    titleResOrNull()?.let { context.getString(it) } ?: rawValue

@Composable fun VenueCategory.localizedName(): String =
    titleResOrNull()?.let { stringResource(it) } ?: rawValue

@StringRes fun VerificationStatus.titleRes(): Int = when (this) {
    VerificationStatus.NONE -> R.string.verification_none
    VerificationStatus.PENDING -> R.string.verification_pending
    VerificationStatus.VERIFIED -> R.string.verification_verified
    VerificationStatus.REJECTED -> R.string.verification_rejected
}

@Composable fun VerificationStatus.localizedTitle(): String = stringResource(titleRes())

@StringRes fun AdCampaign.Kind.titleRes(): Int = when (this) {
    AdCampaign.Kind.BOOST -> R.string.campaign_kind_boost
    AdCampaign.Kind.PUSH -> R.string.campaign_kind_push
}

@Composable fun AdCampaign.Kind.localizedTitle(): String = stringResource(titleRes())

@StringRes fun AdCampaign.Status.titleRes(): Int = when (this) {
    AdCampaign.Status.SCHEDULED -> R.string.campaign_status_scheduled
    AdCampaign.Status.ACTIVE -> R.string.campaign_status_active
    AdCampaign.Status.SENT -> R.string.campaign_status_sent
    AdCampaign.Status.COMPLETED -> R.string.campaign_status_completed
    AdCampaign.Status.CANCELLED -> R.string.campaign_status_cancelled
}

@Composable fun AdCampaign.Status.localizedTitle(): String = stringResource(titleRes())

@StringRes fun AppTheme.titleRes(): Int = when (this) {
    AppTheme.SYSTEM -> R.string.theme_system
    AppTheme.LIGHT -> R.string.theme_light
    AppTheme.DARK -> R.string.theme_dark
}

@Composable fun AppTheme.localizedTitle(): String = stringResource(titleRes())

/** «Блюдо» / «Услуга» / «Объект» — тип объекта для отзыва. Mirrors `VenueItem.kindTitle`. */
@StringRes fun VenueItem.kindTitleRes(): Int = when (kind) {
    "service" -> R.string.host_item_kind_service
    "other" -> R.string.host_item_kind_other
    else -> R.string.host_item_kind_food
}

@Composable fun VenueItem.localizedKindTitle(): String = stringResource(kindTitleRes())

/** Форма деятельности: значение хранится по-русски (Firestore), показывается через каталог. */
@Composable fun legalFormTitle(raw: String): String = when (raw) {
    "ИП" -> stringResource(R.string.legal_form_ip)
    "ООО" -> stringResource(R.string.legal_form_ooo)
    "Самозанятый" -> stringResource(R.string.legal_form_self)
    "" -> stringResource(R.string.hprofile_not_specified)
    else -> raw
}

/** Понедельник … Воскресенье (0 = понедельник). Mirrors `Venue.weekdayLong`. */
@StringRes fun weekdayLongRes(index: Int): Int = when (index) {
    0 -> R.string.weekday_mon
    1 -> R.string.weekday_tue
    2 -> R.string.weekday_wed
    3 -> R.string.weekday_thu
    4 -> R.string.weekday_fri
    5 -> R.string.weekday_sat
    else -> R.string.weekday_sun
}

/** «09:00 – 22:00» или «Выходной». Mirrors `DayHours.label`. */
@Composable fun DayHours.localizedLabel(): String =
    if (closed) stringResource(R.string.venue_form_dayoff) else "${DayHours.time(open)} – ${DayHours.time(close)}"

/**
 * Локализованный статус часов работы. Доменный `hoursStatusText` — русская
 * строка; здесь тот же смысл через каталог, чтобы в английском интерфейсе не
 * оставалось «Открыто · до 23:00». Mirrors `Venue.hoursStatusKey` on iOS.
 */
@Composable fun Venue.localizedHoursStatus(): String {
    val d = todayHours
    return when {
        d.closed -> stringResource(R.string.hours_day_off_today)
        isOpenNow -> stringResource(R.string.hours_open_until, DayHours.time(d.close))
        else -> stringResource(R.string.status_closed)
    }
}

/**
 * «Заканчивается сегодня» / «Осталось 5 ч» — та же логика, что у доменного
 * `Deal.urgencyText` («сегодня» — по календарю ГОРОДА), но через каталог.
 */
@Composable fun Deal.localizedUrgency(): String? {
    if (!isActive) return null
    val now = Date()
    val c1 = City.calendarForSlug(citySlug).apply { time = validUntil }
    val c2 = City.calendarForSlug(citySlug).apply { time = now }
    val isToday = c1.get(Calendar.YEAR) == c2.get(Calendar.YEAR) &&
        c1.get(Calendar.DAY_OF_YEAR) == c2.get(Calendar.DAY_OF_YEAR)
    if (isToday) return stringResource(R.string.deal_ends_today)
    val h = hoursLeft
    if (h in 1..48) return stringResource(R.string.deal_hours_left, h)
    return null
}

// MARK: - Auth: подсказки под полями и ошибки сессии.
//
// Доменный `AuthValidation` отдаёт русские подсказки; здесь те же правила через
// его чистые предикаты и каталог строк — как `Text(L(hint))` на iOS.

/** `null`, пока поле пустое: ошибку показываем только после ввода. */
@Composable fun authEmailHint(raw: String): String? {
    val email = raw.trim()
    if (email.isEmpty()) return null
    return if (AuthValidation.isValidEmail(email)) null else stringResource(R.string.auth_hint_email)
}

@Composable fun authNameHint(raw: String): String? {
    val name = raw.trim()
    if (name.isEmpty()) return null
    val range = AuthValidation.NAME_LENGTH_RANGE
    if (name.length !in range) return stringResource(R.string.auth_hint_name_length, range.first, range.last)
    return if (AuthValidation.isValidName(name)) null else stringResource(R.string.auth_hint_name_chars)
}

@Composable fun authPasswordHint(raw: String): String? {
    if (raw.isEmpty()) return null
    return if (AuthValidation.isValidPassword(raw)) null
    else stringResource(R.string.auth_hint_password, AuthValidation.MIN_PASSWORD_LENGTH)
}

/** Код из `SessionViewModel.ERROR_*` → текст; всё остальное — сообщение провайдера как есть. */
@Composable fun sessionErrorText(message: String?): String = when (message) {
    null -> ""
    SessionViewModel.ERROR_NETWORK -> stringResource(R.string.session_err_network)
    SessionViewModel.ERROR_SIGN_IN -> stringResource(R.string.session_err_sign_in)
    SessionViewModel.ERROR_DELETE -> stringResource(R.string.account_delete_failed)
    else -> message
}
