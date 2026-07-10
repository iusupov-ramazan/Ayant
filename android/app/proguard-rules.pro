# Keep data models (Firestore/JSON reflection + Compose stability).
-keep class kg.ayant.app.data.model.** { *; }

# Kotlin metadata + coroutines
-keepclassmembers class kotlinx.coroutines.** { volatile <fields>; }
-dontwarn kotlinx.coroutines.**

# Firebase (Firestore/Auth/Messaging/Storage) — most ship consumer rules; keep models.
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses

# Credential Manager / Google Identity (Google Sign-In)
-keep class com.google.android.libraries.identity.googleid.** { *; }
-dontwarn com.google.android.libraries.identity.googleid.**

# ML Kit barcode + CameraX
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# Google Maps
-keep class com.google.android.gms.maps.** { *; }
-keep class com.google.maps.android.** { *; }
-dontwarn com.google.maps.android.**

# ZXing
-dontwarn com.google.zxing.**

# Coil
-dontwarn coil.**

# Play in-app review + WorkManager ship their own consumer rules.
