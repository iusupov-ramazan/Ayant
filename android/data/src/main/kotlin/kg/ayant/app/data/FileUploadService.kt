package kg.ayant.app.data

import kg.ayant.app.domain.contract.FileUploadService

import android.net.Uri
import com.google.firebase.storage.FirebaseStorage
import kotlinx.coroutines.tasks.await
import java.util.UUID

class MockFileUploadService : FileUploadService {
    override suspend fun upload(uri: String, folder: String, mimeType: String): String? = null
}

class FirebaseFileUploadService : FileUploadService {
    override suspend fun upload(uri: String, folder: String, mimeType: String): String? =
        runCatching {
            val ext = if (mimeType.startsWith("image")) "jpg" else "pdf"
            val ref = FirebaseStorage.getInstance().reference
                .child("$folder/${UUID.randomUUID()}.$ext")
            ref.putFile(Uri.parse(uri)).await()
            ref.downloadUrl.await().toString()
        }.getOrNull()
}
