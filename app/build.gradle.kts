plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.callagent.gateway"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.callagent.gateway"
        minSdk = 26
        targetSdk = 34
        versionCode = 457
        versionName = "1.4.18"
    }

    // Use one stable signing key for debug/release and module upgrades.
    // CI can provide a dedicated keystore through environment variables.
    // Local builds fall back to the standard Android debug keystore.
    signingConfigs {
        create("shared") {
            storeFile = file(
                System.getenv("GSM2SIP_KEYSTORE_PATH")
                    ?: (System.getProperty("user.home") + "/.android/debug.keystore")
            )
            storePassword = System.getenv("GSM2SIP_KEYSTORE_PASSWORD") ?: "android"
            keyAlias = System.getenv("GSM2SIP_KEY_ALIAS") ?: "androiddebugkey"
            keyPassword = System.getenv("GSM2SIP_KEY_PASSWORD") ?: "android"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("shared")
        }
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("shared")
        }
    }

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = "1.8"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    testImplementation("junit:junit:4.13.2")
}
