package kg.ayant.app.ui.auth

import androidx.annotation.StringRes
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kg.ayant.app.R
import kg.ayant.app.ui.vm.SessionViewModel

/**
 * Тексты отказов гостю. Зеркалит `GuestGate.swift`.
 *
 * Гостя не выкидывают из сессии: экран входа показывается ПОВЕРХ приложения
 * ([GuestAuthSheet]), и после входа корень пересобирается под новый аккаунт.
 */
object GuestGate {
    // Ресурсы, а не строки: текст берётся из каталога на языке приложения.
    @StringRes val SAVE_VENUE = R.string.guest_save_venue
    @StringRes val SAVE_DEAL = R.string.guest_save_deal
    @StringRes val LIKE = R.string.guest_like
    @StringRes val QR = R.string.guest_qr
    @StringRes val BONUSES = R.string.guest_bonuses
    @StringRes val GAME = R.string.guest_game
    @StringRes val REVIEW = R.string.guest_review
}

/**
 * Стандартный отказ гостю: объяснение + экран входа ПОВЕРХ приложения.
 *
 * Раньше «Войти» звало `session.signOut()` — гость вылетал в корневой экран
 * входа и терял место, где стоял. Теперь показываем [GuestAuthSheet].
 */
@Composable
fun GuestAlert(session: SessionViewModel, @StringRes message: Int, onDismiss: () -> Unit) {
    var showAuth by remember { mutableStateOf(false) }

    if (showAuth) {
        GuestAuthSheet(session) { showAuth = false }
        return
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(onClick = { showAuth = true }) { Text(stringResource(R.string.guest_sign_in_or_create)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.onb_not_now)) } },
        title = { Text(stringResource(R.string.guest_need_account)) },
        text = { Text(stringResource(message)) },
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
