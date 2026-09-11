package kg.ayant.app.ui.host

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.ui.theme.AyantMetrics
import kg.ayant.app.ui.theme.AyantMotion
import kg.ayant.app.ui.theme.AyantRadius
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.theme.ayantGroupCard
import kg.ayant.app.ui.theme.ayantPressScale

/**
 * Общие детали хост-форм (SCREENS.md H1, H3–H5, H8). Зеркалит `HostFormKit.swift`.
 *
 * В макете все формы устроены одинаково: карточка с рядами «капслоковая метка
 * сверху, значение снизу», кремовая заметка и липкий футер. Раньше это были
 * обычные Material-диалоги — их вид не совпадал ни с чем в редизайне.
 */

/** Ряд формы: метка-капслок + значение. Mirrors `SanFieldRow`. */
@Composable
fun AyantFieldRow(label: String, value: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 13.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Text(
            label.uppercase(),
            fontSize = 11.sp, fontWeight = FontWeight.Black, letterSpacing = 0.9.sp,
            color = Color(0xFF9A9188),
        )
        value()
    }
}

/** Текстовое поле формы. Пустое значение показывается плейсхолдером `#C0B8AE`. */
@Composable
fun AyantFieldInput(
    placeholder: String,
    value: String,
    onValueChange: (String) -> Unit,
    keyboardType: KeyboardType = KeyboardType.Text,
    singleLine: Boolean = true,
    enabled: Boolean = true,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    val style = TextStyle(fontSize = 15.5.sp, fontWeight = FontWeight.SemiBold, color = c.ink)
    Box(modifier.fillMaxWidth()) {
        if (value.isEmpty()) {
            Text(placeholder, style = style.copy(color = Color(0xFFC0B8AE)))
        }
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            singleLine = singleLine,
            enabled = enabled,
            textStyle = style,
            cursorBrush = SolidColor(c.accent),
            keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** Карточка-группа для рядов формы. Mirrors `SanFieldCard`. */
@Composable
fun AyantFieldCard(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().ayantGroupCard(radius = AyantRadius.card.value.toInt())) { content() }
}

/** Кремовая заметка-предупреждение («уйдёт на модерацию» и т. п.). */
@Composable
fun AyantNoteCard(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        fontSize = 13.sp, color = Color(0xFFC24A12),
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(Color(0xFFFFF3EC))
            .padding(16.dp),
    )
}

/** Прогресс из отрезков: пройденные — акцентный градиент. */
@Composable
fun AyantStepProgress(step: Int, total: Int = 2, modifier: Modifier = Modifier) {
    val c = AyantTheme.colors
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        repeat(total) { i ->
            Box(
                Modifier
                    .weight(1f)
                    .height(4.dp)
                    .clip(CircleShape)
                    .then(
                        if (i <= step) Modifier.background(c.accentGradient)
                        else Modifier.background(Color(0xFFE0DAD1)),
                    ),
            )
        }
    }
}

/** Липкий футер формы: основная кнопка и подпись под ней. */
@Composable
fun AyantStickyFooter(content: @Composable ColumnScope.() -> Unit) {
    val c = AyantTheme.colors
    Column(
        Modifier
            .fillMaxWidth()
            .background(c.canvas.copy(alpha = 0.96f))
            .navigationBarsPadding()
            .padding(horizontal = 18.dp)
            .padding(top = 12.dp, bottom = 14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        content = content,
    )
}

/** Заголовок формы: «Отмена · Название · пусто» одной строкой без переносов. */
@Composable
fun AyantFormHeader(title: String, onCancel: () -> Unit) {
    val c = AyantTheme.colors
    val cancel = stringResource(R.string.action_cancel)
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = AyantMetrics.screenPadding, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            cancel,
            fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = c.accentText,
            modifier = Modifier.clickable(onClick = onCancel),
        )
        Spacer(Modifier.weight(1f))
        Text(title, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = c.ink, maxLines = 1)
        Spacer(Modifier.weight(1f))
        // Балансирующая пустота той же ширины, что и «Отмена».
        Text(cancel, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Color.Transparent)
    }
}

/** Ряд-переключатель с градиентной дорожкой (Material Switch не умеет градиент). */
@Composable
fun AyantGradientToggle(
    title: String,
    subtitle: String? = null,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    val knobOffset by animateDpAsState(
        targetValue = if (checked) 21.dp else 3.dp,
        animationSpec = tween(250, easing = AyantMotion.EnterEasing),
        label = "toggleKnob",
    )
    Row(
        modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, fontSize = 14.5.sp, fontWeight = FontWeight.Bold, color = c.ink)
            subtitle?.let { Text(it, fontSize = 12.sp, color = Color(0xFF9A9188)) }
        }
        Box(
            Modifier
                .size(width = 46.dp, height = 28.dp)
                .clip(CircleShape)
                .then(
                    if (checked) Modifier.background(c.accentGradient)
                    else Modifier.background(Color(0xFFDDD7CE)),
                )
                .clickable { onCheckedChange(!checked) },
        ) {
            Box(
                Modifier
                    .padding(start = knobOffset)
                    .align(Alignment.CenterStart)
                    .size(22.dp)
                    .clip(CircleShape)
                    .background(Color.White),
            )
        }
    }
}

/** Сегментированный выбор (режимы баллов, типы акций). Mirrors `SanSegmented`. */
@Composable
fun <T> AyantSegmented(
    items: List<T>,
    selection: T,
    title: (T) -> String,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = AyantTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(c.surfaceMuted)
            .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        items.forEach { item ->
            val isOn = item == selection
            val interaction = remember { MutableInteractionSource() }
            Box(
                Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(13.dp))
                    .then(if (isOn) Modifier.background(c.surface) else Modifier)
                    .clickable(interactionSource = interaction, indication = null) { onSelect(item) }
                    .ayantPressScale(interaction, scale = 0.96f)
                    .padding(vertical = 10.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    title(item),
                    fontSize = 13.5.sp,
                    fontWeight = if (isOn) FontWeight.Bold else FontWeight.SemiBold,
                    color = if (isOn) c.ink else c.inkSoft,
                    maxLines = 1,
                )
            }
        }
    }
}

/** Разделитель между рядами карточки-группы. */
@Composable
fun AyantFieldDivider(leadingPadding: Int = 16) {
    val c = AyantTheme.colors
    Box(
        Modifier
            .fillMaxWidth()
            .padding(start = leadingPadding.dp)
            .height(0.5.dp)
            .background(c.hairline),
    )
}

/** Ряд формы, открывающий выбор: метка, значение и шеврон. */
@Composable
fun AyantPickerRow(label: String, value: String, onClick: () -> Unit) {
    val c = AyantTheme.colors
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(
                label.uppercase(),
                fontSize = 11.sp, fontWeight = FontWeight.Black, letterSpacing = 0.9.sp,
                color = Color(0xFF9A9188),
            )
            Text(value, fontSize = 15.5.sp, fontWeight = FontWeight.SemiBold, color = c.ink)
        }
        Spacer(Modifier.width(8.dp))
        Text("›", fontSize = 20.sp, color = c.inkSoft)
    }
}
