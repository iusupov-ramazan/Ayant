// Top-level build file. Plugin versions are declared here and applied per-module.
plugins {
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "2.0.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.20" apply false
    // Firebase (Google Services) — applied in :app only when google-services.json exists.
    id("com.google.gms.google-services") version "4.4.2" apply false
}
