package kg.ayant.app.ui.games

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.BonusViewModel
import kotlinx.coroutines.delay
import kotlin.math.abs

private const val GRID = 17

@Composable
fun SnakeGame(onClose: () -> Unit) {
    val c = AyantTheme.colors
    val bonus: BonusViewModel = viewModel()

    var snake by remember { mutableStateOf(listOf(7 to 8, 6 to 8, 5 to 8)) }
    var dir by remember { mutableStateOf(1 to 0) }
    var food by remember { mutableStateOf(11 to 8) }
    var score by remember { mutableIntStateOf(0) }
    var gameOver by remember { mutableStateOf(false) }
    var running by remember { mutableStateOf(true) }

    fun reset() {
        snake = listOf(7 to 8, 6 to 8, 5 to 8); dir = 1 to 0; food = 11 to 8
        score = 0; gameOver = false; running = true
    }

    LaunchedEffect(running, gameOver) {
        while (running && !gameOver) {
            delay(160)
            val head = snake.first()
            val next = ((head.first + dir.first + GRID) % GRID) to ((head.second + dir.second + GRID) % GRID)
            if (snake.contains(next)) { gameOver = true; break }
            val grew = next == food
            snake = if (grew) listOf(next) + snake else listOf(next) + snake.dropLast(1)
            if (grew) {
                score += 1
                bonus.awardGameplay(1)
                var f: Pair<Int, Int>
                do { f = (0 until GRID).random() to (0 until GRID).random() } while (snake.contains(f))
                food = f
            }
        }
    }

    Column(Modifier.fillMaxSize().background(Color(0xFF0E9E86)).padding(16.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(kg.ayant.app.R.string.game_snake_title), fontSize = 22.sp, fontWeight = FontWeight.Black, color = Color.White)
            androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
            Text(stringResource(kg.ayant.app.R.string.game_score, score), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Color.White)
            IconButton(onClick = onClose) { Icon(Icons.Filled.Close, stringResource(kg.ayant.app.R.string.game_close), tint = Color.White) }
        }
        Text(stringResource(kg.ayant.app.R.string.game_snake_bonus, bonus.remainingGameplayToday), fontSize = 12.sp, color = Color.White.copy(alpha = 0.9f), modifier = Modifier.padding(vertical = 6.dp))

        Box(Modifier.fillMaxWidth().padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
            Canvas(
                Modifier.fillMaxWidth().aspectRatio(1f).background(Color(0xFF13B89C), RoundedCornerShape(12.dp))
                    .pointerInput(Unit) {
                        detectDragGestures { _, drag ->
                            if (abs(drag.x) > abs(drag.y)) {
                                if (drag.x > 0 && dir != (-1 to 0)) dir = 1 to 0
                                else if (drag.x < 0 && dir != (1 to 0)) dir = -1 to 0
                            } else {
                                if (drag.y > 0 && dir != (0 to -1)) dir = 0 to 1
                                else if (drag.y < 0 && dir != (0 to 1)) dir = 0 to -1
                            }
                        }
                    },
            ) {
                val cell = size.width / GRID
                // food
                drawRoundRectCell(food, cell, Color(0xFFFF5A1F))
                // snake
                snake.forEachIndexed { i, p ->
                    drawRoundRectCell(p, cell, if (i == 0) Color.White else Color.White.copy(alpha = 0.85f))
                }
            }
        }

        if (gameOver) {
            Column(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(kg.ayant.app.R.string.game_snake_over, score), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Color.White)
                Text(
                    stringResource(kg.ayant.app.R.string.game_play_again), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Color(0xFF0E9E86),
                    modifier = Modifier
                        .clip(RoundedCornerShape(12.dp))
                        .background(Color.White)
                        .clickable { reset() }
                        .padding(horizontal = 24.dp, vertical = 12.dp),
                )
            }
        } else {
            Text(stringResource(kg.ayant.app.R.string.game_snake_hint), fontSize = 13.sp, color = Color.White.copy(alpha = 0.9f), modifier = Modifier.fillMaxWidth(), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        }
    }
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawRoundRectCell(p: Pair<Int, Int>, cell: Float, color: Color) {
    drawRoundRect(
        color = color,
        topLeft = Offset(p.first * cell + cell * 0.08f, p.second * cell + cell * 0.08f),
        size = Size(cell * 0.84f, cell * 0.84f),
        cornerRadius = androidx.compose.ui.geometry.CornerRadius(cell * 0.25f),
    )
}
