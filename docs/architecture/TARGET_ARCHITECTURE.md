---
description: How a provider runs — a provider as a JSON definition, one DataSource type that fetches for every provider through single-job workers, the product and its roles, the runtime from definition to popover, testing; read before changing the lifecycle, a role or a flow.
---

# ClaudeBar — the target architecture

> **#3 of 5** in [the design](ARCHITECTURE.md) · **Answers:** how a provider
> runs — from a JSON file, through one `DataSource`, to the popover ·
> **Builds on:** [CANONICAL_MODEL.md](CANONICAL_MODEL.md) · **Next:**
> [MODULAR_DESIGN.md](MODULAR_DESIGN.md)

---

## 1 · The goal, as two principles

| Principle | Today | Target |
|---|---|---|
| **SRP** — one reason to change | `CodexAPIUsageProbe` changes when the auth file moves, when OAuth refresh changes, when the URL changes, when a header changes, and when the JSON changes. Twenty providers repeat this, each with its own `XxxProvider` lifecycle on top | a **definition** changes when Codex changes. A **worker** changes when its protocol or format changes. **`Provider`** changes when the lifecycle changes. Nothing else |
| **OCP** — open for extension, closed for modification | adding a provider adds ~5 types and edits ~10 files | adding a provider adds **one JSON file**. Adding a protocol or format adds **one case and one worker** to a closed list. Neither touches another provider |

There is no `UsageProbe`, no `XxxUsageProbe`, no `XxxProvider`, no
`XxxCredentialLoader`, and no vendor module. Vendor knowledge — URLs, file
paths, field names, client ids, CLI arguments — is data.

## 2 · The pieces

```text
  codex.json  ─────────────────────────────────────────────────┐   DATA
  deepseek.json · ~/.claudebar/providers/*.json · extensions   │   (what Codex IS)
                                                               ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ ProviderCatalog      reads files → [ProviderDefinition]                  │
│ ProviderFactory.make(_:)   definition → Provider, each data source made live   │
│                      by DataSources.make(_:settings:vault:cloudWatch:)   │
└──────────────────────────────────┬───────────────────────────────────────┘
                                   ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ Provider ◆  THE PRODUCT and THE lifecycle: isEnabled · the data source   │
│             in use · fallback · refresh(account) · use(kind)             │
│   └ accounts: [Account] — the logins: values · isEnabled · usage · sync  │
└──────────────────────────────────┬───────────────────────────────────────┘
                                   │ refresh(account) → dataSource.fetchUsage(for: account)
                                   ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ DataSource ◆  ONE type for every provider: its definition + only the     │
│               connection its fetch needs. fetchUsage() = look up the     │
│               key → fetch → map. isReady. Never knows a vendor           │
└───────┬──────────────────────────┬──────────────────────────┬────────────┘
        ▼                          ▼                          ▼
  CredentialLookup (enum)     Fetch (enum)               Mapping (enum)
  each case's worker:         each case's worker:        each case's worker:
  EnvironmentReader           HTTPFetcher                JSONMapper
  SettingReader               JSONRPCFetcher             TextMapper
  JSONFileReader              CLIFetcher (terminal)
  KeychainReader              CommandFetcher (pipes)
  BrowserCookieReader         FileFetcher
  OAuth2Refresher (refresh)   ScriptFetcher
                              CloudWatchFetcher ── CloudWatchClient (port; AWSClients)
        │                          │
        ▼                          ▼
  settings · vault            NetworkClient · CLIExecutor · RPCTransport
  (passed in by name)         (the module's own, built by its factory)
```

| Piece | One job | Changes when |
|---|---|---|
| `ProviderDefinition` · `DataSourceDefinition` | the provider as data, validated on load | a vendor changes |
| `Provider` | the lifecycle every provider shares, and the fallback between its data sources | the lifecycle changes |
| `DataSource` | fetches one data source's usage: look up the key, fetch, map | the order of those three changes |
| `CredentialLookup` · `Fetch` · `Mapping` | closed sums — one case per JSON tag | a protocol, format or key location is added |
| a worker (`HTTPFetcher`, `JSONMapper`, `OAuth2Refresher`, …) | carries out one case | that protocol or format changes |
| `DataSources.make(_:settings:vault:cloudWatch:)` | the one place a case meets the connection it needs | a connection is added |

## 2.1 · The product and its roles

A product plays a different role in each context — refreshed by the Monitor,
configured on its Settings page, a set of logins on the Accounts card — and
each role is its own type that owns what it decides. Dependencies point one
way, down; nothing refers back up.

```text
Providers  ◆                    THE PROVIDERS YOU KEEP — the Providers pane: add a custom one,
│                               delete it, the order (saved), lineup → [Account] (derived);
│                               provider(of: login) — a login's product, by id
└── Provider  ◆                 THE LIFECYCLE — refresh(login), isAvailable, the switch, status,
    │                           testConnection, hasKey; every product-level answer about a login
    ├── accounts: Accounts  ◆   THE ACCOUNTS CARD — the logins and their order: add (form ·
    │   │                       folder · sign in), remove, rename, move
    │   ├── Account  ◆          A LOGIN — knows only itself; names its product by id
    │   └── depends on ↓ Configuration
    ├── configuration: Configuration  ◆   THE SETTINGS PAGE — data source and fallback, the form's
    │                           values, CLI location; answers definitionAsRun(for: login) and
    │                           revision, which grows on every change. Knows no one
    └── inUse: InUse?           reads accounts below it, never its provider (§9)
```

| Question | Answer |
|---|---|
| How does a changed setting reach the fetch, with no arrow up? | **pulled, not pushed**: the provider remakes a login's data sources when the configuration's `revision` is newer than the one it made them at |
| A new or removed login? | the provider makes a login's data sources when first asked, and drops those of a login `accounts` no longer has |
| Adding a folder reads who is signed in there | `Accounts` is handed the same `makeDataSource` the provider is; it never asks the provider |
| What the lineup prints for a login | `provider.lineupName(of:)`: the product's name while it is the only login, else the login's own — decided once, never by a page |
| How a child refers back, if it must | in order: not at all → the parent passed in (or the parent answers) → `weak` → `unowned`, only in a private helper. Anything public — observable, held by views, Tasks or tests — holds no back-reference; a stored callback captures `weak` |

| Rule | Owner |
|---|---|
| a role never depends on the lifecycle, nor on a role above it: `Provider → Accounts → Configuration` | each role |
| a login's data sources are made in one place, from `configuration.definitionAsRun(for:)` at its current revision | `Provider` |
| a setting is saved where its definition says (vault for a secret); a CLI location must be a program; any change grows `revision` | `Configuration` |
| the default login is first and can't be removed; an added login's folder or values are checked before it is kept | `Accounts` |
| adding or removing a login is the product's, never the collection's or the Monitor's | `Provider` |

- **The product's switch is its own setting**; each login's *Pause* is the
  login's. An older `providers.<id>.isEnabled` was the plain login's switch,
  so it is read once: off while another login of the product is on means the
  plain login was paused; otherwise the product was off.
- `selectedProviderId` keeps its name and value (a login's id): the status
  export and `claudebar://` links carry it.

## 3 · Codex, as data

`Resources/Providers/codex.json` — the whole of Codex, shown here as the worked
example of a definition; the file itself is the truth.

```json
{
  "profile": {
    "id": "codex",
    "name": "Codex",
    "links": { "dashboard": "https://platform.openai.com/usage",
               "status": "https://status.openai.com" },
    "look": { "symbol": "chevron.left.forwardslash.chevron.right", "icon": "CodexIcon",
              "color": { "light": [0.18, 0.72, 0.68], "dark": [0.35, 0.85, 0.78] },
              "gradientEnd": { "light": [0.12, 0.52, 0.72], "dark": [0.25, 0.65, 0.85] } }
  },
  "cli": "codex",
  "enabledByDefault": true,
  "defaultDataSource": "rpc",
  "dataSources": [
    {
      "kind": "rpc", "label": "RPC", "summary": "Uses codex app-server RPC",
      "fetch": { "jsonRpc": {
        "cli": "codex", "args": ["-s", "read-only", "-a", "never", "app-server"],
        "workingDirectory": "probe",
        "handshake": [
          { "request": "initialize", "params": { "clientInfo": { "name": "claudebar", "version": "1.0.0" } } },
          { "notify": "initialized" } ],
        "call": "account/rateLimits/read" } },
      "mapping": { "json": {
        "plan": "$.result.rateLimits.planType",
        "quotas": [
          { "name": "Session", "at": "$.result.rateLimits.primary",
            "usedPercent": "usedPercent", "resetsAt": { "epochSeconds": "resetsAt" },
            "window": { "minutes": "windowDurationMins" } },
          { "name": "Weekly", "at": "$.result.rateLimits.secondary",
            "usedPercent": "usedPercent", "resetsAt": { "epochSeconds": "resetsAt" },
            "window": { "minutes": "windowDurationMins" } },
          { "each": "$.result.rateLimitsByLimitId", "skipKeys": ["codex"],
            "name": { "firstOf": ["limitName", "limitId", "$key"], "dropPrefix": "codex_", "capitalize": true },
            "windows": [ { "at": "primary" }, { "at": "secondary", "suffix": " 7d" } ],
            "usedPercent": "usedPercent", "resetsAt": { "epochSeconds": "resetsAt" },
            "window": { "minutes": "windowDurationMins" } } ] } },
      "fallback": "tty"
    },
    {
      "kind": "api", "label": "API", "summary": "Calls ChatGPT API directly",
      "credential": {
        "jsonFile": { "path": "~/.codex/auth.json",
                      "token": "$.tokens.access_token", "refreshToken": "$.tokens.refresh_token",
                      "account": "$.tokens.account_id", "refreshedAt": "$.last_refresh" },
        "refresh": { "oauth2": { "tokenURL": "https://auth.openai.com/oauth/token",
                                 "clientId": "app_EMoamEEZ73f0CkXaXp7hrann",
                                 "every": "8d", "onStatus": [401],
                                 "expiredCodes": ["refresh_token_expired", "refresh_token_reused", "refresh_token_invalidated"],
                                 "hint": "Run `codex` in terminal to log in again." } } },
      "fetch": { "http": {
        "url": "https://chatgpt.com/backend-api/wham/usage",
        "headers": { "Authorization": "Bearer {{token}}", "ChatGPT-Account-Id": "{{account}}",
                     "Accept": "application/json", "User-Agent": "OpenUsage" } } },
      "mapping": { "json": {
        "plan": "$.plan_type",
        "quotas": [
          { "name": "Session", "at": "$.rate_limit.primary_window",
            "usedPercent": ["$header.x-codex-primary-used-percent", "used_percent"],
            "resetsAt": [ { "epochSeconds": "reset_at" }, { "secondsFromNow": "reset_after_seconds" } ],
            "window": { "seconds": "limit_window_seconds" } },
          { "name": "Weekly", "at": "$.rate_limit.secondary_window", "…": "same shape" },
          { "each": "$.additional_rate_limits[*]",
            "name": { "firstOf": ["limit_name", "metered_feature"], "dropPrefix": "codex_", "capitalize": true },
            "windows": [ { "at": "rate_limit.primary_window" }, { "at": "rate_limit.secondary_window", "suffix": " 7d" } ],
            "…": "same shape" } ],
        "cost": { "kind": "extraUsage", "limit": 1000,
                  "remaining": ["$header.x-codex-credits-balance", "$.credits.balance"] } } }
    },
    {
      "kind": "tty", "label": "Terminal", "hidden": true,
      "fetch": { "terminal": { "cli": "codex", "args": ["-s", "read-only", "-a", "never"], "send": "/status" } },
      "mapping": { "text": { "quotas": [
        { "name": "Session", "pattern": "5h limit[\\s\\S]{0,400}?([0-9]{1,3})% left", "leftPercent": 1 },
        { "name": "Weekly",  "pattern": "Weekly limit[\\s\\S]{0,400}?([0-9]{1,3})% left", "leftPercent": 1 } ] } }
    }
  ]
}
```

What the JSON mapping language must therefore say — each a **feature every
provider gets**, never a Codex special case:

| Feature | Why Codex needs it | Who else will |
|---|---|---|
| `at` · `each` over arrays and maps · `skipKeys` · `$key` | additional limits arrive as an array (API) or a map keyed by limit id (RPC) | any provider with per-model limits |
| `usedPercent` **or** `leftPercent` | Codex reports used | most report used; some left |
| a list = first that answers, including `$header.<name>` | headers are preferred over the body | rate-limit headers are common |
| `resetsAt`: `epochSeconds` · `secondsFromNow` · `iso8601` | both shapes occur | all |
| `window`: `seconds` · `minutes` | the window length is the provider's word ([the law](CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them)) | all |
| name rules: `firstOf`, `dropPrefix`, `capitalize`, `suffix` | `codex_spark` → `Spark`, `Spark 7d` | any provider with model names |
| constants (`"limit": 1000`) | credits have a fixed ceiling | balance providers |

**A rule the language cannot say yet** (today's free-plan defaults in the RPC
client are one) becomes a new mapping feature with its own test, or — if no
second provider could ever use it — is questioned until it goes away. It never
becomes vendor code.

## 4 · The runtime

### 4.1 · The types

```swift
// Providers — the definition: a value, decoded and validated on load
public struct ProviderDefinition: Sendable, Equatable, Codable {
    public let id: String, name: String, cli: String?
    public let links: Links, enabledByDefault: Bool
    public let dataSources: [DataSourceDefinition]   // ≥ 1, unique kinds
    public let defaultDataSource: String             // names one of them
}

// DataSources — the JSON of one data source: no behaviour
public struct DataSourceDefinition: Sendable, Equatable, Codable {
    public let kind: String, label: String, summary: String?, hidden: Bool
    public let credential: CredentialLookup?
    public let fetch: Fetch
    public let mapping: Mapping
    public let fallback: String?
}

// DataSources — three closed sums, one case per JSON tag
public enum CredentialLookup: Sendable, Equatable, Codable {
    case environment(String), setting(String), jsonFile(JSONFileFields),
         keychain(service: String), browserCookies(BrowserCookieCredential)
    indirect case refreshing(CredentialLookup, OAuth2Refresh)
}
public enum Fetch: Sendable, Equatable, Codable {
    case http(HTTPRequest), httpSteps(HTTPSteps),   // both written "http"
         jsonRpc(JSONRPCCall),
         cli(CLICall),            // a TUI in a terminal, its screen captured
         command(CommandCall),    // a command over pipes, its exit code checked
         file(FileCall)           // planned: script(path:), cloudWatch(CloudWatchQuery)
}
public enum Mapping: Sendable, Equatable, Codable {
    case json(JSONMappingRules), text(TextMappingRules), script(ScriptMapping)
}

// DataSources — what came back, before anyone read it ("Response" on the Map fields step)
public struct Response: Sendable, Equatable {
    public let status: Int?, headers: [String: String], body: Data
}

// DataSources — a failure names its step ("Couldn't read your key · connect · find the numbers")
public struct DataSourceError: Error, Sendable {
    public enum Step: Sendable { case lookup, fetch, mapping }
    public let step: Step
    public let reason: UsageError          // today's cases (was ProbeError); never a secret or a body
}

// DataSources — ONE type that fetches for every provider
public struct DataSource: Sendable {
    public let definition: DataSourceDefinition
    public func fetchResponse() async throws(DataSourceError) -> Response      // Test Connection
    public func fetchUsage() async throws(DataSourceError) -> UsageSnapshot    // mapping.read(fetchResponse())
    public func isReady() async -> Bool
}
extension Mapping {
    public func read(_ response: Response, kind: String) throws(DataSourceError) -> UsageSnapshot  // Map fields' live card
}

// DataSources — the factory: the only place a case meets its connection
public enum DataSources {
    public static func make(_ definition: DataSourceDefinition,
                            settings: any ProviderSettingsRepository,
                            vault: any CredentialRepository,
                            cloudWatch: (any CloudWatchClient)? = nil) -> DataSource
}

// Providers — THE lifecycle
@MainActor @Observable
public final class Provider {
    public let definition: ProviderDefinition
    public let dataSources: [DataSource]
    public private(set) var activeKind: String       // persisted
    public var isEnabled: Bool                        // persisted
    public private(set) var isSyncing = false
    public private(set) var snapshot: UsageSnapshot?  // kept on failure
    public private(set) var lastError: Error?
    public func use(_ kind: String) -> Bool
    public func refresh() async throws -> UsageSnapshot   // active, then its fallback
}
```

Inside `DataSource`, `fetchUsage()` switches on the three cases and hands each
to its `internal` worker, built by the factory with **only** the connection
that case needs: `HTTPFetcher` holds a `NetworkClient`, `CLIFetcher` a
`CLIExecutor`, `JSONRPCFetcher` an `RPCTransport` factory, `SettingReader`
the settings, `KeychainReader` the vault. No type receives a bag of
everything.

The Monitor and the views take `Account` (a login) or `Provider` (the
product), never a type that could be either. A usage says which data source
answered (`source: kind` — *via RPC*).

### 4.2 · Flows

**Launch.** `ProviderCatalog` reads the definitions (bundled, then
`~/.claudebar/providers/`, then extensions) → `ProviderFactory.make` builds one
`Provider` each, its data sources made live by `DataSources.make` →
`QuotaMonitor` receives them. A file that fails to decode — an unknown tag
included, since the sums are closed — is logged by file name and left out;
the rest load.

**Refresh.** `QuotaMonitor.refresh(id)` → `provider.refresh(kind)` →
`activeDataSource.fetchUsage()` off the main actor: look up the key
(refreshing it when the lookup says so), fetch, map. On failure the provider
tries the active data source's `fallback` once. Success replaces `snapshot`
and clears `lastError`; failure sets `lastError` and **keeps `snapshot`**. After
a success the Monitor tells its refresh observers (`onRefreshed`) — its one
extension point, so a feature that follows refreshes (In use, §11) never edits
the Monitor.

**A 401.** `HTTPFetcher` reports the status; when the lookup is
`refreshing(_, oauth2)` with `onStatus: [401]`, the data source refreshes once
and fetches once more. An `expiredCodes` match becomes
`sessionExpired(hint:)` with the definition's hint.

**Switching data source.** The card writes `<id>.probeMode`, or calls
`provider.use(kind)`; both land on the same key, read on the next refresh.

**Add Provider** (moments 5–9). *Start from* makes an unsaved
`ProviderDefinition` — `blank(fetch: .http | .cli | .file)` or `copy()` of an
existing one with a new id. *Connect* edits its `fetch` and `credential`;
**Test Connection** builds a throw-away `DataSource` and calls
`fetchResponse()` — no mapping, nothing written — and the sheet shows the
`Response`. *Map fields* edits the `mapping` by pointing at values in that
`Response`, and the preview card is `mapping.read(response)` on every change,
with no second fetch. *Save* validates the definition (§3's laws, plus: at
least one quota or a cost read from the last `Response`), writes
`~/.claudebar/providers/<id>.json`, stores secrets in the vault, and hands the
new `Provider` to the Monitor — no restart.

**Export · Import** (moments 10–11). `definition.exported()` writes the JSON
with every secret setting reduced to its name and lookup order.
`catalog.import(file)` decodes it as a **custom** provider with a fresh id when
the id is taken, shows the URL a key will be sent to and any CLI command it
will run, and lists `missingSettings` (*Key needed*) before *Add*.

## 5 · Settings and secrets

Where each value is kept, by key: [docs/settings.md](../settings.md). The laws —
a secret only in the vault, a refreshed token written back where it was
found — are [CANONICAL §5](CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them)'s.

## 6 · Concurrency, errors, logging

- `Provider` is `@MainActor @Observable`; `DataSource` and its workers are
  `Sendable` and `nonisolated`, so CLI, RPC and HTTP work runs off the main actor.
- One refresh per login is in flight; a second call waits for the first
  one's result ([CANONICAL §5](CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them)).
- `DefinitionError` (bad JSON, unknown tag, missing default, duplicate kind)
  is a load-time error with the file name. It never crashes the app.
- Workers log what they did (`AppLog.probes`), never what they carried: no
  token, header value, `{{secret}}` substitution, or response body at `info`
  or above. A response body is logged at `debug` only by the mapper,
  truncated, and only when mapping fails.

## 7 · Testing

| Subject | Test | How |
|---|---|---|
| each worker | its protocol or format, alone | `@testable`, built with a mocked connection (`NetworkClient`, `CLIExecutor`, `RPCTransport`); Chicago: assert on the payload / snapshot |
| `JSONMapper` · `TextMapper` | every mapping feature | small JSON/text fixtures, one feature per test |
| a mapping script | the old probe's screens and responses, quota for quota | run through its definition in `ProvidersTests` (`ClaudeHarness`), never by calling JavaScript directly |
| `DataSource` | look up → fetch → map, `fetchResponse` stops before mapping, 401-refresh-retry, each error's step | built with mocked connections |
| `Provider` | lifecycle: keeps usage on failure, fallback (and a switched-off one), a rate limit not handed over, one request for overlapping refreshes, `use`, the background floor, held until checked (#216) and again once signed out, no fallback for a signed-out login (`sameLogin`, #525), status across logins | `ProviderTests`: a provider no vendor ships ("Acme") over a fake `NetworkClient` |
| each definition | **golden test**: today's recorded responses (`Tests/…/Fixtures/codex/`) through the definition produce exactly the snapshot today's probe produced | the fixtures are captured from the current probe tests before the probe is deleted |
| the catalog | every bundled definition decodes | one test over `Resources/Providers/*.json` |

The golden tests are how deleting `CodexUsageProbe` stays safe: the JSON must
reproduce its output, quota for quota, before the Swift goes.

## 8 · Open

- **The mapping language's ceiling.** Slices 1, 2 and 5 will find what it must
  express. If a provider needs real computation (Bedrock prices tokens per
  model), that is a fetch case's job — `Fetch.cloudWatch` returns usage
  already priced — not a scripting language inside the mapping.
- **JSONPath dialect.** A small, documented subset (`$.a.b`, `[*]`, `$credential.x`, `$context.file.field`, maps by
  key, `$header.`), implemented and tested here, rather than a dependency.
- ~~**Multi-account in a definition.**~~ — **decided** ([CANONICAL_MODEL §1, §5](CANONICAL_MODEL.md#1--the-tree)):
  a definition declares how an account is added (`accounts.folder` today, an
  account-scope setting in the form later); the provider owns `[Account]`;
  one definition serves every account, the account's values filled when the
  fetch runs. Accounts are simultaneous. **Built** for Codex (#356) and
  Claude (`claude.json`'s `accounts`): `accounts.patch` and `{{account.x}}`,
  one `Provider` owning its `Account`s. The rest is designed in
  [features/multi-account/design.md](../features/multi-account/design.md).
- **A `command` fetch from the UI** — see [CANONICAL_MODEL §9](CANONICAL_MODEL.md#9--open).

## 9 · In use as a capability

*Which login does my next terminal session start with?* is a question the
monitor doesn't answer — every login is still fetched — so it is a
**capability** (CANONICAL §2.1): declared in the definition, run by its own
pieces, reached through a handle that is `nil` when not declared. Design and
laws: [features/in-use/design.md](../features/in-use/design.md).

**Declared as** `accounts.signIn` — the CLI and the variable that points it at
a folder (`claude` + `CLAUDE_CONFIG_DIR`). No new JSON: a provider whose
added logins are folders and whose sign-in names that variable has In use.

| Piece | One job | Changes when |
|---|---|---|
| `InUse` (`Providers`) | which login new sessions start with: `login`, `logins`, `use`, `worthSwitchingTo`, `review()` | the rule for choosing changes |
| `SwitchWhenLow` (`Providers`) | the opt-in policy: is it on, below what, which logins it may pick | the policy changes |
| `LoginsInUse` (port, `Providers`) · `DiskLoginsInUse` | the record: one file per **CLI** (`in-use/claude`), the folder or empty — the shell starts a CLI, not a product | where the shell reads it changes |
| `NewSessions` (`Domain`) | a choice waits for the shell lines; set up, by hand, cancel, turn off; the strip's state; `claudebar://use`; reviews each refresh | how a choice reaches the shell changes |
| `ShellLines` (port, `Domain`) · `ShellSetup` (`Infrastructure`) | the lines per shell, between markers; an alias for the CLI replaced | a shell's syntax changes |
| `InUseAnnouncer` (port, `Domain`) · `InUseNotifications` (`Infrastructure`) | tell the person: worth switching, or switched — one button, a `claudebar://use` link | the wording or the channel changes |
| `QuotaMonitor.onRefreshed` | the Monitor's one extension point | never for In use |

**Flows.** *Choose* — a view tells `newSessions.use(login)`; with the lines in
the shell (or for the plain login) → `inUse.use(login)` → the record; else the
choice waits and the strip shows the setup. *Set up* — `ShellSetup.install`,
then the waiting choice. *After a refresh* — `onRefreshed` →
`newSessions.review(login)` → `inUse.review()` (*Switch when low*, else worth
switching, once per low) → `InUseAnnouncer`. *A link* —
`newSessions.use(providerId:account:)` answers `.used`, `.waitingForSetup` or
`.unknown`; the App only opens the popover for the second.

| A contributor wants… | They change |
|---|---|
| In use for another CLI whose logins are folders | its definition's `accounts.signIn` (`homeVariable`) — nothing else |
| another shell | one case in `LoginShell`, its lines in `ShellSetup`, a test that runs it |
| another policy than *Switch when low* | a policy beside `SwitchWhenLow` that `InUse.review` asks |
| In use for API-key providers | an env-variable record and lines — `InUse` and `NewSessions` unchanged |

## 10 · A definition on disk is a provider

> **Status: BUILT** (2026-10-05). §4.2's *Launch* says the catalog reads the
> definitions; the composition root now does exactly that.

*Adding a provider is writing its definition.* It used to be editing
`ClaudeBarApp.init` too: 27 `Self.builtIn("<id>", …)` calls, a hand-ordered
list, and five things the App knew about particular providers. The rule now
true: **a definition in one of three folders is a provider, and no Swift
names one.**

### 10.1 · What the App still knows, and where each goes

| Was, in `ClaudeBarApp.init` | Is |
|---|---|
| `Self.builtIn("warp", …)`, once per provider | nothing — the file being there is enough |
| its place in `[claude, codex, gemini, …]` | `"order": 70` in its definition; none → after the rest, by name |
| `accounts:` and `secrets: vault` on some calls, not others | the same engine for every provider; a definition uses what its cases ask for |
| Bedrock's `cloudWatch:` and `priceCatalog:` | the engine's cloud ports, made on first use by any `cloudWatch` fetch |
| Z.ai's closure reading one variable from the login shell (#170) | `{ "environment": "{{setting.glmAuthEnvVar}}", "loginShell": true }` |
| DeepSeek's closure renaming its variable | `"settings": [{ "id": "authEnvVar", "default": "DEEPSEEK_API_KEY" }]` and `{{setting.authEnvVar}}` — the card already saves `deepseek.authEnvVar` |
| Claude's `guestPasses:` argument | `"guestPasses": {}` in `claude.json`; the engine runs it |
| the custom and extension loops | the same `detect()` — every origin made on the same engine |

### 10.2 · The pieces

```text
 three folders of definitions, one detector
 ┌───────────────────────────────────────────────┐
 │ app bundle      Resources/Providers/*.json    │  origin: builtIn    (ships with the app)
 │ ~/.claudebar/providers/*.json                 │  origin: custom     (Add Provider)
 │ ~/.claudebar/extensions/*/                    │  origin: extension  (the person's scripts)
 └────────────────────┬──────────────────────────┘
                      ▼
       ProviderCatalog.detect()
         parse each file · log and skip one that doesn't parse
         a built-in id is reserved: another origin's file with it is renamed on import
                      │
                      ▼
       [ProviderDefinition]   sorted by each one's "order", missing ones after, by name
                      │       (the person's saved order still wins, in the lineup)
                      ▼
       ProviderFactory.make(definition, engine)   ── the same Engine for every provider
                      │
                      ▼
       QuotaMonitor(providers)
```

```text
 Engine — everything that touches this Mac, built once by the composition root
 ┌───────────────────────────────────────────────────────────────────────────┐
 │ settings · vault · loginsInUse                                            │
 │ loginShell      the login-shell environment port — only a lookup that     │
 │                 says "loginShell": true waits for it                      │
 │ cloud           CloudWatchClient + PriceCatalog (AWSClients), made the    │
 │                 first time a cloudWatch fetch asks                        │
 │ capabilities    [.guestPasses: source] — run for whichever definition     │
 │                 declares the capability, at that definition's CLI         │
 └───────────────────────────────────────────────────────────────────────────┘
```

```text
 ClaudeBarApp.init — before                      after
 ┌──────────────────────────────────────┐        ┌──────────────────────────────────────┐
 │ let claude = Self.builtIn("claude",  │        │ let engine = Engine(settings: …,     │
 │   guestPasses: …)                    │        │   vault: ProviderVault(),            │
 │ let codex = Self.builtIn("codex", …) │        │   loginShell: ShellEnvironment(),    │
 │ … 25 more …                          │  ───►  │   cloud: .lazy(AWSClients…),         │
 │ let zai = … environment: { closure } │        │   capabilities: [.guestPasses: …])   │
 │ let deepseek = … environment: { … }  │        │ let providers = ProviderCatalog()    │
 │ var providers = [claude, codex, …]   │        │   .detect()                          │
 │ for custom … for extensions …        │        │   .map { ProviderFactory.make($0,    │
 └──────────────────────────────────────┘        │                        engine) }     │
                                                 └──────────────────────────────────────┘
```

| Piece | One job | Changes when |
|---|---|---|
| `ProviderCatalog.detect()` (`Providers`) | every definition in the three folders, parsed, deduplicated and ordered | a folder is added, or the ordering rule changes |
| `ProviderDefinition.order` | where the product sits by default | that product's place changes |
| `Engine` (`Providers`) | the ports every provider shares, built once | a port is added |
| `ProviderFactory.make(_:engine)` | definition + engine → `Provider` | a port is wired differently |
| `ClaudeBarApp.init` (`App`) | builds the `Engine` from Infrastructure and AWSClients | a port's implementation changes — never for a provider |

### 10.3 · What adding a provider is

```text
 before                                   after
 1  write <id>.json (+ <id>-*.js)         1  write <id>.json (+ <id>-*.js), "order" if it matters
 2  golden tests                          2  golden tests
 3  Self.builtIn("<id>", …) in the App
 4  add it to the providers list
 5  any closure its key needs
```

### 10.4 · Laws

| Law | Owner |
|---|---|
| a definition in one of the three folders is a provider; Swift lists none | `ProviderCatalog.detect` |
| the default order is each definition's `order`; missing ones follow, by name; the person's own order wins | `ProviderCatalog` · the `providerOrder` setting |
| a built-in id is reserved: a file from another origin with it is renamed on import, and the bundle's always loads | `ProviderCatalog` |
| every provider gets the same engine; a definition uses only what its cases ask for | `Engine` → `ProviderFactory.make` |
| the cloud ports are made once, on first use | `Engine.cloud` |
| an environment lookup asks the login shell only when it says `loginShell: true` | `EnvironmentReader` + the login-shell port |
| a capability is declared by the definition and run by the engine — never chosen by a provider's name, even when only one product has it | the definition · `Engine.capabilities` |

The last law changed one row of [CANONICAL_MODEL §2.1](CANONICAL_MODEL.md):
guest passes are declared in `claude.json`, their one runner
(`ClaudeGuestPassSource`) supplied by the engine.

### 10.5 · Built in this order, test first, the person seeing no change

1. `ProviderCatalog.detect()` and `order` — the detected built-ins come out
   in exactly today's order; one without `order` comes last, by name.
2. `loginShell` → Z.ai; `authEnvVar` → DeepSeek; `guestPasses` → Claude —
   their existing tests keep passing.
3. `Engine`, with the cloud ports made on first use — Bedrock's tests keep
   passing.
4. `ClaudeBarApp.init` builds the `Engine` and calls `detect()`; the custom
   and extension loops fold into it.
5. The `add-provider` skill loses *Register in ClaudeBarApp*; AGENTS.md and
   §2's chart follow.

**Left for later:** watching the folders so a dropped file appears without a
restart (today, and after this, detection happens at launch), and retiring
`DeepSeekConfigCard` once the definition's settings form replaces it — it
writes the same `deepseek.authEnvVar` key, so it keeps working meanwhile.
