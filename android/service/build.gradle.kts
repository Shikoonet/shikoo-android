import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.library")
}

// Shikoo: libovpn3.so for the same ABIs as :core's libclash.so (android/core/build.gradle.kts).
val ovpnAbiByPlatform =
    linkedMapOf("android-arm" to "armeabi-v7a", "android-arm64" to "arm64-v8a", "android-x64" to "x86_64")
val ovpnAbis =
    (rootProject.findProperty("target-platform") as String?)
        ?.split(",")
        ?.map { ovpnAbiByPlatform[it.trim()] ?: throw GradleException("No OpenVPN 3 for Flutter target platform $it") }
        ?: ovpnAbiByPlatform.values.toList()

android {
    namespace = "com.follow.clash.service"
    compileSdk = libs.versions.compileSdk.get().toInt()
    ndkVersion = libs.versions.ndkVersion.get()

    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()

        ndk {
            abiFilters += ovpnAbis
        }
    }

    externalNativeBuild {
        cmake {
            path("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        // Unit tests live under android/tests/ instead of each module's src/test.
        getByName("test").java.setSrcDirs(listOf("../tests/service"))
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":core"))
    implementation(project(":common"))
    implementation(libs.gson)
    implementation(libs.androidx.core)
    implementation(libs.annotation.jvm)
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
