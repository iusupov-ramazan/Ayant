package kg.ayant.app.ui.games

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.RotateRight
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
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import kg.ayant.app.ui.vm.BonusViewModel
import kotlinx.coroutines.delay

private const val COLS = 10
private const val ROWS = 20

// Tetromino shapes as lists of (x,y) offsets; index used as color id.
private val SHAPES = listOf(
    listOf(0 to 0, 1 to 0, 2 to 0, 3 to 0),   // I
    listOf(0 to 0, 1 to 0, 0 to 1, 1 to 1),   // O
    listOf(0 to 0, 1 to 0, 2 to 0, 1 to 1),   // T
    listOf(1 to 0, 2 to 0, 0 to 1, 1 to 1),   // S
    listOf(0 to 0, 1 to 0, 1 to 1, 2 to 1),   // Z
    listOf(0 to 0, 0 to 1, 1 to 1, 2 to 1),   // J
    listOf(2 to 0, 0 to 1, 1 to 1, 2 to 1),   // L
)
private val COLORS = listOf(
    Color(0xFF29B6F6), Color(0xFFFFCA28), Color(0xFFAB47BC), Color(0xFF66BB6A),
    Color(0xFFEF5350), Color(0xFF5C6BC0), Color(0xFFFF7043),
)

private data class Piece(val cells: List<Pair<Int, Int>>, val color: Int, val x: Int, val y: Int) {
    fun moved(dx: Int, dy: Int) = copy(x = x + dx, y = y + dy)
    fun rotated(): Piece {
        // rotate around approximate center
        val rot = cells.map { (cx, cy) -> (-cy) to cx }
        val minX = rot.minOf { it.first }; val minY = rot.minOf { it.second }
        return copy(cells = rot.map { it.first - minX to it.second - minY })
    }
    fun blocks() = cells.map { (cx, cy) -> (x + cx) to (y + cy) }
}

@Composable
fun TetrisGame(onClose: () -> Unit) {
    val bonus: BonusViewModel = viewModel()
    val grid = remember { Array(ROWS) { IntArray(COLS) { -1 } } }
    var tick by remember { mutableIntStateOf(0) }        // forces recompose on grid change
    var piece by remember { mutableStateOf(spawn()) }
    var score by remember { mutableIntStateOf(0) }
    var lines by remember { mutableIntStateOf(0) }
    var gameOver by remember { mutableStateOf(false) }

    fun collides(p: Piece): Boolean = p.blocks().any { (x, y) ->
        x < 0 || x >= COLS || y >= ROWS || (y >= 0 && grid[y][x] != -1)
    }

    fun lockAndNext() {
        piece.blocks().forEach { (x, y) -> if (y in 0 until ROWS && x in 0 until COLS) grid[y][x] = piece.color }
        // clear full lines
        var cleared = 0
        var row = ROWS - 1
        while (row >= 0) {
            if ((0 until COLS).all { grid[row][it] != -1 }) {
                for (r in row downTo 1) grid[r] = grid[r - 1].copyOf()
                grid[0] = IntArray(COLS) { -1 }
                cleared++
            } else row--
        }
        if (cleared > 0) {
            lines += cleared
            score += cleared * 100
            bonus.awardGameplay(cleared * 5)
        }
        val next = spawn()
        if (collides(next)) gameOver = true else piece = next
        tick++
    }

    fun move(dx: Int, dy: Int): Boolean {
        val moved = piece.moved(dx, dy)
        return if (!collides(moved)) { piece = moved; true } else false
    }

    fun rotate() {
        val r = piece.rotated()
        if (!collides(r)) piece = r
    }

    fun reset() {
        for (r in 0 until ROWS) grid[r] = IntArray(COLS) { -1 }
        piece = spawn(); score = 0; lines = 0; gameOver = false; tick++
    }

    LaunchedEffect(gameOver) {
        while (!gameOver) {
            delay(550)
            if (!move(0, 1)) lockAndNext()
        }
    }

    Column(Modifier.fillMaxSize().background(Color(0xFF241C3A)).padding(16.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(kg.ayant.app.R.string.game_tetris_title), fontSize = 22.sp, fontWeight = FontWeight.Black, color = Color.White)
            androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
            Text(stringResource(kg.ayant.app.R.string.game_score, score), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Color.White)
            IconButton(onClick = onClose) { Icon(Icons.Filled.Close, stringResource(kg.ayant.app.R.string.game_close), tint = Color.White) }
        }
        Text(stringResource(kg.ayant.app.R.string.game_tetris_bonus, bonus.remainingGameplayToday), fontSize = 12.sp, color = Color.White.copy(alpha = 0.9f), modifier = Modifier.padding(vertical = 6.dp))

        Box(Modifier.fillMaxWidth().padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
            Canvas(
                Modifier.fillMaxWidth(0.75f).aspectRatio(COLS.toFloat() / ROWS).background(Color(0xFF160F26), RoundedCornerShape(10.dp))
            ) {
                tick // read to recompose
                val cell = size.width / COLS
                for (r in 0 until ROWS) for (col in 0 until COLS) {
                    if (grid[r][col] != -1) drawCell(col, r, cell, COLORS[grid[r][col]])
                }
                piece.blocks().forEach { (x, y) -> if (y >= 0) drawCell(x, y, cell, COLORS[piece.color]) }
            }
        }

        if (gameOver) {
            Column(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(kg.ayant.app.R.string.game_tetris_over, lines), fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Color.White)
                Text(
                    stringResource(kg.ayant.app.R.string.game_play_again), fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Color(0xFF241C3A),
                    modifier = Modifier.clip(RoundedCornerShape(12.dp)).background(Color.White).clickable { reset() }.padding(horizontal = 24.dp, vertical = 12.dp),
                )
            }
        } else {
            Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.SpaceEvenly) {
                ctrl(Icons.AutoMirrored.Filled.KeyboardArrowLeft) { move(-1, 0) }
                ctrl(Icons.Filled.RotateRight) { rotate() }
                ctrl(Icons.AutoMirrored.Filled.KeyboardArrowRight) { move(1, 0) }
                ctrl(Icons.Filled.KeyboardArrowDown) { if (!move(0, 1)) lockAndNext() }
            }
        }
    }
}

@Composable
private fun ctrl(icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit) {
    Box(
        Modifier.size(64.dp).clip(RoundedCornerShape(16.dp)).background(Color.White.copy(alpha = 0.14f)).clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, tint = Color.White, modifier = Modifier.size(30.dp)) }
}

private fun spawn(): Piece {
    val i = SHAPES.indices.random()
    return Piece(SHAPES[i], i, x = COLS / 2 - 1, y = 0)
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawCell(x: Int, y: Int, cell: Float, color: Color) {
    drawRoundRect(
        color = color,
        topLeft = Offset(x * cell + cell * 0.05f, y * cell + cell * 0.05f),
        size = Size(cell * 0.9f, cell * 0.9f),
        cornerRadius = CornerRadius(cell * 0.2f),
    )
}
