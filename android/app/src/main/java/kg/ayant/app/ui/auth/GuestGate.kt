package kg.ayant.app.ui.auth

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kg.ayant.app.ui.vm.SessionViewModel

/**
 * Тексты отказов гостю. Зеркалит `GuestGate.swift`.
 *
 * Гостя не выкидывают из сессии: экран входа показывается ПОВЕРХ приложения
 * ([GuestAuthSheet]), и после входа корень пересобирается под новый аккаунт.
 */
object GuestGate {
    const val SAVE_VENUE = "Гостям доступен только просмотр. Войдите, чтобы сохранять места."
    const val SAVE_DEAL = "Гостям доступен только просмотр. Войдите, чтобы сохранять предложения."
    const val LIKE = "Войдите, чтобы отмечать предложения — они переедут с вами на другое устройство."
    const val QR = "Личный QR привязан к аккаунту: по нему заведение начисляет баллы. Войдите или создайте аккаунт."
    const val BONUSES = "Баллы, купоны и карты лояльности копятся в аккаунте. Войдите или создайте аккаунт."
    const val GAME = "Награды за игру начисляются в аккаунт. Войдите или создайте аккаунт."
    const val REVIEW = "Отзывы привязаны к аккаунту. Войдите или создайте аккаунт, чтобы оценивать блюда и услуги."
}

/**
 * Стандартный отказ гостю: объяснение + экран входа ПОВЕРХ приложения.
 *
 * Раньше «Войти» звало `session.signOut()` — гость вылетал в корневой экран
 * входа и терял место, где стоял. Теперь показываем [GuestAuthSheet].
 */
@Composable
fun GuestAlert(session: SessionViewModel, message: String, onDismiss: () -> Unit) {
    var showAuth by remember { mutableStateOf(false) }

    if (showAuth) {
        GuestAuthSheet(session) { showAuth = false }
        return
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = { showAuth = true }) { Text("Войти или создать аккаунт") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Не сейчас") } },
        title = { Text("Нужен аккаунт") },
        text = { Text(message) },
    )
}

/**
 * Экран входа поверх приложения — полноэкранный диалог, а не подмена
 * содержимого вкладки: под ним остаётся то, что гость смотрел.
 */
@Composable
fun GuestAuthSheet(session: SessionViewModel, onClose: () -> Unit) {
    Dialog(
        onDismissRequest = onClose,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(Modifier.fillMaxSize()) {
            AuthScreen(session, presentation = AuthPresentation.UPGRADE, onClose = onClose)
        }
    }
}
