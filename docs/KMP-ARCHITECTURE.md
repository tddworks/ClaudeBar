# Kotlin Multiplatform Architecture Blueprint for ClaudeBar

**Document Status:** Architecture Design (Implementation Guide)
**Created:** 2026-01-02
**Target:** ClaudeBar v1.0+ (KMP Migration)

---

## Executive Summary

This document defines the complete architecture for migrating ClaudeBar to Kotlin Multiplatform (KMP) following the **"Shared Core + Platform UI"** pattern. The goal is to:

1. **Share** domain logic, business rules, and cross-platform infrastructure via KMP
2. **Keep** Swift UI for macOS (existing investment, SwiftUI excellence)
3. **Add** Compose Desktop UI for Linux/Windows support
4. **Maintain** the clean architecture principles from the current Swift codebase

**Migration Strategy:** Gradual adoption - port domain layer first, then infrastructure, keeping Swift UI intact for macOS.

---

## Table of Contents

1. [Current Architecture Analysis](#current-architecture-analysis)
2. [KMP Module Structure](#kmp-module-structure)
3. [Swift-KMP Interop Strategy](#swift-kmp-interop-strategy)
4. [Cross-Platform Infrastructure](#cross-platform-infrastructure)
5. [Probe Implementation Strategy](#probe-implementation-strategy)
6. [Build System and Tooling](#build-system-and-tooling)
7. [Testing Strategy](#testing-strategy)
8. [Migration Roadmap](#migration-roadmap)
9. [Critical Design Decisions](#critical-design-decisions)

---

## Current Architecture Analysis

### Patterns Found in ClaudeBar Swift Codebase

#### Layer Structure (Clean Architecture)

```
Domain Layer (Sources/Domain/)
├── Rich domain models with behavior (UsageQuota, UsageSnapshot, QuotaStatus)
├── Protocols for external dependencies (UsageProbe, ProviderSettingsRepository)
├── QuotaMonitor as single source of truth (@Observable actor)
└── Pure business logic, zero external dependencies

Infrastructure Layer (Sources/Infrastructure/)
├── CLI Probes (ClaudeUsageProbe, CodexUsageProbe, GeminiUsageProbe, etc.)
├── Storage implementations (UserDefaultsProviderSettingsRepository)
├── Adapters (InteractiveRunner, ProcessRPCTransport, NetworkClient)
└── Logging (AppLog dual-output: OSLog + FileLogger)

App Layer (Sources/App/)
├── SwiftUI views consuming domain directly (no ViewModel)
├── ClaudeBarApp entry point with dependency injection
└── Platform-specific UI (menu bar, settings, Sparkle updates)
```

#### Key Abstractions Identified

| Abstraction | Current Swift Implementation | KMP Portability |
|-------------|------------------------------|-----------------|
| `UsageQuota` | Struct with computed properties | ✅ Data class with extension functions |
| `UsageSnapshot` | Struct with domain queries | ✅ Data class with extension functions |
| `QuotaStatus` | Enum with business thresholds | ✅ Sealed class |
| `AIProvider` | Protocol with @Observable classes | ⚠️ Interface + StateFlow |
| `QuotaMonitor` | @Observable actor | ⚠️ Class with StateFlow + coroutines |
| `UsageProbe` | Protocol for CLI/API probing | ✅ Interface with suspend functions |
| `ProviderSettingsRepository` | Protocol for UserDefaults | ✅ Interface with expect/actual |
| `NetworkClient` | Protocol over URLSession | ✅ Ktor HttpClient |

---

## KMP Module Structure

### Gradle Module Hierarchy

```
claudebar/
├── shared/                          # KMP shared code
│   ├── domain/                      # Pure domain logic (commonMain only)
│   │   ├── commonMain/
│   │   │   └── kotlin/com/tddworks/claudebar/domain/
│   │   │       ├── model/
│   │   │       │   ├── UsageQuota.kt
│   │   │       │   ├── UsageSnapshot.kt
│   │   │       │   ├── QuotaStatus.kt
│   │   │       │   ├── AccountTier.kt
│   │   │       │   ├── QuotaType.kt
│   │   │       │   └── CostUsage.kt
│   │   │       ├── provider/
│   │   │       │   ├── AIProvider.kt
│   │   │       │   ├── UsageProbe.kt
│   │   │       │   ├── ProviderSettingsRepository.kt
│   │   │       │   └── CredentialRepository.kt
│   │   │       └── monitor/
│   │   │           ├── QuotaMonitor.kt
│   │   │           └── QuotaAlerter.kt
│   │   ├── commonTest/
│   │   └── build.gradle.kts
│   │
│   ├── infrastructure/              # Cross-platform infrastructure
│   │   ├── commonMain/
│   │   │   └── kotlin/com/tddworks/claudebar/infra/
│   │   │       ├── network/
│   │   │       │   ├── NetworkClient.kt          # Ktor-based
│   │   │       │   └── InsecureLocalhostClient.kt
│   │   │       ├── storage/
│   │   │       │   └── ProviderSettings.kt       # multiplatform-settings
│   │   │       ├── probes/
│   │   │       │   ├── CopilotUsageProbe.kt      # 100% shared (HTTP only)
│   │   │       │   ├── GeminiAPIProbe.kt         # 100% shared (HTTP only)
│   │   │       │   └── ProbeError.kt
│   │   │       ├── cli/
│   │   │       │   └── CLIExecutor.kt            # expect/actual interface
│   │   │       └── logging/
│   │   │           └── AppLog.kt                 # expect/actual
│   │   ├── jvmMain/                              # JVM-specific (Compose Desktop)
│   │   │   └── kotlin/com/tddworks/claudebar/infra/
│   │   │       ├── cli/
│   │   │       │   └── JvmCLIExecutor.kt         # ProcessBuilder-based
│   │   │       ├── probes/
│   │   │       │   ├── ClaudeUsageProbe.kt       # CLI-based
│   │   │       │   ├── CodexUsageProbe.kt        # RPC-based
│   │   │       │   └── AntigravityUsageProbe.kt  # Process + API
│   │   │       └── logging/
│   │   │           └── JvmAppLog.kt              # SLF4J
│   │   ├── appleMain/                            # Apple-specific (macOS)
│   │   │   └── kotlin/com/tddworks/claudebar/infra/
│   │   │       ├── cli/
│   │   │       │   └── NativeCLIExecutor.kt      # posix_spawn
│   │   │       └── logging/
│   │   │           └── OSLogAppLog.kt
│   │   ├── linuxMain/                            # Linux-specific
│   │   ├── mingwMain/                            # Windows-specific
│   │   └── build.gradle.kts
│   │
│   └── build.gradle.kts                          # Root shared module config
│
├── macos-swift/                                  # Swift UI for macOS (keep existing)
│   ├── Sources/App/
│   ├── KMPBridge/                                # Swift interop layer
│   │   ├── QuotaMonitorBridge.swift              # StateFlow → @Published
│   │   ├── AIProviderBridge.swift
│   │   └── Extensions.swift
│   └── Package.swift
│
├── desktop-compose/                              # Compose Desktop (JVM)
│   ├── src/jvmMain/kotlin/
│   │   ├── Main.kt
│   │   └── ui/
│   └── build.gradle.kts
│
├── settings.gradle.kts
└── build.gradle.kts
```

### Platform Targets

```kotlin
// shared/build.gradle.kts
kotlin {
    // JVM for Compose Desktop (Linux, Windows, macOS with Rosetta)
    jvm()

    // Native targets
    macosX64()      // Intel Macs
    macosArm64()    // Apple Silicon Macs
    linuxX64()      // Linux
    mingwX64()      // Windows

    sourceSets {
        val commonMain by getting {
            dependencies {
                implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.8.0")
                implementation("org.jetbrains.kotlinx:kotlinx-datetime:0.5.0")
                implementation("io.ktor:ktor-client-core:2.3.7")
                implementation("com.russhwolf:multiplatform-settings:1.1.1")
            }
        }

        val jvmMain by getting {
            dependencies {
                implementation("io.ktor:ktor-client-okhttp:2.3.7")
                implementation("org.slf4j:slf4j-api:2.0.9")
            }
        }

        val nativeMain by creating { dependsOn(commonMain) }
        val appleMain by creating { dependsOn(nativeMain) }
        val macosX64Main by getting { dependsOn(appleMain) }
        val macosArm64Main by getting { dependsOn(appleMain) }
        val linuxX64Main by getting { dependsOn(nativeMain) }
        val mingwX64Main by getting { dependsOn(nativeMain) }
    }
}
```

---

## Swift-KMP Interop Strategy

### Chosen Strategy: KMP Domain + Swift Bridge Layer

**Rationale:**
- Preserves Swift UI excellence and @Observable reactivity for macOS
- Shares 80%+ of logic via KMP (domain + most infrastructure)
- Thin Swift bridge layer converts KMP StateFlow → SwiftUI @Published
- Other platforms (Linux/Windows) get native Compose Desktop UI with direct KMP usage

### Swift Bridge Architecture

```swift
// macos-swift/KMPBridge/QuotaMonitorBridge.swift

import Foundation
import Combine
import ClaudeBarShared  // KMP XCFramework

/// Swift wrapper for KMP QuotaMonitor that bridges StateFlow to Combine
@MainActor
@Observable
public final class QuotaMonitorBridge {
    private let kmpMonitor: QuotaMonitor  // From KMP

    @Published public private(set) var enabledProviders: [AIProviderBridge] = []
    @Published public private(set) var selectedProviderId: String = "claude"
    @Published public private(set) var isRefreshing: Bool = false

    public init(kmpMonitor: QuotaMonitor) {
        self.kmpMonitor = kmpMonitor

        // Bridge StateFlow → Combine Publisher
        kmpMonitor.enabledProvidersFlow.asPublisher()
            .map { providers in
                providers.map { AIProviderBridge(kmpProvider: $0) }
            }
            .receive(on: DispatchQueue.main)
            .assign(to: &$enabledProviders)
    }

    public func refreshAll() async {
        await kmpMonitor.refreshAll()
    }
}
```

---

## Cross-Platform Infrastructure

### Network Layer: Ktor

```kotlin
// shared/infrastructure/commonMain/.../network/NetworkClient.kt

interface NetworkClient {
    suspend fun request(request: HttpRequest): HttpResponse
}

data class HttpRequest(
    val url: String,
    val method: HttpMethod,
    val headers: Map<String, String> = emptyMap(),
    val body: ByteArray? = null,
    val timeoutMs: Long = 30_000
)

data class HttpResponse(
    val statusCode: Int,
    val data: ByteArray,
    val headers: Map<String, String>
)

class KtorNetworkClient(
    private val client: HttpClient = HttpClient { }
) : NetworkClient {
    override suspend fun request(request: HttpRequest): HttpResponse {
        val response = client.request(request.url) {
            method = request.method
            request.headers.forEach { (k, v) -> header(k, v) }
            request.body?.let { setBody(it) }
        }

        return HttpResponse(
            statusCode = response.status.value,
            data = response.readBytes(),
            headers = response.headers.entries().associate { it.key to it.value.joinToString(",") }
        )
    }
}
```

### Settings Storage: multiplatform-settings

```kotlin
// Platform-specific creation (expect/actual)
expect fun createSettings(): ObservableSettings

// appleMain
actual fun createSettings(): ObservableSettings {
    return NSUserDefaultsSettings.Factory()
        .create(NSUserDefaults.standardUserDefaults)
}

// jvmMain
actual fun createSettings(): ObservableSettings {
    return PreferencesSettings(
        Preferences.userRoot().node("com.tddworks.claudebar")
    )
}
```

### CLI Execution: expect/actual Pattern

```kotlin
// commonMain/expect/CLIExecutor.kt

data class CLIResult(val output: String, val exitCode: Int)

expect interface CLIExecutor {
    suspend fun execute(
        binary: String,
        args: List<String>,
        input: String? = null,
        timeoutMs: Long = 30_000,
        workingDirectory: String? = null,
        autoResponses: Map<String, String> = emptyMap()
    ): CLIResult

    fun locate(binary: String): String?
}

// jvmMain - ProcessBuilder
// appleMain - posix_spawn
// mingwMain - CreateProcess
```

---

## Probe Implementation Strategy

### Shareability Matrix

| Probe | CLI/API | KMP Strategy | Shareability |
|-------|---------|--------------|--------------|
| **CopilotUsageProbe** | GitHub API | commonMain | ✅ 100% |
| **GeminiAPIProbe** | Google API | commonMain + expect/actual file | ✅ 95% |
| **ClaudeUsageProbe** | claude CLI | Shared parsing, platform CLI | ⚠️ 70% |
| **CodexUsageProbe** | Codex RPC | Shared RPC, platform PTY | ⚠️ 60% |
| **AntigravityUsageProbe** | Local API | Shared API, platform process detection | ⚠️ 70% |

### Fully Shared Probes (100% commonMain)

```kotlin
// CopilotUsageProbe - pure HTTP + JSON, no platform dependencies
class CopilotUsageProbe(
    private val networkClient: NetworkClient,
    private val credentialRepository: CredentialRepository
) : UsageProbe {

    override suspend fun probe(): UsageSnapshot {
        val token = credentialRepository.get(CredentialKey.GITHUB_TOKEN)
            ?: throw ProbeError.AuthenticationRequired

        val response = networkClient.request(
            HttpRequest(
                url = "$API_BASE_URL/users/$username/settings/billing/premium_request/usage",
                method = HttpMethod.Get,
                headers = mapOf("Authorization" to "Bearer $token")
            )
        )

        return parseUsageResponse(response.data)
    }
}
```

### Partially Shared Probes (expect/actual)

```kotlin
// ClaudeUsageProbe - shared parsing, platform-specific CLI
class ClaudeUsageProbe(private val cliExecutor: CLIExecutor) : UsageProbe {

    override suspend fun probe(): UsageSnapshot {
        val result = cliExecutor.execute(
            binary = "claude",
            args = listOf("/usage", "--allowed-tools", ""),
            autoResponses = mapOf("Esc to cancel" to "\r")
        )

        return parseClaudeOutput(result.output)  // 100% shared parsing
    }

    // All parsing logic is shared (commonMain)
    internal fun parseClaudeOutput(text: String): UsageSnapshot {
        val clean = stripANSICodes(text)
        val sessionPct = extractPercent("Current session", clean)
        // ... regex-based parsing
    }
}
```

---

## Migration Roadmap

### Phase 1: Foundation (Weeks 1-2)
- [ ] Create Gradle multi-module project structure
- [ ] Configure KMP targets (jvm, macosX64, macosArm64, linuxX64, mingwX64)
- [ ] Port domain models to Kotlin
- [ ] Write unit tests for domain models

### Phase 2: Domain Layer (Weeks 3-4)
- [ ] Port domain protocols (AIProvider, UsageProbe, repositories)
- [ ] Port QuotaMonitor (actor → class with StateFlow)
- [ ] Write unit tests for QuotaMonitor

### Phase 3: Infrastructure (Weeks 5-6)
- [ ] Set up Ktor HttpClient
- [ ] Implement multiplatform-settings
- [ ] Set up logging (expect/actual)

### Phase 4: Shared Probes (Weeks 7-8)
- [ ] Port CopilotUsageProbe (100% commonMain)
- [ ] Port GeminiAPIProbe

### Phase 5: CLI Probes (Weeks 9-11)
- [ ] Define CLIExecutor expect/actual
- [ ] Implement JvmCLIExecutor
- [ ] Port ClaudeUsageProbe, CodexUsageProbe, AntigravityUsageProbe

### Phase 6: Swift Bridge (Weeks 12-13)
- [ ] Build XCFramework
- [ ] Create Swift bridge layer
- [ ] Update ClaudeBarApp.swift

### Phase 7: Compose Desktop (Weeks 14-16)
- [ ] Build Compose Desktop UI
- [ ] Package for Linux/Windows

### Phase 8: Polish (Weeks 17-18)
- [ ] CI/CD setup
- [ ] Documentation
- [ ] Release

---

## Critical Design Decisions

### 1. Swift UI Preservation
**Decision:** Keep Swift UI for macOS, add Compose Desktop for other platforms

**Rationale:** SwiftUI is mature and deeply integrated with macOS. Migration cost is high with low ROI.

### 2. QuotaMonitor: Actor → StateFlow
**Decision:** Convert Swift `@Observable actor` to Kotlin class with `StateFlow`

**Rationale:** StateFlow is KMP's standard for observable state, integrates with Compose, bridges to Swift Combine.

### 3. CLI Execution: expect/actual
**Decision:** Platform-specific implementations via expect/actual

**Rationale:** CLI execution is fundamentally different across platforms (ProcessBuilder vs posix_spawn vs CreateProcess).

### 4. Testing: Chicago School TDD
**Decision:** State-based test doubles, no mock verification

**Rationale:** Aligns with current Swift testing philosophy, more maintainable.

---

## Summary

**Key Takeaways:**

1. **Shared Core (80%+):** Domain logic, business rules, and most infrastructure fully shared via KMP
2. **Platform UI:** Swift UI for macOS, Compose Desktop for Linux/Windows
3. **Swift Bridge:** Thin Swift layer bridges KMP StateFlow to SwiftUI @Published
4. **Probe Strategy:** 100% shared for HTTP probes, expect/actual for CLI probes
5. **Build System:** Gradle for KMP, SPM for Swift UI, XCFramework for interop
6. **Migration:** Phased approach over 18 weeks

---

**End of KMP Architecture Blueprint**
