---
name: add-provider
description: |
  Add an AI provider to ClaudeBar as a JSON definition run by the one generic
  Provider and DataSource. Use this skill when:
  (1) Adding a new AI assistant provider (like Antigravity, Cursor, etc.)
  (2) A provider needs a setting, an added account, or an old saved key kept working
  (3) A provider's CLI, API or file format changed and its definition must follow
  (4) User asks "how do I add a new provider" or "create a provider for X"
---

# Add a Provider to ClaudeBar

A provider is **data**: one file, `Modules/Providers/Resources/Providers/<id>.json`.
**The app finds it** — `ProviderCatalog.detect()` reads every definition in the
bundle (and in `~/.claudebar/providers`, `~/.claudebar/extensions`) and makes
each on one shared `Engine` ([TARGET_ARCHITECTURE §10](../../../docs/architecture/TARGET_ARCHITECTURE.md#10--a-definition-on-disk-is-a-provider)).
There is no registration step and no Swift line that names it.
It says where the key is, how to fetch, and how to read the answer. One
`Provider` class and one `DataSource` type run every definition. **You write
no Swift for a vendor**: no `XxxProvider`, no `XxxUsageProbe`, no
`XxxCredentialLoader`.

> Read first: [TARGET_ARCHITECTURE.md](../../../docs/architecture/TARGET_ARCHITECTURE.md)
> (how a definition runs), [MODULAR_DESIGN.md](../../../docs/architecture/MODULAR_DESIGN.md)
> (which module a file goes in), and [CANONICAL_MODEL.md](../../../docs/architecture/CANONICAL_MODEL.md)
> (the words). Every built-in provider is a definition, so there is a worked
> example for most shapes: an API key with a region (`minimax.json`), a CLI's login
> file renewed by OAuth (`grok.json`) or by the CLI itself (`gemini.json`), a TUI
> (`kimi.json`), a browser session over several requests (`alibaba.json`), an app's
> local server (`antigravity.json`), cloud metrics priced into money (`bedrock.json`).
> Their tests are in `Modules/Providers/Tests/`.

**The docs are the source of truth** ([AGENTS.md](../../../AGENTS.md#design-docs-are-the-source-of-truth)).
A provider that fits the definition language needs no design change. One that needs the
language to grow — a new case and worker, a new capability (CANONICAL §2.1), a new setting
kind — is a design change: write it into TARGET_ARCHITECTURE / CANONICAL_MODEL first and ask
the user to confirm before writing code.

## The pieces

| Piece | Where | You touch it when |
|---|---|---|
| `<id>.json` | `Modules/Providers/Resources/Providers/` | always |
| `<id>-*.js` mapping script | beside the JSON | only when no mapping rule can read the format (a TUI screen) |
| golden tests | `Modules/Providers/Tests/<Name>DefinitionTests.swift` | always |
| a generic rule or worker | `Modules/DataSources/` (+ `DataSourcesTests`) | when the definition language can't say what the provider needs |
| look (name, symbol, colour, icon) | `profile.look` in `<id>.json`; the icon image in the asset catalog | always |
| research | `docs/providers/<id>/README.md` (users), `design.md` (contributors) | always |

**The rules** ([MODULAR_DESIGN §3–4](../../../docs/architecture/MODULAR_DESIGN.md#3--the-package-rules)):
- No vendor's name in a module's Swift. A worker is named for its protocol, format or place (`JSONRPCFetcher`, `OAuth2Refresher`), never a vendor.
- No `Probe` names. The words are DataSource, Fetch, Mapping, Usage, Quota, Plan and Cost.
- `Modules/*` never `import Domain`. The usage model is `Quotas`; providers, settings and accounts are `Providers`.

## The definition: three closed sums per data source

```jsonc
{
  "profile": {                          // WHO IT IS
    "id": "acme",                       // stable forever: settings and the menu bar key on it
    "name": "Acme",
    "links": { "dashboard": "https://…", "status": "https://…" },
    "look": { "symbol": "bolt.fill", "icon": "AcmeIcon",          // SF Symbol, asset name
              "color": { "light": [0.2, 0.5, 0.9], "dark": [0.3, 0.6, 1.0] },
              "gradientEnd": { "light": [0.1, 0.3, 0.7], "dark": [0.2, 0.4, 0.8] } }
  },
  "cli": "acme",                        // optional
  "enabledByDefault": true,
  "order": 280,                         // its default place in the lineup; none → after the rest, by name
  "guestPasses": {},                    // optional: a capability the engine runs (Claude's)
  "defaultDataSource": "api",
  "dataSources": [
    {
      "kind": "api",                    // what Settings' Data source picker saves as <id>.probeMode
      "label": "API", "summary": "Calls Acme API directly",
      "credential": { … },              // CredentialLookup — where the key is
      "fetch":      { … },              // Fetch — how to ask
      "mapping":    { … },              // Mapping — how to read the answer
      "fallback": "cli"                 // optional: try this kind when this one fails
    }
  ]
}
```

| Sum | Cases |
|---|---|
| `credential` | `environment` (`"loginShell": true` also asks the person's login shell) · `browserStorage` (a site's local storage, one browser profile) · `setting` (a key pasted into ClaudeBar, in the Keychain) · `jsonFile` (paths `$.a.b`, or a list — the first that answers; `~` and `${VAR:-default}`; `record`, `defaults`) · `keychain` (`account`, `encoding: "goKeyringBase64"`) · `browserCookies` (`format: "value"\|"header"`) · `sqlite` · `firstOf` — any of them refined with `match` (a value must fit a pattern, or no key), `with` (values added) and `cookies` (named cookies read out of a Cookie header); plus `"refresh": { "oauth2": … }` or `"refresh": { "cli": … }` (the CLI renews its own file) |
| `fetch` | `http` (`{{token}}`, `{{x#host}}`, `{{x#jwt.claim}}`, `{{system.timeZone}}`) or `"http": { "steps": [ … ] }` (`keep`, `optional`, `unless`, `attempts`, `dropEmpty`) · `jsonRpc` · `cli` — a terminal, for a TUI (`input`, `inputDelay`, `autoResponses`, `readyWhen`, `screen: "rendered"`) · `command` — pipes, exit code reported · `file` · `directory` · `sqlite` (rows of an app's own database, read-only) · `localServer` (an app's server on 127.0.0.1, found through its process) · `cloudWatch` (cloud metrics through a port, priced from a `PriceCatalog`) |
| `mapping` | `json` (below) · `text` (error phrases, then label + regex for % left/used) · `script` (a `.js` file in JavaScriptCore, no I/O; host `humanDate()`, `jsonDecimal()`, `decimalCents()`, `decimalAdd()`, `decimalMultiply()`; `context.values` from `"values"`; returns `quotas` (with `group`), `notes`, `plan`, `cost` (with `lines`), `account`, or `error`) |

Per data source, also: `errors` (`http.<status>`, `http.default`,
`cli.missing`, `cli.nonzero`, `cli.failed` → a reason; a 429 is always a rate
limit), `fallbackOn` (hand-off by failure tag), `fallback`, `cache.ttl` (also
the background-refresh floor), `context` (JSON files the mapping may read),
`recover.patchJSONFile`, `requiresFiles`, `identity`,
`verifyBeforeBackground`. Per provider: `links.dashboardByPlan` and `accounts`
(added logins, see `codex.json`).

### Settings and added accounts

```jsonc
"settings": [
  { "id": "apiKey", "label": "API Key", "kind": "secret", "scope": "account", "for": ["api"] },
  { "id": "region", "label": "Region", "scope": "account", "default": "china",
    "kind": { "choice": [ { "id": "china", "label": "China", "host": "api.acme.cn" },
                          { "id": "intl",  "label": "International", "host": "api.acme.com" } ] } },
  { "id": "home", "label": "Signed-in Folder", "scope": "account", "for": ["cli"], "kind": { "path": { "mustExist": true } } },
  { "id": "authEnvVar", "label": "Environment variable", "default": "ACME_API_KEY" }
]
```

- A kind owns its rule: `secret` (to the Keychain, fills nothing), `choice` (its options carry values), `path` (`mustExist`), `text` (`pattern`).
- `{{setting.region.host}}` fills any string of the definition; a blank setting leaves its template unfilled (a script's `values` drop it).
- `scope: "account"` is what *Add Account* asks for; `"for": [kind]` asks only while that data source is active, and a login without such a value runs only the sources that don't need it.
- `accounts.patch.<kind>` changes a data source for added logins (`"firstOf": null` drops the default lookups; `{{account.home}}` fills from the login's values).

### The JSON mapping

```jsonc
"json": {
  "plan":  { "path": "$credential.plan", "plans": { "max": "claudeMax" } },   // or "badges"
  "email": ["$.account.email", "$credential.email"],
  "quotas": [
    { "kind": "session", "at": "$.five_hour", "usedPercent": "utilization",
      "resetsAt": { "iso8601": "resets_at" } },               // or epochSeconds / secondsFromNow
    { "kind": "model", "each": "$.limits", "where": { "path": "kind", "equals": "weekly" },
      "name": { "firstOf": ["model.name"], "firstWord": true, "lowercase": true },
      "usedPercent": "percent", "unique": true, "overLimit": true, "countdown": "hours",
      "window": [{ "seconds": "window_seconds" }, { "days": 7 }] },   // the response's word, else the provider's
    { "kind": "time", "name": "Credits",                             // money, not a percentage:
      "left": { "money": "$.data.remaining", "of": "$.data.limit", "currency": "USD" } }  // no "of" = a balance
  ],
  "cost": [                                                    // the first shape that answers
    { "kind": "extraUsage", "when": { "path": "$.spend.enabled", "equals": true },
      "used":  { "amount": "$.spend.used.amount_minor", "decimals": "$.spend.used.exponent" },
      "limit": { "amount": "$.spend.limit.amount_minor", "decimals": "$.spend.limit.exponent" } }
  ],
  "whenEmpty": { "if": { "path": "$.plan", "equals": "free" }, "quotas": [ … ], "otherwise": "No data yet" },
  "notAnObject": "Failed to parse usage response"
}
```

Paths: `$.a.b` from the root, `a.b` from the current object, `$header.x`, `$key`
(the map key inside `each`), `$credential.x` (a non-secret credential value),
`$context.file.field` (a field of a `context` file the data source reads, such as
the email a tool keeps in its own account file).
A list of values means *the first that answers*; a number is a constant.

## TDD workflow (Chicago school)

Name each test `should <outcome> [when <situation>]`, in the person's words, never a method, type or mechanism verb → [Naming tests](../implement-feature/references/tdd-patterns.md#naming-tests).

### 1 · Research and fixtures
Find where the usage really comes from (CLI command, endpoint, local file) and
capture **real** responses, redacted, including the failure answers: logged
out, rate limited, a free plan, an empty account. Write what you learned in
`docs/providers/<id>/design.md`.

### 2 · Golden tests first (red)
`Modules/Providers/Tests/<Name>DefinitionTests.swift` runs the real definition
through the real `Provider` over stubbed connections with `StubbedProvider`
(`Tests/Support/Connections.swift`). They fail first because `<id>.json` doesn't exist.

```swift
@MainActor
@Suite
struct AcmeDefinitionTests {
    @Test
    func `should read Acme from its API by default`() throws {
        let acme = try ProviderFactory.builtIn("acme")
        #expect(acme.dataSources.map(\.kind) == ["api"])
        #expect(acme.defaultDataSource == "api")
    }

    @Test
    func `should show the session window when the API answers`() async throws {
        let stub = try StubbedProvider(providerId: "acme")
        defer { stub.cleanUp() }
        stub.environment = ["ACME_API_KEY": "test-key"]
        stub.answerHTTP(#"{"session":{"used_percent":30,"reset_at":1735000000}}"#)

        let usage = try await stub.make("acme").refreshPlain()

        #expect(usage.quota(for: .session)?.percentRemaining == 70)
        #expect(usage.quota(for: .session)?.resetsAt == Date(timeIntervalSince1970: 1735000000))
    }

    @Test
    func `should say the key is missing when the API has no key`() async throws {
        let stub = try StubbedProvider(providerId: "acme")
        defer { stub.cleanUp() }
        let acme = try stub.make("acme")

        await #expect(throws: UsageError.authenticationRequired) { try await acme.refresh(acme.defaultAccount) }
        #expect(acme.defaultAccount.lastFailedStep == .lookup)
    }
}
```

Assert on **state**: the usage, `lastError`, `lastFailedStep`, `answeredBy`, and
files written back. Don't `verify()` calls. Cover every fixture from step 1.

### 3 · Write the definition (green)
Add `<id>.json` until the golden tests pass. `ProviderFactory.builtIn` validates it:
kinds are unique, and the default and every fallback name an existing kind.

### 4 · When the language can't say it
Don't write vendor code. Find the **generic** shape of the need, for example
"a list filtered by a field" or "money in minor units", and add it to
`DataSources` test-first in `Modules/DataSources/Tests/`. Then use it from the
JSON. [ENGINE_DESIGN §1](../../../docs/architecture/ENGINE_DESIGN.md#1--what-each-provider-needed-as-a-general-rule)
lists the pieces each provider needed. Add your row there.

Only a format no rule can read, like a terminal UI screen, gets a mapping
script, `<id>-<what>.js`. Test it through Swift with real captured screens
(see `ClaudeUsageScreenTests`).

### 5 · Give it a look and a place
There is nothing to register: the file being in `Resources/Providers/` makes it
a provider. `"order"` places it in the default lineup (the built-ins use 10, 20,
… 270); leave it out to come after the rest, by name. The person's own order
still wins. `DetectionTests` lists the built-ins in order — add your id there.

Every provider gets the same `Engine`: settings, the vault, the login shell (for
a lookup with `"loginShell": true`), the cloud ports (for a `cloudWatch` fetch),
the guest-passes runner (for `"guestPasses": {}`). Ask for one in the JSON;
never pass one in Swift.

Its name, symbol and colours are `profile.look` in the JSON — no `switch id`
table to edit. Add the icon image to the asset catalog under `look.icon`
([references/provider-icon-guide.md](references/provider-icon-guide.md)).
Settings need no new protocol: the data source choice is
`dataSourceKind(forProvider:)`, and an on/off setting a definition names (for
example `fallback.enabledBySetting`) is `isOn(_:forProvider:)`.

### 6 · Docs and release note
- `docs/providers/<id>/README.md` (what users see, setup, errors) and `design.md` (sources, fields, gotchas).
- A row in the **Providers** table of the root `README.md` — name, what it tracks, a link to its `docs/providers/<id>/README.md` — placed by its `"order"`, so the table follows the default lineup.
- A tile in the landing page's providers grid (`website/public/index.html`, `<div class="pv" data-id="<id>" …>`), in lineup order, and every count on the page raised by one — `npm test` in `website/` reads the definitions and fails until both match.
- One line under `## [Unreleased]` in `CHANGELOG.md`.
- `python3 scripts/gen-docs.py && python3 scripts/check-docs.py --strict`.

## Keeping what people saved

Every built-in provider is already a definition; when you change one, keep
every saved value working. The data source choice is `<id>.probeMode`, and a
setting `foo` is read from `<id>.foo`. A value kept somewhere else gets a row,
never a branch:

- a setting under another key → `JSONSettingsRepository.legacySettingKeys`
- a setting in UserDefaults → `JSONSettingsRepository.legacyDefaultsKeys` (a saved number or list reads as text)
- a secret in UserDefaults or an older Keychain item → `ProviderVault.legacyKeys`

Each moves to its new place the first time it's saved, and each needs a test.

## Checklist

- [ ] Real fixtures captured (success and every failure), research in `design.md`
- [ ] Golden tests written first and failing
- [ ] `<id>.json` makes them pass; no vendor-named Swift anywhere
- [ ] Any new mapping/fetch/lookup ability added generically to `DataSources`, test-first, and listed in ENGINE_DESIGN §1
- [ ] `"order"` set if it has a place in the default lineup, and its id in `DetectionTests`
- [ ] `profile.look` filled in and the icon added to the asset catalog
- [ ] Provider docs, its row in the root `README.md` Providers table, its landing-page tile and counts (`npm test` in `website/`), and the CHANGELOG line written; docs check passes
- [ ] `tuist test` green
