---
description: THE normative tree ClaudeBar binds to — every node from the Monitor down, the word the screen prints for it, its laws and their owners, and the bounded contexts; read before adding or changing any domain type or provider.
---

# ClaudeBar — the canonical model

> ONE tree. The menu bar, the popover, the Settings window, the notch, the
> Touch Bar and Notify! all read it; none of them adds a rule to it. A node is
> here because a user can point at it on screen, and a rule lives on **the node
> that holds the data it needs** (tell, don't ask).
>
> **#2 of 5** in [the design](ARCHITECTURE.md) · **Answers:** what is true —
> the nodes, the words, the laws and their owners · **Builds on:**
> [USER_JOURNEYS.md](USER_JOURNEYS.md) · **Next:**
> [TARGET_ARCHITECTURE.md](TARGET_ARCHITECTURE.md)

---

## 0 · How to read it

| Mark | Means |
|---|---|
| **◆** | a domain object with commands and laws — it can say no |
| **◇** | a value — it answers, and cannot be told anything |
| **DERIVED** | computed from other nodes, never stored |

**The words are the ones the screen prints.** A name is harvested from the
interface, never from backstage jargon; when the interface has no word yet,
the industry's is taken. The screen prints *Providers*, *All Providers*,
*Accounts*, *Add Account*, *PROBE MODE* (subtitled *Data fetching method*),
*CLI Mode · API Mode · RPC Mode*, *Save & Test Connection*,
*Fetching usage data…*, *No usage data*, *Updated 3m ago*, *Session · Weekly*,
*Low quota*, *each quota window resets*, *% left*, *remaining*, *Resets in 2h 5m*,
*Balance*, *Credits*, *API COST*, *EXTRA USAGE*, *Daily Budget*, *Claude Max
plans*, *HEALTHY · WARNING*, *On track · Running hot · Room to spare*, *TODAY'S
USAGE*. The screens the redesign adds — walked first in
[USER_JOURNEYS.md](USER_JOURNEYS.md) — print *Add Provider*, *Start from: API ·
CLI · File · Copy a provider*, *Key lookup order*, *Test Connection*,
*Response*, *Map fields: Used · Remaining · Limit · Resets*, *Built in ·
Custom · Extension*, *Export*, *Import*, *Couldn't read your key · Couldn't
connect · Couldn't find the numbers*, *via API*. Those are the words below.

### 0.1 · Words the code uses, and ours

| The code's word | Ours | Why ours |
|---|---|---|
| `AIProvider` | **`Provider`** | the screen prints *Providers*. The `AI` prefix tells the reader nothing; every provider is one |
| `UsageProbe`, and every `XxxUsageProbe` (find the credential, refresh it, fetch, fall back AND parse — in one vendor-named type) | **`DataSource`** — a **`DataSourceDefinition`** (`CredentialLookup` + `Fetch` + `Mapping`, plain data) made live with exactly the one connection its fetch needs; it fetches its own usage | the screen has to translate its own header: *PROBE MODE* is subtitled *Data fetching method*, and everywhere else it says *Fetching usage data…* and *Test Connection*. Settings screens that do this job — Grafana, Metabase, Retool — call it a **data source** and test it with *Save & test*. And it is two questions — *how do I get the bytes?* and *what do they say?* — which a user building a provider in the UI answers on two different steps; a third, *whose key?*, the screen already prints as *TOKEN LOOKUP ORDER* · *API KEY LOOKUP ORDER* · *COOKIE SOURCE*. *Probe* is the industry's word for checking something is alive (a Kubernetes liveness probe), which is our `healthCheck`, not this |
| the *PROBE MODE* header | **DATA SOURCE**, choices *CLI · API · RPC* | the subtitle goes; it no longer translates anything. The saved setting key and the extension manifest's `"probe"` key and `probe.sh` stay — keys are match names, labels are display names |
| `ProbeError` | **`DataSourceError`** | the failure of a data source — what *Save & Test Connection* reports when the connection is not verified |
| `UsageSnapshot` | **`Usage`** | the screen prints *Fetching usage data…* · *No usage data* · *Updated 3m ago*, and the vendors' own command is `/usage` (we run `claude /usage`). It is the provider's usage, as of when it was updated. *Snapshot* is the code's word for any frozen value |
| `capturedAt` | **`updatedAt`** | the screen prints *Updated 3m ago* |
| `UsageQuota` | **`Quota`** | the product's own word — *"shows AI coding quotas"* |
| `percentRemaining` + `dollarRemaining` + `dollarCap` (+ `percentRemaining: 100` as a placeholder) | **`Quota.left: Left`** — `share(Percent)` · `money(Money, of: Money?)` | the screen prints *% left* OR *$12.40 remaining*. Never both, and a balance with no ceiling has no percentage |
| `QuotaType` (name **and** a guessed duration) | **`Quota.name`** + **`Quota.window: Window?`** | *Session* is what it's called; *5 hours, resets 11am* is when it refills. The code derives the second from the first |
| `QuotaStatus` | **`Status`** | prints HEALTHY · WARNING · CRITICAL · DEPLETED |
| `UsagePace` | **`Pace`** | prints On track · Running hot · Room to spare |
| `CostUsage` | **`Cost`**, of a kind: `api` · `extraUsage` | the card prints *API COST* or *EXTRA USAGE* — two kinds of money gone, one shape |
| `BudgetStatus` + the API budget setting | **`Budget`** | prints *Daily Budget*, *Claude API Budget* — and ON TRACK · NEAR LIMIT · OVER BUDGET |
| `AccountTier` (`.claudeMax`, `.claudePro`, …) | **`Plan`** | the badge prints MAX · PRO · API; vendors call it a *plan* (Claude Max plan, Coding Plan). A vendor's name does not belong in the shared kernel |
| `ConfigField` (extensions only) | **`Setting`**, in a **`SettingsForm`** | prints *API KEY*, *REGION*, *SETTINGS.JSON PATH*. Every provider's config card is one of these forms |
| `ExtensionManifest` | **`ProviderDefinition`** | the same thing a user makes with *Add Provider*, read from disk instead of a form |

> **One word, two fences.** *Session* means the 5-hour quota window inside
> **Quota**, and a running Claude Code process inside **Activity**. Both are on
> screen and both stay; the fence (§7) is what keeps them from meeting.
> In use's *new terminal sessions* and Usage History's *working sessions* are
> two more; §9 asks for one word each.

## 1 · The tree

```text
Monitor  ◆                                  THE ROOT — what the menu bar is watching. One per app
├── providers: Providers  ◆                THE PROVIDERS YOU KEEP — the Providers pane: add a custom
│                                           one, delete it, their order
├── lineup → [Account]                      DERIVED — the enabled accounts of the enabled providers,
│                                           in that order: the pills, the menu bar, the notifications
├── selection: Provider.ID                  which provider the popover opens on; it shows every login
│                                           of it side by side — the unpaused ones with their quotas, the
│                                           paused ones under PAUSED (multi-account design §3.5)
│   │
│   └── Provider  ◆                         THE PRODUCT — HOW TO FIND OUT, once for all its logins.
│       │                                   Built in, made by the user, or an extension
│       ├── profile: ProviderProfile  ◇     WHO IT IS — the only place an id becomes a face
│       │   ├── id: ProviderID              stable forever; settings are keyed by it
│       │   ├── name                        "DeepSeek"
│       │   ├── look: ProviderLook          symbol · colour · gradient — data, never a switch on id
│       │   ├── links                       dashboard · status page · "Open DeepSeek API Keys"
│       │   └── origin                      builtIn · custom · extension — "Built in · Custom · Extension"
│       ├── isEnabled                       the pane's toggle — off takes the product and every login
│       │                                   of it out of the popover and the menu bar. A different fact
│       │                                   from a login's Pause, which never turns the product off
│       ├── settingsForm: SettingsForm  ◇   WHAT IT NEEDS FROM YOU — [Setting]: API KEY, REGION, ENV
│       │                                   VAR … each says its kind (text · secret · number ·
│       │                                   toggle · choice · path), its default, and its SCOPE:
│       │                                   provider (REGION, ENV VAR NAME) or account (the Codex
│       │                                   folder, an API key) — "Add Account" fills the account
│       │                                   scope. A SECRET is a reference into the vault, never a value
│       ├── dataSource: kind                the one in use — one choice for every login ("DATA SOURCE")
│       ├── dataSources: [DataSource]  ◆    HOW WE FIND OUT — one or more; "DATA SOURCE" picks one
│       │   └── DataSource  ◆               ONE TYPE FOR EVERY PROVIDER — its definition, made live by
│       │       │                           the factory with only the connection its fetch needs
│       │       ├── definition: DataSourceDefinition  ◇   THE JSON — no behaviour:
│       │       │   ├── kind                CLI · API · RPC · Script · HTTP · File — the choices
│       │       │   ├── credential: CredentialLookup?   WHOSE KEY — "TOKEN LOOKUP ORDER": the first
│       │       │   │                       that answers of environment(var) · setting(field) ·
│       │       │   │                       jsonFile(path, fields) · keychain(service) ·
│       │       │   │                       browserCookie(domain) — and how it stays fresh:
│       │       │   │                       refresh: oauth2(tokenURL, clientId, every, on 401)
│       │       │   ├── fetch: Fetch        HOW TO GET THE BYTES — "Data fetching method". A closed sum:
│       │       │   │                       http(request | steps) · jsonRpc(cli, handshake, call, timeout, errors) ·
│       │       │   │                       cli(a TUI, keys) · command(args) · file(path) · script(path)
│       │       │   ├── mapping: Mapping    WHAT THE BYTES SAY — a closed sum:
│       │       │   │                       json(paths, each, used|left, resets) · text(patterns) ·
│       │       │   │                       script(file) — JavaScript in QuickJS, no I/O,
│       │       │   │                       for a format no rule can say (a TUI screen)
│       │       │   │                       · usage — ClaudeBar's own documented output (extensions)
│       │       │   └── fallback: kind?     the data source to try when this one fails — Codex's
│       │       │                           RPC falls back to its terminal
│       │       ├── fetchResponse(for: Account) → Response   "Test Connection" — looks up the key and fetches;
│       │       │                           stops BEFORE mapping, so a person with nothing mapped
│       │       │                           yet can see what came back
│       │       ├── fetchUsage(for: Account) → Usage   "Fetching usage data…" — mapping.read(fetchResponse())
│       │       └── isReady(for: Account)   DERIVED — the key answers and the CLI exists ("Configured")
│       │                                   The ACCOUNT's values fill `{{account.x}}` when the fetch
│       │                                   runs, as the token fills `{{token}}` — one definition,
│       │                                   never a copy per login
│       ├── capabilities  ◇                 WHAT ELSE IT OFFERS (§2.1) — declared in the definition, run
│       │                                   by their own context, handed to each login filled with its
│       │                                   values: `usageHistory` (a UsageLog.Definition) · `accounts.signIn`
│       ├── accounts: Accounts  ◆           NEVER EMPTY. One account is the "default" — the plain login.
│       │   │                               It is SIGNED IN ON THIS MAC; an added one through its folder or
│       │   │                               key, and shows only what that sign-in reaches — never this Mac's
│       │   │                               environment, fixed paths, Keychain names, browser or databases.
│       │   │                               Its logins are INTERCHANGEABLE, and it is the one owner of the
│       │   │                               rule that says so:
│       │   ├── unpaused → [Account]        DERIVED — the logins not paused
│       │   ├── paused → [Account]          DERIVED — the PAUSED group
│       │   ├── status                      DERIVED — unpaused-with-usage .map(status).min(): the product
│       │   │                               has room while one login does. ← THE RULE, one owner
│       │   ├── best → Account?             DERIVED — the unpaused login with the most left: "switch to work"
│       │   ├── cause → Account?            DERIVED — best, while it isn't healthy: the callout's subject
│       │   │                               ("Home is at 18% Weekly — causing Warning")
│       │   ├── pool → Pool?  ◇             DERIVED — the logins' shares, summed: "340% left across 3
│       │   │                               logins" — a SUM OF SHARES, never a forecast, never a
│       │   │                               percentage of a bigger whole; nil below two shares
│       │   │                               ([pool design](../features/providers/quota-pools/design.md))
│       │   └── Account  ◆                  A LOGIN YOU PAY FOR — who, and what we last saw. No behaviour
│       │       ├── id: Account.ID          `<provider>` for the default, `<provider>.<acct>` for an added one
│       │       ├── providerId          its product, by id — a value, never a reference
│       │       ├── label · email           what you gave, or the login file holds — names the pill
│       │       ├── values                  its account-scope settings — the Codex folder, the login's
│       │       │                           account id; a secret as a reference. The default login's
│       │       │                           folder is the definition's `folder.default`
│       │       ├── isPaused                PAUSE without forgetting — no refresh, no pill, no judgement.
│       │       │                           Its last numbers stay, printed as *last seen*. "Remove" forgets
│       │       ├── usage: Usage?  ◇        WHAT WE LAST SAW — survives a failed refresh; carries the
│       │       │                           plan and organization the data source learned
│       │       ├── sync: SyncState  ◇      FETCH HEALTH — isSyncing · lastError: DataSourceError. Never
│       │       │                           erases the usage. The error names its STEP — lookup · fetch ·
│       │       │                           mapping — "Couldn't read your key · Couldn't connect ·
│       │       │                           Couldn't find the numbers" — because each sends you somewhere else
│       │       │   └── needsSetup          DERIVED — "NOT SET UP": no usage yet, and the last refresh found
│       │       │                           no CLI (`cliNotFound`) or no sign-in (`authenticationRequired`).
│       │       │                           Waiting for the person, not failing: the popover shows the
│       │       │                           definition's `setup` (title · text · a button to its url) and
│       │       │                           whatever usage history it can read
│       │       ├── budget: Budget?  ◇      THE USER'S OWN CEILING on this login's Cost — a Daily
│       │       │                           Budget, the Claude API Budget. The vendor sets quotas;
│       │       │                           the user sets budgets. Set in the provider's form
│       │       │                           (account scope), since one login's API spend is not another's
│       │       ├── usageHistory: UsageHistory?  ◆   CAPABILITY (§2.1) — "TODAY'S USAGE" · "DAILY USAGE —
│       │       │   │                       LAST 30 DAYS": WHAT THIS LOGIN USED, DAY BY DAY, from its
│       │       │   │                       tool's own logs on this Mac. Not a meter: nothing is left,
│       │       │   │                       refills or is judged, and the monitor never refreshes it.
│       │       │   │                       `nil` when the definition declares no `usageHistory`
│       │       │   ├── days(in: DateRange) → [Day]   THE ONE READ — every view is a range of it:
│       │       │   │                       TODAY'S USAGE is the last two, the chart the last thirty
│       │       │   ├── ledger: DayLedger  ◇   PAST DAYS, KEPT — a closed day is summed once and kept
│       │       │   │                       on this Mac; only the open days are read from the log
│       │       │   ├── log: UsageLog  ◆    HOW TO EXTRACT IT — the only part that differs per
│       │       │   │   │                   provider. Built by DataSources from the definition's
│       │       │   │   │                   `usageHistory` (a UsageLog.Definition) filled with this
│       │       │   │   │                   login's values (its folder); days(from:to:) reads them:
│       │       │   │   ├── records         WHERE AND HOW — files (a glob), one fixed read-only
│       │       │   │   │   │               command whose JSON answer holds the rows, or one
│       │       │   │   │   │               read-only query of the app's own database · format (a
│       │       │   │   │   │               JSON object per line, or per file) · the record's shape
│       │       │   │   │   │               in the mapping's path language (when, which model,
│       │       │   │   │   │               tokens by kind, its own cost, its identity, its
│       │       │   │   │   │               project — the field of the working directory), or its
│       │       │   │   │   │               `shapes` when the log writes it more than one way,
│       │       │   │   │   │               each read whole
│       │       │   │   ├── prices: PriceList   WHAT A TOKEN COSTS — a price file beside the
│       │       │   │   │                   definition, or a cloud's list through Bedrock's PriceCatalog
│       │       │   │   └── sessionGap: seconds?   a pause longer than this starts a working session
│       │       │   ├── otherApps: [UsageHistory]   OTHER APPS ON THIS MAC that use the same plan and keep
│       │       │   │                       their own count — Claude Desktop's daily total. Each its own
│       │       │   │                       history, label and ledger, never summed with this one's days.
│       │       │   │                       The definition's `usageHistory.otherApps`; the apps belong
│       │       │   │                       to this Mac, so only the default login reads them
│       │       │   └── Day  ◇              ONE DAY — date (local) · THE SUM OF ITS LINES: one line
│       │       │                           per model, a line holding what the day holds — tokens
│       │       │                           input · output · cache write · cache read · cost
│       │       │                           (ESTIMATED unless the log states it); records with no
│       │       │                           model form one unnamed line · one line per project
│       │       │                           when the log names the working directory · sessions ·
│       │       │                           time · cache savings
│       │       ├── guestPasses: GuestPasses?   CAPABILITY — "share a trial": declared `"guestPasses": { "plans": [...] }`,
│       │       │                           run by the engine; offered to those plans only; `nil` when not declared
│       │       └── status                  DERIVED — QUOTA HEALTH: the worst quota in its usage.
│       │                                   The pill's and the menu-bar entry's colour
│       ├── inUse: InUse?  ◆                CAPABILITY (§2.1) — "New terminal sessions use work":
│       │   │                               WHICH LOGIN THE NEXT `claude` / `codex` STARTS WITH. Not the
│       │   │                               monitor's: every login is still fetched and shown. `nil` when
│       │   │                               the definition's `accounts.signIn` names no folder variable
│       │   ├── login: Account              the one in use — the plain login until another is chosen
│       │   ├── logins: [Account]           the plain login and every folder login; a choice when > 1
│       │   ├── command: TerminalCommand ◇  `claude` + `CLAUDE_CONFIG_DIR` — from `accounts.signIn`
│       │   ├── worthSwitchingTo: Account?  DERIVED — the login in use is low, another has more left
│       │   └── switchWhenLow: SwitchWhenLow  ◆   opt-in: isOn · below · mayPick(login)
│       └── status                          DERIVED → accounts.status (tell, don't ask)
│
└── statusPolicy: StatusPolicy  ◇           HOW STRICT TO BE — absolute thresholds, or pace-aware:
                                            warn when it runs out before it resets. ONE for the app
                                            (General): every surface — menu bar, pill, card, Touch
                                            Bar, notch, notifications, status export — reads the
                                            same status. Colours are not policy: they are the page's

Usage  ◇                                    "Fetching usage data…" — WHAT THE PROVIDER SAYS, AS OF A MOMENT
├── updatedAt                               "Updated 3m ago"; stale after 5 minutes
├── source: kind                            "via RPC" · "via Terminal" — which data source answered,
│                                           so a fallback is never silent
├── quotas: [Quota]
│   └── Quota  ◇                            ONE LIMIT THE VENDOR SET
│       ├── name                            Session · Weekly · Opus · Monthly · Balance · Credits
│       ├── group?                          the card section, when one provider spans several
│       │                                   upstream accounts ("Claude · work")
│       ├── left: Left                      A CLOSED SUM OF TWO:
│       │                                     share(Percent)            "62% left"
│       │                                     money(Money, of: Money?)  "$12.40 remaining", "of $50"
│       ├── window: Window?                 WHEN IT REFILLS — length + resetsAt. "Resets in 2h 5m".
│       │                                   A prepaid balance has none
│       ├── rate: SpendRate?     DERIVED    HOW FAST IT IS SPENT — used share ÷ share of the window
│       │                                   gone. nil without a length + reset, for a balance with
│       │                                   no ceiling, and under 3% of the window (noise)
│       ├── forecast: Forecast?  DERIVED    "Lasts until it resets" or "Runs out in 38m — 34m before
│       │                                   it resets": the rate carried forward to zero. nil
│       │                                   without a rate, and once the quota is used up
│       ├── status                          DERIVED — Left × StatusPolicy (× rate, when pace-aware)
│       └── pace                            DERIVED — reads the rate; otherwise unknown
├── cost: Cost?  ◇                          MONEY GONE — "API COST" or "EXTRA USAGE", over a period.
│                                           Judged by a Budget, never by a Quota
└── account facts                           email · organization · plan, when the data source learns them —
                                            the screen prefers these to what the Account was given

Response  ◇                                 "Response" — WHAT CAME BACK, before anyone read it:
                                            status · headers · body. The Map fields step shows it

    DELIBERATELY OUTSIDE THE MONITOR
Activity  ◆                                 Claude Code sessions seen through hooks — the notch
Usage History                               the context that runs each login's `usageHistory` —
                                            outside the monitor: read when the popover opens
New sessions  ◆                             In use's shell side — the lines that make `claude` start on the
                                            login in use; a choice waits for them. Follows refreshes
                                            through the Monitor's one extension point, `onRefreshed`
Rest when empty  ◆                          the products asked to rest while empty, each with one saved
                                            `WhenEmpty`: watching · resting(since:) · shownAnyway. Follows
                                            refreshes through `onRefreshed`; judges *empty* by
                                            `monitor.status(of: provider)`; never touches the switch
Destinations                                notifications · your quota alerts · status alerts · signed out · webhooks · Notify! · live activity · status export ·
                                            the local API (asked, not told: it reads the All page's Overview)

    NOT IN THE MODEL (the page's)
MenuBarLabel · display mode (left/used) · countdown colon · popover height · theme ·
provider pills · card titles shortened for width
```

## 2 · A provider is DATA; one DataSource type fetches for all of them

The user's sentence is the design: *a provider only needs to know how to fetch
the data and how to read the usage.* "Knows how" is a DEFINITION, not a class.
Everything else a provider has today — the syncing flag, the last error, the
enabled toggle, the account switch, the settings plumbing, the icon — is the
same for all of them, so it is written once and a provider does not get a say.

Take Codex. Its two probes do five jobs between them, and **not one of them is
Codex logic**:

| The job | What `CodexAPIUsageProbe` / `CodexUsageProbe` hard-code | What it really is |
|---|---|---|
| whose key | read `~/.codex/auth.json` → `tokens.access_token`, `tokens.account_id` | `credential: jsonFile(path, fields)` |
| keep it fresh | refresh-token grant to `auth.openai.com/oauth/token` after 8 days or on 401, write it back | `refresh: oauth2(tokenURL, clientId, every: 8d, on: 401)` |
| get the bytes | `GET chatgpt.com/backend-api/wham/usage` with three headers · or spawn `codex app-server`, JSON-RPC `initialize` → `initialized` → `account/rateLimits/read` | `fetch: http(…)` · `fetch: jsonRpc(…)` |
| when that fails | scrape the terminal for `5h limit … 62% left` | `fallback` to a `terminal` fetch + `text` mapping |
| what it says | `used_percent` → left, `reset_at` / `reset_after_seconds` → resets, `additional_rate_limits[]` → more quotas, `codex_` prefix dropped | `mapping: json(…)` |

So every provider is ONE KIND OF THING — a definition — and ONE `DataSource`
type does the fetching for all of them: `dataSource.fetchUsage()` looks up
the key, fetches, maps. Each CASE of the three closed sums (`CredentialLookup`
· `Fetch` · `Mapping`) is carried out by one worker with one job, named for its
protocol or format, never for a vendor.

**Why closed sums.** The JSON decoder must know every tag, and the *Add
Provider* sheet offers a fixed list. A new provider is a JSON file — open, no
Swift. A new protocol (say gRPC) is a new case and one new worker: a
deliberate change to a closed list, which is honest, because a new picker
option, decoder tag and form come with it anyway.

**When a vendor really is different** — Bedrock reads AWS CloudWatch through
the AWS SDK; another signs its requests with its own scheme — the difference
is still ONE job, so it is still one case with one worker named for the
technology or the scheme (`Fetch.cloudWatch`, a signature case named for its
algorithm), taking its parameters from the JSON. There is never a type that
does all five jobs for one vendor.

| Origin — the badge the screen prints | Definition lives in | Made by |
|---|---|---|
| **Built in** | `Resources/Providers/<id>.json`, shipped in the app | us |
| **Custom** | `~/.claudebar/providers/<id>.json` | the person, in *Add Provider*, *Copy a provider* or *Import* |
| **Extension** | `~/.claudebar/extensions/<id>/manifest.json` — a `script` fetch | the person, by hand |

The three differ only in *where the file is*. Codex, DeepSeek and a provider
someone made five minutes ago run on the same `DataSource` and the same lifecycle.

## 2.1 · What a provider OWNS, what it OFFERS, and what it isn't

A provider is **the product you pay for, under one or more logins**. Its
abilities fall in three groups, and a new ability is placed by asking which
question it answers for the person.

**Owned** — rules only the provider can keep, because only it sees every login:

| Ability | The rule it keeps |
|---|---|
| identity — name, look, links | the id is stable forever; its face and links are data |
| its logins — add (form · folder · sign-in), remove, rename, reorder | never empty; the default login's id is the provider's; no two logins share a folder |
| its settings | a kind owns its rule; an account's own value beats the provider's; a change rebinds the logins |
| how it finds out — data source choice, fallback, refresh per login, *Test Connection* | the last usage survives a failure; the failed step is named; a 429 is a rate limit; a fallback is never silent |
| derived reads — status, best account, cause | its logins are a pool: the healthiest login's status; the best is the one with the most left |

**Offered** — CAPABILITIES. Each answers *another* question, on its own
cadence and often with its own store, so the provider only **declares** it in
its definition and **hands it out per login**; its own context runs it:

| Capability | The person's question | Declared as | Run by | Reached as |
|---|---|---|---|---|
| Usage History | *how much did I use, day by day?* | `usageHistory` | the login's `UsageHistory`, over a `UsageLog` the data-source machinery runs | `account.usageHistory` → `days(in:)` |
| Guest passes | *can I share a trial?* | `"guestPasses": { "plans": ["claudeMax", "ULTRA"] }` — Claude's alone, offered to the plans it names; its runner is supplied by the engine ([TARGET §10](TARGET_ARCHITECTURE.md#10--a-definition-on-disk-is-a-provider)) | `ClaudeGuestPassSource`, at the declaring definition's CLI | `account.guestPasses` |
| Budget | *am I spending more than I meant to?* | an account-scope setting on the cost | the cost judges it | `account.budget` |
| Sign-in | *add another login* | `accounts.signIn` | `AccountSignIn` | `provider.signIn` |
| In use | *which login does my next terminal session start with?* | `accounts.signIn` — its CLI and the variable that points it at a folder | `InUse` over the `LoginsInUse` record; `NewSessions` over the `ShellLines` port for the shell | `provider.inUse` · `account.isInUse` |

To check their usage history, the person picks a login and the page asks
`account.usageHistory?.days(in: .last(30))`: the provider filled that login's
`usageHistory` with its own values (its folder), and it answers from its
ledger and that login's logs. Two logins show two histories, never summed.

**The rule that keeps it open (OCP):** *how much is left?* is a data source in
the definition — the provider does not change. Any other question is a
capability: a block in the definition, the machinery that runs it, and an
optional handle on `Account` that is `nil` when the definition does not
declare it. A page asks the handle — `account.usageHistory?` — never the
provider's id, and never `definition.usageHistory != nil` (tell, don't ask). A
capability is never chosen in Swift by a provider's name.

**Not the provider's**: the lineup, the selection, the status policy and
alerts (Monitoring, Alerting); menu-bar text and card titles (the page);
Claude Code sessions (Activity); where settings and secrets are kept
(Storage — the provider uses its ports).

## 3 · The commands, and the node each lands on

| The user does | The node is told | Notes |
|---|---|---|
| toggles a provider in Providers | `provider.enable()` · `disable()` | every login of it; the pane keeps its place |
| turns on *Rest when empty* (a product's page in Providers) | `restWhenEmpty.turn(_:product:)` | off by default, per product: the product rests, dimmed, while every counted login is out, and is back at the first refresh that shows room ([design](../features/monitoring/rest-when-empty/design.md)) |
| clicks *Show anyway* on a resting product | `restWhenEmpty.showAnyway(product)` | drawn as usual until it has had room; saved, so a relaunch keeps it |
| toggles one account | `monitor.pause(_:)` · `resume(_:)` → `account.pause()` · `resume()` | pauses that login — no refresh, no pill, no judgement — and keeps its settings. The popover's account menu and the Accounts card are two doors to the same one; the selection never lands on a login that is off the page |
| drags the pane's order | `monitor.providers.move(_:to:)` | the lineup follows |
| picks DATA SOURCE | `provider.use(_ kind:)` | one data source active at a time |
| fills API KEY, REGION … | `provider.settings.set(_:to:)` | a secret goes to the vault; the form keeps the reference |
| *Add Account* · *Remove* | `provider.add(account:)` — fills the form's account scope · `provider.remove(account:)` | never removes the default; removing forgets the account's settings, never its CLI's login files |
| clicks a provider pill | `monitor.select(_ provider:)` | the popover shows all its enabled accounts |
| refreshes | `monitor.refresh(_:kind:)` → `provider.refresh(account, kind)` | interactive or background; one account's fetch |
| *Add Provider* → *Start from* | `ProviderDefinition.blank(fetch:)` · `definition.copy()` | the picker is `http` · `cli` · `file`; a copy gets a new id and the origin **custom** |
| *Connect* → *Test Connection* | `dataSource.fetchResponse(for: account)` → a `Response` or a `DataSourceError` | nothing is mapped yet, nothing is saved |
| *Map fields* — clicks a value | `mapping.quotas.append(…)` / `mapping.cost = …` with *Used · Remaining · Limit · Resets* | the card previews live from the same `Response` |
| *Save* | `catalog.add(definition)` → `monitor.lineup.append` | no restart |
| *Edit* · *Delete* a custom provider | `catalog.replace(definition)` · `catalog.remove(id)` | built-ins can only be disabled |
| *Export…* | `definition.exported()` → a `.json` file | carries the lookup order and the setting names — never a key |
| *Import provider* | `catalog.import(file)` → `definition.missingSettings` | says where a key will be sent, and shows a CLI command, BEFORE asking |
| *Use* on a chip, *Use for New Terminal Sessions* (right-click), the Settings radio, `claudebar://use`, a notification | `newSessions.use(account)` → `provider.inUse.use(account)` | waits for the shell lines when they aren't there; the plain login never waits |
| *Add to ~/.zshrc* · *Copy — I'll Add It* · *Remove* | `newSessions.setUp()` · `setUpByHand()` · `turnOff()` | the lines are shown before they are written |
| turns on *Switch when low*, sets its threshold, unticks a login | `inUse.switchWhenLow.isOn` · `.below` · `.setMayPick(_:_:)` | off by default |
| sets a Daily Budget · the Claude API Budget | `account.budget = …` (an account-scope setting) | judges that login's cost only |
| turns on *Warn when a quota will run out before it resets* | `monitor.statusPolicy = …` | every status and every alert follows at once |
| adds or removes an alert percentage | `quotaAlerts.add(_:)` · `remove(_:)` | whole percents 1–99; 20% and 0% are refused, the status alerts already say them |
| *Add Webhook* · *Edit* · *Remove* · its switch · *Send a test* | `webhooks.add(url:…)` · `edit(_:url:…)` · `remove(_:)` · `turn(_:on:)` · `sendTest(_:)` | an http URL is refused unless it is local; a test is labelled a test, never an alert ([design](../features/alerting/webhooks/design.md)) |
| chooses status colours · high contrast | — the page's theme | how a status looks, never what it is |

## 4 · The reads — what the tree answers

```text
monitor.overallStatus                → Status       the menu bar's colour: the worst PRODUCT's status
monitor.lowestQuota                  → Quota?       each enabled product's best account's lowest quota; the lowest of those
monitor.lineup                       → [Account]    the pills and the menu-bar entries
account.usage                        → Usage?       that login's latest — what its pill shows
account.status                       → Status       QUOTA HEALTH: the worst quota in that usage
account.sync.lastError               → DataSourceError?  FETCH HEALTH: which step failed — never a Status
provider.status                      → Status       → accounts.status: the healthiest unpaused login (min)
monitor.status(of: provider)         → Status?      the healthiest counted login (min), under the
                                                    policy; nil with no usage. overallStatus,
                                                    selectedTabStatus and rest all read it:
                                                    depleted only when every counted login is
provider.accounts.best               → Account?     the most left — "switch to work"
provider.accounts.cause              → Account?     best, while it isn't healthy — the callout
provider.accounts.pool               → Pool?        the logins' shares summed — "340% left across 3 logins"
provider.inUse?.login                → Account      the login new terminal sessions start with
account.isInUse · account.canBeInUse → Bool         the chip's mark; whether it can be chosen
newSessions.state(of: provider)      → State?       the strip: waiting for setup · worth switching · in use
usage.quota(named:)                  → Quota?
usage.isStale                        → Bool         older than 5 minutes
quota.status(under: StatusPolicy)    → Status
quota.pace                           → Pace         unknown without a window
quota.rate                           → SpendRate?   how fast it is spent against its window
quota.forecast                       → Forecast?    lasts until it resets, or runs out N before it
quota.window?.timeUntilReset         → Duration?    "Resets in 2h 5m"
account.budgetStatus                 → BudgetStatus? ON TRACK · NEAR LIMIT · OVER BUDGET —
                                                    usage.cost judged by account.budget
tab.logins                           → [Account]    the product's logins, unpaused and paused, in the
                                                    person's order — the popover's page
tab.unpaused                         → [Account]    the ones not paused: its chips, its cards, and every
                                                    aggregate (status, badge, alert, menu bar)
tab.paused                           → [Account]    the PAUSED group — the exception, named
dataSource.fetchResponse(for:)       → Response     Test Connection: what came back, unmapped
mapping.read(response)               → Usage        Map fields: the live card
definition.missingSettings           → [Setting]    Import: "Key needed"
```

## 5 · The laws, on the node that owns them

| Law | Owner |
|---|---|
| a provider's id is stable forever; settings, the menu-bar choice and the lineup are keyed by it. A custom provider's id is minted once and never derived from its name | `ProviderProfile` |
| a provider's face is DATA — its symbol and colours ride on the profile, so adding one never edits a `switch id` | `ProviderLook` |
| a provider has at least one account; the `default` account's id equals the provider id, an added one's is `<provider>.<acct>` — the ids today's settings and menu-bar pins are keyed by | `Provider.accounts` |
| a provider is the PRODUCT and an account a LOGIN: how to fetch, the data source choice, the look and the provider-scope settings are the provider's, once; who, its values, what we saw and whether the last fetch worked are the account's | `Provider` · `Account` |
| a login knows only itself: it names its product by id and never refers to it; anything product-level about a login is asked of its provider, found through `Providers.provider(of:)` — a stale login never crashes, nothing leaks | `Account` · `Providers` |
| accounts are SIMULTANEOUS — every enabled login is fetched and shown side by side under its provider; the popover shows the selected provider's. (A vendor that allows one live login at a time would add an `active` account; none does today) | `Monitor.selection` |
| one definition serves every account: the account's values fill `{{account.x}}` when the fetch runs; a data source is never copied per login | `DataSource` |
| **an account shows only what its own sign-in reaches** ([USER_JOURNEYS F13](USER_JOURNEYS.md)): a definition is written once, for any account. The default account is signed in on this Mac — its folder is `folder.default`, and every read is reached. An added account is signed in through its folder or key: a read that names nothing of it — an environment variable, a fixed path or Keychain name, browser cookies, a local database or log — is not reached, whatever its definition forgets ([multi-account design](../features/providers/multi-account/design.md#what-an-accounts-sign-in-reaches)) | `ProviderDefinition.dataSources(for:)` — the definition read for one account |
| status is QUOTA health, derived from usage; a failed fetch is FETCH health, in `sync` — a key that expired never turns the menu bar red | `Account.status` · `Account.sync` |
| **a product's logins are INTERCHANGEABLE** — a pool: the product reads its healthiest unpaused login (min), so one empty login never holds its product at DEPLETED while another has room; it reads DEPLETED only when every one is empty. Products are not: one product's room never covers another's, so the menu bar reads the worst product (max). Every login keeps its own truth — its row, pill and alert say its own status and when it resets. A login with no usage yet never stands for its product | `Accounts.status` · `Monitor.overallStatus` |
| **the pool's total is a SUM OF SHARES** — each unpaused login brings the share it already shows (its tightest window's); a login with nothing seen, or with only a balance and no ceiling, brings nothing, and is never guessed at zero or a hundred. Over 100 is fine and meaningful — the logins refill independently — and the sum is never a forecast and never a percentage of a bigger whole; it exists from two shares, so one login with room is its own card ([pool design](../features/providers/quota-pools/design.md)) | `Pool` · `Accounts.pool` |
| *in use* is the TERMINAL's choice, not the monitor's: every enabled login is still fetched and shown; only new `claude` / `codex` sessions start on the login in use. It is not the `active` account the law above rules out | `InUse` |
| the login in use is the plain login or a folder login of the same product; only its folder is recorded, nowhere else, **under its CLI's name** (`in-use/claude`) — the shell starts a CLI, not a product; nothing recorded, or a folder no login has, is the plain login; removing it goes back to the plain login | `InUse` · `LoginsInUse` |
| **a CLI is wrapped once**, however many products run it: two products on `claude` share its record, and the last choice wins | `NewSessions` (its commands, each once) · `ShellSetup` |
| a choice waits for the shell lines, and the plain login never waits; turning off removes the lines and puts every CLI back on its plain login | `NewSessions` |
| *Switch when low* is off until turned on, moves only below its threshold, only to a ticked login with more left, and never touches a running session; a login worth switching to is told once per low | `SwitchWhenLow` · `InUse.review` |
| the Monitor knows nothing that follows a refresh: In use, and anything after it, observes through `onRefreshed` — or `onRefreshFailed` for a refresh that failed, never a paused login's | `QuotaMonitor` |
| a quota alert says once that a login fell below one of the person's percentages, and again only after it climbed back a point above it | `QuotaAlerts` |
| a quota alert judges what the person sees: the lowest share left among the login's quotas not hidden; a balance with no ceiling has no share and is never judged | `QuotaAlerts` |
| a quota alert names the login (*Claude · work*), never only the product, once a product has several | `QuotaAlerts` |
| a status alert says when a login's status got worse under the policy and is not healthy, once per worsening; the first status seen is compared with healthy ([design](../features/alerting/status-alerts/design.md)) | `StatusAlerts` |
| a login is SIGNED OUT when a refresh failed with `sessionExpired` (its last error, as the card shows it) — told once per sign-out, forgotten at the next refresh with no error; never a forecast, since no store records when a sign-in will end ([design](../features/alerting/signed-out/design.md)) | `SignedOutAlerts` |
| an alert names the login by its `lineupName` and carries its provider id; every alert goes to every destination, and no destination decides whether a login is low | `Alert` · `AlertDestinations` |
| a webhook wants an alert when it is on, sends that kind, and the alert's provider is in its scope; it has no percent of its own ([design](../features/alerting/webhooks/design.md)) | `Webhook` |
| how an alert or a test reads in Slack and as JSON; a test is never shaped like an alert | `WebhookBody` |
| how the week's recap reads in Slack and as JSON, from the same `Recap` the card reads ([design](../features/alerting/recap-alerts/design.md)) | `WebhookBody` |
| a webhook URL is https, or http only to a loopback or LAN host | `WebhookAddress` |
| one POST per alert, no retry; a redirect stays on the URL's origin; nothing that could carry the URL reaches a log or the pane | `WebhookClient` |
| a destination's secret (Notify!'s token, a webhook's URL) is never in `settings.json` or a log — webhooks keep the rest under `alerts.webhooks`; one the Keychain refuses falls back to the app credential store, read Keychain first, and the pane says so — one copy of that rule for every destination | `DestinationSecrets` |
| one provider per id; the order is the pane's, saved, a provider's logins together; only a provider you made can be deleted — a built-in is turned off. The Monitor never adds, deletes or orders one | `Providers` |
| a paused account is PAUSED, not forgotten, and is out of every judgement: no refresh, no status, no badge, no alert, no menu-bar name, and no say in its product's status. What it keeps is its last numbers, printed as *last seen* — and a fetch that lands while the login is paused lands nowhere: nothing recorded, success or failure, and nothing published. The refusal is an **outcome** (`UsageError.paused`), never an empty answer dressed as usage | `Account.isPaused` |
| a product is off only when the person turns it off. Pausing every login of it leaves its tab, dimmed, with *Resume* — pause and the switch are two facts, and a login never leaves the popover without saying which one happened. | `Provider.isEnabled` · `QuotaMonitor.tabs` |
| a product asked to *rest when empty* rests while its status is depleted: dimmed and labelled *RESTING*, never hidden and never switched off. Where it is (watching, resting since a moment, shown anyway) is one saved value, moved only by an observed refresh or by the person: a failed fetch neither rests nor wakes it, and *Show anyway* holds until it has had room ([design](../features/monitoring/rest-when-empty/design.md)) | `WhenEmpty.after` · `RestWhenEmpty` |
| a product whose every login is paused reads *PAUSED*, never *NO DATA* — it stopped looking, which is not the same as having nothing to show | `ProviderBadgeState.paused` |
| a failed refresh keeps the last usage and records the error beside it — what we saw is never erased by failing to look again | `Account.sync` |
| at most one refresh per account is in flight | `Provider` |
| exactly one data source is active per provider; switching never loses settings the other one needs | `Provider.dataSources` |
| a data source reads settings only through its form; it never writes settings and never reads another provider's | `DataSource` · `SettingsForm` |
| a secret never appears in `settings.json`, a log line, an error message or a test fixture — the form holds a reference, the vault the value, and the vault falls back when the Keychain refuses an ad-hoc build; the log holds no credential however it arrived: `DataSource` registers every credential it touches, `AppLog` scrubs every line before a sink sees it | `Setting` · `SecretVault` · `DataSource` · `AppLog` |
| **`left` is ONE OF TWO**: a share, or money. A balance with no ceiling has NO percentage — writing 100% is a lie the status then believes | `Quota.left` |
| money keeps its currency; two currencies are never added or compared | `Money` |
| **a window's length is the provider's word**, never guessed from a quota's name — the Codex RPC's primary window can be the weekly one | `Window` |
| pace exists only inside a window with a reset; outside it is `unknown`, never `onPace` | `Quota.pace` |
| **ONE rate per quota**: how fast it is spent against its window — one used share (from `left`, so a capped money quota by its money), one noise floor (3% of the window) — and pace, the pace tick, the pace-aware status and the forecast all read it, never their own copy | `SpendRate` · `Quota.rate` |
| a quota runs out before its reset ⇔ it is used more than 5 points ahead of the share of its window gone; within 5 either side it is on the line. ONE rule, read by Pace, the forecast and the pace-aware status | `SpendRate.runsOutBeforeReset` |
| a forecast is a READ of the rate over the CURRENT window — never stored on `Usage`; it lasts until the reset unless it runs out first, and *Running hot* ⇔ it runs out first, so a card never says both *On track* and *Runs out* | `Forecast` · `UsagePace` |
| no forecast without a rate, or once the quota is used up — it has already run out; never a number invented from nothing | `Forecast` |
| a forecast is said *at this pace*: the window's average, not the next burst | `QuotaCardText` |
| depleted at 0, critical under 20 — ABSOLUTE, whatever the policy | `StatusPolicy` |
| a quota's status under the pace-aware policy warns exactly when it runs out before its reset, from 20% left up; without a rate it is the absolute answer ([design](../features/quota/status-colors/design.md)) | `StatusPolicy` reading `SpendRate` |
| ONE status per quota: the menu bar, the cards, the Touch Bar, the notch, the status export, the local API and the notifications all read `quota.status(under: monitor.statusPolicy)` — never their own copy of the rule | `StatusPolicy` · `Monitor` |
| a quota is the vendor's ceiling; a budget is the user's. A Cost is judged by a Budget, never shown as a Quota. A budget judges ONE account's cost — two logins' spend is never summed against it | `Cost` · `Account.budget` |
| usage is stale 5 minutes after it was updated | `Usage` |
| a background refresh is never faster than the slowest provider's floor, and slower on battery | `Monitor` |
| a data source's definition is DATA; the code behind it is one worker per case, with ONE job, named for a protocol or format — never a vendor | `DataSource` |
| a data source is handed only the connection its fetch needs — an HTTP fetch never holds a CLI | `DataSources` (the factory) |
| a new provider is never a code change; a new protocol or format is one new case and one worker | `Fetch` · `Mapping` · `CredentialLookup` |
| a case answers for itself — where it sends a key, what it runs, where its CLI lives; nothing outside it switches over the cases but the factory. Tell, don't ask: no caller reads a node's state to decide what the node could decide | `Fetch` (each case's `Connection`) |
| a path has one interpretation for credentials, context, recovery, required files, fetches and logs: `{{platform.appData}}` is a platform fact, `~` and `${VAR:-default}` keep their meaning, and a wildcard chooses the newest matching file; a missing platform folder remains a missing path, never the disk root | `Paths` · `DataSources` (facts from `Platform`) |
| **a fetch always ends**: every case that waits on a CLI or a server has a deadline — its `timeout` (the definition's, or the case's default), or for `cloudWatch` the AWS SDK's own; at it a stalled CLI is stopped and the fetch fails with *Request timed out*, so the fallback runs and a refresh never syncs forever (#517). Before a CLI starts, the login shell asked where it is and for its `PATH` has 10s; a shell still running then is stopped and the common folders and the app's own `PATH` answer instead, and its output is read until it exits, not until a program it started lets go (#550). Stopping a child is bounded too: asked, made after 2s (1s for the login shell), and left (logged by name and pid) if it is still there 2s after `SIGKILL`, so the stop the deadline makes can't become the wait (#550) | `Fetch` (each case's timeout) · `BinaryLocator` · `ChildTeardown` |
| a setting's kind owns its rule — a secret has no default and lives in the vault, a choice takes only its options, a path can be required to exist; the setting says what a blank means | `Setting.kind` |
| a choice's options carry their values (*China → kimi.com*), used by name — `{{setting.region.site}}` — wherever a fetch needs them; an account's own value wins over the provider's | `Setting` |
| two logins of a provider never share a path setting — the default login's included | `Provider.accounts` |
| a worker reports a fact (a status, an exit code, a missing CLI) and the definition's `errors` says what it means, in a reason the screen prints — never from the response body or a secret; a 429 stays a rate limit | `DataSource` · `DataSourceError` |
| a credential is looked up in the order the definition gives; the first that answers wins, and a refreshed token is written back where it was found | `CredentialLookup` |
| **a fetch keeps to the origin it named** — a redirect that leaves it (another host, port or scheme) is not followed, key or no key, and the 3xx itself becomes the answer; a credential is never re-sent to a server the fetch didn't name | `NetworkClient` |
| when the active data source fails, its `fallback` is tried once; what the popover shows says which one answered. A signed-out login (*Authentication required*, *Session expired*) is not tried again on a fallback that reads the same login (`fallback.sameLogin`, #525) | `Provider` |
| a data source held until checked (`verifyBeforeBackground`, #216) starts nothing in the background until a click succeeds; a signed-out answer holds it back again (#525). It holds the default login: an added login is checked by being added, and never marks or forgets the default's check | `Provider` |
| a definition is valid before it is saved: a fetch, a mapping that produced at least one quota or a cost on Test, and every required setting filled | `ProviderDefinition` |
| a built-in provider can be disabled but not deleted; a custom one can be both; an extension is removed by removing its folder | `ProviderCatalog` |
| **an exported definition carries no secret** — the lookup order and each setting's name, never its value | `ProviderDefinition` |
| an import says where a key will be sent, and shows any CLI command it will run, before it asks for a key or saves | `ProviderCatalog.import` |
| an error names the step that failed — lookup, fetch or mapping — and never carries the secret or the response body | `DataSourceError` |
| a usage says which data source produced it; a fallback is never silent | `Usage.source` |
| a tool's usage history is DATA: where its logs are, how to read a record and what a token costs live in its definition; a new tool's logs, or a price change, never edit Swift | `UsageLog.Definition` |
| usage history is a SERIES OF DAYS; every view — today against yesterday, the last thirty days, a chart — is a range of it, chosen by the page | `UsageHistory.days(in:)` |
| a day is the local calendar day; a record counts on the day its own timestamp falls in — a timestamp written in UTC (a file name) is converted, never read as local | `Day` |
| a record written twice counts once — the last copy wins (a streamed message is logged as it grows) | `UsageLog.records` |
| a record is read by the first shape whose `where` holds; one shape's paths never answer for another's record | `UsageLog.Records` |
| a log's records come from FILES or from ONE COMMAND — the two cases of one sum, so "both" and "neither" cannot be written; a command's records carry no `format`, because the answer's layout is the reader's business | `UsageLog.Records.source` |
| a reader is TOLD what to read, never asked what it holds: `records(since:)` is one method every reader answers, a file reader finding its own files and the command reader running its command, so no caller branches on which kind of log it has | `LogReader` |
| the range asked for is cut by `days(in:)`, NEVER by the log: a log answers from `since` on, and a query that bounds itself below the range asked would have its older days read as empty and kept that way for good | `UsageLog.days(in:)` |
| a day closes a fixed while after it ends; a closed day is summed once, kept, and never read from the logs again. Today, and the day before until it closes, are read every time | `DayLedger` |
| a day is THE SUM OF ITS LINES: one line per model, a line holding what the day holds — the model's tokens by kind and its cost. The log's own cost wins; otherwise cost is ESTIMATED from the price catalog, and says so. A model served on this Mac costs nothing; an unknown model gets the catalog's fallback price, never zero by omission. Records with no model form one unnamed line, so the lines always add up to the day | `Day.lines` · `PriceList` |
| a range of days answers the page's questions — which models, in order; a day's lines, largest first; its total in a unit; which units it offers — so a view renders and tells. The unit is the view's choice (cost, tokens, cache), and COST is offered only when the log prices its records and a day holds a cost: a log that writes zero everywhere has nothing to say in dollars ; what caching saved over the range | `Days` |
| what a part of a day spent — tokens by kind and their cost — adds up field by field, so a sum over days never drops a field, and reads itself in a unit | `Spend` |
| a line of a day's split is its key and its spend — a model (`ModelUsageLine`) or a project (`ProjectUsageLine`); two lines of one key add up to one | `UsageLine` |
| a range's mix is each line summed over it, largest first, the unnamed part included so the parts add up; each part carries its share — a page that needs a top model or project reads it here, and the unnamed part is never the top. `ModelMix` and `ByProject` are this one mix, each with its own key | `UsageMix` |
| a day keeps its named project lines only, each named by its working directory's last path component; its project split is those and the remainder — the day less them, when that is anything — so the parts add up to the day, and a day that names no project is all remainder; a path is never kept or shown, only its last component ([quota-by-project](../features/usage-history/quota-by-project/design.md)) | `DailyUsageStat` (`projects`, `projectSplit`) · `ProjectUsageLine` |
| a day's share is its value against the range's busiest; a range with nothing used has no busiest day, and every share is 0. The shading band a heatmap draws is the App's | `DayActivity` |
| usage history is per login: an added login reads its own folder's logs; two logins' days are never summed | `Account.usageHistory` |
| a week is the calendar's week holding a day, from the calendar's own first weekday; the range before a range is the same length, one run earlier | `DateRange` (`week`, `before`) |
| two days of one date add up to one day: every count, the cost, the time, the savings, one line per model, one per named project — so several ranges read as one (`Days.merged`) never drop a field, and a day with a split added to one without keeps the other's spend in its remainder | `DailyUsageStat` (`+`) |
| a RECAP is the one read that sums across logins, for the person's total, and names the providers it spans — two logins of one provider are one part; a login's own chart stays its own. It reads in the unit every range offers: cost only when every provider that used anything, this range or the one before, offers cost, tokens otherwise; its change is against the range before, in that unit, and none when nothing was used before; its top model is `ModelMix`'s and its biggest day `DayActivity`'s, over the providers' days merged | `Recap` |
| a recap's span is a period, a week or a month; the period before is the one holding the day before it starts — one rule for both; a recap carries the days it sums | `RecapPeriod` · `RecapRange` · `Recap.range` |
| the recap is read again only when a week or month turned or a login's days were read again since its last read; the page tells it when usage was read and never decides | `Recaps` |
| a week's recap goes out once, at the first refresh after the calendar's week turned, for the week that closed; the due answer is pure (`now`, the last send, the calendar), the send is read through `Recaps` and checked against the recap's own range, and a week that added up to nothing says nothing ([design](../features/alerting/recap-alerts/design.md)) | `RecapDue` · `RecapAlerts` |
| the week's recap is not an `Alert` — an alert names a login and its provider, the recap names the week; it goes to its own destination port, and a webhook wants it when it is on and sends recaps, scope unjudged | `RecapAlert` · `RecapDestination` · `Webhook.wants` |
| a capability is declared by the definition — even one only a single product has (guest passes), whose runner the engine supplies — never chosen by a provider's name, never a vendor name in a module. Either way it is reached through the login's handle (`account.usageHistory`, `account.guestPasses`), `nil` when not offered | `Account` |
| usage history is read when the popover opens, never in the background, and never carried on `Usage`; the year only while a section that shows it is on | `UsageHistory` |
| which usage sections the popover shows — *Today*, *Last 30 days*, *Last year*, *Model mix*, *Recap* — and their defaults: the year's two hidden, the rest shown, until the person chooses | `UsageSection` · `AppSettingsRepository` |
| another app's usage on this Mac (Claude Desktop) is its OWN history under its own name: never summed with the login's days, never a data source, never a quota; the default login reads it; it is this Mac's, so an added login never does | `UsageHistory.otherApps` |
| a login with no usage whose CLI isn't on this Mac, or that never signed in, is NOT SET UP — fetch health, not a failure: it says what setting up takes, keeps showing the usage history it can read, and the badge reads *NOT SET UP*, not *UNAVAILABLE* — or nothing, while that usage history shows: a Claude Desktop user did set Claude up, only the limits need more. Any other failure stays an error | `Account.needsSetup` · `ProviderBadgeState` |
| a day with nothing is an empty day, not a missing one — a series has every date in its range | `UsageHistory.days(in:)` |

## 6 · What is deliberately NOT in the tree

| Absent | Why |
|---|---|
| `UsageProbe`, and every `XxxUsageProbe` | one vendor-named type doing five jobs — the SRP violation this model exists to remove. Its jobs are three closed sums in a definition, and one `DataSource` that carries them out |
| a module, folder or type per vendor | a vendor is a JSON file. Vendor knowledge is DATA: URLs, paths, field names, client ids |
| a `XxxProvider` class per vendor | the lifecycle is identical in all twenty; only the fetch and mapping differ. Claude's CLI and API modes are two data sources, not a subclass |
| a `XxxSettingsRepository` protocol per vendor | a vendor's settings are a `SettingsForm`; storage is one repository keyed by provider and setting id. ISP is kept by handing each data source ONLY its own form |
| `bedrockUsage` on the usage | a vendor's type in the shared kernel. Bedrock's per-model cost is a `Cost` with lines, or a group of quotas |
| `.claudeMax` · `.claudePro` on `Plan` | a vendor's words in the kernel. A plan is a badge and a name; whether it can issue guest passes is a fact the definition states about that plan |
| `menuBarTitle` · `compactTitle` · `formattedDollar…` · `paceTickHelp` on `Quota` | the page's. A quota does not know how wide the menu bar is |
| `menuBarLabel(…)` on the `Monitor` | the page's. The monitor answers *what is true*; the menu bar decides how to print it |
| `percentRemaining: 100` as "no percentage" | see the law on `Quota.left` |
| `QuotaType.duration` guessing 7 days for a model quota or 30 for "Monthly" | see the law on `Window` |
| a ViewModel or AppState | unchanged: views read the tree |
| Claude Code sessions in the Monitor | a different question with a different *Session* — Activity's |
| a `XxxDailyUsageAnalyzer` per tool, a Swift price table | a tool's logs and prices are data in its definition; every reader yields one `LogRecord`; one reader per log FORMAT, one `PriceList`, one day aggregator |
| "today and yesterday" as a type | a view, not a fact: the page asks for a range of days |
| `dailyUsageReport` on the usage | Usage History is another context's answer, read on its own (§9) |
| a `canChooseInUse` flag, In use on `Provider` itself | a capability is a handle that is `nil` when not declared (§2.1); the product's lifecycle doesn't change for it |
| copying a login's tokens to the default place, a proxy in front of the CLI | refresh tokens rotate; a proxy would carry prompts and break provider terms. In use moves a folder path, nothing else |

## 7 · The contexts, and the modules that implement them

Each is a **fence**: inside it every word has one meaning and one model
enforces it. Across a fence the same word may mean something else, as long as
**no type crosses** — a reference does. A reference is an id, a name, or a
value of the Quota kernel; never another context's aggregate, its storage or
its factory.

| Context | Subdomain | Owns the question | Its root | Reaches others only by |
|---|---|---|---|---|
| **Quota** | **shared kernel** | *how much is left, when does it refill, and is that OK?* | values: `Quota`, `Left`, `Window`, `Status`, `StatusPolicy`, `Pace` | — it imports nothing |
| **Providers** | **core** | *who do I pay, under which accounts, and what did they last say?* | ◆ `Providers` → `Provider` → `Accounts` | a `DataSource` the factory makes from a definition |
| **Data Sources** | supporting | *how do we find out?* — DataSource, DataSourceDefinition, CredentialLookup, Fetch, Mapping, Setting, DataSourceError, and every worker | ◆ `DataSource` | the platform's ports |
| **Monitoring** | **core · conductor** | *what is true right now, and when do we look again?* | ◆ `QuotaMonitor` | `onRefreshed` · `onRefreshFailed`: whatever follows a refresh observes it |
| **Alerting** | generic | *who needs to hear it?* — told when it changed: notifications, your quota alerts, status alerts, the week's recap, signed out, webhooks, Notify!, live activity, status export; or asking when it wants: the [local API](../features/alerting/local-api/design.md), a destination that reads and never changes state | ◆ `QuotaAlerts`, `StatusAlerts`, `RecapAlerts`, `SignedOutAlerts`, `Webhooks`, the Notify publication | a login's id, its `lineupName`, its usage, its status under the policy and its last refresh error; the local API reads Monitoring's `Overview(monitor)`, the All page's read, and decides nothing |
| **Activity** | supporting | *what is Claude Code doing right now?* — hooks, sessions, the notch | ◆ `SessionMonitor` | Data Sources' answer to "is this one of my runs" |
| **Usage History** | supporting | *what did I use, day by day?* | ◆ `UsageHistory`, one per login | `account.usageHistory` |
| **In use** | supporting | *which login does my next terminal session start with?* | ◆ `InUse` | the login's id and folder; the best login from `Accounts` |
| **Leaderboard** | supporting | *how do my days compare with everyone else's?* — membership, devices, a new device's request to be added, the signed upload; [its design](../features/leaderboard/design.md) | ◆ `LeaderboardMembership` | its `TokenLogs` port, which the App fills from Usage History |
| **Vault & Settings** | generic | *where is it kept?* — `settings.json`, secrets | the repositories | ports each context declares for itself |
| SDK clients | — (anti-corruption layers) | *what does this SDK say?* — a client that needs a heavy SDK gets its own module, behind a port, so only it links the SDK | — | the port it implements |

```text
                     Quota   (shared kernel: every context may hold its values)

 SDK clients ──implement a port of──▶ Data Sources ──DataSource──▶ Providers ──▶ Monitoring
 (AWSClients)                              │                           │             │
                         "is this my run?" │       account.usageHistory│             │ onRefreshed
                                           ▼                           ▼             ▼
                                       Activity                 Usage History   Alerting · In use
                                                                       │
                                                         TokenLogs, filled by the App
                                                                       ▼
                                                                  Leaderboard

 Vault & Settings ──implements the storage ports each context declares──▶ (any of them)
```

Arrows point from the context that is used to the one that uses it; nothing
points back. The App only wires them: it holds no rule of any context, and a
surface that shows two contexts (the notch shows Activity and a quota) reads
each through its own root.

## 8 · Where the code is still behind

The tree above is the design; where the code disagrees, the code moves. What
is built is not listed — the code is its record. What isn't yet:

| Node | The code today | Moves to |
|---|---|---|
| the words | `UsageSnapshot`, `UsageQuota`, `CostUsage`, `AccountTier`, `capturedAt` | `Usage`, `Quota`, `Cost`, `Plan`, `updatedAt` — one rename per PR; the popover's *No quota data* becomes *No usage data* |
| `Plan` | `AccountTier` with Claude's cases | a name and a badge |
| `Usage` | carries `extensionMetrics` and `dailyUsageReport` | kernel fields only — usage history is read from `account.usageHistory` |
| `Account.budget` | `app.claudeApiBudget` (Claude's card) and Bedrock's `dailyBudget` as a quota | a `Budget` beside the login's `Cost`, judged as `BudgetStatus`; the old keys read as the default login's budget |
| `StatusPolicy` | `StatusColorPolicy` is in `Domain` | colours move to the App |
| page state | `MenuBarLabel`, `CountdownColon`, `PopoverContentHeight`, `MenuBarStackedSize` in `Domain/App`, with the menu-bar builders (`menuBarLabel(…)` and its siblings) as `QuotaMonitor+MenuBar` beside them, so the `Monitoring` module returns none of them | the App |
| `Day` | `DailyUsageReport` / `DailyUsageStat` (with `lines`) | `Day` — the sum of its lines, one per model; records with no model, one unnamed line |
| *Add Provider* | no *Edit*; one quota per response from the sheet | *Edit*; several quotas from one response |
| In use | folder logins only | an environment-variable record for API-key providers |

### Found by checking each context (October 2026)

Each context was checked with [the six questions](../../.claude/skills/implement-feature/references/domain-shape.md#check-by-context).
These are the findings a law above already answers; each is its own change,
test first. Findings that need a decision first are in §9.

| Context | The code today | Moves to |
|---|---|---|
| Quota | one `SpendRate` is graded two ways (`UsagePace`'s words, `PaceLevel`'s six levels), so one quota can read *On track* beside a warm tick | one `Pace` from the rate; the words and the tick are views of it |
| Quota | the share left of a money quota computed twice, once across currencies (`QuotaAlerts.lowestShare`); `<` compares `percentRemaining`, where a balance is 100 | `Left.share`, `nil` for a balance or mixed currencies, read by every comparison |
| Quota · Providers | a login's status has two owners: `Account.status` / `Accounts.status` ignore the policy and hidden quotas, `QuotaMonitor.status(of:)` and `Overview` apply both | `accounts.status(under:)`; the Monitor and the overview delegate |
| Monitoring | the menu-bar quota reads `snapshot` directly, so a hidden quota still colours the menu bar | read through the watched usage |
| Monitoring | which logins the background refresh fetches, and starting the loop, live in `StatusItemLabelDriver` | the Monitor, from what each surface asks to keep fresh; the driver renders |
| Monitoring | `selectedProviderId = "claude"`; `ObservationRenderSync` (a SwiftUI workaround) in `Domain`; `MonitoringEvent.error` never sent | the first in the lineup; the App; removed |
| Alerting | Notify!'s publishing laws (a tile's backoff never silences a widget, the 6-hour pause, forget only the refused handle) in `NotifyPublishDriver` | a `NotifyPublication` in Alerting, told each offer and failure; the driver keeps the timer |
| Alerting | status export recomputes status and *no data*, and turns off with the Touch Bar; Notify!'s tint is hard-coded in `Domain`; `QuotaAlerts` repeats the policy's 20 and 0 | every destination reads the status under the policy; colours come from the App's theme; the policy names its boundaries |
| Providers | `Provider` and `Account` write storage keys (`plainLoginKey`, `isEnabled(forProvider: loginId)`, `verifiedAtLeastOnce`) and migrate old ones | a pause/switch port; compatibility in `JSONSettingsRepository`'s tables |
| Providers | `providerId` is the product in `Account`, the login in a `Usage` and its quotas, either in settings | a login's id under its own name; `ProviderAccount` the one parser of lineup ids |
| Providers | `ProviderFactory.customDefinitions`, a global registry read by views and alerts | `Providers.provider(of:)`; the factory only makes |
| Providers · In use | *the login with the most left* in `Accounts.best`, `InUse.worthSwitchingTo` and `SwitchWhenLow.next`, each slightly different | `Accounts.best`, given what may be picked |
| Providers | *signed out* decided in `Provider.isSignedOut`, `Account.fail` (by tag string) and `Account.needsSetup` | the error answers `isSignedOut` itself |
| Providers · In use | refusals (*already listed*, *another login's folder*) thrown as `UsageError.executionFailed(String)` | a `Refusal` per aggregate, as `QuotaAlerts` has |
| Providers | guest passes run `settings.cliPath ?? cli`, skipping `Configuration`'s CLI places | the login's `configuration.running.cli` |
| Vault & Settings | `ClaudeSettingsRepository`, `CodexSettingsRepository`, `DeepSeekSettingsRepository`, `UsageProbe`, `AccountInfo` still declared; two writers of `verifiedAtLeastOnce` | deleted; DeepSeek's when its card retires |
| Vault & Settings | `ProviderSettingsRepository` holds the switch, configuration, order and page preferences, and its setters default to doing nothing | one port per role; no silent defaults |
| In use | the record's folder known by `DiskLoginsInUse` and again, by hand, in `ShellSetup` | the record port answers the file the shell reads |
| Data Sources | the `{{…}}` grammar parsed in `Template`, `Placeholders`, string replaces and `contains("{{")` guards, in both modules | one `Placeholder` value: parse, fill, names, transforms |
| Data Sources | a fetch or lookup case answers for itself in only some places: five switches, and Providers' own `if case .cloudWatch` | `Connection` grows the questions (`readsCloud`, `keyNames`, …) |
| Data Sources | `Connection` means a payload's disclosures and a platform port; `[*]` ends a path in `JSONPath` and fans out in `LocalEndpoint` | one word each; one path dialect |
| Data Sources | failures worded by workers (*No file at*, *Network error*, OAuth's *Token refresh failed*), retry decided by `tag == "executionFailed"`, `Unavailable` returns text, a missing CloudWatch client words its own | wider `ErrorFact` (`network`, `fileMissing`, `unavailable`, …), one table of failure names |
| Data Sources | `DataSource` reads the refresher's state to decide renewal; the secret field names are a set on the aggregate | the refresher is told and answers a renewal; `Credential` knows its secrets |
| SDK clients | Bedrock's prices and model names in `AWSClients`' Swift | a price file in the definition |
| Activity | the hooks installed are a list beside `SessionEvent.EventName`, without `Notification`, so *Needs you* never comes | the installer registers every `EventName` |
| Activity | "ClaudeBar's own CLI run" decided in four places; `CLAUDEBAR_PROBE` written by hand in `claude.json` and the guest-pass runner | Data Sources marks every child it starts and answers "is this one of my runs" |
| Activity | the notch judges quotas without the policy, ranks by `percentRemaining`, and prints its own phase words and colours | the quota's status under the policy; `Phase.label` and its colour |
| Activity | following Claude Code (hooks file, setting, event loop, sweep, notification text) in `HooksPane` and `ClaudeBarApp` | an Activity root told `turnOn()` / `turnOff()`; the App constructs it |
| Leaderboard | "upload now" after each command, the copied-key retry and the off-notice choice in `AppLeaderboard`; the privacy preview rebuilds the wire format; a member's mix counted in two views | the membership's commands; the encoder's preview; `Board.Member.mix` |
| Leaderboard | its model holds `DailyUsageStat`; the providers with token logs are a sentence in two views | `TokenLogs` answers Leaderboard's own token counts; the names from the catalog |
| App | `provider.id == "antigravity"` in the Touch Bar, `theme.id == "christmas"` / `"cli"` in the popover, eight provider ids as Settings search words | the lineup name; theme capabilities on `AppThemeProvider`; the catalog's names |

## 9 · Open

- ~~**Usage History on the usage.**~~ — **answered**: a second read the
  popover asks for. Each login's `account.usageHistory` answers `days(in:)`
  when the popover opens; `Usage` carries no daily report
  (Mistral #419 already works this way).
- **The mapping's reach.** When a vendor's response needs a rule the JSON
  mapping cannot say (Codex's free plan with no limits; Claude's PTY screen),
  the answer is a mapping FEATURE every provider gets — never a vendor
  escape hatch. Which features, is found provider by provider.
- ~~**Cost lines.**~~ — **answered**: one `Cost` with lines. Bedrock's
  per-model spend is a line each (`CostLine`), judged as a whole by the
  account's budget; never a quota, never a third kind of `Left`.
  Daily usage's `Day` carries its lines itself, not on a `Cost` — a line
  is one model's tokens and cost, because a day is the sum of its model
  calls; `CostLine` stays Bedrock's money-only line.
- ~~**A custom provider with accounts.**~~ — **answered**: the provider's.
  The form has two scopes; an account fills the ACCOUNT scope (one API key
  each, as a reference), and *Add Account* is that form. One definition
  serves every account (§1, §5).
- ~~**`command` fetches from the UI.**~~ — **answered by the journey**
  ([USER_JOURNEYS F10](USER_JOURNEYS.md#3--what-the-journeys-found)): the
  picker offers *CLI*, because a person typing their own command runs it with
  their own rights, as an extension does; a CLI provider that arrives by
  *Import* shows its command and asks before anything is saved or run.
- **Status in the kernel or the policy.** Is `Quota.status` a read that takes
  the policy, or does the Monitor apply it? §4 assumes the first.

Raised by checking each context (October 2026); each needs a decision here
before its §8 rows can move:

- **Who owns hidden quotas?** The Monitor keeps them per product and refuses
  to hide the last, and the kernel repeats that rule; the tree has no node for
  them, so `Account` can't see them and a login's status has two answers.
  Proposed: `Provider.hiddenQuotas`, saved through its form, with
  `hide(_:)` that can say no.
- **Does an added login that is signed out keep its last usage?** §5 says what
  we saw is never erased; `Account.fail` erases it for an added login, so it
  doesn't read as current. Either the law gains that exception, owned by
  `Account`, or the usage stays and reads as stale.
- **Where do the OS's ports live?** `TimeZone`, the network and, after
  [#580](https://github.com/tddworks/ClaudeBar/pull/580), `Processes` are
  declared in Data Sources, so Leaderboard imports Data Sources for a calendar
  and a `NetworkClient`. A small Platform module would let any context hold a
  port without depending on *how do we find out*.
- **Where does Usage History live?** Its words are in the Quota kernel, its
  aggregate and store in Providers, its readers and day totals in Data
  Sources, and the Monitor triggers its reads. A home of its own (module or
  folder), with the popover asking it directly, would make the fence real.
- **What is the notch?** It shows Activity and a quota, and its snooze rules
  are in an App driver. Proposed: a destination that reads `SessionMonitor`'s
  one ordering and a quota's status, with a pure notch policy for snooze and
  the recent window.
- **Where does sign-in live?** `AccountSignIn`, `LoginFolders` and their own
  `Process` runner sit in Data Sources; §2.1 lists sign-in under the
  provider's capabilities. Proposed: Providers, running the CLI as a `Program`.
- **Session means four things.** A quota window (Quota), a Claude Code process
  (Activity), the next terminal (In use) and a working session in a day's
  count (Usage History). §0.1 names only the first two; the glossary should
  name all four and the reference between Activity and In use, if any.
