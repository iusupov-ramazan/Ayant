package kg.ayant.app.data

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.GoogleAuthProvider
import kotlinx.coroutines.tasks.await
import kg.ayant.app.ui.vm.AuthProvider
import kg.ayant.app.ui.vm.AyantUser

/**
 * Google Sign-In through Credential Manager → Firebase Auth.
 * Uses the OAuth web client id from google-services.json (client_type 3).
 * NOTE: for this to succeed at runtime you must register the app's SHA-1 in the
 * Firebase console (Project settings → your Android app → Add fingerprint).
 */
object GoogleAuth {
    // Web client id (oauth_client, client_type 3) from google-services.json.
    private const val WEB_CLIENT_ID = "320025643761-70u1r49nenagc07d50nlkjd8h6tbpnog.apps.googleusercontent.com"

    suspend fun signIn(context: Context): AyantUser {
        val option = GetGoogleIdOption.Builder()
            .setServerClientId(WEB_CLIENT_ID)
            .setFilterByAuthorizedAccounts(false)
            .build()
        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
        val response = CredentialManager.create(context).getCredential(context, request)
        val googleToken = GoogleIdTokenCredential.createFrom(response.credential.data).idToken
        val firebaseCred = GoogleAuthProvider.getCredential(googleToken, null)
        val result = FirebaseAuth.getInstance().signInWithCredential(firebaseCred).await()
        val u = result.user ?: throw IllegalStateException("Не удалось войти")
        return AyantUser(u.uid, u.displayName ?: "Пользователь Google", u.email, AuthProvider.GOOGLE)
    }
}
