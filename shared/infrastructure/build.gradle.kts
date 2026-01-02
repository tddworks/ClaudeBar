plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.touchlab.skie)
}

kotlin {
    // JVM for Compose Desktop (Linux, Windows, macOS)
    jvm()

    // Native targets
    macosX64()
    macosArm64()
    linuxX64()
    mingwX64()

    // Use default hierarchy template (Kotlin 1.9.20+)
    applyDefaultHierarchyTemplate()

    sourceSets {
        commonMain.dependencies {
            api(projects.domain)  // Use api to export domain types in framework
            implementation(libs.kotlinx.coroutines.core)
            implementation(libs.kotlinx.datetime)
            implementation(libs.kotlinx.serialization.json)
            implementation(libs.bundles.ktor.client)
            implementation(libs.multiplatform.settings)
            implementation(libs.multiplatform.settings.coroutines)
        }

        commonTest.dependencies {
            implementation(libs.kotlin.test)
            implementation(libs.kotlinx.coroutines.test)
            implementation(libs.ktor.client.mock)
        }

        jvmMain.dependencies {
            implementation(libs.ktor.client.okhttp)
            implementation(libs.slf4j.api)
            implementation(libs.logback.classic)
        }

        jvmTest.dependencies {
            implementation(libs.bundles.jvm.test)
        }

        // Apple-specific (macOS) - use Darwin HTTP engine
        appleMain.dependencies {
            implementation(libs.ktor.client.darwin)
        }

        // Linux-specific - use Curl HTTP engine
        linuxMain.dependencies {
            implementation(libs.ktor.client.curl)
        }

        // Windows-specific - use WinHttp engine
        mingwMain.dependencies {
            implementation(libs.ktor.client.winhttp)
        }
    }
}

// SKIE configuration for Swift interop
// Flow to AsyncSequence and suspend to async/await are enabled by default in SKIE 0.10+
