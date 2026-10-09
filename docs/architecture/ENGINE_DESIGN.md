---
description: How each case a provider definition can use works — what the person sees and the one piece behind each, settings in one form with two scopes, HTTP in steps, commands and terminals, worded failures; read before adding a fetch, credential or setting case.
---

# ClaudeBar — the engine

> **#5 of 5** in [the design](ARCHITECTURE.md) · **Answers:** how each case
> works — every fetch, credential, setting and CLI rule a definition can use ·
> **Builds on:** [MODULAR_DESIGN.md](MODULAR_DESIGN.md) · **Next:** the
> provider's own `docs/providers/<id>/design.md`

## 1 · What each provider needed, as a general rule

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
| Codex logins in their own folders (#326) | `accounts` (`folder`), `{{account.x}}`, `identity` (fail closed when a folder signs in to someone else), `requiresFiles` (#216; added logins only since #525), `verifyBeforeBackground`, JSON-RPC `then` + `environment` + `errors`, `fallback.sameLogin` (#525), `#jwt.claim` and `$credential.` paths |
| the usage API's model limits, plan and money | JSON mapping rules, not a script: `each` + `where`, names by `firstWord`/`lowercase`, `unique` (first wins), `overLimit` (negative left), `countdown: "hours"`, `plan.plans` from `$credential.`, and a list of `cost` shapes with `when` and exact `{amount, decimals}` minor units |
| today's usage and guest passes | `UsageHistory` beside the providers (read with the popover open, never in the background; keyed by the login whose logs it reads) and the `GuestPasses` capability |
| Claude logins in their own config folders | `accounts.folder` with `email` and `accountId.field` as an `IdentityField` (`$context.account.email`), `derived` values (the Keychain service, from a sha256 of the folder), `identity` read from a context file; today's usage and guest passes stay with the default login |
| a date in a request: "the last 30 days" (OpenAI) | `{{system.day±N.<format>}}` from `SystemValues`, made with the fetch's `now` |
| a file in a folder named by version, across several apps (JetBrains IDEs) | a `*` in any path, a path as a list, the most recently changed match — `Paths` |
| a row of an app's own database as the answer (Windsurf) | `fetch.sqlite` over `ReadOnlyQuery`, shared with the `sqlite` key lookup |
| a sign-in a browser keeps in local storage (Devin) | `browserStorage`, every value from one profile, behind `BrowserStorageReading` |
| a key exported only in the login shell (Z.ai, #170) | `"loginShell": true` on an `environment` lookup — the engine's login-shell port, asked only by a lookup that says so |
| a variable name the person chose (DeepSeek) | a setting with a default, `{{setting.authEnvVar}}` in the lookup — a blank one means the default |

## 2 · The engine

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

### 2.1 · What the person sees, and the one piece behind each

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

### 2.2 · Settings: one form, two scopes

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

**One form for every provider.** Settings draws it (`ProviderSettingsSection`)
for every provider that has no card of its own; no new Swift card comes.

### 2.3 · HTTP in steps, instead of a planner script

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

### 2.4 · A command, and a terminal

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

#### A terminal's session: one id per login, the same forever

A TUI run can sit in a named session (`cli.session`), so polling doesn't
leave a session behind each time (#132). The id is **stable**: derived from
the definition's `stable` text and the call's own environment, so the default
login and each added login (its `CLAUDE_CONFIG_DIR`) get their own, and the
same login gets the same one across restarts. A run **creates** the session
under that id; only a CLI that answers the id is taken gets a **resume** of
the same id.

```text
refresh ─► create:  --session-id <this login's stable id> --name "ClaudeBar Probe"
             │  answers ───────────────────────────────► read it        (one launch)
             │  "already in use" (a CLI that kept the session)
             ▼
           resume:  --resume <the same id> ─────────────► read it
             │  "unknown option '--session-id'" + a non-zero exit
             ▼
           the call's plain args, for this worker's lifetime
```

```json
"session": {
  "id": { "stable": "ClaudeBar Probe" },
  "create": ["--session-id", "{{id}}", "--name", "ClaudeBar Probe"],
  "resume": ["--resume", "{{id}}"],
  "resumeOn": ["already in use"],
  "unsupportedOn": ["unknown option '--session-id'"]
}
```

| Law | Owner |
|---|---|
| a stable id is a UUID derived from the `stable` text and the call's environment — the same login, the same id, across restarts; another login, another id | `CLISessionRunner` |
| a stable session is created first; only `resumeOn` sends the same id to `resume` | `CLISessionRunner` |
| `resumeOn`, `recreateOn` and `unsupportedOn` match the text the screen shows, as a ready marker does | `CLICompletionRule` |

A plan without `id` keeps the older order — resume a remembered random id,
create again on `recreateOn` — for a CLI that keeps every session.

### 2.5 · A worker reports a fact; the definition words it

A worker's failure is a fact that answers for itself (`ReportedFailure`): its
key in `errors`, and the reason it gives when the definition says nothing.

| Fact | Key | Without a rule |
|---|---|---|
| an HTTP status that is not an answer | `http.<status>`, else `http.default` | today's wording (`HTTP error: 500`, *Key needed* on 401/403) |
| a command's (or a terminal's) CLI is not on this Mac | `cli.missing` | *CLI not found* — a login with no usage then reads *NOT SET UP* (CANONICAL §5) |
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

### 2.6 · A case answers for itself

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
  `ProviderDefinition.runningCLI` read the case's own answer (where the CLI
  is found: §2.7); the Add Provider
  sheet asks the definition (`neededSettings`), not the lookup's cases.
- **Adding a case is:**
  - the enum line
  - its payload with its `Connection`
  - its worker
  - one factory line

### 2.7 · Where a provider's CLI is

> **Status: BUILT** (2026-10-05, for #458; journey moment 3a).

*Where is this product's program on this Mac?* already has one answer per
product: the **CLI location**, which `runningCLI` applies to every call that
starts the CLI — each fetch, a credential refresh, Add Account's sign-in.
What is missing is only its **default** when the person chose none and the
program isn't on the PATH, but the product's own app carries one. So `cli`
says every place the program may be, in order:

```json
"cli": ["acme", "/Applications/Acme.app/Contents/Resources/acme"]
```

A bare name is looked for on the PATH, a path is taken as it is. The first
entry is the name every call runs; `"cli": "acme"` is the same as `["acme"]`,
so no definition changes unless its app carries the program.

| Law | Owner |
|---|---|
| the CLI location is the one the person chose; else the first entry of `cli` that is found. A chosen one that is missing is *CLI not found*, never another copy | `Configuration` |
| found when the provider is configured — at launch and when the CLI location changes; the PATH is asked only when a later entry exists on this Mac | `Configuration` |
| every call that starts the CLI follows the location; no call carries places of its own | `ProviderDefinition.runningCLI` |

Sign-in has no places of its own; nothing in `DataSources` knows them. Which places a product uses is that provider's
research: its `design.md` ([Codex](../providers/codex/design.md#desktop-app-cli)).

### 2.8 · Kept as they were, and left out

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

### 2.9 · What a new provider still can't say

> **Status: BUILT** (2026-10-05). Found while adding Cline,
> Warp, Devin, Windsurf and Grok's plan; each gap blocked a provider or
> forced a work-around. None names a vendor.

| Person | Wants | Before |
|---|---|---|
| uses an OpenAI Admin key | "what I spent in the last 30 days" | the request needs a start date; a definition can't compute one |
| uses a JetBrains IDE | "my AI quota, whichever IDE and version" | each IDE version keeps its own folder; a path names one |
| uses Windsurf | "what the app saved on this Mac, without a shell" | `/bin/sh` + `sqlite3` |
| signed in to Devin in Chrome | "use my browser sign-in" | a token copied from the browser's developer tools |

Four pieces, each with one owner and one reason to change. Two of them serve
both sides of a data source, the key and the fetch:

```text
                 ┌──────────────── <id>.json ─────────────────┐
                 │  credential   │      fetch       │ mapping │
                 └──────┬────────┴────────┬─────────┴────┬────┘
                        ▼                 ▼              ▼
              CredentialLookup          Fetch       JSON rules / <id>.js
    environment · setting · keychain    http · steps · jsonRpc · cli · command
    browserCookies · ★ browserStorage   localServer · cloudWatch
    jsonFile · sqlite                   file · directory · ★ sqlite
          │       │                       │            │        │
          │       │                       │            │        └─► Template.fill ─► ★ SystemValues(now)
          │       │                       │            │            (http: url · headers · body)
          │       └─────────┬─────────────┴────────────┘
          │                 ▼
          │      ★ Paths.resolve — both sides
          │        key: jsonFile · sqlite      answer: file · directory · sqlite
          │
          └── sqlite (key) ───┐        ┌── ★ sqlite (answer)
                              ▼        ▼
                         ★ ReadOnlyQuery — both sides
                 SQLiteReader (first row → key)   SQLiteFetcher (rows → answer)

★ BrowserStorageReader → @Mockable BrowserStorageReading → SweetCookieKit   (key side only)
```

#### `SystemValues` (built)

Values the engine computes, made with the fetch's `now`, one row per name:
`system.timeZone`, `system.osVersion`, `system.now.<format>`,
`system.day±N.<format>` (UTC midnight, N days away); formats `epoch` ·
`iso8601` · `date` (`yyyy-MM-dd`). `Template` looks a `system.` name up; a
new value is a new row, never a branch. HTTP fills them in its URL, headers
and body; elsewhere a `system.` name stays unfilled.

```text
DataSources.make(now:) ──► HTTPFetcher ──► SystemValues(now)
                                              one row per name
                                              system.timeZone      → "Asia/Shanghai"
                                              system.osVersion     → "27.0.0"
                                              system.now.epoch     → 1791210600
                                              system.day-29.epoch  → UTC midnight 29 days ago
                                              system.day-29.date   → "2026-09-06"
Template.fill("start_time={{system.day-29.epoch}}")
   ├─ system.* ? ──► SystemValues[name]       (never taken from the credential)
   └─ otherwise ──► credential[name]          (unchanged)
```

#### `Paths` (built)

The one owner of *which file on disk*, on both sides of a data source: the
key (`jsonFile`, `sqlite`) and the answer (`file`, `directory`, `sqlite`).
`PathPattern` is one path or a list, written back the way it was given. A
`*` stands for part of one folder or file name; of every match the most
recently changed is used; none is a missing file. A path without `*` means
what it did.

```text
"path": ["~/Library/Application Support/JetBrains/*/options/AIAssistantQuotaManager2.xml",
         "~/Library/Application Support/Google/*/options/AIAssistantQuotaManager2.xml"]
        │
        ▼  ~ and ${VAR} expand                  (as before)
        ▼  * matches within one name
   IntelliJIdea2025.3/options/…xml   changed 2026-10-05 09:12  ◄─ newest
   PyCharm2025.2/options/…xml        changed 2026-09-30 17:40
   AndroidStudio2025.1/options/…xml  changed 2026-08-02 11:03
        │
        ▼
one path → file · directory · jsonFile · sqlite
no match → a missing file → the source is not Configured
```

#### `fetch.sqlite` and `ReadOnlyQuery` (built)

A row of an app's own database as the answer: one case, one worker,
`SQLiteFetcher`. `ReadOnlyQuery`, taken out of `SQLiteReader`, opens
read-only, refuses a statement that would write, and reads text and UTF-8
or UTF-16LE BLOBs; the key lookup and the fetch both use it. The answer is
the rows, `[{column: text}]`. *Configured* while the file exists; its
`Connection` names no URL and runs nothing.

```text
"sqlite": { "path": "…/state.vscdb", "query": "SELECT value FROM ItemTable WHERE key = '…'" }
        │
        ▼
SQLiteFetcher ── is the file there? ──► no → not Configured
        │
        ▼
ReadOnlyQuery   (shared with the sqlite key lookup)
   open read-only, busy timeout 1 s
   a statement that would write ──► refused, never run
   each column: TEXT · BLOB as UTF-8 · BLOB as UTF-16LE → text
        │
        ▼
answer: [ { "value": "{\"planName\":\"Pro\",…}" } ]  ──► mapping
```

#### `browserStorage` (built)

A value a browser keeps for a site, beside `browserCookies`:
`BrowserStorageReader` behind the `@Mockable` `BrowserStorageReading` port,
over SweetCookieKit's Chromium localStorage. *Key lookup order* shows
*Browser storage · app.devin.ai*. Each value names a key (`*` matches any
part) and, when its value is JSON, a path in it.

```text
"browserStorage": { "origin": "https://app.devin.ai", "values": { token, organization } }
        │
        ▼
BrowserStorageReader
   stores = port.stores(origin:)    one per browser profile, in import order
            Chrome/Default · Chrome/Profile 1 · Arc/Default · …
        │
        ▼  for each store:
           token        = key matching "*auth1_session", then "$.token" in its JSON
           organization = key matching "last-internal-org-for-external-org-v1-*"
           has a token? → every value from THIS store → Credential   (never mixed)
        │
        ▼
Credential { token, organization } ──► {{token}} {{organization}}
                                       never logged · sent only to app.devin.ai
```

| Law | Owner |
|---|---|
| a computed value comes from the fetch's `now`, never the wall clock; days are UTC midnights | `SystemValues` |
| `*` matches within one folder name; of every match, the most recently changed file; none is a missing file | `Paths` |
| no database is written: a statement that would change it is refused, for a lookup and a fetch alike | `ReadOnlyQuery` |
| a database fetch is *Configured* only while its file exists | `SQLiteFetcher` |
| a credential's values all come from one browser profile, never mixed; the first profile with a `token` wins | `BrowserStorageReader` |
| a value read from a browser is a credential like a cookie: never logged, sent only to the hosts the definition names | `BrowserStorageReader`, `Connection` |

#### The definitions it makes possible

Each is data only: the definition, its mapping script, one golden test file
and one registration line.

**Windsurf** — the plan from Windsurf's own database, no shell:

```json
{
  "profile": { "id": "windsurf", "name": "Windsurf", "…": "as before" },
  "enabledByDefault": false,
  "defaultDataSource": "local",
  "dataSources": [
    {
      "kind": "local",
      "label": "Windsurf app",
      "summary": "Reads the plan Windsurf saves on this Mac, read-only. It updates while Windsurf runs.",
      "fetch": {
        "sqlite": {
          "path": "~/Library/Application Support/Windsurf/User/globalStorage/state.vscdb",
          "query": "SELECT value FROM ItemTable WHERE key = 'windsurf.settings.cachedPlanInfo' LIMIT 1"
        }
      },
      "mapping": { "script": { "file": "windsurf-plan.js" } }
    }
  ]
}
```

**JetBrains AI** — the newest quota file across every IDE:

```json
{
  "profile": {
    "id": "jetbrains", "name": "JetBrains AI",
    "links": { "dashboard": "https://account.jetbrains.com/licenses" },
    "look": { "symbol": "j.square.fill", "icon": "JetBrainsIcon",
              "color": { "light": [0.95, 0.2, 0.55], "dark": [1.0, 0.35, 0.65] },
              "gradientEnd": { "light": [0.45, 0.2, 0.9], "dark": [0.6, 0.35, 1.0] } }
  },
  "enabledByDefault": false,
  "defaultDataSource": "local",
  "dataSources": [
    {
      "kind": "local",
      "label": "IDE",
      "summary": "Reads the AI quota your JetBrains IDE saves on this Mac, from the IDE you used last",
      "fetch": {
        "file": {
          "path": [
            "~/Library/Application Support/JetBrains/*/options/AIAssistantQuotaManager2.xml",
            "~/Library/Application Support/Google/*/options/AIAssistantQuotaManager2.xml"
          ]
        }
      },
      "mapping": { "script": { "file": "jetbrains-quota.js" } }
    }
  ]
}
```

`jetbrains-quota.js` finds the `quotaInfo` and `nextRefill` attributes,
decodes their HTML entities and reads the JSON inside: a monthly *AI
credits* quota, `current` of `maximum`, resetting at `nextRefill.next`.

**OpenAI API** — the last 30 days of spend, a date the engine computes:

```json
{
  "profile": {
    "id": "openai", "name": "OpenAI API",
    "links": { "dashboard": "https://platform.openai.com/usage", "status": "https://status.openai.com" },
    "look": { "symbol": "sparkle", "icon": "OpenAIIcon",
              "color": { "light": [0.06, 0.64, 0.5], "dark": [0.25, 0.82, 0.66] },
              "gradientEnd": { "light": [0.04, 0.45, 0.36], "dark": [0.14, 0.62, 0.5] } }
  },
  "enabledByDefault": false,
  "settings": [ { "id": "apiKey", "label": "Admin API key", "kind": "secret", "scope": "account" } ],
  "defaultDataSource": "api",
  "dataSources": [
    {
      "kind": "api",
      "label": "Admin API",
      "summary": "Reads your organization's spend for the last 30 days with an Admin API key",
      "credential": { "firstOf": [ { "environment": "OPENAI_ADMIN_KEY" }, { "setting": "apiKey" } ] },
      "fetch": {
        "http": {
          "url": "https://api.openai.com/v1/organization/costs?start_time={{system.day-29.epoch}}&bucket_width=1d&limit=30&group_by=line_item",
          "headers": { "Authorization": "Bearer {{token}}", "Accept": "application/json" },
          "timeout": 20
        }
      },
      "mapping": { "script": { "file": "openai-costs.js" } },
      "errors": {
        "http.401": { "sessionExpired": "Use an organization Admin API key; project keys can't read spend." },
        "http.403": { "sessionExpired": "Use an organization Admin API key; project keys can't read spend." }
      }
    }
  ],
  "accounts": { "patch": { "api": { "credential": { "firstOf": null, "setting": "apiKey" } } } }
}
```

`openai-costs.js` adds `data[].results[].amount.value` into one `cost`, a
line per `line_item`, for "Last 30 days".

**Devin** — the browser sign-in first, the pasted token after:

```json
{
  "profile": { "id": "devin", "name": "Devin", "…": "as before" },
  "enabledByDefault": false,
  "settings": [
    { "id": "token", "label": "Session token", "kind": "secret", "scope": "account" },
    { "id": "organization", "label": "Organization ID", "scope": "account",
      "kind": { "text": { "pattern": "^org[-_][A-Za-z0-9_-]+$" } } }
  ],
  "defaultDataSource": "web",
  "dataSources": [
    {
      "kind": "web",
      "label": "Web",
      "summary": "Reads your organization's daily and weekly Devin quota with your app.devin.ai sign-in",
      "credential": {
        "firstOf": [
          {
            "browserStorage": {
              "origin": "https://app.devin.ai",
              "values": {
                "token":        { "key": "*auth1_session", "path": "$.token" },
                "organization": { "key": "last-internal-org-for-external-org-v1-*" }
              }
            }
          },
          { "environment": "DEVIN_BEARER_TOKEN", "with": { "organization": "{{setting.organization}}" } },
          { "setting": "token", "with": { "organization": "{{setting.organization}}" } }
        ]
      },
      "fetch": {
        "http": {
          "url": "https://app.devin.ai/api/{{organization}}/billing/quota/usage",
          "headers": { "Authorization": "Bearer {{token}}", "x-cog-org-id": "{{organization}}", "Accept": "application/json" },
          "timeout": 15
        }
      },
      "mapping": { "script": { "file": "devin-quota.js" } },
      "errors": {
        "http.401": { "sessionExpired": "Sign in to app.devin.ai again, or paste a new session token." },
        "http.403": { "sessionExpired": "Sign in to app.devin.ai again, or paste a new session token." }
      }
    }
  ],
  "accounts": {
    "patch": { "web": { "credential": { "firstOf": null, "setting": "token",
                                        "with": { "organization": "{{setting.organization}}" } } } }
  }
}
```

`firstOf` tries each lookup in order and the first that finds a token wins;
each brings its own values, so a browser token never travels with a pasted
organization. `"firstOf": null` in `accounts.patch` drops that list for an
added login, which uses only its own pasted token.

What the person sees:

```text
Settings → Providers → Devin
┌────────────────────────────────────────────────────────┐
│ DATA SOURCE      Web                                   │
│ KEY LOOKUP ORDER 1. Browser storage · app.devin.ai  ✓  │
│                  2. DEVIN_BEARER_TOKEN                 │
│                  3. Session token (pasted)             │
│ SESSION TOKEN    ••••••••            (only if needed)  │
│ ORGANIZATION ID  org_…               (only if needed)  │
└────────────────────────────────────────────────────────┘

Settings → Providers → JetBrains AI
┌────────────────────────────────────────────────────────┐
│ DATA SOURCE  IDE — reads the quota your JetBrains IDE  │
│              saves on this Mac, from the IDE used last │
│ Nothing to paste.                                      │
└────────────────────────────────────────────────────────┘
```

**Built** in that order, each test first: `SystemValues` → `Paths` →
`ReadOnlyQuery` + `fetch.sqlite` → `browserStorage`. Windsurf moved to
`fetch.sqlite`, Devin reads the browser first, and JetBrains AI and OpenAI
arrived as definitions — no vendor-named Swift.

**Left for later, each its own design:** paging (a list over several pages,
a piece around a request, not another `HTTPStep` field) and binary answers
(protobuf, gRPC-web: `Response`, `ScriptMapper` and `ErrorFact` together).
