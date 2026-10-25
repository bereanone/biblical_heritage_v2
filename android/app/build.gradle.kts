import org.gradle.api.tasks.Copy
import java.io.FileInputStream
import java.util.Properties
import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file(
    providers.gradleProperty("releaseSigningProperties").orNull ?: "key.properties"
)
// Explicit test-bed override: the currently installed Android app uses this
// machine's debug certificate. Production release builds still fail closed.
val testBedDebugSigning = providers.gradleProperty("testBedDebugSigning").orNull == "true"
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val playPurchaseProperties = Properties().apply {
    val source = rootProject.file("play-purchases.properties")
    if (source.exists()) source.inputStream().use { load(it) }
}
val playLicensePublicKey = providers.gradleProperty("playLicensePublicKey").orNull
    ?: playPurchaseProperties.getProperty("playLicensePublicKey", "")
val playLegacyCutoffMs = providers.gradleProperty("playLegacyCutoffMs").orNull ?: "0"
val androidBillingEnabled = providers.gradleProperty("dart-defines").orNull.orEmpty()
    .split(",").filter { it.isNotEmpty() }.any {
        runCatching { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
            .getOrDefault("") == "STUDYBIBLE_ANDROID_BILLING=true"
    }
if (androidBillingEnabled) {
    require(playLicensePublicKey.isNotBlank()) { "Play billing requires the app's public verification key." }
    require((playLegacyCutoffMs.toLongOrNull() ?: 0) > 0) {
        "Set playLegacyCutoffMs for existing-customer access before building paid Play release."
    }
    require(!testBedDebugSigning) { "Paid Play release must use production signing." }
}

val playAssetDelivery = providers.gradleProperty("playAssetDelivery").orNull == "true"
android {
    if (playAssetDelivery) assetPacks += setOf(":bible_audio_1", ":bible_audio_2", ":reader_voices")
    namespace = "com.deanbowen.bibleappmac"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.deanbowen.bibleappmac"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Set these only for the validated Play production candidate.
        buildConfigField("String", "PLAY_LICENSE_PUBLIC_KEY", "\"${playLicensePublicKey}\"")
        buildConfigField("long", "PLAY_LEGACY_CUTOFF_MS", "${playLegacyCutoffMs}L")
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = (keystoreProperties["storeFile"] as String?)?.let(::file)
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildFeatures { buildConfig = true }

    buildTypes {
        release {
            // Flutter derives its Dart build mode from this flag. A debuggable
            // release variant can package debug assets with the release engine
            // and abort before Dart starts. Use the debug variant for run-as.
            isDebuggable = false
            // Release builds fail closed when key.properties is absent or
            // incomplete; they must never silently produce a debug-signed APK.
            signingConfig = signingConfigs.getByName(
                if (testBedDebugSigning) "debug" else "release"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.android.billingclient:billing:8.0.0")
    implementation("com.google.android.gms:play-services-auth-blockstore:16.4.0")
    testImplementation("junit:junit:4.12")
}

if (playAssetDelivery) {
    val stagePlayAssets = tasks.register<Exec>("stagePlayAssets") {
        dependsOn("compileFlutterBuildRelease")
        val flutterAssets = layout.buildDirectory.dir("intermediates/flutter/release/flutter_assets")
        inputs.dir(flutterAssets)
        outputs.file(rootProject.file("play_assetpacks/staging-manifest.json"))
        // Rerun to replace hard links whenever Flutter regenerates its assets.
        outputs.upToDateWhen { false }
        commandLine("python3", rootProject.file("../tool/stage_play_asset_packs.py"),
            flutterAssets.get().asFile, rootProject.file("play_assetpacks"))
    }
    tasks.withType<Copy>().configureEach {
        if (name == "copyFlutterAssetsRelease") {
            dependsOn(stagePlayAssets)
            exclude("flutter_assets/assets/audio/qwen_bible/**")
            exclude("flutter_assets/assets/audio/kokoro/**")
        }
    }
}
