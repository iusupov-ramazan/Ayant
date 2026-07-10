package kg.ayant.app.ui.detail

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kg.ayant.app.R
import kg.ayant.app.data.model.Venue
import kg.ayant.app.ui.theme.AyantTheme
import kg.ayant.app.ui.vm.AppViewModel

/**
 * Write / edit a review. Mirrors WriteReviewView — when the venue has review
 * objects (items), a review targets a specific dish/service.
 */
@Composable
fun WriteReviewDialog(
    venue: Venue,
    app: AppViewModel,
    preselectItemID: String?,
    onDismiss: () -> Unit,
) {
    val c = AyantTheme.colors
    val hasItems = venue.items.isNotEmpty()
    var selectedItemID by remember { mutableStateOf(preselectItemID ?: venue.items.firstOrNull()?.id) }
    val existing = app.myReview(venue.id, selectedItemID)
    var rating by remember(selectedItemID) { mutableIntStateOf(existing?.rating ?: 0) }
    var text by remember(selectedItemID) { mutableStateOf(existing?.text ?: "") }
    var itemMenu by remember { mutableStateOf(false) }
    val canPublish = rating > 0 && (!hasItems || selectedItemID != null)

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (existing == null) stringResource(R.string.review_new_title) else stringResource(R.string.review_edit_title)) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                if (!hasItems) {
                    Text(stringResource(R.string.review_no_items_body), fontSize = 14.sp, color = c.inkSoft)
                } else {
                    Text(stringResource(R.string.review_what_rating), fontSize = 13.sp, color = c.inkSoft)
                    val sel = venue.items.firstOrNull { it.id == selectedItemID }
                    Text(
                        "${sel?.emoji ?: ""} ${sel?.name ?: stringResource(R.string.action_choose)}",
                        fontSize = 16.sp, color = c.accent,
                        modifier = Modifier.padding(vertical = 6.dp).clickable { itemMenu = true },
                    )
                    DropdownMenu(expanded = itemMenu, onDismissRequest = { itemMenu = false }) {
                        venue.items.forEach { item ->
                            DropdownMenuItem(text = { Text("${item.emoji} ${item.name}") }, onClick = { selectedItemID = item.id; itemMenu = false })
                        }
                    }
                }
                Row(Modifier.padding(vertical = 10.dp)) {
                    for (i in 1..5) {
                        Icon(
                            if (i <= rating) Icons.Filled.Star else Icons.Filled.StarBorder,
                            null, tint = Color(0xFFF5C518),
                            modifier = Modifier.padding(end = 4.dp).clickable { rating = i }.padding(2.dp),
                        )
                    }
                }
                OutlinedTextField(value = text, onValueChange = { text = it }, label = { Text(stringResource(R.string.review_hint)) }, minLines = 3, modifier = Modifier.padding(top = 4.dp))
            }
        },
        confirmButton = {
            TextButton(enabled = canPublish, onClick = {
                val item = venue.items.firstOrNull { it.id == selectedItemID }
                app.saveReview(venue.id, rating, text.trim(), itemID = selectedItemID, itemName = item?.name)
                onDismiss()
            }) { Text(stringResource(R.string.action_publish)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.action_cancel)) } },
    )
}
