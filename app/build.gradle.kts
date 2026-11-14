// Android shell around the Rust engine: no Java/Kotlin code, only NativeActivity + libmezdu.so.
// The .so files in src/main/jniLibs are built from crates/ by CI (.github/workflows/android.yml) and committed,
// so any Gradle build (AI Studio included) packs the current engine without needing Rust or the NDK.
plugins {
    alias(libs.plugins.android.application)
}

android {
    namespace = "ru.mezhdu.game"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.aistudio.mezhdu.vktxqp"
        minSdk = 26
        targetSdk = 36
        versionCode = 2
        versionName = "0.1.0"
    }

    val debugKs = file("${rootDir}/debug.keystore")
    signingConfigs {
        if (debugKs.exists()) {
            getByName("debug") {
                storeFile = debugKs
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }
}
