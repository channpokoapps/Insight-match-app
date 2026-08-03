import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// リリース署名の情報は key.properties（コミット禁止・gitignore 済み）から読む。
// 鍵を持たない環境（他の開発者・CI の analyze ジョブなど）でもビルドが
// 壊れないよう、ファイルが無い場合は debug 署名にフォールバックする。
// 鍵の作成と各項目の意味は docs/manual_setup/github_automation.md §5 を参照。
//
// storeFile の解決には rootProject.file() を使う。key.properties は
// app/android/ 直下にあり、相対パス（例: upload-keystore.jks）も同じ階層を
// 基準に書かれるため。app モジュール基準の file() だと 1 階層ずれて
// 「ファイルが見つからない」になる。CI は $RUNNER_TEMP の絶対パスを渡して
// くるが、rootProject.file() は絶対パスをそのまま扱うのでどちらも動く。
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKeystore) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}

// google-services.json（Firebase Analytics / FCM 用）が配置されている場合のみ
// google-services プラグインを適用する。未配置でもビルドを通すための条件分岐
// （手順は docs/manual_setup/gcp_firebase.md を参照）。
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "app.insightmatch.android"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.insightmatch.android"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // 鍵が無い環境で create("release") すると storeFile が null のまま
        // 署名タスクが失敗するため、鍵があるときだけ定義する。
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = (keystoreProperties["storeFile"] as String?)?.let {
                    rootProject.file(it)
                }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // 鍵が無い環境向けの退避。ここで作った APK を配布してはならない
                // （App Distribution は署名が変わると上書き更新できなくなる）。
                signingConfigs.getByName("debug")
            }
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
