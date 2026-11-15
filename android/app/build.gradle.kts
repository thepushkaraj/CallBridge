import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Release signing: release.keystore lives outside git (gitignored). CI provides
// it via a secret; local builds fall back to the debug signature.
val releaseKeystoreFile = rootProject.file("release.keystore")
val releaseKeystoreProperties = Properties().apply {
    if (releaseKeystoreFile.exists()) {
        load(FileInputStream(releaseKeystoreFile))
    }
}

android {
    namespace = "io.github.thepushkaraj.callbridge"
    compileSdk = 34

    defaultConfig {
        applicationId = "io.github.thepushkaraj.callbridge"
        minSdk = 26
        targetSdk = 34
        versionCode = 9
        versionName = "0.3.1"
    }

    signingConfigs {
        if (releaseKeystoreFile.exists()) {
            create("release") {
                storeFile = releaseKeystoreFile
                storePassword = "callbridge2026"
                keyAlias = "callbridge"
                keyPassword = "callbridge2026"
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            if (releaseKeystoreFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")

    val camerax = "1.3.4"
    implementation("androidx.camera:camera-core:$camerax")
    implementation("androidx.camera:camera-camera2:$camerax")
    implementation("androidx.camera:camera-lifecycle:$camerax")
    implementation("androidx.camera:camera-view:$camerax")

    // Bundled on-device QR model; no Google Play Services required.
    implementation("com.google.mlkit:barcode-scanning:17.3.0")
}
