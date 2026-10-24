---
description: How ClaudeBar's code is cut into modules — one module per bounded context, the domain at each module's root and its implementations in Internal/, no Infrastructure layer and no vendor modules, one factory per module, the dependency rules, naming, testing, the one package that also builds on Windows and Linux, and what is left to carve; read before adding a file, a type or a module.
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
| `Alerting` | Alerting | `QuotaAlerts`, `StatusAlerts`, `Alert`, `AlertDestination`, `Webhooks`, Notify! values, `NotifySettingsRepository`, `WebhookSettingsRepository` | `Notifications`, `SystemAlertSender`, `WebhookClient`, `NotifyGatewayClient` |
| `Activity` | Activity | `ClaudeSession`, `SessionEvent`, `SessionMonitor`, `NotchActivity`, `HookSettingsRepository` | `HookHTTPServer`, `HookInstaller`, `PortFile` (shared with the local API), `SessionEventParser` |
| `Leaderboard` | Leaderboard | `LeaderboardMembership`, `DailyTokens`, `Username`, `RequestSigner`, `LeaderboardUploader`, the devices' values (`Device`, `DeviceCode`, `DeviceLabel`), the ports `LeaderboardAPI` · `SigningKeyStore` · `MachineIdentity` · `TokenLogs` ([its design §7](../features/leaderboard/design.md#7--architecture)); the factory `Leaderboard.makeAPI(client:)` · `makeKeyStore()` · `makeMachineIdentity()` | `LeaderboardHTTPClient`; `FallbackSigningKeyStore` over `KeychainSigningKeyStore` (macOS) and `DefaultsSigningKeyStore`; `IOKitMachineIdentity` with `MacModel` (macOS); `CredentialManagerSigningKeyStore` and `WindowsMachineIdentity` (Windows) |
| `Storage` | Vault & Settings · generic | `Storage.makeSettings()`, `Storage.makeVault()`, `AppSettingsRepository` | `JSONSettingsRepository`, `JSONSettingsStore`, `KeychainCredentialRepository`, `UserDefaults…`, `SecureCredentialMigration` |
| `Diagnostics` | — cross-cutting | `AppLog` and its categories | the `LogSink`s: `FileLogSink`, `OSLogSink` (macOS) |
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
   Foundation (with `FoundationNetworking`, its networking half off Apple
   platforms), `Crypto` (swift-crypto) and their suppliers, and nothing else;
   a file that imports an Apple framework (`Security`, `OSLog`, `IOKit`,
   `AppKit`, `Darwin`…) or `WinSDK` lives in
   `Internal/macOS/` or `Internal/Windows/`, whole inside `#if os(…)` (§10).
   No other file holds an `#if os(…)`, a platform's name, or a path only one
   platform has (`/bin/sh`, `/usr/bin/security`): it asks the module's
   `Platform` (§10, "One place picks the platform").

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
| no grab-bag types | no `Machines`, `Context`, `Dependencies`, `Environment` bundle: each worker receives the one thing it uses. The one exception is a module's `Platform` (§10): only its factory reads it, and hands each worker the one thing from it | a bag is an ISP violation with a friendly name |
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
│   │                                   files or command · format · where · at · id · model ·
│   │                                   tokens · cost · prices · freeWhen · sessionGap
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
│       ├── Logs/      LogRecord · LogReader (one closed list, one `records(since:)`) ·
│       │              JSONLinesReader · JSONLogReader · CommandLogReader · SQLiteLogReader (a reader per
│       │              log source, each knowing its own) · LogFileFinder (behind the file
│       │              readers) · DayAggregator · PriceList · LocalEndpoint
│       ├── Process/   PipeCLIExecutor · PipeConversation · SubprocessSupport ·
│       │              DefaultCLIExecutor · InteractiveRunner · ChildTeardown ·
│       │              BinaryLocator · LoginShellEnvironment · RunningProcesses ·
│       │              TerminalRenderer; PtySession, the Mac's and Linux' shared
│       │              pty adapter, under its POSIX guard
│       └── Network/   URLSessionNetworkClient · LocalServers · LoopbackClient
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
| `AlertDestination` | Alerting | who hears an alert: this Mac's notifications, the person's webhooks | `Alerting/Internal` |
| `WebhookSending` | Alerting | one POST to a webhook's URL | `Alerting/Internal` |
| `DestinationSecrets` | Alerting | a destination's secret, in the Keychain or its fallback | `Storage` |
| `HookEventReceiver` | Activity | Claude Code's hooks | `Activity/Internal` |
| `ScriptEngine` | DataSources | a JavaScript engine, for a `script` mapping | `DataSources/Internal/Mapping` (QuickJS, vendored, both platforms, §10) |
| `LogSink` | Diagnostics | where a log line goes | `Diagnostics/Internal/macOS` (OSLog) · the file log, both platforms |
| `LeaderboardAPI` · `SigningKeyStore` · `MachineIdentity` | Leaderboard | the board's server, where the key is kept, this machine | `Leaderboard/Internal` · `Internal/macOS` (Keychain, IOKit) · `Internal/Windows` (Credential Manager; the label "Windows PC") |

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

`Quotas`, `Diagnostics`, `DataSources`, `AWSClients`, `Providers` and
`Leaderboard` are built. `Domain` and `Infrastructure` re-export them (`@_exported import`), so
no call site changes while files move, and each old target is deleted once
it is empty.

Until then, each target groups its files by the context they will move to,
so a folder already names its destination:

| Today | Goes to |
|---|---|
| `Domain/Monitoring/`, `Infrastructure/Monitoring/` | `Monitoring` |
| `Domain/Alerting/`, `Infrastructure/Alerting/`, `App/Alerting/` (its drivers stay in the App) | `Alerting` |
| `Domain/Activity/`, `Infrastructure/Activity/`, `App/Activity/` (views stay in the App) | `Activity` (`NSScreen+NotchMetrics` → App) |
| `Domain/InUse/`, `Infrastructure/InUse/` | not decided: beside `InUse` in `Providers`, or a module of its own (§9) |
| `Domain/Settings/`, `Infrastructure/Settings/` | `Storage` |
| `Domain/App/` (page state, `StatusColorPolicy`, `MenuBarProviderSettings`, `PopoverTitle`), `Infrastructure/App/` (terminal theme import) | the App |
| `Domain/Providers/`, `Infrastructure/Providers/` (`ClaudeGuestPassSource`) | deleted (`AccountInfo`, `UsageProbe` are unused); the guest-pass source to the App, the composition root naming its vendor |
| `Infrastructure/DataSources/` (`ShellEnvironment`, `SimpleCLIExecutor`) | `DataSources` |
| `Tests/DomainTests`, `InfrastructureTests`, `AppTests` | split per module, following their sources' context folders; `Quotas`' are in `QuotasTests`, the leaderboard's in `LeaderboardTests` |

The kernel still holds a few types that belong elsewhere; each carries a
`- Note: Interim` naming its final shape, and the canonical model lists them
under *where the code is still behind*.

## 9 · Open

- **`Storage` as a module, or each module's settings in its own `Internal/`?**
  `settings.json` is one file many contexts write, so one owner today.
- **Where In use's app half goes.** `NewSessions` and the shell lines follow
  refreshes and write the person's shell files; `InUse` itself is in
  `Providers`. Beside it, or an `InUse` module once a second consumer appears?
- **One module per heavy SDK.** AWS is the only one today; the next gets its
  own `…Clients` module behind its own port in `DataSources`.
- **Usage History as its own module, later?** Not now: `Providers` is its
  only consumer and its work is `DataSources`' (files, the path language,
  prices). It earns a module when it needs its own SDK (a binary or
  SQLite log) or a second consumer; keeping `Internal/Logs/` and
  `UsageHistory.swift` in their own files keeps that carve cheap.

## 10 · One package, three platforms

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

### The porting surface

**Why.** The point of the package is that ClaudeBar is easy to run on another
platform. The measure: *how little must a new platform write, and how much
runs the same everywhere?* Phase 2's `Platform` grew to one value with 19
optional fields. Two of them were libraries, not facts about the OS
(`scriptEngine`, `sqlite`), and they caused 391 of Windows' 413 skipped tests.
The time zone wasn't in it at all, which is how a KST member's day ended at
09:00 ([#563](https://github.com/tddworks/ClaudeBar/issues/563)).

```text
  Anything that can be a library is a library: ONE copy, the same on every OS.
  Only what the OS truly owns differs: a SMALL, NAMED set of ports, each with a contract suite.
  A new platform = implement those ports. Nothing else.
```

```text
 ┌─────────────────────────────── ClaudeBarKit ──────────────────────────────────┐
 │  WRITTEN ONCE: every OS                                                       │
 │   Quotas · Providers · DataSources · Leaderboard · Monitoring                 │
 │   Vendor/: QuickJS · SQLite · CLDR       (libraries and data, not OS facts)   │
 │                                                                               │
 │  THE PORTING SURFACE: all a new platform implements                           │
 │  ┌──────────┬──────────┬──────────┬────────────┬──────────┬──────────┐        │
 │  │Processes │ Terminal │ Secrets  │LocalNetwork│  Places  │ TimeZone │        │
 │  └──────────┴──────────┴──────────┴────────────┴──────────┴──────────┘        │
 │   each: a protocol + ONE contract suite every platform's adapter must pass    │
 ├──────────── Internal/macOS ───┬──── Internal/Windows ───┬── Internal/Linux ───┤
 │  6 adapters                   │  6 adapters             │  6 adapters         │
 └───────────────────────────────┴─────────────────────────┴─────────────────────┘
   Mac App: views, menu bar, Notify!   Windows client: C interface → HUD   (no Linux client yet)

  Tests:  everything above the ports  ─▶ runs on every OS, never skips
          each port's contract suite  ─▶ runs against each adapter; skips only until it exists
```

**Done when** a third platform means writing 6 adapters and passing 6 contract
suites, with no edit above the line. Linux is the third platform, and its
adapters exist as far as Windows' do: the modules build and pass their tests
there, and the ports whose slice hasn't come (`Secrets`, `LocalNetwork`) are
`nil`, so a case that needs one fails at its named step.

- **A library is vendored, pinned, never hand-edited.** One folder per
  library under `Vendor/`, holding the source, its release `VERSION` and its
  `LICENSE`; shims live in their own file. `scripts/bump-vendor.sh` is the
  one way a pinned version changes. A wrapper package would add a
  supply-chain hop to an app that holds people's API keys.
- **One JavaScript engine, QuickJS, on the Mac too.** With one engine there
  is nothing to keep in sync: a script reads the same on every OS. A spike
  ran all 2,170 Mac tests green on it
  ([#563](https://github.com/tddworks/ClaudeBar/issues/563#issuecomment-6188010943)).
  JavaScriptCore goes.
- **One SQLite, bundled.** The Mac's `SQLite3` goes too, so `ReadOnlyQuery`
  is one file with no `#if`.
- **What the OS owns is a port**, `@Mockable`, in `Ports/`, with one contract
  suite in `Tests/Contracts/` that runs against `Platform.current`'s adapter.
  The fields a port takes over leave `Platform`:

| Port | Takes over today's | Mac adapter | Windows adapter | Linux adapter |
|---|---|---|---|---|
| `TimeZone` | (new) | `TimeZone.current` | the zone's registry key, through CLDR: built ([#567](https://github.com/tddworks/ClaudeBar/pull/567)) | the zone Foundation reads from `/etc/localtime`: built ([#600](https://github.com/tddworks/ClaudeBar/pull/600)) |
| `Processes` | `runCommand` · `rpcTransport` · `binaryLocator` · `scriptCommand` · `loginShellCommand` | the login shell's `PATH`, `sh` for a script, `SIGTERM` then `SIGKILL`, `$SHELL -l -i` | `PATH` + `PATHEXT`, a script run as the file itself, `TerminateProcess`, the PowerShell profile: built ([#580](https://github.com/tddworks/ClaudeBar/pull/580)). The OS answers four facts; finding, running, talking and reporting are one neutral copy ([below](#processes-a-program-the-person-has)) | `PATH`, `/bin/sh` for a script, `SIGTERM` then `SIGKILL` after 2 s: built ([#600](https://github.com/tddworks/ClaudeBar/pull/600)) |
| `LocalNetwork` | `localNetwork` · `localServer` · `localServerCommands` · `processList` | `proc_listallpids`, `pgrep`, `lsof`, `URLSession` trusting this machine's certificate | `EnumProcesses`, each process's command line from its process information, the TCP listener table, WinHTTP with the certificate checks off on that request: built ([#588](https://github.com/tddworks/ClaudeBar/issues/588)). The OS answers four facts; finding the app and asking it are one neutral copy ([below](#localnetwork-an-apps-own-server)) | not yet: `/proc/<pid>/cmdline` and `/proc/net/tcp` with socket inodes, its own follow-up; `LocalNetworkContract` is skipped, saying why |
| `Terminal` | `runCLI` · `screenRenderer` | a pty (`openpty`, one at a time), its CLI started and read by `PtySession`; SwiftTerm renders | a pseudo console (ConPTY), the CLI created attached to it in a job that ends its whole tree; SwiftTerm renders: built ([#625](https://github.com/tddworks/ClaudeBar/pull/625)). The OS starts the CLI in its terminal; typing, reading until the screen settles and rendering are one neutral copy ([below](#terminal-a-clis-screen)) | a pty (`posix_openpt`) through the same `PtySession`, and SwiftTerm's core |
| `Secrets` | `keychain` · `browserCookies` · `browserStorage` | `KeychainItems` over the `security` tool; SweetCookieKit | Credential Manager, an item named `service:account` as go-keyring names it, one call at a time (changed by several threads at once, it loses some changes): built ([#640](https://github.com/tddworks/ClaudeBar/issues/640)); cookies and storage `Unavailable` in phase 5 | `secret-tool`, the way the leaderboard's key store proved; cookies and storage `Unavailable` |
| `Places` | `applicationData` · `pathSeparator` | `~/Library/Application Support`, `/` | `APPDATA`, `\` (phase 4) | `$XDG_DATA_HOME`, else `~/.local/share`, `/`: built ([#600](https://github.com/tddworks/ClaudeBar/pull/600)) |

#### Processes: a program the person has

A data source asks for a program in the person's words: *run the CLI they
installed*, *talk to it*, *run their own script*, *what does their login
set*. Pipes, argv, `PATH` and signals are how, and
stay below. So the port is split by what each fact answers, and the
business is one neutral copy above it:

```text
DOMAIN, neutral, one copy
  Processes        the programs on this machine, from the four facts below
    .program(named:)  → Program?      an installed CLI, found
    .script(at:)      → Program?      the person's script file, when it is there
    .loginEnvironment → LoginShellEnvironment
  Program          a program found, started the way this OS starts it
    .run(args, input, environment, timeout, in:) → what it printed
        throws the facts: missing · couldn't start · exited n   ◀ the one owner
    .talk(args, environment, in:)                → a conversation
TECHNICAL, neutral, one copy
  PipeCLIExecutor (the timeout race, stdout and stderr as one text)
  PipeConversation (a line at a time; Subprocess starts it, as the pipe runner does,
                    so the program gets its pipes and none of the app's other handles)
PORTS, Ports/Processes.swift: what each OS answers, one question each
  InstalledPrograms   find(name) → path?          login PATH + tool folders │ PATH + PATHEXT
  ScriptStart         command(path) → argv        sh 'exec "$1"'            │ the file itself
  LoginShell          command(printing:between:)  $SHELL -l -i              │ PowerShell profile
  ChildLaunch         environment(for:) ·         PATH + tool folders,      │ names ignoring case,
                      stopGrace                   exact names; 2s           │ none: the job is ended
```

- **Each piece changes for one reason.** How a CLI is found changes
  `InstalledPrograms`; a new kind of script changes `ScriptStart`; a login
  shell changes `LoginShell`; a timeout changes `PipeCLIExecutor`; how a
  failed run is worded changes `Program`.
- **A new platform answers the four facts**, in one adapter that conforms to
  them (`MacProcesses`, `WindowsProcesses`), and passes `ProcessesContract`.
  Nothing above the ports is edited. A fetch kind that runs a program uses
  `Program` and edits no adapter.
- **A worker never sees argv, `PATH` or a pipe.** `CommandFetcher`,
  `ScriptFetcher` and `JSONRPCFetcher` find a `Program` and tell it to run
  or talk; `LoginShellEnvironment` owns its markers and hands `LoginShell`
  them to print between.
- **A test hands in the running, not the facts.** `Processes.with(pipes:…)`
  keeps this OS's facts and runs programs on what the test gives, so the
  factory's stubbed `make` and a provider's test say the same thing.

#### LocalNetwork: an app's own server

A `localServer` fetch asks for an app in the person's words: *is it
running*, *what was it started with*, *where does it listen*, *ask it*.
The flow (find the app, read its values, try its ports and paths, word the
failure) is one neutral copy; the OS answers four facts
([#588](https://github.com/tddworks/ClaudeBar/issues/588)):

```text
DOMAIN, neutral, one copy
  LocalServers         the four facts below, and a client that asks only here
    .fetcher(for:)   → LocalServerFetcher   find, read values, try ports and paths
    .commands(for:)  → what Import discloses: the programs reading the facts runs
  LoopbackClient       refuses an address off this machine before sending (isLoopback,
                       the rule each adapter reads too); follows a redirect only
                       within the same origin (SameOriginRedirectDelegate.sameOrigin)
PORTS, Ports/LocalNetwork.swift                    Mac                     │ Windows
  RunningPrograms      paths()                     proc_listallpids        │ EnumProcesses
  ProgramCommandLines  commandLines(naming:)       pgrep -a -lf            │ NtQueryInformationProcess
  ListeningPorts       ports(of:)                  lsof -iTCP -sTCP:LISTEN │ GetExtendedTcpTable
  LoopbackRequests     send(_:) → no redirect      URLSession, any cert    │ WinHTTP, cert checks off
                       followed; a host off this   on 127.0.0.1            │ on that request
                       machine refused, unsent
```

- **Windows runs no program to find an app.** Its command lines and ports
  come from the kernel, so Import discloses nothing for them there.
- **`URLSession` can't be the Windows client.** swift-corelibs-foundation
  has no server trust (`URLProtectionSpace.serverTrust` is unsupported), and
  its one way to skip the check is a process-wide variable read on Android
  only. WinHTTP turns the checks off on one request; the SDK's `WinSDK`
  module leaves `winhttp.h` out, so a two-line system-library module
  (`CWinHTTP`) brings it in, on Windows only.
- **A test hands in the running, not the facts.** The stubbed `make` takes
  `running: [RunningProgram]` (path, command line, ports), so Antigravity's
  tests run on every platform.

#### Terminal: a CLI's screen

A `cli` fetch runs a TUI as a person would, types into it and reads the
screen it draws. A POSIX pty is two file descriptors the child is given as
its standard files; a Windows pseudo console is attached to the child as it
is created. So starting the child is the OS's answer, and the session above
it reads and writes through what it started:

```text
NEUTRAL, one copy
  DefaultCLIExecutor   off the cooperative pool, the call's environment and ready markers
  InteractiveRunner    the input delay, autoResponses, the quiet spell, readyWhen;
                       the session's one change, applied by ChildLaunch under the OS's
                       name rule: the call's exclusions out, HOME TERM COLORTERM CI
                       (and LANG) as defaults where the app has none, the terminal's
                       PATH and the call's additions set over both
  TerminalRenderer     SwiftTerm's headless screen, and the screen's size (160×50) the
                       runner opens the terminal at
  ChildTeardown        ask, wait, kill, wait: a child's end within a bound; the wait
                       before the kill is ChildLaunch's stopGrace, none means kill at once
PORT, Ports/Terminal.swift
  PseudoTerminal   start(launch) → TerminalSession · sessionPath() · fallbackLocale
                   Mac: the login shell's PATH, en_US.UTF-8 │ Linux: C.UTF-8 │ Windows: neither
  TerminalSession  read() · write(_:) · isRunning · exitCode · end()
                   Mac, Linux: PtySession over openpty │ posix_openpt, SIGTERM then SIGKILL
                   Windows:    ConPtySession — CreatePseudoConsole, CreateProcessW with
                               null standard handles, a job, a thread draining the output;
                               ChildTeardown with no grace, so the job is ended at once
```

- **The child gets the console and nothing else.** An app whose own standard
  files are redirected (a GUI app, a test runner) would hand them to the
  child, which then writes past the console; null standard handles keep it
  in the console.
- **A session runs until its last frame is in.** The console paints after
  the program writes, so a Windows session counts as running until it has
  been quiet for 300 ms after the program ended.
- **The whole tree ends.** `claude.cmd` starts `node`: the child starts
  suspended and joins a job before it runs, and ending the session ends the
  job.

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
│       ├── macOS/         #if os(macOS): the Mac's adapters for the ports
│       │                  (Keychain, OSLog, IOKit, Darwin processes,
│       │                  SweetCookieKit)
│       ├── Windows/       #if os(Windows): the same ports, one slice at a
│       │                  time (Credential Manager, WinSDK processes, the
│       │                  console's pseudo-terminal)
│       └── Linux/         #if os(Linux): the same ports, one slice at a time
│                          (libsecret, glibc's stat, the pty); no client yet
Vendor/<Library>/          pinned C and data, never hand-edited: QuickJS,
                           SQLite, CLDR; changed only by scripts/bump-vendor.sh
├── Resources/
└── Tests/                 Swift Testing — run on macOS, on windows-latest and on Linux
```

- **Each module's factory picks the platform's implementation.** The Windows
  client calls the same factories as the App (`Leaderboard.make…`,
  `ProviderFactory.makeCatalog…`); no client names `Internal/`.
- **A platform's file names are its own.** SwiftPM names each source file's
  object after the file, so two platforms' files in one target can't share a
  basename even when both are `#if`-guarded: hence `SystemTimeZone.swift` on
  the Mac and `LinuxTimeZone.swift`, not a second `SystemTimeZone.swift`. An
  extension of a shared type is fine — `FileStamp+Linux.swift` names the
  platform in the file itself.
- **An Apple-only package is a platform-conditional dependency**
  (`.product(…, condition: .when(platforms: [.macOS]))`): SwiftTerm and
  SweetCookieKit in `DataSources`. `AWSClients` builds on macOS only.
- **`CryptoKit` becomes `Crypto`** (swift-crypto), which re-exports CryptoKit
  on Apple platforms, so the Mac's signatures and hashes don't change.
- **SQLite and QuickJS are vendored C targets** on both platforms, not the
  system's `SQLite3` or JavaScriptCore ([#570](https://github.com/tddworks/ClaudeBar/issues/570)).
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

### One place picks the platform

**Why.** A module that has platform workers needs, on each platform, *what
this machine offers*: a way to run a CLI, a Keychain, the person's zone.
Asked in many places (`#if os` in the factory, two types with one name, a
`nil` argument meaning "use the default"), the answer drifts: a third
platform falls into every `#else`, a Mac test can't reach what Windows does,
and a new capability edits shared files. So it is asked once.

The folders, as the slices leave them; *(slice N)* marks what is not built
yet:

```text
Package.swift                    + CQuickJS · CSQLite C targets (#570)
Vendor/                          pinned, never hand-edited; changed only by
│                                scripts/bump-vendor.sh
├── CLDR/       windowsZones.xml · VERSION · LICENSE (#567)
├── CQuickJS/   quickjs-amalgam.c · include/quickjs.h · include/shim.h ·
│               VERSION · LICENSE (#570)
└── CSQLite/    sqlite3.c · include/sqlite3.h · VERSION · LICENSE (#570)
Modules/DataSources/Sources/
├── DataSources.swift          the factory: make(…, platform: .current) — never #if
├── ScriptEngine.swift         a neutral worker's port, @Mockable, so a test can
│                              hand a mapping its answer — not a platform's
├── Ports/                     the porting surface, @Mockable, one file each
│   ├── TimeZoneSource.swift   the person's zone, and DataSources.timeZone() ·
│   │                          .calendar(), the one public way to it (#567)
│   ├── Processes.swift        InstalledPrograms · ScriptStart · LoginShell ·
│   │                          ChildLaunch: what an OS answers about
│   │                          programs (#579)
│   ├── LocalNetwork.swift     RunningPrograms · ProgramCommandLines ·
│   │                          ListeningPorts · LoopbackRequests: what an OS
│   │                          answers about an app's own server (#588)
│   ├── Terminal.swift         PseudoTerminal · TerminalSession: a CLI's
│   │                          terminal session (#623)
│   └── Secrets.swift          KeychainItems: an item in the OS's secret
│                              store, by service and account (#640)
└── Internal/
    ├── Platform.swift         ◇ struct Platform — holds the ports, nothing
    │                            else; Platform.bare: the name and zone. Until
    │                            a slice moves them, today's optional fields
    │                            stay here
    ├── Unavailable.swift      a case whose connection is nil: fails at its step
    │                            as ErrorFact.unavailable, naming it and platform.name
    ├── Mapping/QuickJSEngine.swift   the one engine, on CQuickJS (#570)
    ├── Mapping/LocalDateScript.swift Date's local time is the zone the
    │                                 engine is given, not the OS's (#570)
    ├── Lookup/ReadOnlyQuery.swift    the one SQLite reader, on CSQLite (#570)
    ├── Time/WindowsZones.swift   a Windows zone key to its zone: CLDR's table
    │                             (+Table, generated from Vendor/CLDR) or the OS's
    │                             offset — neutral, so its tests run everywhere
    ├── Process/               Processes · Program: a program the person has,
    │                            found, run and talked to, its failures reported;
    │                            PipeCLIExecutor · PipeConversation ·
    │                            SubprocessSupport underneath, one copy for every
    │                            platform (#579)
    ├── Network/               LocalServers · LoopbackClient, and
    │                            Fetch/LocalServerFetcher: an app's own server,
    │                            found and asked, one copy (#588)
    ├── Fetch/ Lookup/ Mapping/ Logs/ Network/   neutral workers
    ├── macOS/                 #if os(macOS), whole file: one adapter per port
    │   ├── Platform+macOS.swift      static let current = Platform(name: "macOS", …)
    │   ├── Time/SystemTimeZone.swift   TimeZone.current
    │   ├── Process/MacProcesses.swift   the four facts: BinaryLocator, sh,
    │   │                               $SHELL -l -i, SIGTERM then kill (#579)
    │   ├── Network/MacLocalServers.swift   RunningProcesses, pgrep, lsof,
    │   │                               URLSession trusting 127.0.0.1 (#588)
    │   └── Process/ · Lookup/ · Network/ · Logs/   today's workers, regrouped
    │                                 under their ports in slices 3–5
    ├── Windows/               #if os(Windows), whole file: the same ports
    │   ├── Platform+Windows.swift    static let current = Platform(name: "Windows", …)
    │   ├── Time/WindowsTimeZone.swift   the zone's registry key and offset (#567)
    │   ├── Process/WindowsProcesses.swift   the four facts: PathBinaryLocator (PATH +
    │   │                                   PATHEXT), the file itself, PowerShell,
    │   │                                   TerminateProcess (#579)
    │   ├── Network/WindowsLocalServers.swift   EnumProcesses, NtQueryInformationProcess,
    │   │                                   GetExtendedTcpTable, WinHTTP (#588)
    │   └── Logs/                     FileStamp+Windows · ByteSearch+Windows
    └── Linux/                 #if os(Linux), whole file: the same ports, as far as
        ├── Platform+Linux.swift     static let current = Platform(name: "Linux", …)
        ├── Time/LinuxTimeZone.swift     TimeZone.current; a zone with no tzdata
        │                                 file is the OS's offset, fixed
        ├── Process/LinuxProcesses.swift  the four facts: LinuxBinaryLocator (PATH),
        │                                 /bin/sh, $SHELL -l -i, SIGTERM then kill
        └── Logs/                    FileStamp+Linux · ByteSearch+Linux
Modules/DataSources/Tests/
├── Contracts/                 one suite per port, run against Platform.current's
│                                adapter: TimeZoneContract (#567),
│                                ProcessesContract (#579), the rest with their slices
├── UnavailableTests.swift     the factory with Platform.bare — runs on the Mac too
├── …                          everything else: every OS, no skips
└── macOS/ · Windows/ · Linux/   an adapter's own tests, under #if os(…)
Modules/Monitoring/            QuotaMonitor's neutral core (slice 6, its own design
                               review first)
```

- **`Platform` is a value, and `Platform.current` is its only `#if`.** Each
  platform folder defines `current` once. Neutral code reads the value and
  never asks which OS it is on; a third platform is a new folder and a new
  `current`, not an edit to a shared file.
- **`nil` means one thing: this platform has none.** The factory takes a
  `Platform`; the public `make` passes `.current`. It never takes a `nil` to
  mean "the default", so a test hands in `Platform.bare` (or `.current` with
  one connection removed) and checks on the Mac what Windows does.
- **A platform worker is reached through a port** declared in the neutral
  part (`Ports/`, and `CLIExecutor`, `RPCTransport` … until their slices
  move them, §6). Two types of one name, one per folder, are not allowed:
  nothing makes their APIs agree.
- **Only the factory reads `Platform`.** It hands each worker the one thing it
  uses (§4); no worker receives the bag.
- **What the platform lacks is a fact, not text.** `Unavailable` fails as
  `ErrorFact.unavailable`, so a definition's `errors` may word it and a
  screen can tell "not on Windows yet" from a failure.
- **Everything above the ports runs on every OS and never skips.** A test
  that needs a port names it (`.needsTerminal`, in Providers'
  `Tests/Support/Capabilities.swift`) and runs wherever `Platform.current` has
  that port; when a slice brings the Windows adapter, its tests start running
  there with no edit. A library is never a reason to skip.
- **Each port has one contract suite**, in `Tests/Contracts/`, that runs
  against `Platform.current`'s adapter on every OS. It holds the adapter to
  what the OS itself says, as `TimeZoneContract` compares the zone with the
  OS's own offset.
- **A platform's facts are connections too:** the shell argv, the tools a
  worker runs (`lsof`, `pgrep`, `security`), the folder a CLI trusts, app-data
  and path separators. The factory supplies them to workers and to path
  expansion; definitions use `{{platform.appData}}`, not a Mac folder literal.
  A missing fact remains unavailable; it never becomes a guessed command.
- **The person's time zone is a port, never Foundation's `.current`.** On
  Windows Foundation answers GMT: it looks the zone up by its display name,
  which is in the person's language
  ([swift-foundation#2244](https://github.com/swiftlang/swift-foundation/issues/2244)).
  So a day, a reset or a zone handed to a script reads `TimeZoneSource`
  through the factory, and other modules and clients read
  `DataSources.timeZone()` / `.calendar()`. `Quotas` has no platform, so its
  `DateRange` takes a calendar and has no default. The Mac's adapter is
  `TimeZone.current`. Windows' reads the zone's registry key
  (`TimeZoneKeyName`, never translated) and maps it to an IANA zone through
  CLDR's `windowsZones`, the table ICU uses. It falls back to the OS's own
  offset when daylight saving's automatic adjustment is off, when the key
  isn't in the table, or when the zone is one Foundation on Windows can't
  format a date in (`Etc/UTC` and four others stop the process). Those five
  each kept one offset since 2022 or earlier, and a test formats a date in
  every zone the table gives. It never loads the system `icu.dll`: once that
  is loaded, Foundation's named zones are gone from the process. Its contract
  (`TimeZoneContract`) holds each adapter to the OS's own offset at instants
  across two years, including every daylight-saving change.

A module with no platform workers has no `Platform`. `Diagnostics` and
`Leaderboard` follow the same shape for their own ports (`LogSink`,
`SigningKeyStore`, `MachineIdentity`).

### Phases

Each phase leaves main shippable and the Mac app unchanged in behaviour.

| # | Phase | Done when |
|---|---|---|
| 0 | **Prove the toolchain.** A `windows-latest` job builds and tests `Quotas` with the Swift toolchain, Mockable included | the job is green — built ([#523](https://github.com/tddworks/ClaudeBar/pull/523)): Swift 6.3.3 builds and tests `Quotas`, and a `@Mockable` port's mock works there |
| 1 | **The package.** Root `Package.swift` declares today's modules; Tuist consumes it; no source changes | `tuist test` and the macOS `swift test` are green — built ([#526](https://github.com/tddworks/ClaudeBar/pull/526)): `tuist test` runs the same 3,099 tests as before, and `swift test` runs the modules' tests without Tuist |
| 2 | **The leaderboard slice.** Carve `Leaderboard` (§8); `CryptoKit` → `Crypto` in `UsageLog`, `CLISession`, `ProviderDefinition`, `RequestSigner`, `SigningKey`; Diagnostics behind `LogSink`; the Mac-only files of `DataSources` move to `Internal/macOS/` | `Quotas`, `Diagnostics`, `DataSources`, `Providers` and `Leaderboard` build and pass on Windows, including the log-reading tests and `vectors.json` — the Windows client can start — built ([#527](https://github.com/tddworks/ClaudeBar/pull/527), [#528](https://github.com/tddworks/ClaudeBar/pull/528), [#529](https://github.com/tddworks/ClaudeBar/pull/529), [#537](https://github.com/tddworks/ClaudeBar/pull/537)): Windows runs 1,355 of the 1,746 tests and skips the rest, each saying why; the leaderboard's run in full |
| 3 | **Windows adapters for the slice:** `SigningKeyStore` on Credential Manager, `MachineIdentity` as "Windows PC" (the model Windows reports names a self-built PC's motherboard, so it isn't read; the hardware UUID came with the copied-key check, [#549](https://github.com/tddworks/ClaudeBar/pull/549)), `LeaderboardAPI` on `URLSession` as on the Mac | a program on Windows joins, uploads and leaves against the real server through the factories — built ([#547](https://github.com/tddworks/ClaudeBar/pull/547)) |
| 4 | **Paths and shells.** App-data and path separators, shell argv, local-server discovery and the trusted CLI directory are platform facts supplied by the factory. Definitions use `{{platform.appData}}` ([ENGINE_DESIGN](ENGINE_DESIGN.md)); Mac process workers stay in `Internal/macOS/`, and Windows execution remains unavailable until phase 5 | definitions that read local files resolve on Windows — implemented in [#556](https://github.com/tddworks/ClaudeBar/pull/556), for review: redirected `APPDATA`, native drive/UNC paths, newest IDE file, and unchanged Mac paths/archived days |
| 5 | **Quotas on Windows**, in the slices below | the Windows client shows quotas, and Windows skips no test |
| 6 | **Linux, as far as Windows got.** `Internal/Linux/` implements `TimeZone`, `Places` and the log stamps, `Processes` over `/bin/sh` (the running-program listing it had over `/proc` moved to `LocalNetwork`, which Linux doesn't answer yet), and the leaderboard's key store over libsecret with the app's own store behind it; `Package.swift` and a `ubuntu-latest` job build and test the modules there | `swift test` is green on Linux and `ProcessesContract` and `TimeZoneContract` pass there; the ports without a slice (`Terminal`, `Secrets`, `LocalNetwork`) stay `nil`, so their contracts are skipped, saying why — built ([#600](https://github.com/tddworks/ClaudeBar/pull/600)): 2,021 tests in 185 suites, 18 skipped with their reasons |
| 7 | **Terminal on Linux.** `runCLI` and the screen renderer on a pty (`posix_openpt`): the Mac's interactive session — `InteractiveRunner`, `DefaultCLIExecutor`, `TerminalRenderer` — becomes one neutral copy, the pty and the session's environment join the Terminal port as its first facts, and the child's bound end keeps its one copy beside the session ([#615](https://github.com/tddworks/ClaudeBar/pull/615)) | the 9 `reads a CLI's screen` tests run on Linux; `TerminalContract` holds the Mac and Linux to one rendered answer; the Mac's tests are unchanged; Linux skips only the local server |

Phase 5's slices, each its own issue and PR
([#563](https://github.com/tddworks/ClaudeBar/issues/563)):

| # | Slice | Done when |
|---|---|---|
| 0 | **`TimeZone` port.** The person's zone, read through the factory; every `.current` calendar default reads it | a KST test runs on any machine — built ([#567](https://github.com/tddworks/ClaudeBar/pull/567)) |
| 1 | **Vendor QuickJS and SQLite; one engine everywhere.** `QuickJSEngine` replaces JavaScriptCore on the Mac and is the engine on Windows; one `ReadOnlyQuery` on bundled SQLite | Windows no longer skips a test for a script engine or SQLite (−391); the Mac's numbers don't change; release-build timing, the size added to the Mac app, and scripts in definitions people wrote checked — built ([#571](https://github.com/tddworks/ClaudeBar/pull/571)) |
| 2 | **`Processes`**: port, contract, Windows adapter | its tests run on Windows — built ([#580](https://github.com/tddworks/ClaudeBar/pull/580)): `command`, `script` and `jsonRpc` fetches, `command` logs and the login-shell lookup run on Windows |
| 3 | **`LocalNetwork`**, with the localhost-certificate spike | its tests run on Windows — built ([#588](https://github.com/tddworks/ClaudeBar/issues/588)): a `localServer` fetch (Antigravity's `local` source) runs on Windows |
| 4 | **`Terminal`**, with the SwiftTerm-on-Windows spike | its tests run on Windows — built ([#625](https://github.com/tddworks/ClaudeBar/pull/625)): `cli` fetches read a CLI's screen through a pseudo console, and the runner's own suites run on all three platforms |
| 5 | **`Secrets`**: Credential Manager; browser cookies and storage stay `Unavailable` | its tests run on Windows — built ([#640](https://github.com/tddworks/ClaudeBar/issues/640)): a `keychain` lookup reads a Credential Manager item, the GitHub CLI's login included, and saves a renewed login back to an unencoded one |
| 6 | **`Monitoring` into the package**, so no platform rewrites refresh scheduling and alert logic; the menu bar and Notify! stay in the Mac app | its own design review first, since it reshapes the domain's root |

### Open

- **`Places` has no slice of its own.** Its two fields came with phase 4 and
  already work on Windows and on Linux. Slice 2 kept to `Processes`, so they
  stay fields of `Platform` until a slice needs them as a port.
- **Linux is where Windows is, but for `LocalNetwork`.** Its adapters exist
  as far as Windows' do, and the Terminal port begins with its pty. `Secrets`
  is the slice neither platform has; `LocalNetwork` is built on Windows and
  still `nil` on Linux, where `LocalNetworkContract` is skipped, saying why
  ([#563](https://github.com/tddworks/ClaudeBar/issues/563), slices 3–5). What
  Linux answers in its own words: a `secret-tool` key store with the app's own
  store behind it, `~/.local/share` for `{{platform.appData}}`, the zone
  Foundation reads from `/etc/localtime`, and a pty of its own for a CLI
  fetch. The key goes into the tool's pipe *before* the tool starts: a write
  to a tool that has already gone — `env` exiting 127 when `secret-tool`
  isn't installed — is a write to a pipe with no reader, and `SIGPIPE`'s
  default action ends the whole app, not just that call.
- **No Linux client.** The modules carry no UI: the Mac's is the Mac's, and
  the Windows client is its own repo. A Linux one would be a third, and would
  start where the Windows one started.
- **Extension scripts on Windows.** An extension's script runs as the file
  itself, so a `.cmd`, `.bat` or `.exe` works and the example's `.sh`
  doesn't. Running a `.ps1` through PowerShell, or a `.sh` through Git for
  Windows' `sh` when it is there, are left for an issue that asks
  ([#579](https://github.com/tddworks/ClaudeBar/issues/579)).
- ~~**The JavaScript engine on Windows.**~~ QuickJS, vendored, on the Mac too
  ([#570](https://github.com/tddworks/ClaudeBar/issues/570)).
- ~~**A script's local time on Windows.**~~ A script's `Date` local time is
  the person's zone, on every platform: the engine takes it from the
  `TimeZone` port. QuickJS asks the OS (libc's zone on the Mac; on Windows,
  today's offset for every date, quickjs-ng v0.17.0), so `ScriptEngine`'s
  `evaluate` takes a `localTime` zone and `QuickJSEngine` runs
  `LocalDateScript` before the scripts, which binds `new Date(y, m, d)`, the
  local getters and setters, a date-time text with no zone and `toString()` to
  it. Scripts are plain JavaScript. Its contract test checks five zones
  against Foundation's calendar, every quarter hour around each clock change
  ([#570](https://github.com/tddworks/ClaudeBar/issues/570)).
- **Foundation's differences on Windows** (paths, symlinks, `FileManager`,
  date formats, and APIs it lacks outright, such as `RelativeDateTimeFormatter`)
  are found by running the same tests there, which is why every module's tests
  run on both. A file that imports only Foundation can still fail to build.
- **Foundation's differences on Linux** are found the same way. One already is:
  `TimeZone(identifier:)` answers a name the OS's tzdata no longer carries —
  Ubuntu keeps CLDR's deprecated aliases (`Asia/Calcutta`, `Europe/Kiev`, …) in
  a separate `tzdata-legacy` package — and the zone it answers can't back a
  `DateFormatter`, which stops the process instead of failing. Linux's own
  adapter owns it: `LinuxTimeZone` answers a `TZ` with no file under
  `/usr/share/zoneinfo` with the OS's offset, fixed, which is what the C
  library's clock keeps for it, and the TimeZone contract's *should give a zone
  a date can be written in* proves it on every OS (Linux CI runs it in
  `Asia/Calcutta`) ([#600](https://github.com/tddworks/ClaudeBar/pull/600)).
- **Swift's Glibc modulemap carries none of glibc's pty calls.** `posix_openpt`,
  `grantpt`, `unlockpt` and `ptsname` are libc's to answer, but Swift cannot
  import them, so the Linux pty declares the four by name.
- ~~**The machine GUID** is kept by a disk image cloned to another PC, unlike a
  Mac's `IOPlatformUUID`; the leaderboard design decides whether that is
  enough for its copied-key check.~~ It isn't: Windows reads the firmware's
  SMBIOS system UUID instead (`GetSystemFirmwareTable`), which a disk image
  doesn't carry, and keeps no hash on a board whose maker left a placeholder
  ([#549](https://github.com/tddworks/ClaudeBar/pull/549)).

