import org.jetbrains.kotlin.gradle.dsl.JvmTarget

/**
 * :data — реализации доменных контрактов на Firebase и на локальных данных.
 *
 * Единственный модуль, которому разрешён Firebase SDK: зависимости на Firestore /
 * Auth / Storage объявлены здесь и **не** попадают в `:feature` и `:app`, поэтому
 * обращение к Firestore из экрана или ViewModel — ошибка компоновки, а не замечание
 * на ревью.
 *
 * Зависит только на `:domain`. Зеркалит Swift-пакет `AyantData` на iOS.
 */
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "kg.ayant.app.data"
    compileSdk = 34
    defaultConfig { minSdk = 26 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    api(project(":domain"))

    implementation(platform("com.google.firebase:firebase-bom:33.3.0"))
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.firebase:firebase-storage")
    implementation("com.google.firebase:firebase-messaging")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.8.1")

    // Google Sign-In через Credential Manager (data/GoogleAuth.kt).
    implementation("androidx.credentials:credentials:1.3.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.3.0")
    implementation("com.google.android.libraries.identity.googleid:googleid:1.1.1")
}
