package kg.ayant.app.ui.bonus

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import kg.ayant.app.R
import kg.ayant.app.data.model.Coupon
import kg.ayant.app.ui.components.QrCode
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.CouponViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MyCouponsScreen(onBack: () -> Unit, onCoupon: (String) -> Unit) {
    val c = AyantTheme.colors
    val vm: CouponViewModel = viewModel()
    val available = vm.coupons.filter { !it.used }
    val used = vm.coupons.filter { it.used }

    Scaffold(
        containerColor = c.canvas,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.title_my_coupons), fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.action_back)) } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = c.canvas, titleContentColor = c.ink),
            )
        },
    ) { padding ->
        if (vm.coupons.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(32.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.ConfirmationNumber, null, tint = c.accent, modifier = Modifier.size(48.dp))
                    Text(stringResource(R.string.coupon_empty_title), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = c.ink)
                    Text(stringResource(R.string.coupon_empty_body), fontSize = 14.sp, color = c.inkSoft)
                }
            }
        } else {
            LazyColumn(Modifier.fillMaxSize().padding(padding), contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (available.isNotEmpty()) {
                    item { Text(stringResource(R.string.coupon_available, available.size), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = c.inkSoft) }
                    items(available, key = { it.id }) { CouponRow(it, onCoupon) }
                }
                if (used.isNotEmpty()) {
                    item { Text(stringResource(R.string.coupon_used_section, used.size), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = c.inkSoft) }
                    items(used, key = { it.id }) { CouponRow(it, onCoupon) }
                }
            }
        }
    }
}

@Composable
private fun CouponRow(coupon: Coupon, onCoupon: (String) -> Unit) {
    val c = AyantTheme.colors
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(c.surface).border(0.5.dp, c.hairline, RoundedCornerShape(16.dp)).clickable { onCoupon(coupon.id) },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.width(62.dp).height(88.dp).background(
                if (coupon.used) Brush.verticalGradient(listOf(Color(0xFFBDBDBD), Color(0xFF9E9E9E)))
                else Brush.verticalGradient(listOf(Color(0xFFFF4D29), Color(0xFFFFB300)))
            ),
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.Filled.ConfirmationNumber, null, tint = Color.White, modifier = Modifier.size(24.dp)) }
        Column(Modifier.padding(horizontal = 14.dp, vertical = 12.dp).weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(coupon.title, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = c.ink, maxLines = 2)
            if (coupon.venueName.isNotEmpty()) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.LocationOn, null, tint = c.inkSoft, modifier = Modifier.size(12.dp))
                    Text(" ${coupon.venueName}", fontSize = 12.sp, color = c.inkSoft, maxLines = 1)
                }
            }
            StatusPill(coupon.used)
        }
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = c.inkSoft, modifier = Modifier.padding(end = 14.dp).size(18.dp))
    }
}

@Composable
private fun StatusPill(used: Boolean) {
    val color = if (used) AyantTheme.colors.inkSoft else AyantTheme.colors.open
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(color.copy(alpha = 0.14f)).padding(horizontal = 8.dp, vertical = 3.dp),
    ) {
        Icon(Icons.Filled.CheckCircle, null, tint = color, modifier = Modifier.size(11.dp))
        Text(" " + (if (used) stringResource(R.string.coupon_status_used) else stringResource(R.string.coupon_status_active)), fontSize = 11.sp, fontWeight = FontWeight.Bold, color = color)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CouponDetailScreen(couponID: String, onBack: () -> Unit) {
    val c = AyantTheme.colors
    val vm: CouponViewModel = viewModel()
    val coupon = vm.coupon(couponID) ?: run {
        Box(Modifier.fillMaxSize().background(c.canvas), contentAlignment = Alignment.Center) { Text(stringResource(R.string.coupon_not_found)) }
        return
    }
    var confirmUse by remember { mutableStateOf(false) }
    val isUsed = coupon.used

    Scaffold(
        containerColor = c.canvas,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.title_coupon), fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.action_back)) } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = c.canvas, titleContentColor = c.ink),
            )
        },
    ) { padding ->
        Column(
            Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Ticket
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(26.dp))) {
                Column(
                    Modifier.fillMaxWidth().background(
                        if (isUsed) Brush.linearGradient(listOf(Color(0xFF9E9E9E), Color(0xFFBDBDBD)))
                        else Brush.linearGradient(listOf(Color(0xFFFF4D29), Color(0xFFFFB300)))
                    ).padding(horizontal = 20.dp, vertical = 22.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text(if (isUsed) stringResource(R.string.coupon_badge_used) else stringResource(R.string.coupon_badge_active), fontSize = 12.sp, fontWeight = FontWeight.Black, color = Color.White)
                    Text(coupon.title, fontSize = 22.sp, fontWeight = FontWeight.Black, color = Color.White)
                    if (coupon.venueName.isNotEmpty()) Text(coupon.venueName, fontSize = 14.sp, color = Color.White)
                }
                Column(Modifier.fillMaxWidth().background(c.surface).padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    QrCode(coupon.code, size = 200)
                    Text(stringResource(R.string.coupon_code_label), fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = c.inkSoft)
                    Text(coupon.code, fontSize = 20.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, color = c.ink)
                }
            }

            when {
                isUsed -> Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.CheckCircle, null, tint = c.open, modifier = Modifier.size(20.dp))
                    Text(" " + stringResource(R.string.coupon_used_msg), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = c.open)
                }
                coupon.isVenueBound -> Text(stringResource(R.string.coupon_show_qr_hint), fontSize = 13.sp, color = c.inkSoft)
                else -> Text(
                    stringResource(R.string.coupon_use), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Color.White,
                    modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(c.accent).clickable { confirmUse = true }.padding(vertical = 15.dp),
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                )
            }
        }
    }

    if (confirmUse) {
        AlertDialog(
            onDismissRequest = { confirmUse = false },
            title = { Text(stringResource(R.string.coupon_use_confirm_title)) },
            text = { Text(stringResource(R.string.coupon_use_confirm_body)) },
            confirmButton = { TextButton(onClick = { confirmUse = false; vm.markUsed(coupon) }) { Text(stringResource(R.string.coupon_use_confirm_yes)) } },
            dismissButton = { TextButton(onClick = { confirmUse = false }) { Text(stringResource(R.string.action_cancel)) } },
        )
    }
}
