---
description: How ClaudeBar's code is cut — everything but the UI is one Kotlin Multiplatform SDK, ClaudeBarKit, with a package per bounded context; the macOS app is SwiftUI on top of it; the package rules, the platform adapters, the UI bridge, naming, testing, and the migration from today's Swift modules; read before adding a file, a type or a package.
---

# ClaudeBar — the modular design

> **#4 of 5** in [the design](ARCHITECTURE.md) · **Answers:** where the code
> lives — which package a file goes in, what a package shows and hides, what it
> may use, and what stays native · **Builds on:** [TARGET_ARCHITECTURE.md](TARGET_ARCHITECTURE.md) ·
> **Next:** [ENGINE_DESIGN.md](ENGINE_DESIGN.md)
>
> **Status: IN PROGRESS (rethink of 2026-10-07)** — the target below replaces
> the Swift-modules design. Built: phases 0–2 (§8) — `ClaudeBarKit/` with
> the `quotas`, `diagnostics` and `storage` packages and `ArchitectureTest`;
> `Modules/Kit` is the Swift face.

---

## 1 · Two halves: a Kotlin SDK and a native UI

ClaudeBar is two things: **what it knows** (quotas, providers, data sources,
the monitor, alerts, sessions, settings) and **what it shows** (the menu bar,
the popover, the notch, the Touch Bar, Settings). The first is the same on any
platform; the second is the platform's. So the code is cut there:

```text
ClaudeBarKit/                 THE SDK — one Kotlin Multiplatform project, everything but the UI
├── build.gradle.kts          one Gradle module → one ClaudeBarKit.xcframework (SKIE)
├── definitions/              the built-in provider definitions (*.json, *.js, prices)
└── src/
    ├── commonMain/kotlin/com/tddworks/claudebar/
    │   ├── quotas/           the usage model and its laws
    │   ├── datasources/      look up → fetch → map, the engine every provider runs on
    │   ├── providers/        the Provider lifecycle, accounts, catalog, usage history
    │   ├── monitoring/       QuotaMonitor: refreshes, the state the UI shows
    │   ├── alerting/         quota alerts, Notify!
    │   ├── activity/         Claude Code sessions, the notch's activity, hooks
    │   ├── leaderboard/      the public board
    │   ├── storage/          settings.json, the vault, the usage-history ledger
    │   ├── diagnostics/      AppLog
    │   └── kit/              ClaudeBarCore.start(…) — the composition root
    ├── macosMain/kotlin/…    the platform adapters, same packages: Keychain, processes,
    │                         PTYs, JavaScriptCore, notifications, IOKit (§4)
    ├── jvmMain/kotlin/…      — nothing yet; a JVM app's adapters would go here
    └── jvmTest/kotlin/…      the tests, JUnit (§7)

Sources/App/                  THE UI — SwiftUI and AppKit only
├── Kit/                      the Swift face of ClaudeBarKit: Sendable vouching, Date/Decimal
│                             views, `shape` enums, KitObservation (§5)
├── Views/ Theme/ Notch/ TouchBar/ …
└── ClaudeBarApp.swift        starts the kit, hands its state to the views
```

**Why one Gradle module, not a module per context.** Kotlin/Native gives every
framework its own runtime and its own copy of each type, so two Kotlin
frameworks in one app can't hand each other a `UsageQuota`. The SDK ships as
**one framework**, built from one project. Inside it, a context is a
**package**, and the rules between packages (§3) are enforced by an
architecture test rather than by Gradle. A Gradle module per context
re-exported through one umbrella framework is possible, but it buys build
isolation we don't need yet at the cost of a build file per context. It
becomes the move when one package needs a dependency the others must not see.

**There is no Infrastructure layer and no vendor code.** An adapter lives in
its context's package under `macosMain`. A vendor is a JSON file in
`definitions/` ([target §3](TARGET_ARCHITECTURE.md#3--codex-as-data)), run by
one `DataSource`.

```swift
// App — the composition root, in a few lines; it starts the kit and shows its state
let kit = ClaudeBarCore.companion.start(home: NSHomeDirectory())   // the class can't share the framework's name
KitObservation.shared.follow(kit.changes)          // one revision; views re-render on it
Button("Refresh") { kit.monitor.refreshAll() }     // views tell; Kotlin decides
```

## 2 · The packages

| Package | Context ([model §7](CANONICAL_MODEL.md#7--the-contexts-and-the-modules-that-implement-them)) | Public (the domain) | Adapters (`macosMain`) | From today's |
|---|---|---|---|---|
| `quotas` | Quota · shared kernel | `UsageSnapshot`, `UsageQuota`, `QuotaType`, `QuotaStatus`, `StatusPolicy`, `Left`, `Money`, `CostUsage`, `BudgetStatus`, `AccountTier`, `DailyUsageStat` … | — none: pure values | `Modules/Quotas` (built) |
| `datasources` | Data Sources | `DataSource`, `DataSourceDefinition`, `Response`, `DataSourceError`, the closed sums `CredentialLookup` · `Fetch` · `Mapping`, `UsageLog`; the ports `CLIExecutor`, `NetworkClient`, `RPCTransport`, `SecretStore`, `CloudWatchClient`, `PriceCatalog`, `ScriptEngine` | process and PTY runner, JavaScriptCore `ScriptEngine`, browser cookie reader, login-shell environment, running processes | `Modules/DataSources`, `Modules/AWSClients` |
| `providers` | Providers · core | `Provider`, `Account`, `UsageHistory`, `Providers` (the lineup), `ProviderDefinition`, `ProviderCatalog`, `ProviderSettingsRepository`, `CredentialRepository`, `LedgerStore` | — | `Modules/Providers`, `Domain/Provider` |
| `monitoring` | Monitoring · conductor | `QuotaMonitor` and its `state: StateFlow<MonitorState>`, `MonitoringEvent`, `RefreshInterval`, `Clock`, `PowerState` | IOKit power state | `Domain/Monitor` |
| `alerting` | Alerting | `QuotaAlerts`, Notify! values, `NotifySettingsRepository`, the port `AlertSender` | UserNotifications `AlertSender` | `Domain/Alerts`, `Domain/Notify`, `Infrastructure/Notify`, `Infrastructure/Notifications` |
| `activity` | Activity | `Session` (today's `ClaudeSession`: "Claude" is a vendor word), `SessionEvent`, `SessionMonitor`, `NotchActivity`, `InUse`, `HookSettingsRepository` | the hook HTTP server, hook installer, port discovery | `Domain/Session`, `Domain/Notch`, `Domain/InUse`, `Infrastructure/Hooks`, `Infrastructure/InUse` |
| `leaderboard` | Leaderboard | `Leaderboard`, `DailyTokens`, its settings | — | `Domain/Leaderboard`, `Infrastructure/Leaderboard` |
| `storage` | Vault & Settings · generic | `SettingsFile` (`settings.json` by dotted name), `CredentialRepository` (the vault's interface) | `KeychainCredentials` (`Security`), the UserDefaults store | `Infrastructure/Storage` |
| `diagnostics` | — cross-cutting | `AppLog` and its categories | the unified-log sink | `Modules/Diagnostics` |
| `kit` | — the composition root | `ClaudeBarCore.start(…)`: builds every context, wires the ports, owns the coroutine scope, merges their revisions into `changes` | — | `Sources/App/ClaudeBarApp.swift` (its wiring) |

**Stays native, in `Sources/App`:** SwiftUI views and themes, the status item,
popover, notch window and Touch Bar, page state (`MenuBarLabel`,
`MenuBar*Display`, `PopoverContentHeight` …), Terminal theme import, Sparkle,
launch at login, `NSScreen` metrics. A thing stays native when it draws, or
when it is the app's shell rather than something it knows.

## 3 · The package rules

```text
                     kit (composition root)        ← Sources/App (UI) uses kit and the domain types
     ┌──────────┬──────────┼───────────┬────────────┐
     ▼          ▼          ▼           ▼            ▼
 monitoring  alerting   activity  leaderboard       │
     │          │          │           │            │
     ▼          ▼          ▼           ▼            ▼
 providers ─────────────────────▶ datasources
     │                                  │
     ▼                                  ▼
 ┌────────────────────── quotas ───────────────────────┐   (+ diagnostics and storage, which anyone may use)
```

1. **Arrows point at the supplier.** `quotas` uses nothing but the Kotlin
   standard library.
2. **Siblings never use each other.** `monitoring` does not use `alerting`; it
   emits `MonitoringEvent` and `alerting` collects it.
3. **No package names a vendor.** A vendor's name is in its definition and in
   test fixtures, nowhere in Kotlin.
4. **A library is used by exactly one package.** Ktor's server → `activity`;
   SQLite, JavaScriptCore, CommonCrypto, the PTY → `datasources`; `Security` →
   `storage` for ClaudeBar's own Keychain items, and `datasources` for other
   apps' (a browser's Safe Storage key — other apps' tokens are read through
   `/usr/bin/security`, which doesn't prompt on every read, #94). The
   platform's own libraries — kotlinx (coroutines, serialization, io, datetime)
   and the Ktor *client*, Kotlin's `URLSession` — are open to every package.
5. **`internal` is the default.** A type is `public` only when another package
   or the UI must name it, and then its name is a word from the canonical model.
   **Public type names are unique across the SDK**: the framework's
   Objective-C names are flat, so two `Provider`s would reach Swift as
   `Provider` and `Provider_`.
6. **`diagnostics` and `storage` are the cross-cutting packages.** Neither holds
   a rule: one is the log, the other `settings.json` and the vault, which every
   context's own settings repository and secrets read.
7. **Kotlin never calls Swift.** The SDK uses Apple frameworks directly through
   Kotlin/Native (§4); Swift never implements a Kotlin interface.

**Enforced by a test, not by convention.** `ArchitectureTest` (JUnit, with
[Konsist](https://docs.konsist.lemonappdev.com/)) reads the sources and fails
when a file imports across a forbidden arrow, a public name repeats, or a
vendor name appears outside `definitions/`. Today `Project.swift` enforces the
same rules by target dependencies; the test takes over that job.

## 4 · The platform: commonMain decides, macosMain does

Everything that decides is in `commonMain`, so it runs on the JVM and is tested
there with JUnit. Everything that touches the Mac sits behind a **port** (an
interface in `commonMain`) with its macOS adapter in `macosMain`, which calls
the Apple framework directly. Kotlin/Native ships bindings for `Foundation`,
`Security`, `JavaScriptCore`, `CommonCrypto`, `Network`, `UserNotifications`,
`IOKit`, `OSLog` and POSIX.

| Need | Port (commonMain) | macOS adapter (macosMain) | Replaces (Swift) |
|---|---|---|---|
| run a CLI to completion | `CLIExecutor` | `posix_spawn` + pipes | `Subprocess` |
| drive an interactive CLI and read its screen | `InteractiveRunner` | `openpty` + `TerminalScreen` (a VT parser in commonMain, JUnit-tested on recorded captures) | `SwiftTerm` |
| JSON-RPC over a process's stdio | `RPCTransport` | `posix_spawn` + pipes | `Process` |
| HTTP | `NetworkClient` | Ktor client, Darwin engine (tests: Ktor `MockEngine`) | `URLSession` |
| AWS CloudWatch, price list | `CloudWatchClient`, `PriceCatalog` | SigV4 (commonMain, `kotlincrypto`) over Ktor | AWS SDK for Swift |
| a definition's script mapping | `ScriptEngine` | `JavaScriptCore` | `JavaScriptCore` |
| browser cookies | `BrowserCookies` | Safari's binarycookies parser (commonMain); Chromium and Firefox SQLite, Chrome Safe Storage key via `Security` + `CommonCrypto` | `SweetCookieKit` |
| SQLite files | `SQLiteReader` | `androidx.sqlite` bundled driver (runs on the JVM too) | `SQLite.swift` |
| Keychain | `SecretStore`, `CredentialRepository` | `SecItem…` (`Security`) | `Security` |
| files | — (kotlinx-io in commonMain) | — | `FileManager` |
| notifications | `AlertSender` | `UNUserNotificationCenter` | `UserNotifications` |
| Claude Code hooks | `HookEventReceiver` | Ktor server (CIO) | `Network` |
| battery, clock | `PowerState`, `Clock` | `IOKit`; system time | `IOKit` |
| hashing, PKCE, HMAC | — (`kotlincrypto` in commonMain) | — | `CryptoKit` |
| the log | `LogSink` | unified log through a one-function C shim (cinterop: `os_log` is a macro); the user's file is `FileLogSink` in commonMain | `OSLog` |

**Definitions are compiled in.** A Gradle task turns `definitions/` into Kotlin
source, so the built-in providers need no bundle and read the same on every
platform. Custom definitions and extensions are still read from
`~/.claudebar/` at run time.

## 5 · The UI bridge

```text
Kotlin (ClaudeBarKit)                               Swift (Sources/App)
QuotaMonitor, Provider, Account … mutate state ──▶  kit.changes: StateFlow<Long>   (one revision)
                                                          │
                                                    KitObservation (@Observable) republishes it
                                                          │
views read monitor.lineup, account.snapshot  ◀── face properties touch KitObservation, then read Kotlin
views call monitor.refreshAll(), accounts.add(…) ──▶ Kotlin commands
```

1. **Kotlin owns state and concurrency; Swift observes one change signal.** Every
   aggregate the UI shows (`QuotaMonitor`, `Providers`, `Provider`, `Account`,
   `SessionMonitor` …) keeps its state in Kotlin and, after any change, bumps the
   kit's single `changes` revision. One Swift class, `KitObservation`
   (`@Observable`), collects it on the main actor. Every face property that reads
   changing state touches `KitObservation` first, so SwiftUI re-renders whatever
   read it. Views keep writing `monitor.lineup` and `account.snapshot`, as they do
   today. Invalidation is coarse — a change re-evaluates the visible views — which a
   menu-bar popover affords, and which spares a mirror type per aggregate. A view
   that needs one value's stream (a countdown, a session's activity) may take
   `Observed<T>` over that value's own `StateFlow`.
2. **Views tell, Kotlin decides.** A view calls a command (`refresh`,
   `addAccount`, `hide(quotaKey)`). Commands that wait are `suspend` (Swift
   `async`); the rest return at once and work in the kit's scope. Views never
   compare, count or read quotas to decide; Kotlin hands them the decision
   (`notePlacement`, `status`, `badgeText`).
3. **Values cross, exceptions don't.** A command that can fail returns an outcome
   value (usage or a reason, a response or a step that failed); Kotlin throws only
   inside the SDK.
4. **The face is one folder.** `Sources/App/Kit/` (until phase 6, the Swift
   module `Modules/Kit`, the only target that links the framework) holds the
   `@retroactive @unchecked Sendable` lines (Kotlin values are immutable and
   Kotlin/Native objects are thread-safe; SKIE marks enums itself), the
   `Date`/`Decimal`/`Int` views, construction shortcuts, the `shape` enums for
   `switch`, the `Codable` structs where Swift still reads or writes JSON,
   `KitObservation` and `Observed`. No other Swift file names `onEnum`,
   `KotlinLong` or a `…Seconds`/`…Nanos` field, so switching to Swift export later
   changes this folder alone.
5. **Strings a card prints are page state** ("$14.26", "19.5M"): they are
   formatted in the face or the view, because Kotlin's common code has no
   `String.format` and the model keeps presentation out (CANONICAL_MODEL §6).

## 6 · Kotlin conventions

| Rule | Example | Why |
|---|---|---|
| times are `Double` Unix seconds (since 1970) | `resetsAtSeconds`; laws take `nowSeconds` | Kotlin has no `Date`, and once Kotlin reads times from a vendor the SDK needs one epoch every platform shares; the face turns them into `Date` (to the microsecond) |
| money is `Long` nano-units | `totalCostNanos` | exact to $0.000000001, as per-token prices need; no `Decimal` in Kotlin |
| counts are `Long` | `totalTokens` | a day's tokens pass 2³¹ |
| a clean Kotlin name, renamed for Swift with `@ObjCName` when the face shows it with a Swift type | `@ObjCName("totalTokens64") val totalTokens: Long` → face `totalTokens: Int` | Kotlin stays readable for a second platform |
| sealed classes, not sealed interfaces | `sealed class QuotaType` | Swift can add `.session` shortcuts on a class |
| constructors are public | `UsageQuota(…)` | the face adds convenience inits with defaults; Kotlin defaults don't reach Swift |
| no `Codable` on kernel classes; JSON is kotlinx.serialization in Kotlin | `@Serializable` DTOs in the owning package | a Kotlin class can't adopt `Codable` from Swift |
| a public name is a word the screen prints, else the industry's | `DataSource`, `CredentialLookup`, `Fetch` | the model's rule |
| a worker is named for its protocol, format or place, never a vendor | `JsonRpcFetcher`, `OAuth2Refresher` | |
| a port is the domain word; its adapter names the technology | `SecretStore` → `KeychainSecretStore` | |
| no grab-bag types | each worker receives the one thing it uses | |

Tooling: Kotlin 2.4.20, SKIE 0.10.15 (default-argument interop off: it fails
to link), kotlinx.coroutines, kotlinx.serialization, kotlinx-io, Ktor,
`androidx.sqlite`, `kotlincrypto`, JUnit 6, Konsist. Targets `macosArm64` and
`macosX64` (releases are universal; `macosX64` is deprecated upstream, and
Intel support ends when Kotlin removes it) plus `jvm()` for tests.
`scripts/build-kotlin.sh` builds the framework before `tuist generate`.
**Why SKIE, not Swift export**, and the friction met:
[`ClaudeBarKit/README.md`](../../ClaudeBarKit/README.md).

## 7 · Testing

- **JUnit on the JVM for everything in `commonMain`**: laws, the engine, the
  workers, the monitor. Chicago school: assert on state and returned values,
  with hand-written fakes for the ports (no mocking library; Mockable goes away
  with the Swift modules). Named `` `should … when …` ``.
- **Adapters get a small native suite** (`kotlin.test`, `macosArm64Test`):
  Keychain, the PTY, JavaScriptCore against the real system, in a temporary
  home.
- **Golden tests follow the definitions**: recorded responses and screen
  captures → expected snapshots, one folder per definition, on the JVM.
- **`ArchitectureTest`** guards §3.
- **Swift keeps `AppTests` only**: views render the state they're given. While
  a context migrates, its Swift tests keep running as the proof the Kotlin
  answers the same, and retire once its JUnit tests cover the same behaviour.

## 8 · Migration: bottom-up, one context at a time

Kotlin never calls Swift, so contexts move from the bottom of §3 upward. A
moved context keeps its Swift API through the face, so the Swift code above
it compiles unchanged, and its Swift tests keep passing until JUnit replaces
them.

| Phase | Moves | Replaces | Status |
|---|---|---|---|
| 0 | `Modules/Quotas/Kotlin` becomes `ClaudeBarKit/` (framework `ClaudeBarKit`, package `quotas`); `ArchitectureTest` | `QuotaKernel` | **built** |
| 1 | `quotas`: `UsageSnapshot` and everything it holds | `Modules/Quotas` (except `DateRange`, `UsageError`, `UsageDisplayMode`, `StatusInfo`, which move with their users) | **built** |
| 2 | `diagnostics` | `Modules/Diagnostics` (the face moves to the new `Modules/Kit`) | **built** |
| 2 | `storage`: `SettingsFile`, `KeychainCredentials` (Swift's `JSONSettingsStore` and `KeychainCredentialRepository` become faces over them) | `Infrastructure/Storage`'s file and Keychain code | **built** |
| 3 | `datasources`: definitions, look-ups, fetches, mappings, usage logs, the AWS clients | `Modules/DataSources`, `Modules/AWSClients`, SwiftTerm, SweetCookieKit, Subprocess, SQLite.swift, the AWS SDK | |
| 4 | `providers`: lifecycle, accounts, catalog, extensions, usage history; with them the vault (`ProviderVault`, the legacy-key migration, the UserDefaults store), which composes the Swift `CredentialRepository` that Swift tests mock until this phase | `Modules/Providers`, `Domain/Provider`, the rest of `Infrastructure/Storage` | |
| 5 | `monitoring`, `alerting`, `activity`, `leaderboard`, `kit` | `Domain`, `Infrastructure` | |
| 6 | the App on the face and commands alone; delete the Swift modules, `Domain`, `Infrastructure`, Mockable | — | |

Phase 3 is the largest and the riskiest: it replaces four Swift libraries.
`TerminalScreen` is proven first against `scripts/claude-usage-captures/`
before any interactive CLI moves.

**Each context keeps its own settings.** `settings.json` is one file, owned by
`storage`'s `SettingsFile`; the *repositories* over it (app settings, provider
settings, hooks, Notify!, Leaderboard, accounts) belong to their contexts and
move with them. Until then Swift's `JSONSettingsRepository` keeps its code and
runs on `SettingsFile` through `JSONSettingsStore`.

## 9 · Open

- **AWS credentials beyond static profiles.** Without the AWS SDK, `datasources`
  resolves environment keys and `~/.aws/credentials`/`config` profiles (named or
  default). SSO, assumed roles (`role_arn`/`source_profile`), `credential_process`,
  web identity and instance metadata are not resolved yet; a profile that needs one
  fails naming what it needs. The SDK resolved them all, so a Bedrock login on SSO
  regresses until they are added.

- **JVM adapters.** `jvmMain` is empty: the JVM runs tests only. A Windows or
  Linux app would fill it (`ProcessBuilder`, a JVM keyring, `java.net.http`),
  and `commonMain` would not change.
- **Script mappings on the JVM.** `ScriptEngine` is JavaScriptCore on macOS;
  golden tests of a definition's `.js` need a JVM engine (Rhino or GraalJS), or
  run in the native suite.
- **Swift export.** Re-checked with each Kotlin release (next: 2.5, December
  2026); §5 rule 3 keeps the switch to one folder.
