plugins {
    id("com.android.application")
}

dependencies {
}

android {
    namespace = "com.slint_app.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.slint_app.app"
        minSdk = 31
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"

        ndk {
            // Default: arm64-v8a (most devices) + x86_64 (emulators)
            // armeabi-v7a and x86 require building Skia from source
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    // Enable AAB (App Bundle) support
    bundle {
        language {
            enableSplit = true
        }
        density {
            enableSplit = true
        }
        abi {
            enableSplit = true
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }
}
