package kg.ayant.app.ui.games

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.domain.Tetris
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.BonusViewModel
import kotlinx.coroutines.delay

/**
 * Тетрис. Правила — в `Tetris` (домен), здесь только отрисовка сетки и ввод.
 * Зеркалит `TetrisGameView.swift`.
 *
 * Поле — обычная сетка прямоугольников, поэтому у экрана есть 1:1 пара на iOS.
 * Прошлая версия была на SpriteKit, у которого нет пары в Compose, — из-за этого
 * её и убирали.
 */
@Composable
fun TetrisGame(bonus: BonusViewModel, onClose: () -> Unit) {
    val c = AyantTheme.colors
    var state by remember { mutableStateOf(Tetris.start(System.currentTimeMillis())) }
    var awarded by remember { mutableIntStateOf(0) }

    /** Применяет ход и начисляет бонусы за НОВЫЕ линии; лимит держит VM. */
    fun step(transform: (Tetris.State) -> Tetris.State) {
        val before = state.lines
        state = transform(state)
        val gained = state.lines - before
        if (gained > 0) awarded += bonus.awardGameplay(gained * Tetris.BONUS_PER_LINE)
    }

    // Один цикл на партию: сам останавливается вместе с экраном.
    LaunchedEffect(state.isOver) {
        while (!state.isOver) {
            delay((600L - state.lines * 20L).coerceAtLeast(160L))
            step { Tetris.tick(it) }
        }
    }

    Column(
        Modifier.fillMaxSize().background(c.canvas).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    stringResource(R.string.tetris_lines, state.lines),
                    fontSize = 17.sp, fontWeight = FontWeight.Bold, color = c.ink,
                )
                Text(
                    stringResource(R.string.tetris_earned, awarded),
                    fontSize = 12.5.sp, color = c.inkSoft,
                )
            }
            Text(
                stringResource(R.string.action_done),
                fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = c.accentText,
                modifier = Modifier.clickable(onClick = onClose),
            )
        }

        Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
            Board(state)
            if (state.isOver) {
                Column(
                    Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f)),
                    verticalArrangement = Arrangement.Center,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        stringResource(R.string.game_over),
                        fontSize = 20.sp, fontWeight = FontWeight.Black, color = Color.White,
                    )
                    Text(
                        stringResource(R.string.tetris_result, state.lines, awarded),
                        fontSize = 14.sp, color = Color.White.copy(alpha = 0.85f),
                    )
                    Box(
                        Modifier
                            .padding(top = 12.dp)
                            .clip(CircleShape)
                            .background(Color.White)
                            .clickable {
                                awarded = 0
                                state = Tetris.start(System.currentTimeMillis())
                            }
                            .padding(horizontal = 20.dp, vertical = 12.dp),
                    ) {
                        Text(
                            stringResource(R.string.action_again),
                            fontSize = 15.sp, fontWeight = FontWeight.Bold, color = c.ink,
                        )
                    }
                }
            }
        }

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ControlButton(Icons.AutoMirrored.Filled.ArrowBack, Modifier.weight(1f)) { step { Tetris.move(it, -1) } }
            ControlButton(Icons.Filled.Refresh, Modifier.weight(1f)) { step { Tetris.rotate(it) } }
            ControlButton(Icons.AutoMirrored.Filled.ArrowForward, Modifier.weight(1f)) { step { Tetris.move(it, 1) } }
            ControlButton(Icons.Filled.Download, Modifier.weight(1f)) { step { Tetris.hardDrop(it) } }
        }

        Text(
            stringResource(R.string.tetris_rule, Tetris.BONUS_PER_LINE, bonus.remainingGameplayToday),
            fontSize = 12.sp, color = c.inkSoft, modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
private fun Board(state: Tetris.State) {
    val c = AyantTheme.colors
    // Клетки падающей фигуры считаем один раз на кадр, а не на каждую ячейку.
    val moving = state.piece?.occupied.orEmpty()
        .filter { it.y >= 0 }
        .associate { (it.y * Tetris.COLUMNS + it.x) to state.piece!!.shape }

    Column(
        Modifier
            .aspectRatio(Tetris.COLUMNS.toFloat() / Tetris.ROWS.toFloat())
            .fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(1.dp),
    ) {
        for (y in 0 until Tetris.ROWS) {
            Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(1.dp)) {
                for (x in 0 until Tetris.COLUMNS) {
                    val shape = moving[y * Tetris.COLUMNS + x] ?: state.board[y][x]
                    Box(
                        Modifier
                            .weight(1f)
                            .fillMaxSize()
                            .clip(RoundedCornerShape(3.dp))
                            .background(shape?.let { shapeColor(it) } ?: c.surfaceMuted),
                    )
                }
            }
        }
    }
}

/** Цвета живут в UI: домен про них ничего не знает (как и у `Venue.gradient`). */
private fun shapeColor(shape: Tetris.Shape): Color = when (shape) {
    Tetris.Shape.I -> Color(0xFF2FA88C)
    Tetris.Shape.O -> Color(0xFFFF9500)
    Tetris.Shape.T -> Color(0xFF7C6BE8)
    Tetris.Shape.S -> Color(0xFF2FA24C)
    Tetris.Shape.Z -> Color(0xFFE8556B)
    Tetris.Shape.J -> Color(0xFF3D7BE8)
    Tetris.Shape.L -> Color(0xFFFF5A1F)
}

@Composable
private fun ControlButton(icon: ImageVector, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val c = AyantTheme.colors
    Box(
        modifier
            .height(52.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(c.surface)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = c.ink, modifier = Modifier.size(22.dp))
    }
}
