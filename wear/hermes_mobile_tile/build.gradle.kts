// Wave 4 Wear OS tile: a documented stub. NOT included in android/settings.gradle.kts,
// so the phone APK build and CI are unaffected. See wear/README.md to build it.
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.hermesagent.hermesMobile.wear"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.hermesagent.hermes_android"   // same id as the phone app (Wear pairing)
        minSdk = 30                                          // Wear OS 3+
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0-wear"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin { jvmToolchain(17) }

dependencies {
    implementation("androidx.wear.tiles:tiles:1.4.1")
    implementation("androidx.wear.protolayout:protolayout:1.2.1")
    implementation("androidx.wear.protolayout:protolayout-material:1.2.1")
    implementation("com.google.guava:guava:33.3.1-android")
}
