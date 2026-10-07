# ClaudeBarKit: everything but the UI, in Kotlin

`UsageSnapshot` and every value it holds (`UsageQuota`, `QuotaType`,
`QuotaStatus`, `StatusPolicy`, `UsagePace`, `PaceLevel`, `QuotaDuration`, `Left`,
`Money`, `Window`, `QuotaGroup`, `AccountTier`, `CostUsage`, `CostLine`,
`BudgetStatus`, `DailyUsageStat`, `DailyUsageReport`, `ExtensionMetric`,
`MetricDelta`), with their laws, are written once in Kotlin Multiplatform, so a second platform reads
quotas with the same code. The Swift app links them as `ClaudeBarKit.xcframework`
through the `Quotas` module, whose `Sources/Kernel/` is their Swift face. The
design and its rules: [MODULAR_DESIGN](../docs/architecture/MODULAR_DESIGN.md#1--two-halves-a-kotlin-sdk-and-a-native-ui).

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

- **Times are `Double` Unix seconds (since 1970); money is `Long`
  nano-units; counts are `Long`.** Kotlin has no `Date` or `Decimal`, and a
  day's tokens pass 2³¹. A law that needs "now" takes `nowSeconds`.
- **Use sealed classes, not sealed interfaces**, so Swift can add static
  shortcuts (`.session`) to the base class.
- **Keep Kotlin names clean; rename for Swift with `@ObjCName`** when the face
  shows the field under the same name with a Swift type: a `Long` count
  (`@ObjCName("totalTokens64")` → face `totalTokens: Int`) or a nullable number,
  which reaches Swift boxed (`@ObjCName("percentLeftOrNull")` → face
  `percentLeft: Double?`). A field that carries its unit (`resetsAtSeconds`,
  `totalCostNanos`) needs no rename.
- **No `Codable` on kernel classes.** Swift persists and reads JSON through a
  face struct with the old keys (`DailyUsageStat.Stored`,
  `ExtensionMetric.Reported`).
- **Strings a card prints stay in the face** (`formattedCost`, "19.5M"):
  Kotlin common code has no `String.format`, and they are page state.
- **Constructors are public**, so the face can add convenience inits with
  default arguments. Kotlin defaults don't reach Swift.
- **Swift never implements a Kotlin interface.** The edges stay Swift ports.
- Every new class gets its `@retroactive @unchecked Sendable` line in
  `Modules/Quotas/Sources/Kernel/ClaudeBarKit+Swift.swift`. SKIE marks enums `Sendable` itself.

## Porting a Swift area

The Swift is the specification: port its behaviour exactly, and port its tests.

1. **Where.** What decides goes in `src/commonMain/kotlin/com/tddworks/claudebar/<context>/<area>/`
   (e.g. `datasources/mapping`). What touches the Mac sits behind a port (an interface in
   commonMain) with its adapter in `src/macosMain/…`, same package, calling the Apple
   framework through Kotlin/Native (`platform.Foundation`, `platform.Security`,
   `platform.posix`, `platform.JavaScriptCore` …). Kotlin never calls Swift.
2. **Visibility.** Everything is `internal` until its context switches over. In one Gradle
   module `internal` means *the whole SDK, hidden from Swift*, so a Kotlin type never
   collides with the Swift type it replaces while both exist.
3. **Tests.** JUnit 6 in `src/jvmTest/…`, same package; adapters in `src/macosTest/…` with
   `kotlin.test`. Every test is `` @Test fun `should … when …`() `` in the person's words.
   Chicago school: assert on returned values and resulting state, with hand-written fakes
   for the ports — no mocking library. Each Swift test file becomes one Kotlin test file.
4. **The foundation** (`datasources/*.kt`): `UsageError` (quotas), `DataSourceError`,
   `Response`, `Credential` / `FoundCredential` / `MappingFacts`, the ports in `Ports.kt`,
   the worker roles in `Workers.kt` (`CredentialFinding`, `CredentialRefreshing`, `Fetching`,
   `Reading`, `Recovering`, `ReportedFailure`, `ErrorFact`, `HTTPStatusError`, `UsageMemory`),
   `JsonScope` / `JsonPath` / `Placeholders` / RFC 7396 `merged`, `PathPattern` / `Paths`,
   `Template` / `Jwt` / `SystemValues`, the `Fetch` model, and `DefinitionJson` with its
   decoding helpers. Change a foundation file only through its owner, never from an area.
5. **Definitions** decode with kotlinx.serialization: `@Serializable` data classes with the
   Swift defaults; a shape with more than one spelling (a closed sum's single tag, a
   string-or-object) gets a small `KSerializer` over `JsonElement`, as in `Fetch.kt`. A bad
   definition throws `DefinitionError` saying where.
6. **Concurrency.** A fetch is `suspend`; blocking work runs in `withContext(Dispatchers.IO)`.
   Shared mutable state takes an atomicfu `SynchronizedObject`.
7. **Logging.** `AppLog.probes` (and the other categories): what happened, never a token,
   key, cookie or credential.

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
| A face init and a Kotlin init that differ only in `Double?` versus `KotlinDouble?` make a `nil` argument ambiguous | `@ObjCName` on the Kotlin field |
| Kotlin enums, data classes and companions: `==` on `NSObject` can't find `.session` | the face declares `==` per base class |
| Kotlin classes are non-final to Swift, so an extension can't add `Codable` (`init(from:)` must be `required`) | a `Codable` face struct per JSON use |
| A failable init can't return a subclass from a class extension | `QuotaType(quotaKey:)` lives in a protocol extension, which may assign `self` |
| KMMBridge writes `Package.swift` to the git root, beside Tuist | not used: a Gradle task builds the XCFramework in-repo |
