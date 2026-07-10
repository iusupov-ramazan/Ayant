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
import kg.ayant.app.ui.theme.AyantPrimaryButton
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.SessionViewModel

@Composable
fun AuthScreen(session: SessionViewModel) {
    val c = AyantTheme.colors
    var tab by remember { mutableIntStateOf(0) } // 0 = sign in, 1 = register
    var name by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }

    Box(
        Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(Color(0xFFFF4D29), Color(0xFFFFB300)))),
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp)
                .padding(top = 48.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("Ayant", fontSize = 64.sp, fontWeight = FontWeight.Black, color = Color.White)
            Text(stringResource(R.string.auth_tagline), fontSize = 14.sp, fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.9f))
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
                    OutlinedTextField(
                        value = name, onValueChange = { name = it },
                        label = { Text(stringResource(R.string.auth_name)) }, singleLine = true,
                        leadingIcon = { Icon(Icons.Filled.Person, null) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
                OutlinedTextField(
                    value = email, onValueChange = { email = it },
                    label = { Text(stringResource(R.string.auth_email)) }, singleLine = true,
                    leadingIcon = { Icon(Icons.Filled.Email, null) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = password, onValueChange = { password = it },
                    label = { Text(stringResource(R.string.auth_password)) }, singleLine = true,
                    leadingIcon = { Icon(Icons.Filled.Lock, null) },
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    modifier = Modifier.fillMaxWidth(),
                )

                AyantPrimaryButton(
                    text = if (tab == 0) stringResource(R.string.auth_do_sign_in) else stringResource(R.string.auth_create_account),
                    enabled = !session.isWorking,
                    onClick = {
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
                TextButton(onClick = { session.continueAsGuest() }, modifier = Modifier.fillMaxWidth()) {
                    Text(stringResource(R.string.auth_guest), color = c.inkSoft)
                }
                if (session.isWorking) CircularProgressIndicator(Modifier.align(Alignment.CenterHorizontally))
            }
        }
    }

    if (session.errorMessage != null) {
        AlertDialog(
            onDismissRequest = { session.errorMessage = null },
            confirmButton = { TextButton(onClick = { session.errorMessage = null }) { Text(stringResource(R.string.action_ok)) } },
            title = { Text(stringResource(R.string.auth_error)) },
            text = { Text(session.errorMessage ?: "") },
        )
    }
}
