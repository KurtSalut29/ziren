plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.ziren.app"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        // Required by flutter_local_notifications, which is how a responder's
        // phone actually rings when a dispatcher assigns them an incident.
        //
        // The plugin schedules through java.time, which arrived in API 26 —
        // this app supports API 23. Desugaring rewrites those calls at build
        // time so they work on the older devices, and without it the build
        // fails outright at :app:checkDebugAarMetadata with
        // "Dependency ':flutter_local_notifications' requires core library
        // desugaring to be enabled". Not optional, and not a warning: the APK
        // does not build at all.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ziren.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }

        debug {
            // ============================================================
            // One ABI in debug, and the reason is the Flutter tool, not the
            // phone.
            //
            // A debug APK bundles a full native payload per ABI, and Gradle
            // packages every ABI the engine ships. That came to 335 MB here:
            // 84 MB of arm64 plus 86 MB of x86, x86_64 and armeabi-v7a that
            // no device in this project can execute.
            //
            // Size alone would be survivable. What is not is what the tool
            // does with it afterwards: _calculateSha in flutter_tools'
            // gradle.dart reads the FINISHED APK into a single byte buffer to
            // hash it, and the crypto sink grows a second buffer beside it.
            // On this ~7 GB machine that is where the build died, after a
            // successful Gradle run:
            //
            //     OutOfMemoryError
            //     #7  HashSink.add (package:crypto/src/hash_sink.dart:79)
            //     #10 _calculateSha (flutter_tools/src/android/gradle.dart:972)
            //     #11 AndroidGradleBuilder.buildGradleApp (gradle.dart:617)
            //
            // NOT `flutter run --target-platform android-arm64`. That flag
            // selects the Dart target; in debug it leaves the packaged ABIs
            // alone, and the APK comes out byte-identical. The filter has to
            // be here, where Gradle decides what goes in.
            //
            // Debug only. Release and the Play Store bundle keep every ABI —
            // this is about the machine doing the building, not about which
            // phones the app supports. To test on an armeabi-v7a handset, add
            // it to this list rather than removing the filter.
            //
            // Same family of problem as the jvmargs note in
            // android/gradle.properties: two workloads, one small box.
            // ============================================================
            ndk {
                abiFilters += listOf("arm64-v8a")
            }
        }
    }
}

dependencies {
    // The desugaring runtime enabled above. 2.1.4 is the minimum
    // flutter_local_notifications 18.x asks for.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
