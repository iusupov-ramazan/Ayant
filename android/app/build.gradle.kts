plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Firebase is optional until you register the Android app and drop google-services.json
// into app/. When present, the Google Services plugin is applied automatically and you can
// flip AppConfig.useFirebase to true. Until then the app runs entirely on MockData.
val googleServicesJson = file("google-services.json")
if (googleServicesJson.exists()) {
    apply(plugin = "com.google.gms.google-services")
}

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
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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

    // Image loading (AsyncImage equivalent)
    implementation("io.coil-kt:coil-compose:2.7.0")

    // Location (fused) — for distances (Haversine)
    implementation("com.google.android.gms:play-services-location:21.3.0")

    // QR generation (coupon codes)
    implementation("com.google.zxing:core:3.5.3")

    // --- Firebase (uncomment usage once google-services.json is added) ---
    implementation(platform("com.google.firebase:firebase-bom:33.3.0"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")

    debugImplementation("androidx.compose.ui:ui-tooling")
}
