import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

// ClaudeBarKit: everything but the UI, one Kotlin Multiplatform project with a package per
// context (docs/architecture/MODULAR_DESIGN.md). scripts/build-kotlin.sh builds
// ClaudeBarKit.xcframework; Project.swift links it.
plugins {
    kotlin("multiplatform") version "2.4.20"
    kotlin("plugin.serialization") version "2.4.20"
    id("co.touchlab.skie") version "0.10.15"
}

group = "com.tddworks.claudebar"
version = "1.0.0"

kotlin {
    jvmToolchain(21)

    // JVM runs the JUnit suite; macOS is what the app links. Releases are universal.
    jvm()

    val xcf = XCFramework("ClaudeBarKit")
    listOf(macosArm64(), macosX64()).forEach {
        // os_log is a C macro; diagnostics calls it through a one-function shim.
        it.compilations.getByName("main").cinterops.create("oslog") {
            definitionFile.set(project.file("src/nativeInterop/cinterop/oslog.def"))
        }
        it.binaries.framework {
            baseName = "ClaudeBarKit"
            isStatic = true
            binaryOption("bundleId", "com.tddworks.claudebar.kit")
            xcf.add(this)
        }
    }

    sourceSets {
        // @ObjCName renames a Long count for Swift, so the face can show it as Int.
        all {
            languageSettings.optIn("kotlin.experimental.ExperimentalObjCName")
            // The macOS adapters call Apple frameworks through cinterop.
            languageSettings.optIn("kotlinx.cinterop.ExperimentalForeignApi")
        }
        commonMain.dependencies {
            implementation("org.jetbrains.kotlinx:kotlinx-io-core:0.9.1")
            implementation("org.jetbrains.kotlinx:atomicfu:0.33.0")
            implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.11.0")
            implementation("io.ktor:ktor-client-core:3.6.0")
            // activity's hook receiver: Claude Code's hooks POST to it on 127.0.0.1.
            implementation("io.ktor:ktor-server-cio:3.6.0")
            implementation("org.kotlincrypto.hash:sha2:0.8.0")
            implementation("org.kotlincrypto.macs:hmac-sha2:0.8.0")
        }
        macosMain.dependencies {
            implementation("io.ktor:ktor-client-darwin:3.6.0")
        }
        // The adapters' native suite (kotlin.test): Keychain and friends against the real system.
        macosTest.dependencies {
            implementation(kotlin("test"))
        }
        jvmTest.dependencies {
            implementation(project.dependencies.platform("org.junit:junit-bom:6.1.3"))
            implementation("org.junit.jupiter:junit-jupiter")
            implementation("org.junit.jupiter:junit-jupiter-params")
            runtimeOnly("org.junit.platform:junit-platform-launcher")
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
            implementation("io.ktor:ktor-client-mock:3.6.0")
            // ArchitectureTest: the package rules of MODULAR_DESIGN §3.
            implementation("com.lemonappdev:konsist:0.17.3")
        }
    }
}

tasks.named<Test>("jvmTest") {
    useJUnitPlatform()
}

skie {
    // XCFrameworks need a .swiftinterface; SKIE emits one only for distributable builds.
    build { produceDistributableFramework() }
    analytics { disableUpload.set(true) }
}
