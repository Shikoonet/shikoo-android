plugins {
    id("com.android.library")
}

android {
    namespace = "dev.steenbakker.mobile_scanner"
    compileSdk = libs.versions.compileSdk.get().toInt()

    defaultConfig {
        minSdk = libs.versions.minSdk.get().toInt()
    }
}
