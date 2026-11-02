import java.util.Properties
import java.security.KeyStore
import java.security.cert.X509Certificate
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseProperties = Properties().apply {
    val localFile = rootProject.file("key.properties")
    if (localFile.isFile) localFile.inputStream().use { load(it) }
}
fun releaseValue(property: String, environment: String): String? =
    System.getenv(environment)?.takeIf { it.isNotBlank() }
        ?: releaseProperties.getProperty(property)?.takeIf { it.isNotBlank() }

val releaseStorePath = releaseValue("storeFile", "SEICYCLE_STORE_FILE")
val releaseStorePassword = releaseValue("storePassword", "SEICYCLE_STORE_PASSWORD")
val releaseKeyAlias = releaseValue("keyAlias", "SEICYCLE_KEY_ALIAS")
val releaseKeyPassword = releaseValue("keyPassword", "SEICYCLE_KEY_PASSWORD")
val releaseStoreFile = releaseStorePath?.let { rootProject.file(it) }

val validateReleaseCredentials = tasks.register("validateReleaseCredentials") {
    doLast {
        val missing = listOf(
            "storeFile" to releaseStorePath,
            "storePassword" to releaseStorePassword,
            "keyAlias" to releaseKeyAlias,
            "keyPassword" to releaseKeyPassword,
        ).filter { it.second == null }.map { it.first }
        if (missing.isNotEmpty()) throw GradleException(
            "Release signing is blocked: configure ${missing.joinToString()} in protected " +
                "android/key.properties or SEICYCLE_* environment variables. " +
                "See docs/PHASE_08_ANDROID_RELEASE.md. Debug signing is never a release fallback."
        )
        if (releaseStoreFile?.isFile != true) throw GradleException(
            "Release signing is blocked: the owner-managed keystore is unavailable."
        )
        try {
            val store = KeyStore.getInstance(releaseStoreFile, releaseStorePassword!!.toCharArray())
            val certificate = store.getCertificate(releaseKeyAlias) as? X509Certificate
                ?: throw IllegalArgumentException()
            require(store.isKeyEntry(releaseKeyAlias))
            require(store.getKey(releaseKeyAlias, releaseKeyPassword!!.toCharArray()) != null)
            require(!certificate.subjectX500Principal.name.contains("CN=Android Debug", ignoreCase = true))
            require(!releaseKeyAlias.equals("androiddebugkey", ignoreCase = true))
            certificate.checkValidity()
        } catch (_: Exception) {
            throw GradleException(
                "Release signing is blocked: keystore credentials/certificate are invalid or use an Android debug key."
            )
        }
    }
}
tasks.matching { it.name == "preReleaseBuild" || it.name == "validateSigningRelease" }.configureEach {
    dependsOn(validateReleaseCredentials)
}

android {
    namespace = "id.seicycle.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "id.seicycle.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = releaseStoreFile
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
