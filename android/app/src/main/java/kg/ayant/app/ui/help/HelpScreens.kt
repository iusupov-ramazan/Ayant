package kg.ayant.app.ui.help

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Chat
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.PhotoCamera
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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.core.openUrl
import kg.ayant.app.ui.auth.AyantLinks
import kg.ayant.app.ui.theme.AyantHairline
import kg.ayant.app.ui.theme.AyantSectionHeader
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantGroupCard

// Экраны помощи. Зеркалят `HelpViews.swift`: «О приложении», «Вопросы и
// ответы», «Поддержка». Тексты — те же ключи каталога, что на iOS.

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
    ) { p -> Column(Modifier.fillMaxSize().padding(p).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) { content() } }
}

// MARK: - О приложении

@Composable
fun AboutScreen(onBack: () -> Unit) {
    val c = AyantTheme.colors
    val context = LocalContext.current
    HelpScaffold(stringResource(R.string.help_about), onBack) {
        Text("Ayant", fontSize = 34.sp, fontWeight = FontWeight.Black, color = c.accent)
        Text(stringResource(R.string.about_intro), fontSize = 16.sp, color = c.ink)

        AboutGroup(stringResource(R.string.about_find_title)) {
            MarkdownText(stringResource(R.string.about_find_lead), fontSize = 16.sp)
            Bullet(stringResource(R.string.about_b1_title), stringResource(R.string.about_b1_text))
            Bullet(stringResource(R.string.about_b2_title), stringResource(R.string.about_b2_text))
            Bullet(stringResource(R.string.about_b3_title), stringResource(R.string.about_b3_text))
            Bullet(stringResource(R.string.about_b4_title), stringResource(R.string.about_b4_text))
            Text(stringResource(R.string.about_find_footer), fontSize = 16.sp, color = c.ink)
        }

        AboutGroup(stringResource(R.string.about_bonus_title)) {
            Text(stringResource(R.string.about_bonus_lead), fontSize = 16.sp, color = c.ink)
            Bullet(stringResource(R.string.about_bonus_b1_title), stringResource(R.string.about_bonus_b1_text))
            Bullet(stringResource(R.string.about_bonus_b2_title), stringResource(R.string.about_bonus_b2_text))
            MarkdownText(stringResource(R.string.about_bonus_spend), fontSize = 16.sp)
        }

        Text(stringResource(R.string.about_closing), fontSize = 15.sp, color = c.inkSoft)

        Text(
            stringResource(R.string.help_privacy_policy),
            fontSize = 15.sp, fontWeight = FontWeight.Medium, color = c.accentText,
            modifier = Modifier.padding(top = 4.dp).clickable { context.openUrl(AyantLinks.PRIVACY_POLICY) },
        )
    }
}

@Composable
private fun AboutGroup(title: String, content: @Composable () -> Unit) {
    val c = AyantTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = c.ink)
        content()
    }
}

/** «• **Жирное:** остальное» — как `bullet(_:_:)` на iOS. */
@Composable
private fun Bullet(bold: String, rest: String) {
    val c = AyantTheme.colors
    Text(
        buildAnnotatedString {
            withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append("• "); append(bold) }
            append(" "); append(rest)
        },
        fontSize = 15.sp, color = c.ink,
    )
}

/** Минимальная разметка: `**жирный**` внутри строки каталога. */
@Composable
private fun MarkdownText(text: String, fontSize: androidx.compose.ui.unit.TextUnit) {
    val c = AyantTheme.colors
    Text(markdownBold(text), fontSize = fontSize, color = c.ink)
}

private fun markdownBold(text: String): AnnotatedString = buildAnnotatedString {
    val parts = text.split("**")
    parts.forEachIndexed { i, part ->
        if (i % 2 == 1) withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(part) } else append(part)
    }
}

// MARK: - Вопросы и ответы

@Composable
fun FaqScreen(onBack: () -> Unit) {
    val faqs = listOf(
        stringResource(R.string.help_faq_q1) to stringResource(R.string.help_faq_a1),
        stringResource(R.string.help_faq_q2) to stringResource(R.string.help_faq_a2),
        stringResource(R.string.help_faq_q3) to stringResource(R.string.help_faq_a3),
        stringResource(R.string.help_faq_q4) to stringResource(R.string.help_faq_a4),
        stringResource(R.string.help_faq_q5) to stringResource(R.string.help_faq_a5),
        stringResource(R.string.help_faq_q6) to stringResource(R.string.help_faq_a6),
        stringResource(R.string.help_faq_q7) to stringResource(R.string.help_faq_a7),
    )
    HelpScaffold(stringResource(R.string.help_faq), onBack) {
        Column(Modifier.fillMaxWidth().ayantGroupCard()) {
            faqs.forEachIndexed { i, (q, a) ->
                FaqItem(q, a)
                if (i < faqs.size - 1) AyantHairline(leading = 14)
            }
        }
    }
}

/** Раскрывающийся вопрос — как `DisclosureGroup` на iOS. */
@Composable
private fun FaqItem(q: String, a: String) {
    val c = AyantTheme.colors
    var open by remember { mutableStateOf(false) }
    Column(
        Modifier.fillMaxWidth().clickable { open = !open }.padding(horizontal = 14.dp, vertical = 13.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("❓ $q", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = c.ink, modifier = Modifier.weight(1f))
            Icon(if (open) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null, tint = c.inkSoft, modifier = Modifier.size(20.dp))
        }
        if (open) Text(a, fontSize = 14.sp, color = c.inkSoft, modifier = Modifier.padding(vertical = 4.dp))
    }
}

// MARK: - Поддержка

private const val TELEGRAM_APP = "tg://resolve?domain=bonus_kg_bot"
private const val TELEGRAM_WEB = "https://t.me/bonus_kg_bot"
private const val INSTAGRAM = "https://www.instagram.com/ayant_kg"
private const val WHATSAPP = "https://wa.me/996707266556"
private const val EMAIL = "mailto:ostepp1@gmail.com"

@Composable
fun SupportScreen(onBack: () -> Unit) {
    val c = AyantTheme.colors
    val context = LocalContext.current
    HelpScaffold(stringResource(R.string.help_support), onBack) {
        Text(stringResource(R.string.support_intro), fontSize = 15.sp, color = c.inkSoft)

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            AyantSectionHeader(stringResource(R.string.support_contact_us))
            Column(Modifier.fillMaxWidth().ayantGroupCard()) {
                // Сначала пробуем открыть приложение Telegram (tg://), затем веб как фолбэк.
                SupportRow(
                    Icons.AutoMirrored.Filled.Send,
                    stringResource(R.string.support_telegram_bot),
                    stringResource(R.string.support_telegram_sub),
                ) { context.openWithFallback(TELEGRAM_APP, TELEGRAM_WEB) }
                AyantHairline(leading = 52)
                SupportRow(Icons.Filled.PhotoCamera, "Instagram") { context.openUrl(INSTAGRAM) }
                AyantHairline(leading = 52)
                SupportRow(Icons.Filled.Chat, "WhatsApp") { context.openUrl(WHATSAPP) }
                AyantHairline(leading = 52)
                SupportRow(Icons.Filled.Email, stringResource(R.string.support_email_short)) { context.openUrl(EMAIL) }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            AyantSectionHeader(stringResource(R.string.support_documents))
            Column(Modifier.fillMaxWidth().ayantGroupCard()) {
                SupportRow(Icons.Filled.PanTool, stringResource(R.string.help_privacy_policy)) {
                    context.openUrl(AyantLinks.PRIVACY_POLICY)
                }
            }
        }
    }
}

@Composable
private fun SupportRow(icon: ImageVector, title: String, subtitle: String? = null, onClick: () -> Unit) {
    val c = AyantTheme.colors
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = c.accent, modifier = Modifier.size(26.dp))
        Spacer(Modifier.width(12.dp))
        Column {
            Text(title, fontSize = 16.sp, color = c.ink)
            if (subtitle != null) Text(subtitle, fontSize = 12.sp, color = c.inkSoft)
        }
    }
}

/** Открыть [primary]; если обработчика нет (приложение не установлено) — [fallback]. */
private fun Context.openWithFallback(primary: String, fallback: String) {
    try {
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(primary)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (_: ActivityNotFoundException) {
        openUrl(fallback)
    }
}
