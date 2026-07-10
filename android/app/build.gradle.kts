import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// Firebase is optional until you register the Android app and drop google-services.json
// into app/. When present, the Google Services plugin is applied automatically and you can
// flip AppConfig.useFirebase to true. Until then the app runs entirely on MockData.
val googleServicesJson = file("google-services.json")
if (googleServicesJson.exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Secrets are read from local.properties (gitignored): MAPS_API_KEY=...
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val mapsApiKey = localProps.getProperty("MAPS_API_KEY", "YOUR_MAPS_API_KEY")

// Release signing is read from keystore.properties (gitignored) if present.
val keystoreProps = Properties().apply {
    val f = rootProject.file("keystore.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProps.getProperty("storeFile") != null

android {
    namespace = "kg.ayant.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "kg.ayant.app"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "0.3"
        vectorDrawables { useSupportLibrary = true }
        // Injected into AndroidManifest as ${MAPS_API_KEY}.
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (hasReleaseKeystore) signingConfig = signingConfigs.getByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    buildFeatures { compose = true }
    packaging {
        resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.09.02")
    implementation(composeBom)

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.6")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.6")
    implementation("androidx.activity:activity-compose:1.9.2")

    // Compose UI + Material 3
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")

    // Navigation
    implementation("androidx.navigation:navigation-compose:2.8.1")

    // JSON persistence (host content in SharedPreferences). 1.7.x targets Kotlin 2.0.x.
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    // Image loading (AsyncImage equivalent)
    implementation("io.coil-kt:coil-compose:2.7.0")

    // Location (fused) — for distances (Haversine)
    implementation("com.google.android.gms:play-services-location:21.3.0")

    // Google Maps (Compose) — search map. Needs a Maps API key (see README).
    implementation("com.google.maps.android:maps-compose:6.1.0")
    implementation("com.google.maps.android:maps-compose-utils:6.1.0")
    implementation("com.google.android.gms:play-services-maps:19.0.0")

    // QR generation (coupon codes)
    implementation("com.google.zxing:core:3.5.3")

    // In-app review prompt
    implementation("com.google.android.play:review-ktx:2.0.2")

    // Background reminders (bonus goal nudge)
    implementation("androidx.work:work-runtime-ktx:2.9.1")

    // Camera QR scanning (host) — CameraX + ML Kit barcode (all aligned to 1.4.2,
    // the version line where camera-mlkit-vision is published).
    implementation("androidx.camera:camera-core:1.4.2")
    implementation("androidx.camera:camera-camera2:1.4.2")
    implementation("androidx.camera:camera-lifecycle:1.4.2")
    implementation("androidx.camera:camera-view:1.4.2")
    implementation("androidx.camera:camera-mlkit-vision:1.4.2")
    implementation("com.google.mlkit:barcode-scanning:17.3.0")
    // Real Guava ListenableFuture (avoids the empty stub CameraX otherwise trips on).
    implementation("com.google.guava:guava:33.3.1-android")

    // --- Firebase (uncomment usage once google-services.json is added) ---
    implementation(platform("com.google.firebase:firebase-bom:33.3.0"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.firebase:firebase-storage")
    implementation("com.google.firebase:firebase-messaging")
    // Await Firebase Tasks from coroutines (FirebaseDataRepository).
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.8.1")

    // Google Sign-In via Credential Manager
    implementation("androidx.credentials:credentials:1.3.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.3.0")
    implementation("com.google.android.libraries.identity.googleid:googleid:1.1.1")

    debugImplementation("androidx.compose.ui:ui-tooling")

    // --- Unit tests (JVM, no Android framework) ---
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
}
