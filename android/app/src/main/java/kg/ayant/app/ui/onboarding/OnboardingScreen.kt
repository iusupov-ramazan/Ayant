package kg.ayant.app.ui.onboarding

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.ui.theme.AyantPrimaryButton
import kg.ayant.app.ui.theme.AyantTheme

/** 2-step onboarding: location, notifications. Mirrors OnboardingView (Bishkek only). */
@Composable
fun OnboardingScreen(onFinished: () -> Unit) {
    val c = AyantTheme.colors
    var step by remember { mutableIntStateOf(0) }

    val locationLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { step = 1 }

    val notifLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { onFinished() }

    Column(
        Modifier.fillMaxSize().background(c.canvas),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // Progress dots
        Row(
            Modifier.padding(top = 24.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            for (i in 0 until 2) {
                Box(
                    Modifier
                        .height(8.dp)
                        .width(if (i == step) 22.dp else 8.dp)
                        .background(if (i == step) c.accent else c.hairline, RoundedCornerShape(50))
                )
            }
        }

        if (step == 0) {
            PrePrompt(
                icon = Icons.Filled.LocationOn,
                title = "Включи геолокацию",
                subtitle = "Разреши доступ к локации, чтобы видеть, как далеко заведения от тебя. Без неё всё работает — просто без расстояний.",
                primary = "Разрешить геолокацию",
                secondary = "Не сейчас",
                onPrimary = {
                    locationLauncher.launch(
                        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
                    )
                },
                onSkip = { step = 1 },
            )
        } else {
            PrePrompt(
                icon = Icons.Filled.Notifications,
                title = "Не пропусти новые акции",
                subtitle = "Уведомим, когда сохранённые заведения опубликуют новое предложение. Включить можно позже в настройках.",
                primary = "Включить уведомления",
                secondary = "Позже",
                onPrimary = {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        notifLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                    } else onFinished()
                },
                onSkip = onFinished,
            )
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.ColumnScope.PrePrompt(
    icon: ImageVector,
    title: String,
    subtitle: String,
    primary: String,
    secondary: String,
    onPrimary: () -> Unit,
    onSkip: () -> Unit,
) {
    val c = AyantTheme.colors
    Spacer(Modifier.weight(1f))
    Icon(icon, null, tint = c.accent, modifier = Modifier.size(64.dp))
    Spacer(Modifier.height(20.dp))
    Text(title, fontSize = 22.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold, color = c.ink, textAlign = TextAlign.Center)
    Spacer(Modifier.height(12.dp))
    Text(
        subtitle, fontSize = 16.sp, color = c.inkSoft, textAlign = TextAlign.Center,
        modifier = Modifier.padding(horizontal = 32.dp),
    )
    Spacer(Modifier.weight(1f))
    Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        AyantPrimaryButton(text = primary, onClick = onPrimary)
        TextButton(onClick = onSkip) { Text(secondary, color = c.inkSoft) }
    }
}
