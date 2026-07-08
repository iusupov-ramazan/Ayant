package kg.ayant.app.ui.detail

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.data.model.Review

/** Write / edit a review. Mirrors WriteReviewView (venue-level, simplified). */
@Composable
fun WriteReviewDialog(
    existing: Review?,
    onDismiss: () -> Unit,
    onSave: (rating: Int, text: String) -> Unit,
) {
    var rating by remember { mutableIntStateOf(existing?.rating ?: 5) }
    var text by remember { mutableStateOf(existing?.text ?: "") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (existing == null) "Оставить отзыв" else "Изменить отзыв") },
        text = {
            androidx.compose.foundation.layout.Column {
                Row {
                    for (i in 1..5) {
                        Icon(
                            if (i <= rating) Icons.Filled.Star else Icons.Filled.StarBorder,
                            null, tint = Color(0xFFF5C518),
                            modifier = Modifier.padding(end = 4.dp).clickable { rating = i }.padding(2.dp),
                        )
                    }
                }
                OutlinedTextField(
                    value = text, onValueChange = { text = it },
                    label = { Text("Ваш отзыв") },
                    modifier = Modifier.padding(top = 12.dp),
                    minLines = 3,
                )
            }
        },
        confirmButton = { TextButton(onClick = { onSave(rating, text.trim()) }) { Text("Опубликовать") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена") } },
    )
}
