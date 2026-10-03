---
description: The architecture that implements the canonical model — a provider as a JSON definition, one DataSource type that fetches for every provider through single-job internal workers, no vendor-named code, the runtime from definition to popover, settings keys, testing, and the migration slices starting with Codex; read before moving a provider to JSON or adding a fetch, mapping or credential case.
---

# ClaudeBar — the target architecture

> [CANONICAL_MODEL.md](CANONICAL_MODEL.md) says WHAT the domain is.
> [MODULAR_DESIGN.md](MODULAR_DESIGN.md) says which module each file lives in.
> [USER_JOURNEYS.md](USER_JOURNEYS.md) walks the screens first; the flows in §4.2
> are its moments, seen from inside.
> **This document says how a provider runs**: from a JSON file, through one
> `DataSource`, to the popover — and in what order today's code gets there.
>
> **Status: BUILT** for every built-in provider (slices 1–6 below, merged
> through #419); slice 7 (Claude's renames, `AIProvider` folding into
> `Provider`) is what remains. Today's wiring is [ARCHITECTURE.md](ARCHITECTURE.md).

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
│ Providers.make(_:)   definition → Provider, each data source made live   │
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

## 3 · Codex, as data

`Resources/Providers/codex.json` — the whole of Codex. The fields below are the
ones today's two probes hard-code; slice 1 pins every one of them with a test
against the current probes' fixtures before those probes are deleted.

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
public final class Provider: AIProvider {
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

`AIProvider` stays the protocol the Monitor and views consume while the other
providers move; `Provider` conforms. When the last `XxxProvider` is gone it
folds into `Provider`. `UsageSnapshot` keeps its name until the renames of
slice 7 (`Usage`), and gains `source: kind` — *via RPC* — in slice 1.

### 4.2 · Flows

**Launch.** `ProviderCatalog` reads the definitions (bundled, then
`~/.claudebar/providers/`, then extensions) → `Providers.make` builds one
`Provider` each, its data sources made live by `DataSources.make` →
`QuotaMonitor` receives them. A file that fails to decode — an unknown tag
included, since the sums are closed — is logged by file name and left out;
the rest load.

**Refresh.** `QuotaMonitor.refresh(id)` → `provider.refresh(kind)` →
`activeDataSource.fetchUsage()` off the main actor: look up the key
(refreshing it when the lookup says so), fetch, map. On failure the provider
tries the active data source's `fallback` once. Success replaces `snapshot`
and clears `lastError`; failure sets `lastError` and **keeps `snapshot`**.

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

| Key | Means | Status |
|---|---|---|
| `providers.<id>.isEnabled` | the Providers pane toggle | unchanged |
| `<id>.probeMode` | the active data source's `kind` | unchanged — a match name, so no user's setting moves |
| `providers.<id>.settings.<field>` | a non-secret form value | new |
| vault `claudebar.<id>.<field>` | a secret form value | new; Keychain with the file fallback Notify! uses for ad-hoc builds |

A credential lookup never writes settings, with one exception the definition
asks for by name: `OAuth2Refresher` writes the refreshed token **back to where
the credential came from** (for Codex, `~/.codex/auth.json`, preserving every
other field), because the CLI that owns that file must keep working.

## 6 · Concurrency, errors, logging

- `Provider` is `@MainActor @Observable`; `DataSource` and its workers are
  `Sendable` and `nonisolated`, so CLI, RPC and HTTP work runs off the main actor.
- At most one refresh per provider is in flight; a second call waits for the
  first one's result.
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
| `Provider` | lifecycle: keeps usage on failure, fallback (and a switched-off one), a rate limit not handed over, one request for overlapping refreshes, `use`, the background floor, held until checked (#216), status across logins | `ProviderTests`: a provider no vendor ships ("Acme") over a fake `NetworkClient` |
| each definition | **golden test**: today's recorded responses (`Tests/…/Fixtures/codex/`) through the definition produce exactly the snapshot today's probe produced | the fixtures are captured from the current probe tests before the probe is deleted |
| the catalog | every bundled definition decodes | one test over `Resources/Providers/*.json` |

The golden tests are how deleting `CodexUsageProbe` stays safe: the JSON must
reproduce its output, quota for quota, before the Swift goes.

## 8 · Migration slices

Each slice is one PR, green, with no change a user can see unless it says so.

| # | Slice | Done when |
|---|---|---|
| 1 ✅ | **Codex** — the definition types, `CredentialLookup` · `Fetch` · `Mapping`, `DataSource`, `Provider`; workers `JSONFileReader`, `OAuth2Refresher`, `HTTPFetcher`, `JSONRPCFetcher`, `CLIFetcher` (terminal), `JSONMapper`, `TextMapper`; `codex.json`; golden tests | `CodexProvider`, `CodexUsageProbe`, `CodexAPIUsageProbe`, `DefaultCodexRPCClient`, `CodexCredentialLoader` are deleted; both modes and the fallback work; `codex.probeMode` is read as before |
| 1a ✅ | **Accounts under one Provider** — `Provider` owns `[Account]`; `{{account.x}}` filled at fetch time; `codex.json`'s `accounts.dataSources` deleted; `AddedAccounts` → `provider.add(account:)` | same ids, pills, pins and settings keys; no visible change |
| 2a ✅ | **DeepSeek** — `deepseek.json`, balance script, `accounts.form`, scoped keys and verified legacy-key migration | its probe and provider class are deleted; golden tests cover currency, paid/granted details and independent keys |
| 2 ✅ | the remaining HTTP + API-key providers on the engine of [§8.2](#82--the-engine-the-remaining-migrations-share): MiniMax #401, Vercel #403, Command Code #404, Cursor #407, Grok #408, OpenCode Go #409, Z.ai #410, Copilot #412, #415 | their probes and provider classes are deleted |
| 3 ✅ | the look (#353), the Data source section (#352) and the settings form (#399) move into the JSON; the `switch id` tables and the config cards go — only Claude's budget card and DeepSeek's card remain | adding a provider edits no Swift |
| 4 ✅ | the kernel laws: `Left` (no fake 100%), `Window` (no guessed length) | balance definitions map money only |
| 5 ✅ | the CLI, cookie and local providers on the engine of [§8.2](#82--the-engine-the-remaining-migrations-share): Amp #405, Kiro #406, Kimi #411, Alibaba #413, Gemini #414, Antigravity #416, Oh My Pi #418, Mistral #419; Bedrock via `Fetch.cloudWatch` and the `AWSClients` module #417; *PROBE MODE* → *Data fetching method* | no `XxxUsageProbe` is left |
| 6 ✅ | *Add Provider* (#354), *Export*, *Import* (#355) — the screens of [USER_JOURNEYS.md](USER_JOURNEYS.md) moments 5–11, outer loop from its §5 scenarios | a person adds, shares and imports a provider without a restart, and no exported file contains a key |
| 7 | Claude (PTY CLI, multi-account, guest passes, budget); the renames (`Usage`, `Plan`, `Cost`, `DataSourceError`) | `AIProvider` folds into `Provider` |

## 8.1 · What each provider added

Claude needed more than Codex, and every provider after it brought its own
needs; each became a generic piece, never a vendor type:

| Need | Generic piece |
|---|---|
| a TUI screen and human reset dates no rule can say | `Mapping.script` — a JavaScript file in JavaScriptCore, no I/O, host `humanDate()`; the scripts ship beside the definition. `values` hands it settings (`{{setting.x}}`); a blank one isn't there, and the script never writes one back |
| Claude Code's Keychain item | `CredentialLookup.keychain(service, fields)` via `security`, hex-decoded, written back as compact JSON |
| expiry in milliseconds, a JSON refresh body with `scope` | `OAuth2Refresh.dueWhen`, `bodyFormat`, `scope`; values keep their JSON type on write-back; a failed refresh re-reads the store |
| another CLI's Keychain login (`gh`, go-keyring) | `keychain.account`, `keychain.encoding: goKeyringBase64`; an encoded item is never written back |
| one report covering many accounts (Oh My Pi) | a script quota's `group`, and `notes` — a row under a group with nothing to measure |
| a cloud's metrics priced into money (Bedrock) | `cloudWatch` with `prices`: `CloudWatchClient` and `PriceCatalog` ports, implemented in `AWSClients`; a script prices them exactly (`decimalMultiply`) into one `Cost` with lines |
| an app's own server on this Mac (Antigravity) | `localServer`: the process by name and command line, values from its arguments, its listening ports, declared loopback paths; readiness without starting a process |
| a login file a CLI renews itself (Gemini) | `refresh: {"cli": …}` beside `oauth2`: on a 401 the CLI runs and the file is read again; the refresher says it doesn't write back |
| a console session: one cookie read out of the Cookie header (`sec_token`, a CSRF cookie), a header left out when its value is missing | `"cookies"` on a credential lookup; `dropEmpty` covers headers |
| `env`, ready markers and a rendered screen for the CLI; a TUI that discards input typed during its startup paint | `CLICall.environment`, `readyWhen`, `screen`, `inputDelay` |
| `/cost` only for API-billed accounts; API→CLI only while a setting allows | `fallbackOn` (hand-off by failure) and `fallback.enabledBySetting`; the provider follows the chain and reports the first real failure |
| 15-minute cache, a remembered 429 | `cache.ttl` (also the background floor) and rate-limit memory on `DataSource` |
| the account's email and billing type | `context` files handed to the mapping |
| the folder-trust prompt | `recover.patchJSONFile`, tried once |
| Codex logins in their own folders (#326) | `accounts` (`folder`), `{{account.x}}`, `identity` (fail closed when a folder signs in to someone else), `requiresFiles` (#216), `verifyBeforeBackground`, JSON-RPC `then` + `environment`, `#jwt.claim` and `$credential.` paths |
| the usage API's model limits, plan and money | JSON mapping rules, not a script: `each` + `where`, names by `firstWord`/`lowercase`, `unique` (first wins), `overLimit` (negative left), `countdown: "hours"`, `plan.plans` from `$credential.`, and a list of `cost` shapes with `when` and exact `{amount, decimals}` minor units |
| today's usage and guest passes | `UsageHistory` beside the providers (read with the popover open, never in the background; keyed by the login whose logs it reads) and the `GuestPasses` capability |
| Claude logins in their own config folders | `accounts.folder` with `email` and `accountId.field` as an `IdentityField` (`$context.account.email`), `derived` values (the Keychain service, from a sha256 of the folder), `identity` read from a context file; today's usage and guest passes stay with the default login |

## 8.2 · The engine the remaining migrations share

Seventeen migration PRs (#381–#398) were built against slices 2 and 5, and
every one of them edited the same Swift:
- `ClaudeBarApp.swift`, `ProvidersPane.swift` and `Provider.swift` in all 17
- `Fetch.swift` and `Fetchers.swift` in 16
- `ProviderVisualIdentity.swift` in 14

So §1's OCP promise did not hold. SRP broke in the same places:
- `HTTPRequest` grew from 5 fields to 13.
- The account form gained eight flags.
- `Provider` started checking files.

Every vendor quirk became a field, because nobody asked what the *person*
sees. This section starts there. Every piece below is something on screen, and
owns one rule.

**Tell, don't ask.** A caller never reads a piece's state to decide what that
piece could decide. The `Setting` says what a blank means, whether two values
are the same folder and where its value is kept. A worker's failure says which
fact it is. A fetch case says where it sends a key. A data source says which
one takes over when it has no key. Views may look at a kind only to draw it.

### 8.2.1 · What the person sees, and the one piece behind each

| On screen | The person thinks | The piece | Its rule |
|---|---|---|---|
| **API KEY · REGION · CLI DATA FOLDER** in a provider's settings and in *Add Account* | "it needs these from me" | a **`Setting`** of a **kind** (`secret · choice · path · text`) and a **scope** (`provider` · `account`): the `SettingsForm` of CANONICAL §1 | the kind checks the value |
| **REGION: China · International** | "I'm in China, so it talks to China's site" | each option of a choice setting **carries its values**: `China → site: kimi.com`. A definition says `{{setting.region.site}}` | an account's own region wins over the provider's |
| **DATA SOURCE: API · CLI** | "where it reads my usage" | `DataSource`, one active per provider | unchanged |
| **KEY LOOKUP ORDER · COOKIE SOURCE** | "where it finds my key" | `CredentialLookup`, adding **`browserCookies`** | the first that answers wins |
| *Start from: **API** · **CLI** · File* | "call a URL" · "run a command" | `Fetch.http` (with **steps**) · `Fetch.command` (a command over pipes). A TUI that only draws in a terminal stays `Fetch.cli` | one worker each |
| ***Test Connection*** → ***Response*** | "show me what came back" | the response of the last step that ran | stops before mapping |
| *Couldn't read your key · Couldn't connect · Couldn't find the numbers* + what to do | "which step broke, and where do I go" | `DataSourceError(step, reason)`, the reason worded by the definition's **`errors`** | no response body, no secret |
| *Import:* ***sends your key to …*** · ***runs …*** | "where does my key go, what will it run" | each fetch case's **`Connection`** answers for itself | every host a setting can pick is listed |
| ***Configured*** | "it will work" | `isReady` of the data source a refresh would end on | follows the no-key hand-off |
| *Add Account* → saved | "my key is kept" | the vault, read back before the account is kept | nothing half-saved |

### 8.2.2 · Settings: one form, two scopes

```json
"settings": [
  { "id": "apiKey", "label": "API key", "kind": "secret", "scope": "account" },
  { "id": "region", "label": "Region", "scope": "account", "default": "china",
    "kind": { "choice": [
      { "id": "china",         "label": "China",         "site": "kimi.com" },
      { "id": "international", "label": "International", "site": "kimi.ai" } ] } },
  { "id": "home", "label": "CLI data folder", "scope": "account", "default": "~/.kimi",
    "kind": { "path": { "mustExist": true } } }
],
"fetch": { "http": { "url": "https://www.{{setting.region.site}}/apiv2/…/GetUsages",
                     "headers": { "Origin": "https://www.{{setting.region.site}}" } } }
```

**Why one form instead of `choices` plus form flags.** The person sees one
*REGION* control, not a setting and a separate choice. A choice that carries
its values replaces the four `…BySetting` fields and the
`"value": "{{account.x}}"` patches. `{{setting.<id>}}` and
`{{setting.<id>.<value>}}` fill any string of a definition — a URL, a header,
a cookie domain, the dashboard link. `Provider` fills them for each login when
it makes that login's data sources, as it fills `{{account.x}}`;
`provider.set(_:to:)` saves a value and makes every login's data sources again,
so a changed *Region* needs no restart. A secret fills nothing: a key reaches
a fetch only through its credential lookup.

**Scope is the person's model of logins.**
- **Provider scope.** The value is the same for every login, like *ENV VAR
  NAME*. It is kept under `<id>.<setting>` — today's `minimax.region` and
  `kimi.region` — so no setting moves.
- **Account scope.** Each login has its own value; *Add Account* asks for
  exactly these. The default login's value is the provider-scope one, which is
  why it lives under the same key.
- **A setting only some data sources use says so** (`"for": ["api"]`): Kimi's
  session token is the API's, its signed-in folder the CLI's. *Add Account*
  asks only for what the active data source uses (`provider.accountForm`),
  and a login added without such a value runs only the sources that don't
  need it.

**The rules sit with whoever holds the data.**
- **Each kind owns its rule.** `setting.check(value, paths:)` returns the
  sentence the sheet prints; `setting.value(from:)` says what a blank means
  (the default, or a choice's first option); `setting.keep(_:in:)` puts a
  secret with the vault's keys and anything else with the saved values.
  - A secret has no default.
  - A choice takes only its options.
  - A path can be required to exist; `paths` is a `@Mockable` port.
- **"Two logins never share a path" belongs to `Provider`.** Only `Provider`
  knows every login's values, the default one included; it asks the setting
  whether two values are the same place (`isSamePlace`). No `notIn` list is
  written in the JSON.

**Old files still decode.** Today's `accounts.form` (`"secret": true`,
`"choices": […]`) reads as account-scope settings.

**This is slice 3's form.** Settings draws it (`ProviderSettingsSection`) for
every definition-driven provider that has no card of its own yet; the Region
and API-key cards of the providers that migrate go, and no new Swift card
comes.

### 8.2.3 · HTTP in steps, instead of a planner script

The PRs needed four shapes, and all of them are *call A, then B with something
A said*:
- Command Code: `httpSequence`
- Gemini: project, then quota
- Alibaba: dashboard token, then console
- Antigravity: `workflow`

JSON-RPC already says this with `then`. HTTP says it the same way:

```json
"http": { "steps": [
  { "name": "project", "request": { … }, "optional": true, "attempts": 2,
    "keep": { "project": "$.cloudaicompanionProject" } },
  { "name": "quota", "request": { "body": "{\"project\": \"{{project}}\"}" },
    "dropEmpty": ["project"] } ] }
```

- **What a step can do.** `keep` names values from a step's response, by JSON
  path — or a list of paths, the first that answers — or by a `pattern` over
  text. `optional` lets a step fail without ending the fetch, though a
  refused key or a rate limit still ends it. `unless` skips a step when a
  value is already known, such as a `sec_token` already in the cookie.
- **Every step answers.** The response is each step's answer by name —
  `{ "whoami": {…}, "credits": {…} }`, text where it wasn't JSON — so the
  mapping reads what any step said and *Test Connection* shows them all.
- **A kept value never replaces a credential value.** A step's answer cannot
  swap the key a later step sends. A value filled into a URL is
  percent-encoded, so it can never add a query item.
- **`attempts`** (1 to 3) tries a step again after a network failure or a 5xx.
  **`dropEmpty`** leaves out a JSON body key or URL query item whose value is
  missing — `?orgId={{orgId}}` goes without `orgId` when no step found one.
- **Import lists every host.**

This replaces the JS planner (`httpFlow`), as well as `commandPlan` and
`workflow`. **It reverses the earlier decision to keep `httpFlow`.** A
planner script is the escape hatch §3 warns about: the person cannot read what
it will do, and Import cannot show it. If a provider proves a flow these rules
cannot say, that provider brings the rule in its own PR.

### 8.2.4 · A command, and a terminal

Two protocols, two cases — never one type with a mode flag, where half the
fields would mean nothing in each mode.

| Tag | Meaning | Worker |
|---|---|---|
| `command` | run a command over pipes; read its output; its exit code is a fact | `CommandFetcher` (`PipeCLIExecutor`) |
| `cli` | drive a TUI that only draws in a terminal — Claude's `/usage`, Codex's `/status` — and capture its screen | `CLIFetcher` (the PTY executor), unchanged |

- **Nothing that exists moves.** `cli` keeps its meaning, so `claude.json`,
  `codex.json` and the files people made keep working as they are.
- ***Add Provider*'s *CLI* makes a `command`.** A command a person types is
  plain output; a TUI needs a definition written for it.
- **`{{token}}` reaches a command through its environment**, never its
  arguments, the same way it reaches a header.

### 8.2.5 · A worker reports a fact; the definition words it

A worker's failure is a fact that answers for itself (`ReportedFailure`): its
key in `errors`, and the reason it gives when the definition says nothing.

| Fact | Key | Without a rule |
|---|---|---|
| an HTTP status that is not an answer | `http.<status>`, else `http.default` | today's wording (`HTTP error: 500`, *Key needed* on 401/403) |
| a command's CLI is not on this Mac | `cli.missing` | *CLI not found* |
| a command exited non-zero | `cli.nonzero` | "`acme` exited with code 2" |
| a command could not start | `cli.failed` | "`acme` could not be started" |

```json
"errors": { "http.404": "subscriptionRequired",
            "http.403": { "sessionExpired": "Sign in to the console again." },
            "cli.missing": { "cliNotFound": "kiro-cli" } }
```

- **A rule says what a fact means**, in the reasons the screen prints. Nothing
  from the response fills it: no `{{status}}`, no `{{body}}`, and no flag kept
  only to reproduce an old probe's sentence; a golden test updates its
  expected text instead.
- **Fixed rules.** A 429 is always a rate limit with its `Retry-After`, and
  `http.429` is refused. A 401 or 403 still gets the one refresh-and-retry
  first.
- **What stays on the request.** `acceptedStatuses` stays on the request,
  because which statuses are an answer is part of the protocol.

### 8.2.6 · A case answers for itself

```swift
public protocol Connection: Sendable {
    var urls: [String] { get }        // as written; Import spells out each setting's options
    var commands: [[String]] { get }  // "runs"
}
extension Fetch {
    public var connection: any Connection                            // the one switch, beside the cases
    public func runningCLI(_ cli: String, at binary: String) -> Fetch   // CLI LOCATION
}
```

- **Nothing else switches over the cases but the factory.**
  `ProviderSharing` (*Import*'s "sends your key to" and "runs") and
  `ProviderDefinition.runningCLI` read the case's own answer; the Add Provider
  sheet asks the definition (`neededSettings`), not the lookup's cases.
- **Adding a case is:**
  - the enum line
  - its payload with its `Connection`
  - its worker
  - one factory line

### 8.2.7 · Kept as they were, and left out

**Kept as built in the PRs:**
- `browserCookies` + `BrowserCookieReader` (SweetCookieKit, behind a
  `@Mockable` port); its domains may name a setting
- `DecimalScript` — `jsonDecimal` and `decimalCents` in every mapping script,
  for exact money
- the *Configured* hand-off: a source with no key is configured when the one
  it hands a missing key to is (`dataSource.handOffWithoutKey`)
- the vault read-back before an added login is kept
- the Data source and Accounts sections for every JSON provider

**Folded into what exists:** `availability: files` becomes `requiresFiles`,
which now also makes a source not *Configured* while its files are missing.

**Left out, by decision:**
- **A data source per account.** One active per provider is the law; Alibaba
  and Kimi pick by data source, not by account.
- **One-provider escape hatches:** `script` credentials, a mapping that writes
  settings, page fields in script output, `bedrockUsage`.

## 9 · Open

- **The mapping language's ceiling.** Slices 1, 2 and 5 will find what it must
  express. If a provider needs real computation (Bedrock prices tokens per
  model), that is a fetch case's job — `Fetch.cloudWatch` returns usage
  already priced — not a scripting language inside the mapping.
- **JSONPath dialect.** A small, documented subset (`$.a.b`, `[*]`, maps by
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

## 10 · Usage History as data

> **Status: PROPOSED.** The model, laws and words are in
> [CANONICAL_MODEL](CANONICAL_MODEL.md) §1, §5, §8. This section says how it
> runs and the order of the work.

### 10.1 · What a person asks, and what is true

A person asks **"how much did I use, day by day?"** *TODAY'S USAGE* (today
against yesterday) and a *Daily token usage — last 30 days* chart (input,
output, cache read and cache write per day, two axes) are **two views of that
one answer**: the last two days, and the last thirty. So the model is a
**series of days**, and a view is a range the page asks for:

```swift
account.usageHistory?.days(in: .last(2))    // TODAY'S USAGE
account.usageHistory?.days(in: .last(30))   // the chart; every date present, empty days included
```

A `Day` holds what every view needs: tokens by kind, a `Cost` with a line per
model (so a chart can stack by model too), sessions, working time and cache
savings. Nothing about "today and yesterday" is a type.

Today two vendor-named analyzers answer only the last two days, and each one
hard-codes the same five jobs:

| Job | Claude (`ClaudeDailyUsageAnalyzer` + 5 helpers) | Mistral (`VibeSessionLogAnalyzer`) | What it really is |
|---|---|---|---|
| where the records are | `~/.claude/projects/**/*.jsonl`, changed since yesterday | `~/.vibe/logs/session/session_*/meta.json` | a glob |
| how to read one | an assistant line: `message.model`, `message.usage.*`, `timestamp` | `stats.session_total_llm_tokens`, `stats.session_cost`; the time from the folder name, in UTC | a format and field paths |
| which copy counts | `message.id` + `requestId`, the last wins | each file once | an identity |
| what it cost | `ModelPricing` — a Swift table; a local model, or a base URL on this Mac, is free | the log says | a price catalog, or the record's own cost |
| the day | local midnight; a 30-minute pause starts a session | local midnight; a file is a session | one aggregator |

None of these is a vendor's behaviour; each is a value. So, as for usage
(§2), **a tool's usage history is a definition and one engine runs it**: a new
tool's logs, a new model's price or a new view never edit a vendor's Swift
(OCP).

### 10.2 · The definition: `usageHistory` beside `dataSources`

Record fields use **the mapping's path language** (§3: `$.a.b`, a list is the
first that answers, `where`), so there is one way to point into JSON.

```jsonc
// claude.json
"usageHistory": {
  "records": {
    "files": "${CLAUDE_CONFIG_DIR:-~/.claude}/projects/**/*.jsonl",
    "format": "jsonLines",                       // jsonLines (append-only, read incrementally) · json (one record per file)
    "where": { "path": "$.type", "equals": "assistant" },
    "at": "$.timestamp",                          // ISO 8601
    "id": ["$.message.id", "$.requestId"],        // together its identity: written twice, it counts once — the last wins
    "model": "$.message.model",
    "tokens": {
      "input": "$.message.usage.input_tokens",
      "output": "$.message.usage.output_tokens",
      "cacheWrite": "$.message.usage.cache_creation_input_tokens",
      "cacheRead": "$.message.usage.cache_read_input_tokens"
    }
  },
  "prices": { "file": "claude-prices.json" },    // a PriceList — or { "service": "AmazonBedrock" }, through PriceCatalog
  "freeWhen": { "localEndpoint": { "file": "${CLAUDE_CONFIG_DIR:-~}/.claude.json",
                                   // the first entry that answers decides; a list is one entry
                                   "url": ["$.env.ANTHROPIC_BASE_URL",
                                           ["$.providers[*].base_url", "$.providers[*].env.ANTHROPIC_BASE_URL"]] } },
  "sessionGap": 1800
},
"accounts": { "patch": { "usageHistory": { "records": { "files": "{{account.configDirectory}}/projects/**/*.jsonl" } } } }
```

```jsonc
// mistral.json
"usageHistory": {
  "records": {
    "files": "~/.vibe/logs/session/session_*/meta.json",
    "format": "json",
    "at": { "fromPath": "session_(\\d{8}_\\d{6})", "format": "yyyyMMdd_HHmmss", "timeZone": "UTC" },
    "tokens": { "total": "$.stats.session_total_llm_tokens" },
    "cost": "$.stats.session_cost"               // the log's own cost wins over any price
  }
}
```

```jsonc
// claude-prices.json — beside the definition; a price change edits this, never Swift
{
  "currency": "USD", "per": 1000000,
  "models": [                                     // exact id first, then the longest prefix
    { "id": "claude-opus-5",   "name": "Claude Opus 5",   "input": "5", "output": "25", "cacheWrite": "6.25", "cacheRead": "0.50" },
    { "id": "claude-sonnet-5", "name": "Claude Sonnet 5", "input": "2", "output": "10", "cacheWrite": "2.50", "cacheRead": "0.20" }
  ],
  "families": [ { "contains": "opus", "as": "claude-opus-4-6" }, { "contains": "haiku", "as": "claude-haiku-4-5-20251001" } ],
  "free": [ "qwen", "llama", "gemma", "mistral", "gpt-oss", "ollama" ],   // a model of a local family costs nothing
  "otherwise": { "input": "3", "output": "15", "cacheWrite": "3.75", "cacheRead": "0.30" }
}
```

- **One price shape, two origins.** A price file is data, decoded into a
  `PriceList` that holds the rules: exact id → the longest prefix (either
  way round) → a family → a free family → `freeWhen` → `otherwise`. A cloud's
  price list (`{ "service": … }`) is fetched through the `PriceCatalog` port
  Bedrock uses (#417) into the same `PriceList`. A tool that writes its own
  cost needs neither.
- **Per login, like data sources.** The default login reads `usageHistory`; an
  added login gets `accounts.patch.usageHistory` merged in and its values filled
  (`{{account.configDirectory}}`), so an added Claude login has its own
  usage history for the first time. A definition without `usageHistory` has none.
- **Money stays exact.** Prices are decimal texts; cost is
  tokens × price ÷ `per` in `Decimal`, shown as an estimate unless the record
  gave its own `cost`.
- **`freeWhen.localEndpoint`** replaces `ClaudeLocalInferenceDetector`: a
  base URL in that file on a loopback host (`localhost`, `127.0.0.1`, `::1`,
  `0.0.0.0`, `*.localhost`) makes an unpriced model free. It describes the
  route **now**, so it prices only the day that holds now; an earlier day
  keeps its estimate — over-reporting is the safe direction.

#### When logs differ: one record, three tiers

Tools write their logs differently. The difference stays at the edge: every
reader turns its file into the same **`LogRecord`** — `at`, `id`, `model`,
`tokens` (input · output · cache write · cache read, or a `total`), `cost` —
and everything after it (dedupe, days, sessions, prices, the ledger, the
screens) never learns which tool wrote it.

| How a tool's logs differ | What a contributor changes | Swift? |
|---|---|---|
| where the files are, what a field is called (Claude's `message.usage.input_tokens`, Vibe's `stats.session_total_llm_tokens`) | `files` and the field paths | no |
| the same idea, said another way: the time in a folder's name, the log's own cost, a session per file, a running total | an option: `at.fromPath`, `cost`, no `sessionGap`, `"cumulative": true` | no |
| a record no path can say (a field to compute, a list to add up) | `"script": "x-log.js"` — `read(record, context)` returns one `LogRecord`, the escape hatch a mapping already has (built when a tool first needs it) | no |
| a file of another kind (SQLite, binary) | a new `format` case and its reader, named for the format, with a test that names no tool | once |

**A script, by example.** Say a tool logs one line per turn, in an
OpenAI-style shape no path can turn into a record: the time in epoch
milliseconds, cached tokens *included* in the input count, and one usage
entry per model in a list.

```jsonc
// a line of ~/.example/history/2026-10-03.jsonl
{"kind":"turn","ts":1759500000123,"turn":"t_81","usage":[
  {"model":"gpt-5","prompt_tokens":12000,"cached_tokens":9000,"completion_tokens":800},
  {"model":"gpt-5-mini","prompt_tokens":3000,"cached_tokens":0,"completion_tokens":200}]}
```

The definition keeps what paths can say — the files, the format, the
filter — and hands each record to a script instead of naming its fields:

```jsonc
// example.json
"usageHistory": {
  "records": {
    "files": "~/.example/history/*.jsonl",
    "format": "jsonLines",
    "where": { "path": "$.kind", "equals": "turn" },   // still the byte prefilter: the script sees only these
    "script": "example-log.js"                         // in place of at · id · model · tokens · cost
  },
  "prices": { "file": "example-prices.json" },
  "sessionGap": 1800
}
```

```js
// example-log.js — read(record, context) → a LogRecord, a list of them, or null to skip
function read(record, context) {
  if (!Array.isArray(record.usage)) return null;
  return record.usage.map(function (u, i) {
    return {
      at: record.ts / 1000,                          // epoch seconds
      id: record.turn + "#" + i,                     // one record per model in the turn
      model: u.model,
      tokens: {
        input: u.prompt_tokens - u.cached_tokens,    // the log counts cached tokens as input
        cacheRead: u.cached_tokens,
        output: u.completion_tokens
      }
      // cost: "0.0123" — when the log states it; a decimal text stays exact
    };
  });
}
```

That line becomes two records — `gpt-5` with 3,000 input, 9,000 cache read
and 800 output tokens, `gpt-5-mini` with 3,000 and 200 — priced, deduped and
summed into days exactly like Claude's. The rules are a mapping script's
(§2): it runs in JavaScriptCore with no file, network or process access;
`context` holds `now`, `timeZone`, the file's `path` and the definition's
`values`; money helpers (`jsonDecimal`, `decimalAdd`) keep a stated cost
exact; and it turns one record into records, nothing else. A script is
slower than paths, so `where` filters first, and a tool whose fields paths
*can* reach never needs one.

**Neither Claude nor Mistral uses a script**, and the script tier is not
built with them. Claude's logs are paths plus options (`where`, a composite
`id`, `sessionGap`, `freeWhen`), and they run to gigabytes: a JavaScriptCore
call per line would undo the incremental reader and the byte prefilter.
Mistral's one tool-shaped fact — the time in the folder's name — is a
common one (logs rotated by date), so it is an option, `at.fromPath`, that
any tool can use. The rule for choosing: **an idea several tools share is
an option; an idea only one tool has is a script.**

`format` is a closed sum like `Fetch`: the engine stays closed, a new tool is
data. The reading rules every format shares:

- **`files`** is a glob: `**` any depth, `*` within one name; hidden files
  are skipped, and only files changed since the range's first day are read.
- **`where`** keeps the records that match; its text values are also a byte
  prefilter, so a line without them is never decoded.
- A record without `at`, or without a declared `model`, is skipped; so is
  one where no token field and no `cost` answers — it says nothing about
  usage (Claude's assistant line without `usage`, a Vibe `meta.json`
  without `stats`). Otherwise a missing token field counts 0.
- **`id`**'s paths together are a record's identity; a record missing any of
  them is never merged with another.

### 10.3 · Thirty days without re-reading thirty days: the ledger

Claude's logs run to gigabytes; re-reading thirty days on every popover open
is not an option, and today's in-memory cache only covers two. The day is the
natural unit to keep:

- **A day closes** a fixed while after its midnight (late lines from a
  session that ran past midnight still land). A closed day is summed once
  and kept in a **`DayLedger`** — per login, one small JSON file under
  `~/.claudebar/usage-history/`, a few hundred bytes a day.
- **Open days** (today, and yesterday until it closes) are read from the logs
  every time — incrementally, as today, so a popover open reads only what
  was appended.
- **Dedupe stays exact**: a record's identity only has to be remembered
  while its day is open.
- **A ledger is a cache, not a record**: deleting it re-reads the logs; a
  change to the definition (`usageHistory` or the prices) invalidates it.

### 10.4 · Where it lives: the login owns it, `DataSources` extracts it

**No new module.** A module earns its place with its own SDK, a second
consumer, or a boundary the build must enforce; usage history has none —
`Providers` is its only consumer, and the work it needs (find files, read
JSON with the path language, expand `~`, price tokens) is what `DataSources`
already does behind `internal`. So it splits along the line every provider
already has:

- **The login owns it.** `Account` holds `usageHistory: UsageHistory?` —
  `nil` when the definition has no `usageHistory` — and `UsageHistory`
  (in `Providers`) answers `days(in:)` from its `DayLedger` of closed days,
  asking its log for the open ones. A page reads
  `account.usageHistory?.days(in:)` (CANONICAL §2.1), never a dictionary
  keyed by provider ids, and there is no app-wide registry.
- **`DataSources` extracts it** — the only part that differs per provider.
  The definition's `usageHistory` decodes as a `UsageLog.Definition` (as
  `dataSources` decode as `DataSourceDefinition`); `DataSources.makeUsageLog`
  fills it with the login's values and returns a `UsageLog` whose
  `days(from:to:)` reads and prices the records. Its readers and aggregator
  are `internal` workers beside `FileFetcher` and `JSONMapper`.
- **`Day` is a kernel value** in `Quotas`, beside `Cost` and `CostLine`,
  replacing `DailyUsageReport`/`Stat`, which already live there.

Not in `Provider`'s refresh: usage history is not a meter and is read on its
own cadence (popover open, never the background poll).

| Piece | Job | From today's |
|---|---|---|
| `UsageLog.Definition` (`DataSources`) | the JSON, `Codable`, no behaviour | the constants in both analyzers |
| `UsageLog` (`DataSources`) | `days(from:to:)`: the readers, prices and aggregator for one login | both analyzers' entry points |
| `JSONLinesReader` (`DataSources/Internal`) | one record per matching line; reads only what was appended since the last scan, re-reads a file that changed under it; a byte prefilter derived from `where` | `SessionJSONLParser` + `SessionLogCache`, generalised |
| `JSONLogReader` (`DataSources/Internal`) | one record per file; `at.fromPath` reads the time from the path | `VibeSessionLogAnalyzer.loadSessions` |
| `LogRecord` (`DataSources/Internal`) | the one shape every reader produces | `TokenUsageRecord`, `ParsedSession` |
| `PriceList` (`DataSources/Internal`) | the record's own cost, else the list (exact → longest prefix → family → free → `freeWhen` → otherwise); cache savings | `ModelPricing` |
| `LocalEndpoint` (`DataSources/Internal`) | `freeWhen.localEndpoint`: is the route in that file on this Mac? | `ClaudeLocalInferenceDetector` |
| `LogFileFinder` (`DataSources/Internal`) | `files`' glob, changed since a date | `findRecentJSONLFiles` |
| `DayAggregator` (`DataSources/Internal`) | dedupe by `id` (last wins), split by local day, sessions by `sessionGap` (a record is a session without one), working time, cache savings, a cost line per model | both analyzers' `aggregate` |
| `DayLedger` (`Providers/Internal`) | closed days kept per login; open days asked of the `UsageLog` | — (new) |
| `UsageHistory` (`Providers`, @Observable, one per login) | `days(in:)`, every date present | `Domain/UsageHistory` (one object for all logins, two days only) |
| `Day` (`Quotas`) | the answer; `DailyUsageStat` until the words land | `Quotas` |

Ports: the ledger's store (a `@Mockable` `LedgerStore`) in `Providers`, and
`PriceCatalog` for a cloud's prices. **The log files are not a port**: the
readers' whole job is bytes on disk (offsets, inodes, half-written lines), so
they are tested on files in a temporary folder, as credential files already
are; a mock would test nothing they do. No module names
a vendor; the readers are named for formats. The page owns the views:
*TODAY'S USAGE* cards read `days(in: .last(2))`, a chart reads
`days(in: .last(30))` and stacks `tokens` by kind (or `cost.lines` by model).

### 10.5 · Is it easy to change? The checks

| A person or a contributor wants… | They change |
|---|---|
| a *Last 30 days* chart, a week view, a month total | the page only: another range of `days` |
| a new model's price, or a price cut | `claude-prices.json` |
| *TODAY'S USAGE* for another tool that logs JSON | that tool's definition: a `usageHistory` block |
| Codex's usage history (`~/.codex/sessions/**/rollout-*.jsonl`, whose `token_count` events carry a session's **running total**) | `codex.json`'s `usageHistory`, plus one reader option, `"cumulative": true` (the last record per session counts), with a neutral test |
| a binary log format | one new reader, named for the format |
| an added login's own usage history | nothing: `accounts.patch.usageHistory` |

### 10.6 · The rest of `Infrastructure/Claude`

Deleting the folder also needs a home for **guest passes**
(`ClaudeGuestPassSource`): `claude /passes` in a terminal, the referral link
from the screen or, failing that, the clipboard, and an optional count. As
data: a `guestPasses` block in `claude.json` holding a `cli` fetch and a
`claude-passes.js` mapping, run by the same `DataSource` machinery; the one
new piece is a `cli` option that hands the clipboard's text to the mapping
after the run (`"clipboard": true`, a `@Mockable` `Clipboard` port). The `GuestPasses` capability in `Providers` stays, takes any definition's `guestPasses`, and is reached as `account.guestPasses` — no longer handed to `builtIn("claude", …)` by name in the App.

### 10.7 · Slices

Each slice is one PR, green, with no change a user can see unless it says so.

| # | Slice | Done when |
|---|---|---|
| UH1 ✅ | **Move**: `UsageHistory` into `Providers`, held by each `Account` (`account.usageHistory`), over today's analyzers behind `DailyUsageAnalyzing` | `Domain/UsageHistory` is empty; the App reads `account.usageHistory`; no visible change |
| UH2 ✅ | **Claude as data**: `UsageLog` + `UsageLog.Definition` in `DataSources`, `JSONLinesReader`, `PriceList` + `claude-prices.json`, `LocalEndpoint`, `DayAggregator`, `days(in:)`; claude.json's `usageHistory`. Golden tests: today's `ClaudeDailyUsageAnalyzerTests`, `SessionJSONLParserTests`, `SessionLogCacheTests`, `ModelPricingTests` fixtures through the definition | `ClaudeDailyUsageAnalyzer`, `SessionJSONLParser`, `SessionLogCache`, `ModelPricing`, `ClaudeLocalInferenceDetector` deleted; the same two-day numbers |
| UH3 | **Mistral as data**: `JSONLogReader`, `at.fromPath`; mistral.json's `usageHistory`; `VibeSessionLogAnalyzerTests` fixtures | `Infrastructure/Mistral` deleted |
| UH4 | **The ledger**: `DayLedger`, closed days kept, invalidated by a definition change | 30 days read in the time 2 take today |
| UH5 | **The chart**: *Daily usage — last 30 days* (tokens by kind, two axes; cost by model) on the provider's page | visible |
| UH6 | **Per login**: `accounts.patch.usageHistory`; `account.usageHistory` on every login | an added Claude login shows its own usage history (visible) |
| GP | **Guest passes as data**: `cli.clipboard`, claude.json's `guestPasses` + `claude-passes.js`; `ClaudeGuestPassSourceTests` fixtures | `Infrastructure/Claude` deleted |
| — | the words: `Day`, `DayLedger`; the typealiases go | with §8 slice 7 |
