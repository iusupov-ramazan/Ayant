package kg.ayant.app.ui.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import kg.ayant.app.R
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import kg.ayant.app.domain.AuthValidation
import kg.ayant.app.ui.theme.AyantPrimaryButton
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.SessionViewModel

/**
 * Экран входа. Зеркалит `AuthView.swift`, включая два режима подачи.
 *
 * [presentation] `ROOT` — корень для невошедшего: есть «продолжить как гость».
 * `UPGRADE` — тот же экран ПОВЕРХ приложения для гостя, упёршегося в закрытую
 * функцию: гостевой кнопки нет (он уже гость), зато есть крестик. Экран
 * закрывается сам, как только гость перестал быть гостем — через [onClose].
 */
enum class AuthPresentation { ROOT, UPGRADE }

@Composable
fun AuthScreen(
    session: SessionViewModel,
    presentation: AuthPresentation = AuthPresentation.ROOT,
    onClose: () -> Unit = {},
) {
    val c = AyantTheme.colors
    var tab by remember { mutableIntStateOf(0) } // 0 = sign in, 1 = register
    var name by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    val keyboard = LocalSoftwareKeyboardController.current
    // Подписка, а не чтение `session.isWorking`: у getter'а по `_state.value`
    // композиция не обновляется, и спиннер с ошибкой не появлялись бы.
    val sessionState by session.state.collectAsState()

    // Кнопка активна только на валидной форме — проверки общие с iOS
    // (`AuthValidation` в домене), поэтому пустые поля больше не уходят
    // в Firebase за ошибкой на английском.
    val canSubmit = if (tab == 0) AuthValidation.canSignIn(email, password)
                    else AuthValidation.canRegister(name, email, password)

    // Клавиатура прячется протяжкой по экрану и тапом по фону: на маленьких
    // экранах она перекрывала кнопку входа, а закрыть её было нечем.
    val hideKeyboardOnScroll = remember(keyboard) {
        object : androidx.compose.ui.input.nestedscroll.NestedScrollConnection {
            override fun onPreScroll(
                available: androidx.compose.ui.geometry.Offset,
                source: androidx.compose.ui.input.nestedscroll.NestedScrollSource,
            ): androidx.compose.ui.geometry.Offset {
                if (available.y != 0f) keyboard?.hide()
                return androidx.compose.ui.geometry.Offset.Zero
            }
        }
    }

    // Вход состоялся — гость перестал быть гостем: закрываем экран, под ним
    // уже обновлённый корень.
    if (presentation == AuthPresentation.UPGRADE && !sessionState.isGuest && sessionState.isSignedIn) {
        androidx.compose.runtime.LaunchedEffect(sessionState.user?.id) { onClose() }
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(Color(0xFFFF4D29), Color(0xFFFFB300))))
            .pointerInput(Unit) { detectTapGestures { keyboard?.hide() } },
    ) {
        if (presentation == AuthPresentation.UPGRADE) {
            androidx.compose.material3.IconButton(
                onClick = onClose,
                modifier = Modifier.align(Alignment.TopStart).padding(start = 8.dp, top = 8.dp),
            ) {
                Icon(Icons.Filled.Close,
                     contentDescription = stringResource(R.string.action_close),
                     tint = Color.White)
            }
        }
        Column(
            Modifier
                .fillMaxSize()
                .nestedScroll(hideKeyboardOnScroll)
                .verticalScroll(rememberScrollState())
                .padding(20.dp)
                .padding(top = 48.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("Ayant", fontSize = 64.sp, fontWeight = FontWeight.Black, color = Color.White)
            Text(
                if (presentation == AuthPresentation.UPGRADE) stringResource(R.string.auth_upgrade_tagline)
                else stringResource(R.string.auth_tagline),
                fontSize = 14.sp, fontWeight = FontWeight.Medium,
                color = Color.White.copy(alpha = 0.9f),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
            Spacer(Modifier.height(22.dp))

            Column(
                Modifier
                    .fillMaxWidth()
                    .background(c.surface, RoundedCornerShape(24.dp))
                    .padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                TabRow(selectedTabIndex = tab, containerColor = Color.Transparent, contentColor = c.accent) {
                    Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text(stringResource(R.string.auth_sign_in)) })
                    Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text(stringResource(R.string.auth_register)) })
                }

                if (tab == 1) {
                    val nameHint = AuthValidation.nameHint(name)
                    OutlinedTextField(
                        value = name, onValueChange = { name = it },
                        label = { Text(stringResource(R.string.auth_name)) }, singleLine = true,
                        leadingIcon = { Icon(Icons.Filled.Person, null) },
                        isError = nameHint != null,
                        supportingText = { if (nameHint != null) Text(nameHint) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                val emailHint = AuthValidation.emailHint(email)
                OutlinedTextField(
                    value = email, onValueChange = { email = it },
                    label = { Text(stringResource(R.string.auth_email)) }, singleLine = true,
                    leadingIcon = { Icon(Icons.Filled.Email, null) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    isError = emailHint != null,
                    supportingText = { if (emailHint != null) Text(emailHint) },
                    modifier = Modifier.fillMaxWidth(),
                )
                val passwordHint = if (tab == 1) AuthValidation.passwordHint(password) else null
                OutlinedTextField(
                    value = password, onValueChange = { password = it },
                    label = { Text(stringResource(R.string.auth_password)) }, singleLine = true,
                    leadingIcon = { Icon(Icons.Filled.Lock, null) },
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    isError = passwordHint != null,
                    supportingText = { if (passwordHint != null) Text(passwordHint) },
                    modifier = Modifier.fillMaxWidth(),
                )

                AyantPrimaryButton(
                    text = if (tab == 0) stringResource(R.string.auth_do_sign_in) else stringResource(R.string.auth_create_account),
                    enabled = !sessionState.isWorking && canSubmit,
                    onClick = {
                        keyboard?.hide()
                        if (tab == 0) session.signInEmail(email, password)
                        else session.registerEmail(name, email, password)
                    },
                )

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f).height(1.dp).background(c.hairline))
                    Text("  ${stringResource(R.string.auth_or)}  ", fontSize = 12.sp, color = c.inkSoft)
                    Box(Modifier.weight(1f).height(1.dp).background(c.hairline))
                }

                val ctx = androidx.compose.ui.platform.LocalContext.current
                TextButton(onClick = { session.signInGoogle(ctx) }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.auth_google), fontWeight = FontWeight.SemiBold, color = c.ink)
                }
                // «Продолжить как гость» — только в корне: гостю эта кнопка
                // вернула бы его ровно туда, откуда он пришёл.
                if (presentation == AuthPresentation.ROOT) {
                    TextButton(onClick = { session.continueAsGuest() }, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.auth_guest), color = c.inkSoft)
                    }
                }
                if (sessionState.isWorking) CircularProgressIndicator(Modifier.align(Alignment.CenterHorizontally))
            }
        }
    }

    if (sessionState.errorMessage != null) {
        AlertDialog(
            onDismissRequest = { session.errorMessage = null },
            confirmButton = { TextButton(onClick = { session.errorMessage = null }) { Text(stringResource(R.string.action_ok)) } },
            title = { Text(stringResource(R.string.auth_error)) },
            text = { Text(sessionState.errorMessage ?: "") },
        )
    }
}
