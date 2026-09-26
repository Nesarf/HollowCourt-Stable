plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// RELEASE SIGNING, AND WHY IT IS NOT A BUILT-IN DEFAULT.
//
// An Android application's identity IS its signing key: the platform will only install an update whose
// signature matches the copy already there. Signing releases with the debug key -- which is what this
// file did -- is fine for sideloading onto a test device and fatal the moment a copy is anywhere else,
// because the debug keystore lives in the build directory and dies with it. The app that was installed
// can then never be updated by anybody, including its author.
//
// So the key is read from `android/key.properties`, which is NOT in git:
//
//     storeFile=release.jks      (relative to android/, or absolute)
//     storePassword=...
//     keyAlias=...
//     keyPassword=...
//
// `packaging/android/make_keystore.sh` writes both the keystore and that file. With no key.properties
// the build still works and falls back to the debug key, because a build that refuses to run is worse
// than one that warns -- but it warns LOUDLY, and the warning names the file to create. A silently
// debug-signed "release" is the failure this whole arrangement exists to prevent, and it is invisible
// without checking the signer, which `packaging/android/signing.sh` does.
import java.io.FileInputStream
import java.util.Properties

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.nesarf.hollow_court"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The application id is chosen, not left as the template's TODO. It is the identity Play and
        // every installed copy key off, so it is permanent once anything has shipped: `docs/DESIGN.md`
        // 0.1 fixes the naming (Hollow Court and nothing else) and 0.2 records that an earlier
        // section had the package name wrong and what it was.
        applicationId = "com.nesarf.hollow_court"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        // **The version the owner named, which is four-part and pubspec's `build-name` cannot be.** pub
        // requires `major.minor.patch`, so `version: 1.0.0+514` holds the number and this line shows the
        // name Android displays on the device: **1.0.0.514**. It is *derived* rather than written out, so
        // pubspec remains the single place a version is changed -- and the same string reaches the About
        // screen through `--dart-define=APP_VERSION`, built from the same two pubspec fields by the
        // packaging scripts. A version written in three places is a version that will disagree with itself.
        versionName = "${flutter.versionName}.${flutter.versionCode}"
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                // rootProject, NOT file(): the Android Gradle plugin resolves a relative path here
                // against the MODULE directory (android/app/), while key.properties sits in android/.
                // With `file()` the build failed at :app:validateSigningRelease looking for
                // android/app/release.jks -- and the failure was invisible because the script that
                // ran the build piped it into `tail`.
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKey) signingConfigs.getByName("release")
                else signingConfigs.getByName("debug")
        }
    }
}

// Said once per configuration, at the top of the build output rather than buried in it.
if (!hasReleaseKey) {
    logger.warn(
        "hollow-court: building a RELEASE without a release key. android/key.properties is absent, so " +
        "the APK will carry the DEBUG signature -- an installation of it can never be updated, because " +
        "the debug keystore lives in the build directory. Run packaging/android/make_keystore.sh to " +
        "create one, or packaging/android/signing.sh <apk> to see which key an artifact carries."
    )
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
