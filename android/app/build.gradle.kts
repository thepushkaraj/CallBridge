plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Release signing: android/release.keystore is gitignored. CI writes it from
// RELEASE_KEYSTORE_B64. Passwords come from the environment, never the repo.
// Without the keystore, release builds keep the debug signature.
val releaseKeystoreFile = rootProject.file("release.keystore")
val releaseStorePassword = System.getenv("CALLBRIDGE_STORE_PASSWORD")
val releaseKeyPassword = System.getenv("CALLBRIDGE_KEY_PASSWORD")

android {
    namespace = "io.github.thepushkaraj.callbridge"
    compileSdk = 34

    defaultConfig {
        applicationId = "io.github.thepushkaraj.callbridge"
        minSdk = 26
        targetSdk = 34
        versionCode = 14
        versionName = "0.4.3"
    }

    signingConfigs {
        if (releaseKeystoreFile.exists()
            && !releaseStorePassword.isNullOrEmpty()
            && !releaseKeyPassword.isNullOrEmpty()
        ) {
            create("release") {
                storeFile = releaseKeystoreFile
                storePassword = releaseStorePassword
                keyAlias = "callbridge"
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfigs.findByName("release")?.let { signingConfig = it }
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

gradle.taskGraph.whenReady {
    val assemblingRelease = allTasks.any {
        it.project == project && (it.name == "assembleRelease" || it.name == "bundleRelease")
    }
    if (assemblingRelease
        && releaseKeystoreFile.exists()
        && (releaseStorePassword.isNullOrEmpty() || releaseKeyPassword.isNullOrEmpty())
    ) {
        throw GradleException(
            "release.keystore is present but CALLBRIDGE_STORE_PASSWORD or " +
                "CALLBRIDGE_KEY_PASSWORD is not set. Refusing to sign the release with the debug key."
        )
    }
}
