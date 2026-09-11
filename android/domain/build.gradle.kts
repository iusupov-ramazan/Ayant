import org.jetbrains.kotlin.gradle.dsl.JvmTarget

/**
 * :domain — чистый Kotlin/JVM, БЕЗ Android.
 *
 * Здесь только модели, чистые функции (Ranking, PointsMath) и контракты
 * репозиториев. Модуль намеренно не подключает android-плагин: попытка
 * затащить сюда Context, Compose или Firebase не пройдёт компиляцию —
 * граница слоёв держится сборкой, а не договорённостью на ревью.
 *
 * Зеркалит Swift-пакет `AyantDomain` на iOS.
 */
plugins {
    id("org.jetbrains.kotlin.jvm")
    id("org.jetbrains.kotlin.plugin.serialization")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}

sourceSets {
    named("test") {
        // Общий фикстур математики баллов лежит в корне репозитория: тот же файл
        // гоняют iOS и Cloud Functions (specs/fixtures/points-fixtures.json).
        // PointsFixtureTest читает его как ресурс "/points-fixtures.json".
        resources.srcDir(rootProject.file("../specs/fixtures"))
    }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    // Flow как язык описания «живого» чтения в контрактах репозиториев.
    // Чистый Kotlin/JVM, без Android — границу слоя не нарушает.
    // api, а не implementation: Flow виден в сигнатурах, которые использует :app.
    api("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.1")

    // Юнит-тесты домена гоняются на голой JVM — без эмулятора и без Robolectric.
    testImplementation("junit:junit:4.13.2")
}
