import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

// The Quotas kernel, written once (docs/architecture/MODULAR_DESIGN.md §3.1).
// scripts/build-kotlin.sh builds QuotaKernel.xcframework; Project.swift links it into Quotas.
plugins {
    kotlin("multiplatform") version "2.4.20"
    id("co.touchlab.skie") version "0.10.15"
}

group = "com.tddworks.claudebar"
version = "1.0.0"

kotlin {
    jvmToolchain(21)

    // JVM runs the JUnit suite; macOS is what the app links. Releases are universal.
    jvm()

    val xcf = XCFramework("QuotaKernel")
    listOf(macosArm64(), macosX64()).forEach {
        it.binaries.framework {
            baseName = "QuotaKernel"
            isStatic = true
            binaryOption("bundleId", "com.tddworks.claudebar.quotakernel")
            xcf.add(this)
        }
    }

    sourceSets {
        // @ObjCName renames a Long count for Swift, so the face can show it as Int.
        all { languageSettings.optIn("kotlin.experimental.ExperimentalObjCName") }
        jvmTest.dependencies {
            implementation(project.dependencies.platform("org.junit:junit-bom:6.1.3"))
            implementation("org.junit.jupiter:junit-jupiter")
            runtimeOnly("org.junit.platform:junit-platform-launcher")
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
