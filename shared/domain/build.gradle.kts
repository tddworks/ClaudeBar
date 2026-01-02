plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    // JVM for Compose Desktop (Linux, Windows, macOS)
    jvm()

    // Native targets
    macosX64()
    macosArm64()
    linuxX64()
    mingwX64()

    sourceSets {
        val commonMain by getting {
            dependencies {
                implementation(libs.kotlinx.coroutines.core)
                implementation(libs.kotlinx.datetime)
                implementation(libs.kotlinx.serialization.json)
            }
        }

        val commonTest by getting {
            dependencies {
                implementation(libs.kotlin.test)
                implementation(libs.kotlinx.coroutines.test)
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
        }

        val mingwX64Main by getting {
            dependsOn(nativeMain)
        }
    }
}
