---
description: How ClaudeBar's code is cut into modules — one module per bounded context, the domain at each module's root and its implementations in Internal/, no Infrastructure layer and no vendor modules, one factory per module, the dependency rules, naming, testing, the one package that also builds on Windows, and what is left to carve; read before adding a file, a type or a module.
---

# ClaudeBar — the modular design

> **#4 of 5** in [the design](ARCHITECTURE.md) · **Answers:** where the code
> lives — which module a file goes in, what a module shows and hides, and what
> it may import · **Builds on:** [TARGET_ARCHITECTURE.md](TARGET_ARCHITECTURE.md) ·
> **Next:** [ENGINE_DESIGN.md](ENGINE_DESIGN.md)
>
> **Status: IN PROGRESS** — what is left is §8, and §10's phases 2 to 5 (0 and 1 are built).

---

## 1 · Modules by context, not layers by technology

Today Codex is spread across all three layers: `Domain/Provider/Codex/`,
`Infrastructure/Codex/`, a settings protocol in `Domain/Provider/`, two
implementations in `Infrastructure/Storage/`, and a card in `App/`. A layer
groups code that changes for different reasons and splits code that changes
together.

The target cuts the other way: **one module per bounded context**, and inside
each module **two halves**:

```text
Modules/<Context>/
├── Sources/
│   ├── *.swift            THE DOMAIN — public values, aggregates, and the
│   │                      ports (protocols) for what lies outside the app
│   ├── <Context>.swift    THE FACTORY — a public enum that builds the
│   │                      context's objects and wires what they need
│   └── Internal/          THE IMPLEMENTATION — `internal` types that talk to
│                          a process, a socket, a file, the Keychain
├── Resources/             data the module ships (definitions, fixtures)
└── Tests/                 `@testable import` — Internal is reachable from here
```

**There is no Infrastructure layer.** An implementation lives next to the
domain it serves, in that module's `Internal/`, and Swift's `internal` access
level keeps it there: the App and every other module **cannot name it**. They
get a domain object from the module's factory.

**There are no vendor modules.** A vendor is a JSON file
([target §3](TARGET_ARCHITECTURE.md#3--codex-as-data)). The Swift behind it is
one `DataSource` type and a worker per case of its three closed sums, named
for a protocol or a format — all in `DataSources`.

```swift
// App — the composition root, in a few lines; it cannot construct an implementation
let settings = Storage.makeSettings()                     // → any ProviderSettingsRepository
let vault    = Storage.makeVault()                        // → any CredentialRepository
let catalog  = ProviderFactory.makeCatalog(settings: settings, vault: vault,
                                     cloudWatch: AWSClients.makeCloudWatch(),
                                     priceCatalog: AWSClients.makePriceCatalog())
let monitor  = Monitoring.makeMonitor(providers: catalog.load())
```

## 2 · The modules

| Module | Context ([model §7](CANONICAL_MODEL.md#7--the-contexts-and-the-modules-that-implement-them)) | Public (the domain) | `Internal/` (the implementation) |
|---|---|---|---|
| `Quotas` | Quota · shared kernel | `UsageSnapshot`, `UsageQuota`, `QuotaType`, `QuotaStatus`, `UsagePace`, `CostUsage`, `BudgetStatus`, `AccountTier`, `UsageError`, `Day` (a day of usage history — today `DailyUsageReport`/`Stat`) — today's shapes; the final kernel is the model's `Usage`, `Quota`, `Left`, `Window`, `Status`, `Pace`, `Cost`, `Budget`, `Plan` | — none: pure values, no I/O |
| `DataSources` | Data Sources | `DataSource`, `DataSourceDefinition`, `Response`, `DataSourceError`, the closed sums `CredentialLookup` · `Fetch` · `Mapping`, `ConfigField`; `UsageLog` and `UsageLog.Definition` (how a login's usage history is extracted from its logs); the ports `CLIExecutor`, `NetworkClient`, `RPCTransport`, `SecretStore`, `CloudWatchClient`, `PriceCatalog`; the factory `DataSources.make(_:providerId:…)` | the workers — `Lookup/`, `Fetch/`, `Mapping/`, `Logs/` — and the implementations of its own ports — `Process/`, `Network/` (§5) |
| `AWSClients` | Data Sources (SDK-backed) | `AWSClients.makeCloudWatch()` → `any CloudWatchClient`, `AWSClients.makePriceCatalog()` → `any PriceCatalog` | the CloudWatch client and the AWS Price List reader; the only module that links AWS |
| `Providers` | Providers · core | `Provider` (the product), `Account` (a login — today `ProviderAccount`) and its capability handles `usageHistory: UsageHistory?` · `guestPasses` (nil when the definition doesn't offer them), `UsageHistory` (`days(in:)`), `Providers` (the providers you keep: add, delete, order, the lineup), `ProviderFactory`, `ProviderDefinition`, `ProviderCatalog`, `ProviderSettingsRepository`, `CredentialRepository` | definition-file reading, `DayLedger` (closed days, under `~/.claudebar/usage-history/`), `Extensions` (a manifest read as a definition) |
| `Providers/Resources/Providers/` | — | **the built-in definitions**: `codex.json`, `deepseek.json`, … | |
| `Monitoring` | Monitoring · conductor | `QuotaMonitor`, `MonitoringEvent`, `RefreshInterval`, `RefreshKind`, `Clock`, `PowerStateProvider` | `SystemClock`, `SystemPowerStateProvider`, `SingleFlightCache` |
| `Alerting` | Alerting | `QuotaAlerter`, Notify! values, `NotifySettingsRepository` | `NotificationAlerter`, `SystemAlertSender`, `NotifyGatewayClient` |
| `Activity` | Activity | `ClaudeSession`, `SessionEvent`, `SessionMonitor`, `NotchActivity`, `HookSettingsRepository` | `HookHTTPServer`, `HookInstaller`, `PortDiscovery`, `SessionEventParser` |
| `Leaderboard` | Leaderboard | `LeaderboardMembership`, `DailyTokens`, `Username`, `RequestSigner`, `LeaderboardUploader`, the devices' values, the ports `LeaderboardAPI` · `SigningKeyStore` · `MachineIdentity` · `TokenLogs` ([its design §7](../features/leaderboard/design.md#7--architecture)) | `LeaderboardHTTPClient`, `CredentialSigningKeyStore`, `IOKitMachineIdentity` (macOS) and their Windows twins (§10) |
| `Storage` | Vault & Settings · generic | `Storage.makeSettings()`, `Storage.makeVault()`, `AppSettingsRepository` | `JSONSettingsRepository`, `JSONSettingsStore`, `KeychainCredentialRepository`, `UserDefaults…`, `SecureCredentialMigration` |
| `Diagnostics` | — cross-cutting | `AppLog` and its categories | `AppLogger`, `FileLogger` |
| `ClaudeBar` (App) | — the composition root | SwiftUI views, themes, menu-bar label, page state, the Add Provider sheet | — |

## 3 · The dependency rules

```text
                         ClaudeBar (App)
       ┌────────┬────────┬────┴─────┬──────────┐
       ▼        ▼        ▼          ▼          ▼
  Monitoring Alerting Activity AWSClients  Storage
       │        │                   │          │
       ▼        │                   ▼          ▼
   Providers ───┼──────────────▶ DataSources ◀─┘ (implements its ports)
       │        │                   │
       ▼        ▼                   ▼
   ┌──────────────── Quotas ────────────┐   (+ Diagnostics, which anyone may import)
```

1. **Arrows point at the supplier.** `Quotas` imports nothing but Foundation.
2. **Siblings never import across the fence.** `Monitoring` does not import
   `Alerting`; it emits `MonitoringEvent` and `Alerting` subscribes.
3. **No module names a vendor.** A vendor's name appears in its JSON file,
   and in a test fixture folder —
   nowhere in a module's Swift.
4. **An SDK is linked by exactly one module.** AWS → `AWSClients`;
   SweetCookieKit, SwiftTerm, Subprocess → `DataSources`; Sparkle → the App.
5. **`internal` is the default.** A type is `public` only when another module
   must name it, and a public type is a word from the canonical model.
6. **Diagnostics is the only cross-cutting module.** It holds no rule.
7. **Only a platform folder names a platform.** A module's files import
   Foundation, `Crypto` (swift-crypto) and their suppliers, and nothing else;
   a file that imports an Apple framework (`Security`, `OSLog`,
   `JavaScriptCore`, `IOKit`, `AppKit`, `Darwin`…) or `WinSDK` lives in
   `Internal/macOS/` or `Internal/Windows/`, whole inside `#if os(…)` (§10).

The build enforces it: a forbidden import fails to compile, because the target
has no such dependency in `Package.swift`; rule 7 fails the Windows CI build.

## 4 · Naming

| Rule | Example | Why |
|---|---|---|
| a public name is a word the screen prints, else the industry's | `DataSource` (*DATA SOURCE*), `CredentialLookup` (*TOKEN LOOKUP ORDER*), `Fetch` (*Data fetching method*), `CLIExecutor` (*CLI Mode*) | the model's rule, kept at the module boundary |
| a module is named for its context, a type for its node | module `Providers`, type `Provider` | |
| **no type has its module's name** | `Quotas` holds `UsageQuota`, never a type `Quotas` | `Quotas.Quotas` breaks qualification in Swift |
| no module shadows an Apple or package module | not `Settings` (SwiftUI's scene), not `Logging` (swift-log, pulled in by the AWS SDK), not `ActivityKit` | |
| **a worker is named for its protocol, format or place — never a vendor** | `JSONRPCFetcher`, `OAuth2Refresher`, `JSONFileReader` | a vendor-named type is a vendor's five jobs coming back |
| a port is the domain word; its implementation names the technology | `NetworkClient` → `URLSessionNetworkClient` | |
| no grab-bag types | no `Machines`, `Context`, `Dependencies`, `Environment` bundle: each worker receives the one thing it uses | a bag is an ISP violation with a friendly name |
| a factory is the module's name as an enum | `enum DataSources { static func make(…) }` | |

## 5 · Inside a module

```text
Modules/DataSources/
├── Sources/
│   ├── DataSource.swift              ◆ fetchResponse() · fetchUsage() · isReady — one type for every provider
│   ├── Response.swift                ◇ status · headers · body — what Test Connection shows
│   ├── DataSourceError.swift         step: lookup · fetch · mapping
│   ├── DataSourceDefinition.swift    ◇ kind · credential · fetch · mapping · fallback — Codable
│   ├── CredentialLookup.swift        ◇ enum: environment · setting · jsonFile · keychain ·
│   │                                   browserCookies · sqlite · refined · firstOf ·
│   │                                   refreshing(_, oauth2 | cli)
│   ├── Fetch.swift                   ◇ enum: http · httpSteps · jsonRpc · cli · command · file ·
│   │                                   localServer · cloudWatch · directory
│   ├── Mapping.swift                 ◇ enum: json · text · script
│   ├── CLIExecutor.swift             port, @Mockable
│   ├── NetworkClient.swift           port, @Mockable
│   ├── RPCTransport.swift            port, @Mockable
│   ├── SecretStore.swift             port, @Mockable — implemented in Storage
│   │   (Fetch.swift also declares the ports CloudWatchClient · PriceCatalog, @Mockable —
│   │    implemented in AWSClients)
│   ├── UsageLog.swift                ◆ days(from:to:) for one login · ◇ UsageLog.Definition —
│   │                                   files · format · where · at · id · model · tokens · cost ·
│   │                                   prices · freeWhen · sessionGap
│   ├── DataSources.swift             the factory: make(_:providerId:…)
│   └── Internal/
│       ├── Lookup/    EnvironmentReader · SettingReader · JSONFileReader · KeychainReader ·
│       │              BrowserCookieReader · SQLiteReader · RefinedReader · FirstOfReader ·
│       │              OAuth2Refresher · CLIRefresher
│       ├── Fetch/     HTTPFetcher · HTTPStepsFetcher · JSONRPCFetcher · CLIFetcher ·
│       │              CommandFetcher · FileFetcher · DirectoryFetcher · LocalServerFetcher ·
│       │              CloudWatchFetcher
│       ├── Mapping/   JSONMapper (+ the path dialect) · TextMapper · ScriptMapper ·
│       │              DecimalScript · HumanDate
│       ├── Logs/      LogRecord · JSONLinesReader · JSONLogReader (a reader per log
│       │              format) · LogFileFinder · DayAggregator · PriceList · LocalEndpoint
│       ├── Process/   DefaultCLIExecutor · ProcessRPCTransport · InteractiveRunner ·
│       │              BinaryLocator · LoginShellEnvironment · RunningProcesses ·
│       │              TerminalRenderer
│       └── Network/   URLSessionNetworkClient · InsecureLocalhostNetworkClient
└── Tests/
    ├── Fetch/JSONRPCFetcherTests.swift
    ├── Mapping/JSONMapperTests.swift  one test per mapping feature
    └── DataSourceTests.swift          look up → fetch → map, the 401 refresh
```

```text
Modules/Providers/
├── Sources/
│   ├── Provider.swift                  ◆ the lifecycle, and the fallback between data sources
│   ├── Account.swift                   ◆ a login: refresh() · usageHistory? · guestPasses?
│   ├── UsageHistory.swift              ◆ one per login: days(in: DateRange) → [Day], over its
│   │                                     UsageLog and its ledger
│   ├── LedgerStore.swift               port, @Mockable — where closed days are kept
│   ├── ProviderDefinition.swift        ◇ the definition and its laws; its optional blocks
│   │                                     usageHistory · guestPasses are the capabilities
│   ├── ProviderCatalog.swift           built in · custom · extension; add · import · export
│   ├── ProviderSettingsRepository.swift  port, @Mockable
│   ├── CredentialRepository.swift      port, @Mockable
│   ├── Providers.swift                 the factory: makeCatalog(settings:vault:cloudWatch:priceCatalog:)
│   └── Internal/
│       ├── DefinitionFiles.swift       reads *.json from Bundle.module or a folder
│       └── DayLedger · FileLedgerStore closed days kept in ~/.claudebar/usage-history/
├── Resources/Providers/                codex.json · claude.json · claude-*.js ·
│                                       claude-prices.json · …   — the vendors
└── Tests/
    ├── ProviderTests.swift
    ├── CatalogTests.swift              every bundled definition decodes
    └── Golden/codex/                   recorded responses → expected snapshots
```

## 6 · Ports: as many as the requirement, and no more

A port (a `public protocol` at a module's root) exists because the domain
needs something outside the app that it must not build itself. Each is named
for that thing, is `@Mockable`, and has its implementation in an `Internal/`.

| Port | Declared in | What lies outside | Implemented in |
|---|---|---|---|
| `CLIExecutor` | DataSources | a CLI, run to completion | `DataSources/Internal/Process` |
| `NetworkClient` | DataSources | an HTTP endpoint | `DataSources/Internal/Network` |
| `RPCTransport` | DataSources | a JSON-RPC pipe to a process | `DataSources/Internal/Process` |
| `CloudWatchClient` | DataSources | AWS CloudWatch | `AWSClients` |
| `PriceCatalog` | DataSources | a cloud's price list (AWS) — a price file a definition ships is data, not a port | `AWSClients` |
| `SecretStore` | DataSources | the Keychain, for secrets a login saved | `Storage` |
| `LedgerStore` | Providers | `~/.claudebar/usage-history/` | `Providers/Internal` (→ `Storage`) |
| `ProviderSettingsRepository` · `CredentialRepository` | Providers | `settings.json`, the Keychain | `Storage` |
| `Clock` · `PowerStateProvider` | Monitoring | time, the battery | `Monitoring/Internal` |
| `QuotaAlerter` | Alerting | the user's notifications | `Alerting/Internal` |
| `HookEventReceiver` | Activity | Claude Code's hooks | `Activity/Internal` |
| `ScriptEngine` | DataSources | a JavaScript engine, for a `script` mapping | `DataSources/Internal/macOS` (JavaScriptCore) · `Internal/Windows` (a bundled engine, §10) |
| `LogSink` | Diagnostics | where a log line goes | `Diagnostics/Internal/macOS` (OSLog) · the file log, both platforms |
| `LeaderboardAPI` · `SigningKeyStore` · `MachineIdentity` | Leaderboard | the board's server, where the key is kept, this machine | `Leaderboard/Internal` · `Internal/macOS` (Keychain, IOKit) · `Internal/Windows` (Credential Manager, the machine GUID) |

Not a port: a definition (it is parsed, not injected), a closed sum's worker
(the factory picks it; tests build it with `@testable`), a module's own
aggregate (views call `Provider` directly), or anything added "for
testability" alone.

## 7 · Testing

- One test target per module: `QuotasTests`, `DataSourcesTests`, `ProvidersTests` …
  A module's tests link only that module and its suppliers, so `QuotasTests`
  no longer links six AWS SDKs.
- What each piece's tests guard: [TARGET §7](TARGET_ARCHITECTURE.md#7--testing).
- `AcceptanceTests` stays at the App level and composes real modules with
  stubbed ports.
- `MOCKING` turns on the generated mocks. The modules and their tests set it
  for debug builds in `Package.swift`'s `swiftSettings`; the app's targets
  inherit it from `App/Project.swift`'s project settings, so a new one gets it.

## 8 · Still to carve

`Quotas`, `Diagnostics`, `DataSources`, `AWSClients` and `Providers` are
built. `Domain` and `Infrastructure` re-export them (`@_exported import`), so
no call site changes while files move, and each old target is deleted once
it is empty.

| Today | Goes to |
|---|---|
| `Domain/Leaderboard/`, `Infrastructure/Leaderboard/` | `Leaderboard` — carved first, because ClaudeBar for Windows needs it first (§10, phase 2) |
| `Domain/Monitor/` | `Monitoring` (`QuotaAlerter` → `Alerting`) |
| `Domain/Notify/`, `Infrastructure/Notifications/`, `Notify/` | `Alerting` |
| `Domain/Session/`, `Domain/Notch/`, `Infrastructure/Hooks/` | `Activity` (`NSScreen+NotchMetrics` → App) |
| `Domain/Settings/`, `Infrastructure/Storage/` | `Storage` (`StatusColorPolicy`, `MenuBarProviderSettings` → App) |
| `Domain/Provider/` page state (`MenuBarLabel`, `MenuBar*Display`, `MenuBarStackedSize`, `CountdownColon`, `PopoverContentHeight`) | the App |
| `Infrastructure/Claude/ClaudeGuestPassSource` | the App — Claude's alone, a source the composition root hands in behind `GuestPassSource` |
| `Infrastructure/TerminalImport/` | the App — themes are presentation |
| `Tests/DomainTests`, `InfrastructureTests` | split per module, following their sources; `Quotas`' are in `QuotasTests` |

The kernel still holds a few types that belong elsewhere; each carries a
`- Note: Interim` naming its final shape, and the canonical model lists them
under *where the code is still behind*.

## 9 · Open

- **`Storage` as a module, or each module's settings in its own `Internal/`?**
  `settings.json` is one file many contexts write, so one owner today.
- **One module per heavy SDK.** AWS is the only one today; the next gets its
  own `…Clients` module behind its own port in `DataSources`.
- **Usage History as its own module, later?** Not now: `Providers` is its
  only consumer and its work is `DataSources`' (files, the path language,
  prices). It earns a module when it needs its own SDK (a binary or
  SQLite log) or a second consumer; keeping `Internal/Logs/` and
  `UsageHistory.swift` in their own files keeps that carve cheap.

## 10 · One package, two platforms

**Why.** A member of the Leaderboard who also codes on a Windows PC uses
*ClaudeBar for Windows*, the community client in
[tddworks/ClaudeBar-Windows](https://github.com/tddworks/ClaudeBar-Windows)
([#507](https://github.com/tddworks/ClaudeBar/issues/507)). The board is only
fair if a day counts the same on both: the same log reading, the same
`DailyTokens`, the same signing. Two implementations drift, and `vectors.json`
pins signing, not log reading. So the modules are **one Swift package that
builds on macOS and Windows**, and the Windows client depends on it.

**Why Swift, not a Kotlin core.** A Kotlin Multiplatform core was spiked
(`spike/kmp-shared-domain`). Its shared code compiled for Windows with only 15
platform functions missing, but Kotlin/Native's Windows target is Tier 3 and has no
ARM64 build, and the Mac would gain a bridge (SKIE, a Swift face, Gradle and a
JDK in its build). Swift ships official Windows toolchains, Swift 6's
Foundation is the same code on every platform, and the Mac keeps calling its
modules directly. Main's modules import Foundation and each other in all but
29 files; those 29 are this section's work.

### The shape

```text
Package.swift              ← at the repository root, so a client can depend on
                             this repo by URL at a tag or commit
Modules/<Context>/
├── Sources/
│   ├── *.swift            the domain, the ports, the factory — Foundation,
│   │                      Crypto and suppliers only (§3 rule 7)
│   └── Internal/
│       ├── *.swift        implementations that need no platform
│       ├── macOS/         #if os(macOS) — Keychain, OSLog, JavaScriptCore,
│       │                  IOKit, Darwin processes, SwiftTerm, SweetCookieKit
│       └── Windows/       #if os(Windows) — Credential Manager, WinSDK
│                          processes, the console's pseudo-terminal, a
│                          bundled JS engine
├── Resources/
└── Tests/                 Swift Testing — run on macOS and on windows-latest
```

- **Each module's factory picks the platform's implementation.** The Windows
  client calls the same factories as the App (`Leaderboard.make…`,
  `ProviderFactory.makeCatalog…`); no client names `Internal/`.
- **An Apple-only package is a platform-conditional dependency**
  (`.product(…, condition: .when(platforms: [.macOS]))`): SwiftTerm and
  SweetCookieKit in `DataSources`. `AWSClients` builds on macOS only.
- **`CryptoKit` becomes `Crypto`** (swift-crypto), which re-exports CryptoKit
  on Apple platforms, so the Mac's signatures and hashes don't change.
- **SQLite is a bundled package** on both platforms, not the system's `SQLite3`.
- **What a platform lacks is not a stub.** A fetch or lookup case with no
  Windows implementation fails as a `DataSourceError` naming the case and the
  platform; a capability with none is `nil`, as when a definition doesn't
  declare it.
- **`MOCKING`** is in `Package.swift`'s `swiftSettings`, for debug builds and
  tests.
- **The App stays a Tuist target** and depends on the package's products. Its
  project is `App/Project.swift`, because Tuist maps one project per folder
  and the root is the package's
  ([tuist#4624](https://github.com/tuist/tuist/issues/4624)); `Workspace.swift`
  at the root holds the schemes, which run both projects' tests.
  Sparkle, the notch, the Touch Bar, status-item drivers and every view stay
  in the App: they are the Mac's.
- **What isn't here:** the Windows client's UI, its composition root and,
  if its UI is C#, a C interface over the factories. Those live in its repo.

### Phases

Each phase leaves main shippable and the Mac app unchanged in behaviour.

| # | Phase | Done when |
|---|---|---|
| 0 | **Prove the toolchain.** A `windows-latest` job builds and tests `Quotas` with the Swift toolchain, Mockable included | the job is green — built ([#523](https://github.com/tddworks/ClaudeBar/pull/523)): Swift 6.3.3 builds and tests `Quotas`, and a `@Mockable` port's mock works there |
| 1 | **The package.** Root `Package.swift` declares today's modules; Tuist consumes it; no source changes | `tuist test` and the macOS `swift test` are green — built ([#526](https://github.com/tddworks/ClaudeBar/pull/526)): `tuist test` runs the same 3,099 tests as before, and `swift test` runs the modules' tests without Tuist |
| 2 | **The leaderboard slice.** Carve `Leaderboard` (§8); `CryptoKit` → `Crypto` in `UsageLog`, `CLISession`, `ProviderDefinition`, `RequestSigner`, `SigningKey`; Diagnostics behind `LogSink`; the Mac-only files of `DataSources` move to `Internal/macOS/` | `Quotas`, `Diagnostics`, `DataSources`, `Providers` and `Leaderboard` build and pass on Windows, including the log-reading tests and `vectors.json` — the Windows client can start |
| 3 | **Windows adapters for the slice:** `SigningKeyStore` on Credential Manager, `MachineIdentity` on the machine GUID, `LeaderboardAPI` on `URLSession` | the Windows client joins and uploads against the real server |
| 4 | **Paths and shells.** The engine's Mac assumptions without an import (`/bin/zsh`, `/usr/bin/security`, `~/Library/Application Support`, `:` in `PATH`) become facts each worker receives; definitions name a platform's app-data folder through the path language ([ENGINE_DESIGN](ENGINE_DESIGN.md) changes first) | the definitions that read local files resolve on Windows |
| 5 | **Quotas on Windows.** The rest of `Internal/Windows/`: processes, the pseudo-terminal, the JS engine, `Monitoring`, `Alerting`, `Storage` | the Windows client shows quotas |

### Open

- **The JavaScript engine on Windows.** QuickJS through a C target is the
  candidate; only `script` mappings need it, not the leaderboard.
- **Foundation's differences on Windows** (paths, symlinks, `FileManager`,
  date formats, and APIs it lacks outright, such as `RelativeDateTimeFormatter`)
  are found by running the same tests there, which is why every module's tests
  run on both. A file that imports only Foundation can still fail to build.
- **The machine GUID** is kept by a disk image cloned to another PC, unlike a
  Mac's `IOPlatformUUID`; the leaderboard design decides whether that is
  enough for its copied-key check.

