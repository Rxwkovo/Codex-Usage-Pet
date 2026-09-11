plugins { id("com.android.application") }
android {
    namespace = "dev.rxwkovo.codexpet"
    compileSdk = 37
    defaultConfig {
        applicationId = "dev.rxwkovo.codexpet"
        minSdk = 26
        targetSdk = 35
        versionCode = 3
        versionName = "0.2.0-preview"
        testInstrumentationRunner = "android.test.InstrumentationTestRunner"
    }
    buildTypes { release { isMinifyEnabled = false } }
}
dependencies {
    implementation("com.google.zxing:core:3.5.3")
    testImplementation("junit:junit:4.13.2")
}
