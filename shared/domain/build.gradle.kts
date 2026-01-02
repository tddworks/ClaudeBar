plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    // JVM for Compose Desktop (Linux, Windows, macOS)
    jvm()

    // Native targets - default hierarchy template handles source set relationships
    macosX64()
    macosArm64()
    linuxX64()
    mingwX64()

    // Use default hierarchy template (Kotlin 1.9.20+)
    applyDefaultHierarchyTemplate()

    sourceSets {
        commonMain.dependencies {
            implementation(libs.kotlinx.coroutines.core)
            implementation(libs.kotlinx.datetime)
            implementation(libs.kotlinx.serialization.json)
        }

        commonTest.dependencies {
            implementation(libs.kotlin.test)
            implementation(libs.kotlinx.coroutines.test)
        }
    }
}
