package kg.ayant.app.ui.components

import android.graphics.Bitmap
import android.graphics.Color as AColor
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.unit.dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter

/** QR code for a coupon code. Mirrors QRCodeView. */
@Composable
fun QrCode(text: String, size: Int = 110, modifier: Modifier = Modifier) {
    val bmp = remember(text, size) { generate(text, size) }
    androidx.compose.foundation.layout.Box(
        modifier
            .clip(RoundedCornerShape(10.dp))
            .background(Color.White)
            .padding(8.dp)
            .size(size.dp),
    ) {
        if (bmp != null) Image(bmp.asImageBitmap(), contentDescription = "QR", modifier = Modifier.size(size.dp))
    }
}

private fun generate(text: String, size: Int): Bitmap? = runCatching {
    val px = size * 3
    val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, px, px)
    val bmp = Bitmap.createBitmap(px, px, Bitmap.Config.RGB_565)
    for (x in 0 until px) for (y in 0 until px) {
        bmp.setPixel(x, y, if (matrix[x, y]) AColor.BLACK else AColor.WHITE)
    }
    bmp
}.getOrNull()
