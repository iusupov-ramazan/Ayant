package kg.ayant.app.ui.bonus

import android.app.Activity
import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.PathFillType
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.core.AppLanguage
import kg.ayant.app.core.shareText
import kg.ayant.app.domain.model.Coupon
import kg.ayant.app.ui.components.QrCode
import kg.ayant.app.ui.theme.AyantHairline
import kg.ayant.app.ui.theme.AyantIconTile
import kg.ayant.app.ui.theme.AyantPrimaryButton
import kg.ayant.app.ui.theme.AyantRadius
import kg.ayant.app.ui.theme.AyantShadow
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.AyantTiming
import kg.ayant.app.ui.theme.ayantCard
import kg.ayant.app.ui.theme.ayantRise
import kg.ayant.app.ui.theme.ayantRisoHatch
import kg.ayant.app.ui.theme.ayantScreenEnter
import kg.ayant.app.ui.theme.ayantShadow
import kg.ayant.app.ui.vm.CouponViewModel
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat

/*
 * Купоны: список, билет-купон и лист «подарок готов». Mirrors the SwiftUI
 * views in `CouponStore.swift` (MyCouponsView, CouponTicketCard,
 * CouponDetailView, GiftShareSheet).
 */

// MARK: - Форма билета: скруглённый прямоугольник с вырезами на перфорации
//
// Два полукруглых выреза лежат на линии перфорации. `vertical` — линия
// вертикальная (x = cut), вырезы сверху и снизу (карточка в списке); иначе
// линия горизонтальная (y = cut), вырезы слева и справа (билет на экране
// купона). Круги наполовину торчат за край, поэтому путь — even-odd: тогда
// пересечение с прямоугольником вычитается.

private class TicketShape(
    private val cut: Dp,
    private val vertical: Boolean,
    private val notchRadius: Dp,
    private val cornerRadius: Dp,
) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline {
        val path = Path().apply {
            fillType = PathFillType.EvenOdd
            val corner = with(density) { cornerRadius.toPx() }
            addRoundRect(RoundRect(Rect(Offset.Zero, size), CornerRadius(corner)))
            val r = with(density) { notchRadius.toPx() }
            val c = with(density) { cut.toPx() }
            if (vertical) {
                addOval(Rect(Offset(c, 0f), r))
                addOval(Rect(Offset(c, size.height), r))
            } else {
                addOval(Rect(Offset(0f, c), r))
                addOval(Rect(Offset(size.width, c), r))
            }
        }
        return Outline.Generic(path)
    }
}

// MARK: - Общий вид купона (подписи вида, глиф, «погашенный» градиент)

private object CouponLook {
    /** Подпись под названием: откуда взялся купон. */
    @Composable
    fun kindLabel(kind: String): String = stringResource(
        when (kind) {
            "loyalty" -> R.string.coupon_kind_loyalty
            "deal" -> R.string.coupon_kind_deal
            "gift" -> R.string.coupon_kind_gift
            else -> R.string.coupon_kind_bonus
        }
    )

    /** Что показать на корешке: эмодзи по виду или инициал заведения. */
    fun glyph(coupon: Coupon): String = when (coupon.kind) {
        "loyalty" -> "🎁"
        "deal" -> "🎟"
        else -> coupon.venueName.trim().firstOrNull()?.uppercase() ?: "🎟"
    }

    /** Приглушённый тёплый серый — для использованных купонов. */
    val usedGradient: Brush = Brush.linearGradient(listOf(Color(0xFFB5ADA4), Color(0xFF8E867E)))

    @Composable
    fun gradient(used: Boolean): Brush = if (used) usedGradient else AyantTheme.colors.accentGradient

    /** «3 активных купона» — склонение по последним цифрам. */
    @Composable
    fun activeText(n: Int): String =
        if (n == 0) stringResource(R.string.coupons_active_none)
        else pluralStringResource(R.plurals.coupons_active_count, n, n)
}

// MARK: - Мои купоны

/**
 * Список купонов. Открывается пушем из профиля и с экрана бонусов; системную
 * панель без заголовка — ради редакторского заголовка в теле.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MyCouponsScreen(vm: CouponViewModel, onBack: () -> Unit, onCoupon: (String) -> Unit) {
    val c = AyantTheme.colors
    val coupons by vm.coupons.collectAsState()
    val available = coupons.filter { !it.used }
    val used = coupons.filter { it.used }

    Scaffold(
        containerColor = c.canvas,
        topBar = {
            TopAppBar(
                title = {},
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.action_back), tint = c.ink) } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = c.canvas),
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            // Заголовок
            Column(
                Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 8.dp).ayantScreenEnter(),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    stringResource(R.string.coupons_title),
                    fontSize = 44.sp, fontWeight = FontWeight.Black,
                    letterSpacing = (-2.5).sp, lineHeight = 41.sp, color = c.ink,
                )
                var subtitle = CouponLook.activeText(available.size)
                if (used.isNotEmpty()) subtitle += stringResource(R.string.coupons_used_suffix, used.size)
                Text(subtitle, fontSize = 14.sp, lineHeight = 20.sp, color = c.inkSoft)
            }

            if (coupons.isEmpty()) {
                EmptyCoupons(Modifier.padding(horizontal = 20.dp))
            } else {
                if (available.isNotEmpty()) {
                    CouponSection(stringResource(R.string.coupons_section_active), available, startIndex = 0, onCoupon = onCoupon)
                }
                if (used.isNotEmpty()) {
                    CouponSection(stringResource(R.string.coupons_section_used), used, startIndex = available.size, onCoupon = onCoupon)
                }
            }
        }
    }
}

@Composable
private fun CouponSection(title: String, items: List<Coupon>, startIndex: Int, onCoupon: (String) -> Unit) {
    val c = AyantTheme.colors
    Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            "${title.uppercase()} · ${items.size}",
            fontSize = 11.5.sp, fontWeight = FontWeight.Black, letterSpacing = 1.2.sp,
            color = c.inkSoft, modifier = Modifier.padding(start = 4.dp),
        )
        items.forEachIndexed { index, coupon ->
            CouponTicketCard(
                coupon = coupon,
                modifier = Modifier
                    .ayantRise(startIndex + index, key = coupon.id,
                        staggerMs = AyantTiming.DEAL_ROW_STAGGER_MS, durationMs = AyantTiming.DEAL_ROW_RISE_MS)
                    .alpha(if (coupon.used) 0.6f else 1f)
                    .clickable { onCoupon(coupon.id) },
            )
        }
    }
}

@Composable
private fun EmptyCoupons(modifier: Modifier = Modifier) {
    val c = AyantTheme.colors
    Column(
        modifier.fillMaxWidth().ayantCard(padding = 24, radius = 26),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("🎟", fontSize = 52.sp)
        Text(stringResource(R.string.coupons_empty_title), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = c.ink)
        Text(
            stringResource(R.string.coupons_empty_body),
            fontSize = 14.sp, lineHeight = 20.sp, color = c.inkSoft, textAlign = TextAlign.Center,
        )
    }
}

// MARK: - Карточка-билет в списке

/**
 * Корешок слева (градиент + глиф), перфорация, справа — название, заведение,
 * вид купона, код и статус.
 */
@Composable
fun CouponTicketCard(coupon: Coupon, modifier: Modifier = Modifier) {
    val c = AyantTheme.colors
    val stubWidth = 76.dp
    val shape = remember { TicketShape(cut = stubWidth, vertical = true, notchRadius = 9.dp, cornerRadius = AyantRadius.card) }
    Row(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(c.surface)
            .border(0.5.dp, c.hairline, shape)
            .heightIn(min = 96.dp),
    ) {
        // Корешок
        Box(
            Modifier
                .width(stubWidth)
                .fillMaxSize()
                .heightIn(min = 96.dp)
                .background(CouponLook.gradient(coupon.used))
                .ayantRisoHatch(alpha = 0.14f),
            contentAlignment = Alignment.Center,
        ) {
            // Эмодзи цвет игнорируют, инициал становится белым — один стиль на оба.
            Text(CouponLook.glyph(coupon), fontSize = 26.sp, fontWeight = FontWeight.Black, color = Color.White)
            DashedLine(
                vertical = true, color = Color.White.copy(alpha = 0.7f), stroke = 1.5.dp, dash = 4.dp,
                modifier = Modifier.align(Alignment.CenterEnd).width(1.5.dp).fillMaxSize().padding(vertical = 12.dp),
            )
        }
        Column(
            Modifier.weight(1f).padding(horizontal = 14.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                coupon.title, fontSize = 15.sp, fontWeight = FontWeight.Bold,
                letterSpacing = (-0.2).sp, color = c.ink, maxLines = 2, overflow = TextOverflow.Ellipsis,
            )
            if (coupon.venueName.isNotEmpty()) {
                Text(coupon.venueName, fontSize = 12.5.sp, fontWeight = FontWeight.Medium, color = c.inkSoft, maxLines = 1)
            }
            Text(CouponLook.kindLabel(coupon.kind), fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold, color = c.accentText, maxLines = 1)
            Row(Modifier.fillMaxWidth().padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    coupon.code, fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold,
                    fontFamily = FontFamily.Monospace, color = c.inkSoft, maxLines = 1,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false),
                )
                Spacer(Modifier.width(8.dp).weight(1f))
                CouponStatusPill(used = coupon.used)
            }
        }
    }
}

/** Пунктирная линия перфорации. */
@Composable
private fun DashedLine(vertical: Boolean, color: Color, stroke: Dp, dash: Dp, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val effect = PathEffect.dashPathEffect(floatArrayOf(dash.toPx(), dash.toPx()))
        if (vertical) {
            drawLine(color, Offset(size.width / 2, 0f), Offset(size.width / 2, size.height), stroke.toPx(), pathEffect = effect)
        } else {
            drawLine(color, Offset(0f, size.height / 2), Offset(size.width, size.height / 2), stroke.toPx(), pathEffect = effect)
        }
    }
}

/** Пилюля статуса купона (активен / использован). */
@Composable
fun CouponStatusPill(used: Boolean) {
    val c = AyantTheme.colors
    val tint = if (used) c.inkSoft else c.open
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        modifier = Modifier
            .clip(CircleShape)
            .background(if (used) c.surfaceMuted else c.open.copy(alpha = 0.12f))
            .padding(horizontal = 9.dp, vertical = 4.dp),
    ) {
        Icon(if (used) Icons.Filled.Verified else Icons.Filled.CheckCircle, null, tint = tint, modifier = Modifier.size(11.dp))
        Text(
            if (used) stringResource(R.string.coupon_status_used) else stringResource(R.string.coupon_status_active),
            fontSize = 10.5.sp, fontWeight = FontWeight.Black, letterSpacing = 0.2.sp, color = tint,
        )
    }
}

// MARK: - Подарок готов (картинка купона + текст для шаринга)

/** Картинка-купон для шаринга (на iOS рендерится в UIImage, здесь — превью в листе). */
@Composable
private fun GiftCardImage(title: String) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Brush.linearGradient(listOf(Color(0xFFFF4D29), Color(0xFFFFB300))))
            .padding(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text("🎁", fontSize = 56.sp)
        Text(stringResource(R.string.gift_card_eyebrow), fontSize = 15.sp, fontWeight = FontWeight.Black, letterSpacing = 2.sp, color = Color.White)
        Text(title, fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Color.White, textAlign = TextAlign.Center)
        Text(
            stringResource(R.string.gift_card_hint), fontSize = 14.sp,
            color = Color.White.copy(alpha = 0.95f), textAlign = TextAlign.Center,
        )
    }
}

/** «Подарок готов!» — лист с картинкой купона и кнопкой «Поделиться». */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GiftShareSheet(code: String, title: String, onDismiss: () -> Unit) {
    val c = AyantTheme.colors
    val context = LocalContext.current
    val caption = stringResource(R.string.bonus_gift_share, title, code)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = c.canvas,
    ) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            GiftCardImage(title)
            Text(stringResource(R.string.gift_ready_title), fontSize = 22.sp, fontWeight = FontWeight.Bold, color = c.ink)
            Text(
                stringResource(R.string.gift_ready_body), fontSize = 14.sp, color = c.inkSoft,
                textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 16.dp),
            )
            Row(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(c.accent)
                    .clickable { context.shareText(caption, "Ayant") }
                    .padding(vertical = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Share, null, tint = Color.White, modifier = Modifier.size(18.dp))
                Text(stringResource(R.string.action_share), fontSize = 17.sp, fontWeight = FontWeight.Bold, color = Color.White)
            }
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_done), color = c.accentText) }
        }
    }
}

// MARK: - Купон (показать сотруднику)

/**
 * Билет: градиентная шапка, перфорация с вырезами, белое тело с QR и кодом.
 * Открывается пушем из списка и со страницы акции.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CouponDetailScreen(couponID: String, vm: CouponViewModel, onBack: () -> Unit) {
    val c = AyantTheme.colors
    val coupons by vm.coupons.collectAsState()
    val coupon = coupons.firstOrNull { it.id == couponID } ?: run {
        Box(Modifier.fillMaxSize().background(c.canvas), contentAlignment = Alignment.Center) { Text(stringResource(R.string.coupon_not_found)) }
        return
    }
    var showUseConfirm by remember { mutableStateOf(false) }
    val isUsed = coupon.used

    // Ярче — легче сканировать; яркость возвращаем, когда экран закрыт.
    val context = LocalContext.current
    DisposableEffect(isUsed) {
        val window = (context as? Activity)?.window
        val previous = window?.attributes?.screenBrightness
        if (!isUsed && window != null) {
            window.attributes = window.attributes.apply { screenBrightness = 1f }
        }
        onDispose {
            if (window != null && previous != null) {
                window.attributes = window.attributes.apply { screenBrightness = previous }
            }
        }
    }

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
            Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(top = 8.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Ticket(coupon = coupon, isUsed = isUsed)

            // Действия под билетом
            when {
                isUsed -> UsedState()
                coupon.isVenueBound -> InfoRow(Icons.Filled.QrCodeScanner, stringResource(R.string.coupon_show_qr_hint))
                else -> Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    InfoRow(Icons.Filled.Info, stringResource(R.string.coupon_info_show_screen))
                    AyantPrimaryButton(stringResource(R.string.coupon_use), onClick = { showUseConfirm = true })
                }
            }
        }
    }

    if (showUseConfirm) {
        AlertDialog(
            onDismissRequest = { showUseConfirm = false },
            title = { Text(stringResource(R.string.coupon_use_confirm_title)) },
            text = { Text(stringResource(R.string.coupon_use_confirm_body)) },
            confirmButton = { TextButton(onClick = { showUseConfirm = false; vm.markUsed(coupon) }) { Text(stringResource(R.string.coupon_use_confirm_yes)) } },
            dismissButton = { TextButton(onClick = { showUseConfirm = false }) { Text(stringResource(R.string.action_cancel)) } },
        )
    }
}

@Composable
private fun UsedState() {
    val c = AyantTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(AyantRadius.card))
            .background(c.open.copy(alpha = 0.12f))
            .padding(18.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(Icons.Filled.Verified, null, tint = c.open, modifier = Modifier.size(28.dp))
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(stringResource(R.string.coupon_used_msg), fontSize = 17.sp, fontWeight = FontWeight.Bold, color = c.open)
            Text(stringResource(R.string.coupon_used_body), fontSize = 13.sp, fontWeight = FontWeight.Medium, color = c.inkSoft)
        }
    }
}

@Composable
private fun InfoRow(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String) {
    val c = AyantTheme.colors
    Row(
        Modifier.fillMaxWidth().ayantCard(padding = 14, radius = 22),
        verticalAlignment = Alignment.Top,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        AyantIconTile(icon, size = 36)
        Text(text, fontSize = 14.sp, lineHeight = 20.sp, color = c.inkSoft, modifier = Modifier.weight(1f))
    }
}

// MARK: Билет-купон

private val PERFORATION_HEIGHT = 30.dp

@Composable
private fun Ticket(coupon: Coupon, isUsed: Boolean) {
    val c = AyantTheme.colors
    // Высота шапки — по ней ставятся вырезы перфорации.
    var headerHeight by remember { mutableStateOf(132.dp) }
    val density = androidx.compose.ui.platform.LocalDensity.current
    val shape = remember(headerHeight) {
        TicketShape(
            cut = headerHeight + PERFORATION_HEIGHT / 2, vertical = false,
            notchRadius = PERFORATION_HEIGHT / 2, cornerRadius = AyantRadius.hero,
        )
    }
    Column(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(c.surface)
            .border(0.5.dp, c.hairline, shape),
    ) {
        // Шапка
        Column(
            Modifier
                .fillMaxWidth()
                .androidx.compose.ui.layout.onSizeChanged { headerHeight = with(density) { it.height.toDp() } }
                .background(CouponLook.gradient(isUsed))
                .ayantRisoHatch(alpha = 0.12f)
                .padding(horizontal = 22.dp)
                .padding(top = 22.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    (coupon.venueName.ifEmpty { stringResource(R.string.title_coupon) }).uppercase(),
                    fontSize = 11.5.sp, fontWeight = FontWeight.Black, letterSpacing = 1.2.sp,
                    color = Color.White.copy(alpha = 0.85f), maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    "AYANT", fontSize = 10.5.sp, fontWeight = FontWeight.Black, letterSpacing = 2.5.sp, color = Color.White,
                    modifier = Modifier.clip(CircleShape).background(Color.White.copy(alpha = 0.2f)).padding(horizontal = 9.dp, vertical = 5.dp),
                )
            }
            Text(coupon.title, fontSize = 26.sp, fontWeight = FontWeight.Black, letterSpacing = (-0.8).sp, lineHeight = 30.sp, color = Color.White)
            Text(CouponLook.kindLabel(coupon.kind), fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.85f))
        }

        // Полоса перфорации: сами вырезы делает `TicketShape`, здесь — пунктир между ними.
        Box(Modifier.fillMaxWidth().height(PERFORATION_HEIGHT), contentAlignment = Alignment.Center) {
            DashedLine(
                vertical = false, color = c.inkSoft.copy(alpha = 0.35f), stroke = 2.dp, dash = 6.dp,
                modifier = Modifier.fillMaxWidth().height(2.dp).padding(horizontal = PERFORATION_HEIGHT / 2 + 12.dp),
            )
        }

        // Тело: QR + код. QR только у купона заведения — он записан в Firestore и
        // его сканирует сотрудник. У бонус-купона документа на сервере нет,
        // показывать сканируемый код нельзя: остаётся код текстом и кнопка ниже.
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(top = 8.dp, bottom = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            if (coupon.isVenueBound) {
                Box(
                    Modifier
                        .padding(top = 6.dp)
                        .size(236.dp)
                        .ayantShadow(AyantShadow.QrCard, RoundedCornerShape(22.dp))
                        .clip(RoundedCornerShape(22.dp))
                        .background(Color.White),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(Modifier.alpha(if (isUsed) 0.35f else 1f)) { QrCode(coupon.code, size = 200) }
                    if (isUsed) UsedStamp()
                }
            } else if (isUsed) {
                Box(Modifier.padding(vertical = 8.dp)) { UsedStamp() }
            }

            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    stringResource(R.string.coupon_code_label).uppercase(),
                    fontSize = 11.5.sp, fontWeight = FontWeight.Black, letterSpacing = 1.2.sp, color = c.inkSoft,
                )
                Text(
                    coupon.code, fontSize = 24.sp, fontWeight = FontWeight.Black, letterSpacing = 1.5.sp,
                    fontFamily = FontFamily.Monospace, color = c.ink, maxLines = 1,
                )
                CopyButton(coupon.code)
            }

            AyantHairline()

            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                // «11 сентября» — родительный падеж даёт сам формат `d MMMM` в ru_RU.
                val received = remember(coupon.createdAt) { SimpleDateFormat("d MMMM", AppLanguage.locale).format(coupon.createdAt) }
                Text(stringResource(R.string.coupon_received, received), fontSize = 12.5.sp, fontWeight = FontWeight.Medium, color = c.inkSoft)
                Spacer(Modifier.weight(1f))
                CouponStatusPill(used = isUsed)
            }
        }
    }
}

@Composable
private fun CopyButton(code: String) {
    val c = AyantTheme.colors
    val clipboard = LocalClipboardManager.current
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) { if (copied) { delay(1500); copied = false } }
    val a11y = stringResource(R.string.coupon_copy_a11y)
    Row(
        Modifier
            .clip(CircleShape)
            .background(if (copied) c.open.copy(alpha = 0.12f) else c.surfaceMuted)
            .clickable { clipboard.setText(AnnotatedString(code)); copied = true }
            .padding(horizontal = 14.dp, vertical = 9.dp)
            .semantics { contentDescription = a11y },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        val tint = if (copied) c.open else c.ink
        Icon(if (copied) Icons.Filled.Check else Icons.Filled.ContentCopy, null, tint = tint, modifier = Modifier.size(13.dp))
        Text(
            if (copied) stringResource(R.string.coupon_copied) else stringResource(R.string.coupon_copy),
            fontSize = 13.5.sp, fontWeight = FontWeight.Bold, color = tint,
        )
    }
}

@Composable
private fun UsedStamp() {
    val red = Color(0xFFE53935).copy(alpha = 0.85f)
    Text(
        stringResource(R.string.coupon_redeemed_stamp),
        fontSize = 20.sp, fontWeight = FontWeight.Black, letterSpacing = 2.sp, color = red,
        modifier = Modifier
            .rotate(-15f)
            .border(3.dp, red, RoundedCornerShape(8.dp))
            .padding(horizontal = 12.dp, vertical = 5.dp),
    )
}
