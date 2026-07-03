import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}
val releaseSigningKeys = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
val hasReleaseSigning = releaseSigningKeys.all { key ->
    !keystoreProperties.getProperty(key).isNullOrBlank()
}

android {
    namespace = "my.turin.vault"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "my.turin.vault"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 인라인 자동완성(키보드 추천 줄) 지원
    implementation("androidx.autofill:autofill:1.1.0")
}

gradle.taskGraph.whenReady {
    val needsReleaseSigning = allTasks.any { task ->
        val taskName = task.name.lowercase()
        taskName.contains("release") &&
            (taskName.contains("assemble") || taskName.contains("bundle") || taskName.contains("package"))
    }

    if (needsReleaseSigning && !hasReleaseSigning) {
        throw GradleException(
            "Android release signing is not configured. Create app/android/key.properties or use GitHub Actions signing secrets.",
        )
    }
}
