plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.touchlab.skie)
}

kotlin {
    // JVM for Compose Desktop (Linux, Windows, macOS)
    jvm()

    // Native targets for Swift interop via SKIE
    macosX64()
    macosArm64()
    linuxX64()
    mingwX64()

    sourceSets {
        val commonMain by getting {
            dependencies {
                implementation(projects.domain)
                implementation(libs.kotlinx.coroutines.core)
                implementation(libs.kotlinx.datetime)
                implementation(libs.kotlinx.serialization.json)
                implementation(libs.bundles.ktor.client)
                implementation(libs.multiplatform.settings)
                implementation(libs.multiplatform.settings.coroutines)
            }
        }

        val commonTest by getting {
            dependencies {
                implementation(libs.kotlin.test)
                implementation(libs.kotlinx.coroutines.test)
                implementation(libs.ktor.client.mock)
            }
        }

        val jvmMain by getting {
            dependencies {
                implementation(libs.ktor.client.okhttp)
                implementation(libs.slf4j.api)
                implementation(libs.logback.classic)
            }
        }

        val jvmTest by getting {
            dependencies {
                implementation(libs.bundles.jvm.test)
            }
        }

        // Native source set hierarchy
        val nativeMain by creating {
            dependsOn(commonMain)
        }

        val nativeTest by creating {
            dependsOn(commonTest)
        }

        val appleMain by creating {
            dependsOn(nativeMain)
            dependencies {
                implementation(libs.ktor.client.darwin)
            }
        }

        val appleTest by creating {
            dependsOn(nativeTest)
        }

        val macosX64Main by getting {
            dependsOn(appleMain)
        }

        val macosArm64Main by getting {
            dependsOn(appleMain)
        }

        val linuxX64Main by getting {
            dependsOn(nativeMain)
            dependencies {
                implementation(libs.ktor.client.curl)
            }
        }

        val mingwX64Main by getting {
            dependsOn(nativeMain)
            dependencies {
                implementation(libs.ktor.client.winhttp)
            }
        }
    }
}

// SKIE configuration for Swift interop
skie {
    features {
        // Enable Flow to AsyncSequence bridging
        enableFlowInterop.set(true)
        // Enable suspend function to async/await bridging
        enableSwiftUIInterop.set(true)
    }
}
