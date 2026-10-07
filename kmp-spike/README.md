# KMP spike: share domain logic with Kotlin Multiplatform

A throwaway spike, not part of the app build. It answers one question: can ClaudeBar's
domain modules be written once in Kotlin and called from the Swift app, using
[SKIE](https://github.com/touchlab/SKIE) for the Swift API and
[KMMBridge](https://github.com/touchlab/KMMBridge) to ship the XCFramework?

**Answer: yes, it builds and runs on macOS with the latest of everything. It does not
pay off today**, because the app has one platform and the parts that would be worth
sharing are the parts that are Apple-only (see [Verdict](#verdict)).

## Versions (latest as of 2026-10-07)

| Tool | Version | Released | Note |
|---|---|---|---|
| Kotlin | 2.4.20 | 2026-09-07 | 2.5.0 due Dec 2026 (adds Xcode 27) |
| SKIE | 0.10.15 | 2026-09-25 | supports Kotlin 2.0.0 → 2.4.20 |
| KMMBridge | 1.2.1 | 2025-01-27 | repo active, no release in 20 months |
| kotlinx-coroutines | 1.11.0 | | |
| JUnit | 6.1.3 (BOM) | | Jupiter on the JVM target |
| Gradle | 9.5.0 | | |
| Xcode / Swift | 27.0 / 6.4 | | above Kotlin 2.4's tested 26.4; worked anyway |

## What is here

```
kmp-spike/
├── quotas/                         Kotlin module: a port of Modules/Quotas' status rules
│   ├── src/commonMain/…            QuotaStatus, StatusPolicy, QuotaType, Left/Money, Quota, QuotaFeed
│   └── src/jvmTest/…               JUnit 6 suite, Chicago school, `should …` names
├── Package.swift                   written by KMMBridge `spmDevBuild` (local XCFramework path)
└── swift-consumer/                 Swift 6 package standing in for the app
```

```bash
./gradlew :quotas:jvmTest            # 10 JUnit tests, all pass
./gradlew spmDevBuild                # SKIE + KMMBridge → universal macOS XCFramework
swift run --package-path swift-consumer QuotasDemo
```

## What worked

- **Kotlin 2.4.20 + SKIE 0.10.15 + KMMBridge 1.2.1** build a universal (arm64 + x86_64)
  static XCFramework on Xcode 27, and a Swift 6 package links it through the generated
  `Package.swift`.
- **SKIE bridges** do what they say from Swift:
  - Kotlin `enum class` → a Swift `enum`, exhaustive `switch`
  - `sealed interface` → `switch onEnum(of:)`, exhaustive
  - `suspend fun` → `try await`
  - `StateFlow` → `for await` (`AsyncSequence`)
- **JUnit**: the shared rules are tested on a `jvm()` target with JUnit Jupiter 6
  (`@Nested`, backticked `should …` names), fast and IDE-friendly.

## Friction found

| # | Issue | Workaround | Cost to ClaudeBar |
|---|---|---|---|
| 1 | **Kotlin types are not `Sendable`.** Swift 6 refuses to pass a `Quota` across actors | `extension Quota: @retroactive @unchecked Sendable {}` per type, or `@preconcurrency import` | High: `UsageSnapshot`/`UsageQuota` cross actors everywhere; every shared type needs a hand-written promise |
| 2 | **Swift implementing a Kotlin `suspend` interface** sees SKIE's hidden `__fetch()` | name the method `__fetch` | Medium: our ports (`CLIExecutor`, `NetworkClient`, `SecretStore`) are exactly this shape, implemented in Swift |
| 3 | Swift classes adopting a Kotlin interface must subclass `NSObject` | `final class X: NSObject, Port` | Low, but no `struct`/`actor` adopters |
| 4 | No common `Decimal`; money is `Decimal` in Swift | minor units (`Long`), or a BigDecimal library | Medium: a change to the money model |
| 5 | **`macosX64` is deprecated** in 2.4.20 and will be removed | none; Intel builds stop when it goes | High while we ship to Intel Macs |
| 6 | Mockable can't mock Kotlin protocols; Kotlin needs its own fakes | hand-written fakes in Kotlin | Low |
| 7 | KMMBridge writes `Package.swift` to the **git root** by default, beside Tuist | `spm(spmDirectory = …)` | Low |
| 8 | SKIE needs `produceDistributableFramework()` or `xcodebuild -create-xcframework` fails (no `.swiftinterface`) | set it | Low |
| 9 | SKIE uploads build analytics by default | `analytics { disableUpload.set(true) }` | Low, but turn it off |
| 10 | Adds a JVM/Gradle/Kotlin toolchain to a Tuist-only repo and CI; ~9 MB fat XCFramework (Kotlin runtime + coroutines) | | Medium: two build systems, two test runners |

## Swift export (JetBrains' own path) vs SKIE

Swift export is **Alpha** in Kotlin 2.4 (`suspend` → `async`, `Flow` → `AsyncSequence`,
enums, sealed → Swift enums in 2.4.20, no generics); the docs list only iOS targets.
SKIE works on the Objective-C export and is the mature choice today; once Swift export is
stable it will replace it. JetBrains is also removing Swift IDE support from the KMP plugin
(IntelliJ 2026.3), so Swift stays in Xcode either way.

## KMMBridge: what it is for

KMMBridge publishes the XCFramework (GitHub release or Maven) and keeps a `Package.swift`
pointing at it, so an **iOS team in another repo** can depend on a Kotlin team's
binary. In a single repo it only adds `spmDevBuild`; a plain `assembleXCFramework` Gradle
task called from a Tuist pre-build script would do the same with one less plugin. Use it
only if the Kotlin code moves into its own repo.

## Verdict

Of ClaudeBar's modules, only **Quotas** (2k lines, pure Foundation) is cheap to share.
**DataSources** (10k lines) is mostly CLI, PTY, Keychain, cookies, SQLite, CryptoKit and
JavaScriptCore, so it is Apple-only. **Providers** and **Domain** use `@Observable`, which
Kotlin can't produce. Sharing logic is worth it when a second consumer exists, such as a
Windows/Linux tray app, an Android companion, or a JVM leaderboard backend. With only the
macOS app today, KMP adds a toolchain and the `Sendable` and `suspend`-port friction while
removing no code.

**Recommendation:** don't move the domain yet. If a second platform is planned, start with
`Quotas` plus the provider JSON definitions' mapping rules (the "providers are data" design
already suits this), use SKIE for the Swift API, and skip KMMBridge while everything lives
in one repo. Re-check when Kotlin 2.5 lands (Xcode 27, possibly Swift export Beta).
