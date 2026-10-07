plugins {
    kotlin("multiplatform")
    id("co.touchlab.skie")
    id("co.touchlab.kmmbridge.github")
}

group = "com.tddworks.claudebar"
version = "0.0.1"

kotlin {
    jvmToolchain(21)

    // JVM runs the JUnit suite; macOS is what the app links. KMMBridge builds the XCFramework.
    jvm()

    listOf(macosArm64(), macosX64()).forEach {
        it.binaries.framework {
            baseName = "ClaudeBarQuotas"
            isStatic = true
            binaryOption("bundleId", "com.tddworks.claudebar.kmp.quotas")
        }
    }

    sourceSets {
        commonMain.dependencies {
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.11.0")
        }
        jvmTest.dependencies {
            implementation(project.dependencies.platform("org.junit:junit-bom:6.1.3"))
            implementation("org.junit.jupiter:junit-jupiter")
            runtimeOnly("org.junit.platform:junit-platform-launcher")
            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
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

kmmbridge {
    gitHubReleaseArtifacts()
    // Default is the git root, which would sit beside Tuist; keep the package in the spike.
    spm(spmDirectory = rootProject.projectDir.path, swiftToolVersion = "6.0") {
        macOS { v("15") }
    }
}
