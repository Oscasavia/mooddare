import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingFile = rootProject.file("key.properties")
if (signingFile.exists()) signingFile.inputStream().use { signingProperties.load(it) }

android {
    namespace = "com.example.mooddare"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Keep in sync with Firebase. Choose the store application ID before release.
        applicationId = "com.example.mooddare"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signingFile.exists()) {
            create("release") {
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
                storeFile = file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
            }
        }
    }
    buildTypes {
        release {
            // Never silently sign a production build with the debug key.
            if (signingFile.exists()) signingConfig = signingConfigs.getByName("release")
        }
    }

}

flutter {
    source = "../.."
}

dependencies {
    // FlutterFire 5.x otherwise selects Auth 23.2.1, whose encrypted session
    // persistence has a documented regression. Keep Auth on the repaired line.
    implementation("com.google.firebase:firebase-auth:24.2.0")
    implementation("androidx.media3:media3-transformer:1.5.1")
    testImplementation("junit:junit:4.13.2")
    // Bundled detector works offline, including on the first launch.
    implementation("com.google.mlkit:face-detection:16.1.7")
    implementation("com.google.mlkit:face-mesh-detection:16.0.0-beta1")
    // Match the CameraX version used by the pinned Flutter camera plugin.
    implementation("androidx.camera:camera-camera2:1.5.0-beta01")
    implementation("androidx.camera:camera-lifecycle:1.5.0-beta01")
    implementation("com.google.guava:guava:33.4.8-android")
}
