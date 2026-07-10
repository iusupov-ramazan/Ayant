package kg.ayant.app.ui.help

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.core.openUrl
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantCard
import kg.ayant.app.ui.theme.ayantGroupCard

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun HelpScaffold(title: String, onBack: () -> Unit, content: @Composable () -> Unit) {
    val c = AyantTheme.colors
    Scaffold(
        containerColor = c.canvas,
        topBar = {
            TopAppBar(
                title = { Text(title, fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.action_back)) } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = c.canvas, titleContentColor = c.ink),
            )
        },
    ) { p -> Column(Modifier.fillMaxSize().padding(p).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) { content() } }
}

@Composable
fun AboutScreen(onBack: () -> Unit) {
    val c = AyantTheme.colors
    HelpScaffold(stringResource(R.string.help_about), onBack) {
        Text("Ayant", fontSize = 28.sp, fontWeight = FontWeight.Black, color = c.accent)
        Text(stringResource(R.string.help_about_body), fontSize = 15.sp, color = c.ink)
        Column(Modifier.fillMaxWidth().ayantCard()) {
            Text(stringResource(R.string.app_version), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = c.ink)
            Text(stringResource(R.string.help_about_region), fontSize = 13.sp, color = c.inkSoft)
        }
    }
}

@Composable
fun FaqScreen(onBack: () -> Unit) {
    val faqs = listOf(
        stringResource(R.string.faq_q1) to stringResource(R.string.faq_a1),
        stringResource(R.string.faq_q2) to stringResource(R.string.faq_a2),
        stringResource(R.string.faq_q3) to stringResource(R.string.faq_a3),
        stringResource(R.string.faq_q4) to stringResource(R.string.faq_a4),
    )
    HelpScaffold(stringResource(R.string.help_faq), onBack) {
        faqs.forEach { (q, a) -> FaqItem(q, a) }
    }
}

@Composable
private fun FaqItem(q: String, a: String) {
    val c = AyantTheme.colors
    var open by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().ayantGroupCard().clickable { open = !open }.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(q, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = c.ink)
        if (open) Text(a, fontSize = 14.sp, color = c.inkSoft)
    }
}

@Composable
fun SupportScreen(onBack: () -> Unit) {
    val c = AyantTheme.colors
    val context = LocalContext.current
    HelpScaffold(stringResource(R.string.help_support), onBack) {
        Text(stringResource(R.string.support_contact), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = c.ink)
        SupportRow("WhatsApp") { context.openUrl("https://wa.me/996700000000") }
        SupportRow("Telegram") { context.openUrl("https://t.me/ayant_kg") }
        SupportRow("Instagram") { context.openUrl("https://www.instagram.com/ayant_kg") }
        SupportRow(stringResource(R.string.support_email)) { context.openUrl("mailto:support@ayant.kg") }
    }
}

@Composable
private fun SupportRow(title: String, onClick: () -> Unit) {
    val c = AyantTheme.colors
    Text(
        title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = c.ink,
        modifier = Modifier.fillMaxWidth().ayantGroupCard().clickable(onClick = onClick).padding(16.dp),
    )
}
