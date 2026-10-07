# QuotaKernel: the Quotas kernel in Kotlin

`UsageQuota` and the values and laws it reads (`QuotaType`, `QuotaStatus`,
`StatusPolicy`, `UsagePace`, `PaceLevel`, `QuotaDuration`, `Left`, `Money`,
`Window`) are written once in Kotlin Multiplatform, so a second platform reads
quotas with the same code. The Swift app links them as `QuotaKernel.xcframework`
through the `Quotas` module, whose `Sources/Kernel/` is their Swift face. The
design and its rules: [MODULAR_DESIGN §3.1](../../../docs/architecture/MODULAR_DESIGN.md#31--the-kernel-written-once-in-kotlin).

```bash
./scripts/build-kotlin.sh          # from the repo root: the release XCFramework Tuist links
./gradlew jvmTest                  # from here: the JUnit suite
```

| Tool | Version | Note |
|---|---|---|
| Kotlin | 2.4.20 | officially tested to Xcode 26.4; builds with Xcode 27.0 |
| SKIE | 0.10.15 | the Swift API; supports Kotlin 2.0.0 → 2.4.20 |
| JUnit | 6.1.3 (BOM) | Jupiter, on the `jvm()` target |
| Gradle | 9.5.0 | wrapper in this folder |
| JDK | 21 | |

Targets are `macosArm64` and `macosX64`, because releases are universal.
`macosX64` is deprecated upstream: when Kotlin removes it, Intel support goes
with it.

## Writing kernel code

- **Times are `Double` seconds on the caller's clock; money is `Long`
  micro-units.** Kotlin has no `Date` or `Decimal`. A law that needs "now"
  takes `nowSeconds`.
- **Use sealed classes, not sealed interfaces**, so Swift can add static
  shortcuts (`.session`) to the base class.
- **Give a nullable number a name the face won't reuse** (`percentLeftOrNull`,
  `resetsAtSeconds`). It reaches Swift boxed (`KotlinDouble?`), and the face
  shows it under the Swift name (`percentLeft: Double?`).
- **Constructors are public**, so the face can add convenience inits with
  default arguments. Kotlin defaults don't reach Swift.
- **Swift never implements a Kotlin interface.** The edges stay Swift ports.
- Every new class gets its `@retroactive @unchecked Sendable` line in
  `Sources/Kernel/QuotaKernel.swift`. SKIE marks enums `Sendable` itself.

## Why SKIE, and what the spike found

Both bridges build for macOS and both ran the design (Kotlin owns state in a
`StateFlow`; a `@MainActor @Observable` Swift model observes it) under Swift 6.

| | SKIE 0.10.15 | Swift export (Alpha in 2.4) |
|---|---|---|
| How it reaches Xcode | prebuilt XCFramework; Xcode never runs Gradle | `embedSwiftExportForXcode`, a build phase run by Xcode with script sandboxing off; no XCFramework or SPM |
| Kotlin enum | Swift enum, `.healthy`, `Sendable` | Swift enum, Kotlin's names, not `Sendable` |
| Sealed members | `QuotaType.Session`, `onEnum(of:)` | nested names emitted `internal`; Swift needs the mangled `_ExportedKotlinPackages_…` |
| Nullable / returned numbers | boxed: `KotlinLong?`, `KotlinInt` | native: `Int64?`, `Int32` |
| Default arguments | its opt-in interop fails to link (keep it off) | dropped |
| Stability | stable; Kotlin support can lag a release by weeks | "breaking changes expected" |

Swift export is JetBrains' direction. Re-check it with each Kotlin release
(next: 2.5, December 2026). Only `Sources/Kernel/` names SKIE's API, so the
switch changes one folder.

Friction met, and where it is handled:

| Friction | Handled by |
|---|---|
| Kotlin classes aren't `Sendable`; calling a Kotlin `suspend` member from the main actor is a "sending" error under Swift 6 | one `@retroactive @unchecked Sendable` per class, in the face |
| A Swift class adopting a Kotlin interface must subclass `NSObject`, and SKIE hides a `suspend` requirement as `__name` | rule: Swift never implements a Kotlin interface |
| `xcodebuild -create-xcframework` fails without a `.swiftinterface` | `skie { build { produceDistributableFramework() } }` |
| SKIE uploads build analytics by default | `analytics { disableUpload.set(true) }` |
| Kotlin enums, data classes and companions: `==` on `NSObject` can't find `.session` | the face declares `==` per base class |
| A failable init can't return a subclass from a class extension | `QuotaType(quotaKey:)` lives in a protocol extension, which may assign `self` |
| KMMBridge writes `Package.swift` to the git root, beside Tuist | not used: a Gradle task builds the XCFramework in-repo |
