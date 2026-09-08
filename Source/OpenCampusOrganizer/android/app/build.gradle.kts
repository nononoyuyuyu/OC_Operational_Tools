plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val verifyReleaseSigning by tasks.registering {
    doLast {
        val requiredVariables = listOf(
            "OCO_ANDROID_STORE_FILE",
            "OCO_ANDROID_STORE_PASSWORD",
            "OCO_ANDROID_KEY_ALIAS",
        )
        check(requiredVariables.all { !System.getenv(it).isNullOrBlank() }) {
            "OCO_RELEASE_SIGNING_REQUIRED: 配布用署名の環境変数が必要です。"
        }
        check(file(System.getenv("OCO_ANDROID_STORE_FILE")).isFile) {
            "OCO_RELEASE_SIGNING_REQUIRED: 配布用署名鍵が見つかりません。"
        }
    }
}

tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(verifyReleaseSigning)
}

android {
    namespace = "jp.nononoyuyuyu.open_campus_organizer"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "jp.nononoyuyuyu.open_campus_organizer"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    sourceSets.getByName("androidTest").java.srcDir("../../../../Tests/OpenCampusOrganizer/android_appearance")

    signingConfigs {
        create("release") {
            storeFile = System.getenv("OCO_ANDROID_STORE_FILE")?.let { file(it) }
            storePassword = System.getenv("OCO_ANDROID_STORE_PASSWORD")
            keyAlias = System.getenv("OCO_ANDROID_KEY_ALIAS")
            keyPassword = System.getenv("OCO_ANDROID_STORE_PASSWORD")
        }
    }

    buildTypes {
        release {
            // 署名情報がない場合は検証タスクで失敗させ、debug鍵では配布しない。
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
}

// GitHubで直接配布するAPKは、CPU別版と共通版の間でも更新できる番号にする。
// Flutter 3.44の旧Variant APIによるCPU別加算の後に設定する。
@Suppress("DEPRECATION")
android.applicationVariants.configureEach {
    outputs.forEach { output ->
        (output as com.android.build.gradle.api.ApkVariantOutput).versionCodeOverride = flutter.versionCode
    }
}
