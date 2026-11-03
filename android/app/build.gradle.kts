import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties =
    Properties().apply {
        val localPropertiesFile = rootProject.file("local.properties")
        if (localPropertiesFile.exists()) {
            localPropertiesFile.inputStream().use { load(it) }
        }
    }

val releaseStoreFile = file("keystore.jks")
val releaseStorePassword = localProperties.getProperty("storePassword")
val releaseKeyAlias = localProperties.getProperty("keyAlias")
val releaseKeyPassword = localProperties.getProperty("keyPassword")
val hasReleaseSigning =
    releaseStoreFile.exists() &&
        releaseStorePassword != null &&
        releaseKeyAlias != null &&
        releaseKeyPassword != null

android {
    namespace = "com.follow.clash"
    compileSdk =
        libs.versions.compileSdk
            .get()
            .toInt()
    ndkVersion = libs.versions.ndkVersion.get()

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.follow.clash.root"
        minSdk = flutter.minSdkVersion
        targetSdk =
            libs.versions.targetSdk
                .get()
                .toInt()
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        val dartDefines =
            providers
                .gradleProperty("dart-defines")
                .orNull
                .orEmpty()
                .split(",")
        val safeMode =
            dartDefines.any {
                runCatching {
                    String(
                        Base64.getDecoder().decode(it),
                    ) == "SAFE_MODE=true"
                }.getOrDefault(false)
            }
        buildConfigField("boolean", "ROOT_TUN_SAFE_MODE", safeMode.toString())
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            keepDebugSymbols.add("**/libroot_mihomo.so")
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
        }

        release {
            isMinifyEnabled = true
            isShrinkResources = true
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    sourceSets {
        // Unit tests live under android/tests/ instead of each module's src/test.
        getByName("test").java.setSrcDirs(listOf("../tests/app"))
    }

    buildFeatures {
        buildConfig = true
    }
}

androidComponents {
    finalizeDsl { dsl ->
        val platforms = providers.gradleProperty("target-platform").orNull?.split(",")
        val rootAbis =
            listOfNotNull(
                "arm64-v8a".takeIf { platforms == null || "android-arm64" in platforms },
                "x86_64".takeIf { platforms == null || "android-x64" in platforms },
            )
        if (dsl.splits.abi.isEnable) {
            dsl.defaultConfig.ndk.abiFilters
                .clear()
            dsl.splits.abi.reset()
            dsl.splits.abi.include(*rootAbis.toTypedArray())
        } else {
            dsl.defaultConfig.ndk.abiFilters
                .retainAll(rootAbis)
            if (dsl.defaultConfig.ndk.abiFilters
                    .isEmpty()
            ) {
                dsl.defaultConfig.ndk.abiFilters
                    .addAll(rootAbis)
            }
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
    implementation(project(":root-tun"))
    implementation("org.yaml:snakeyaml:2.3")
    implementation(project(":service"))
    implementation(project(":common"))
    implementation(project(":core"))
    implementation(libs.core.splashscreen)
    implementation(libs.gson)
    implementation(libs.smali.dexlib2) {
        exclude(group = "com.google.guava", module = "guava")
    }
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
