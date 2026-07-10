package kg.ayant.app.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Apartment
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.Contrast
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Storefront
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import kg.ayant.app.R
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.core.Links
import kg.ayant.app.core.shareText
import kg.ayant.app.ui.components.StarRating
import kg.ayant.app.ui.theme.AyantHairline
import kg.ayant.app.ui.theme.AyantIconTile
import kg.ayant.app.ui.theme.AyantScreenTitle
import kg.ayant.app.ui.theme.AyantSectionHeader
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantCard
import kg.ayant.app.ui.theme.ayantGroupCard
import kg.ayant.app.ui.vm.AppViewModel
import kg.ayant.app.ui.vm.SessionViewModel
import androidx.compose.ui.platform.LocalContext

@Composable
fun ProfileScreen(
    app: AppViewModel,
    session: SessionViewModel,
    theme: kg.ayant.app.ui.vm.ThemeViewModel? = null,
    onCoupons: () -> Unit = {},
    onHost: () -> Unit = {},
    onHelp: (String) -> Unit = {},
) {
    val c = AyantTheme.colors
    val context = LocalContext.current
    val coupons: kg.ayant.app.ui.vm.CouponViewModel = androidx.lifecycle.viewmodel.compose.viewModel()
    val username = session.user?.name ?: stringResource(R.string.profile_guest_name)
    var showDelete by remember { mutableStateOf(false) }

    Column(
        Modifier
            .fillMaxSize()
            .background(c.canvas)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .padding(top = 16.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(22.dp),
    ) {
        AyantScreenTitle(stringResource(R.string.title_profile))

        // Profile card
        Row(Modifier.fillMaxWidth().ayantCard(padding = 16), verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier.size(64.dp).clip(RoundedCornerShape(18.dp)).background(c.accentGradient),
                contentAlignment = Alignment.Center,
            ) {
                Text(username.take(1).uppercase(), fontSize = 28.sp, fontWeight = FontWeight.Black, color = Color.White)
            }
            Column(Modifier.padding(start = 14.dp)) {
                Text(username, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = c.ink)
                session.user?.email?.let { Text(it, fontSize = 14.sp, color = c.inkSoft) }
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 2.dp)) {
                    Icon(Icons.Filled.LocationOn, null, tint = c.inkSoft, modifier = Modifier.size(12.dp))
                    Text(" ${app.selectedCity.name}", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = c.inkSoft)
                }
            }
        }

        // My coupons
        Row(
            Modifier.fillMaxWidth().ayantGroupCard().clickable(onClick = onCoupons).padding(horizontal = 14.dp, vertical = 13.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            AyantIconTile(Icons.Filled.ConfirmationNumber, size = 34)
            Text(stringResource(R.string.title_my_coupons), fontSize = 16.sp, color = c.ink, modifier = Modifier.padding(start = 12.dp))
            Spacer(Modifier.weight(1f))
            if (coupons.activeCount > 0) {
                Text(
                    "${coupons.activeCount}", fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Color.White,
                    modifier = Modifier.clip(androidx.compose.foundation.shape.CircleShape).background(c.accent).padding(horizontal = 9.dp, vertical = 3.dp),
                )
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = c.inkSoft, modifier = Modifier.padding(start = 8.dp).size(18.dp))
        }

        // Settings
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            AyantSectionHeader(stringResource(R.string.settings))
            Column(Modifier.fillMaxWidth().ayantGroupCard()) {
                SettingRow(Icons.Filled.Apartment, stringResource(R.string.setting_city), app.selectedCity.name)
                AyantHairline(leading = 60)
                LanguageRow()
                if (theme != null) {
                    AyantHairline(leading = 60)
                    ThemeRow(theme)
                }
            }
        }

        // Host mode
        Row(
            Modifier.fillMaxWidth().ayantGroupCard().clickable(enabled = !session.isGuest, onClick = onHost).padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            AyantIconTile(Icons.Filled.Storefront, filled = true, size = 44)
            Column(Modifier.padding(start = 14.dp).weight(1f)) {
                Text(stringResource(R.string.profile_host_mode), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = c.accent)
                Text(if (session.isGuest) stringResource(R.string.profile_host_guest) else stringResource(R.string.profile_host_sub), fontSize = 13.sp, color = c.inkSoft)
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = c.accent, modifier = Modifier.size(18.dp))
        }

        // My reviews
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            AyantSectionHeader(stringResource(R.string.profile_my_reviews))
            val reviews = app.myReviews()
            if (reviews.isEmpty()) {
                Box(Modifier.fillMaxWidth().ayantGroupCard().padding(16.dp)) {
                    Text(stringResource(R.string.profile_no_reviews), fontSize = 15.sp, color = c.inkSoft)
                }
            } else {
                Column(Modifier.fillMaxWidth().ayantGroupCard()) {
                    reviews.forEachIndexed { i, r ->
                        Column(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 13.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(app.venue(id = r.venueID)?.name ?: stringResource(R.string.venue_section), fontSize = 15.sp, fontWeight = FontWeight.Bold, color = c.ink)
                                Spacer(Modifier.weight(1f))
                                StarRating(rating = r.rating.toDouble(), size = 11)
                            }
                            if (r.text.isNotEmpty()) {
                                Text(r.text, fontSize = 13.sp, color = c.inkSoft, maxLines = 2)
                            }
                        }
                        if (i < reviews.size - 1) AyantHairline(leading = 14)
                    }
                }
            }
        }

        // Referral (card like iOS: icon tile + share action + description)
        if (!session.isGuest) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                AyantSectionHeader(stringResource(R.string.profile_invite_friend))
                Column(
                    Modifier.fillMaxWidth().ayantGroupCard()
                        .clickable {
                            context.shareText(
                                context.getString(R.string.profile_referral_share, Links.referral(app.currentUserID)),
                                "Ayant",
                            )
                        }
                        .padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        AyantIconTile(Icons.Filled.Group, size = 34)
                        Text(stringResource(R.string.profile_share_invite), fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = c.ink, modifier = Modifier.padding(start = 12.dp))
                        Spacer(Modifier.weight(1f))
                        Icon(Icons.Filled.Share, null, tint = c.accent, modifier = Modifier.size(18.dp))
                    }
                    Text(stringResource(R.string.profile_referral_desc), fontSize = 13.sp, color = c.inkSoft)
                }
            }
        }

        // Help
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            AyantSectionHeader(stringResource(R.string.help))
            Column(Modifier.fillMaxWidth().ayantGroupCard()) {
                HelpRow(stringResource(R.string.help_about)) { onHelp("about") }
                AyantHairline(leading = 14)
                HelpRow(stringResource(R.string.help_faq)) { onHelp("faq") }
                AyantHairline(leading = 14)
                HelpRow(stringResource(R.string.help_support)) { onHelp("support") }
            }
        }

        // Account
        Column(Modifier.fillMaxWidth().ayantGroupCard()) {
            AccountRow(Icons.AutoMirrored.Filled.Logout, stringResource(R.string.account_sign_out)) { session.signOut() }
            AyantHairline(leading = 14)
            AccountRow(Icons.Filled.Delete, stringResource(R.string.account_delete)) { showDelete = true }
        }

        Text(stringResource(R.string.app_version), fontSize = 13.sp, color = c.inkSoft, modifier = Modifier.fillMaxWidth(), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
    }

    if (showDelete) {
        AlertDialog(
            onDismissRequest = { showDelete = false },
            title = { Text(stringResource(R.string.account_delete_confirm_title)) },
            text = { Text(stringResource(R.string.account_delete_body)) },
            confirmButton = { TextButton(onClick = { showDelete = false; session.signOut() }) { Text(stringResource(R.string.action_delete), color = Color(0xFFD32F2F)) } },
            dismissButton = { TextButton(onClick = { showDelete = false }) { Text(stringResource(R.string.action_cancel)) } },
        )
    }
}

@Composable
private fun SettingRow(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, value: String) {
    val c = AyantTheme.colors
    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 13.dp), verticalAlignment = Alignment.CenterVertically) {
        AyantIconTile(icon, size = 34)
        Text(title, fontSize = 16.sp, color = c.ink, modifier = Modifier.padding(start = 12.dp))
        Spacer(Modifier.weight(1f))
        Text(value, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = c.inkSoft)
    }
}

@Composable
private fun LanguageRow() {
    val c = AyantTheme.colors
    val context = LocalContext.current
    var open by remember { mutableStateOf(false) }
    val current = kg.ayant.app.core.LocaleUtil.currentLang(context)
    val currentTitle = when (current) { "en" -> "English"; "ky" -> "Кыргызча"; else -> "Русский" }
    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 13.dp), verticalAlignment = Alignment.CenterVertically) {
        AyantIconTile(Icons.Filled.Language, size = 34)
        Text(stringResource(R.string.setting_language), fontSize = 16.sp, color = c.ink, modifier = Modifier.padding(start = 12.dp))
        Spacer(Modifier.weight(1f))
        Box {
            Text(currentTitle, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = c.accent, modifier = Modifier.clickable { open = true })
            androidx.compose.material3.DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                listOf("ru" to "Русский", "en" to "English", "ky" to "Кыргызча").forEach { (code, title) ->
                    androidx.compose.material3.DropdownMenuItem(text = { Text(title) }, onClick = {
                        open = false
                        kg.ayant.app.core.LocaleUtil.setLang(context, code)
                        (context as? android.app.Activity)?.recreate()
                    })
                }
            }
        }
    }
}

@Composable
private fun ThemeRow(theme: kg.ayant.app.ui.vm.ThemeViewModel) {
    val c = AyantTheme.colors
    var open by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 13.dp), verticalAlignment = Alignment.CenterVertically) {
        AyantIconTile(Icons.Filled.Contrast, size = 34)
        Text(stringResource(R.string.setting_theme), fontSize = 16.sp, color = c.ink, modifier = Modifier.padding(start = 12.dp))
        Spacer(Modifier.weight(1f))
        Box {
            Text(theme.theme.title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = c.accent, modifier = Modifier.clickable { open = true })
            androidx.compose.material3.DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                kg.ayant.app.ui.vm.AppTheme.entries.forEach { t ->
                    androidx.compose.material3.DropdownMenuItem(text = { Text(t.title) }, onClick = { theme.set(t); open = false })
                }
            }
        }
    }
}

@Composable
private fun HelpRow(title: String, onClick: () -> Unit) {
    val c = AyantTheme.colors
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, fontSize = 16.sp, color = c.ink, modifier = Modifier.weight(1f))
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = c.inkSoft, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun AccountRow(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 14.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, tint = Color(0xFFD32F2F), modifier = Modifier.size(22.dp))
        Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Color(0xFFD32F2F), modifier = Modifier.padding(start = 12.dp))
    }
}
