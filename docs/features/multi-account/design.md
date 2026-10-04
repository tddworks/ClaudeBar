---
description: Contributor design for multiple accounts under one provider — how Monitor, Provider, Account, DataSource, the definition's accounts block, settings and the vault talk to each other; the three ways to add an account as data; the laws and their owners; and how PR #358 is refactored onto this shape without vendor code. Read before touching Add Account, account naming, sign-in or per-account keys.
---

# Multiple accounts: design — "Add Account"

User guide: [README.md](README.md).

**Status: BUILT, slices 1–6.** Built: one `Provider` owns `[Account]`; an
added login runs the **same** data sources with `accounts.patch` merged in and
`{{account.x}}` filled from its values; added by `accounts.folder` — Codex
(#356) and Claude (slice 1: `IdentityField`, `derived`, identity from a context
file); `displayName`, `rename`, a saved default-account name and short
menu-bar names (slice 2); `accounts.signIn`, `provider.signIn` /
`addAccount(signedInAt:)`, `SignedInFolder` and the `LoginFolders` port
(slice 3); the Accounts card and the Add Account sheet, `Provider.move` and
`signInAgain` (slice 4); `accounts.form`, `addAccount(filling:)`,
`SecretStore.scoped(to:)` and `SecretVault`, with API providers made in Add
Provider asking for a key per account (slice 5); the popover by provider —
`ProductTab`, `QuotaMonitor.tabs` / `selectedTab`, `Provider.worstAccount`,
account chips and the callout (slice 6). `selectedProviderId` stays a lineup id
underneath (the tab's first login), so the menu bar, the refresh loop and the
Touch Bar read it unchanged. PR #358 adds Claude (as data — kept), browser sign-in, rename and
compact labels (kept, reshaped below), and a Swift bridge that gives the 18
legacy providers, custom definitions and extensions accounts (replaced by this
design — see [§ What is wrong today](#what-is-wrong-today)).

This document owns **the account: how one is added, named, isolated and
refreshed**. Its neighbours own the rest:

| For | Read |
|---|---|
| what a Provider, DataSource, Usage *is* — the words and the tree | [CANONICAL_MODEL.md](../../architecture/CANONICAL_MODEL.md) |
| how a definition runs, the closed sums, the migration slices | [TARGET_ARCHITECTURE.md](../../architecture/TARGET_ARCHITECTURE.md) |
| which module a file lives in | [MODULAR_DESIGN.md](../../architecture/MODULAR_DESIGN.md) |
| Codex's folder and identity rules, as JSON | [providers/codex/design.md](../../providers/codex/design.md) |
| where settings and keys are stored | [settings.md](../../settings.md) |

---

## What the product already says

```text
  "Add Account…"                    ← an account is ADDED to a provider; it is not a provider
  "Sign in with browser"            ← one way to add: run the vendor's own login, in a new folder
  "Choose Signed-in Folder"         ← another: point at a folder a login already lives in
  "API KEY" (on the Add Account form) ← a third: fill the provider's ACCOUNT-scope settings
  "work@acme.com" on the pill       ← an account is told apart by WHO it is
  "Rename"                          ← …or by the name the person gave it
  "Remove"                          ← forgets it HERE; never signs out the CLI
  "This folder now signs in to someone else" ← identity is checked, and a mismatch fails closed
  "ACCOUNTS  Personal · Work · Side"   ← (concept) one provider, its logins side by side
  "Work — Acme is at 18% Opus — causing Warning" ← (concept) the aggregate names its cause
  "Re-auth"                             ← (concept) a failed fetch is a login to fix, not a quota colour
```

The finding: **adding an account never adds code.** Each of the three ways is
something the definition *says*; the screen only renders what it says.

## The one sentence

**A provider is fetched one way for all its logins; an account is one login —
its values fill the definition's `{{account.x}}` and its secrets come from its
own corner of the vault.**

```text
                       codex.json / claude.json / <custom>.json
                       ┌──────────────────────────────────────┐
                       │ dataSources: [ … {{account.home}} … ] │  written ONCE
                       │ accounts: { add, patch, identity }    │
                       └──────────────────┬───────────────────┘
                                          │  patched + filled per login
             ┌────────────────────────────┼────────────────────────────┐
             ▼                            ▼                            ▼
     Account  "codex"            Account "codex.7f3a"          Account "codex.c19e"
     values: {}                  values: {home: ~/A}           values: {home: ~/B}
     vault: provider.codex.*     vault: provider.codex.        vault: provider.codex.
                                        account.7f3a.*                account.c19e.*
             │                            │                            │
             ▼                            ▼                            ▼
       [DataSource]                 [DataSource]                 [DataSource]
       bound once,                  bound once,                  bound once,
       own cache                    own cache                    own cache
```

---

## What is wrong today

PR #358 reaches the right screen through the wrong shape. The evidence, in its
diff:

| Cost | The evidence |
|---|---|
| **Two lifecycles in `Provider`** (SRP) | `Provider.swift`: a `convenience init(…makeAccountSource:)`, `accountSources: [String: any AccountUsageSource]`, and an `if let source = accountSources[…]` branch at the top of `isAvailable`, `refresh`, `backgroundRefreshFloor`, `dashboardURL` — a second copy of in-flight dedupe, `isSyncing`, identity check and succeed/fail |
| **A probe by another name in a module** | `Modules/Providers/Sources/AccountUsageSource.swift` — `isAvailable()` + `refresh()` is `UsageProbe` |
| **`switch id` tables** (OCP) | `AccountConnectionRecipe.builtIn` (18 ids), `LegacyAccountConnections.source` (15 ids, builds each `XxxUsageProbe`, hard-codes `.omp/agent/agent.db`, kiro's sqlite path), `credentialKey` (6 ids), `ProviderAccountsCard` (`switch provider.id` for regions). Adding a provider edits 4 Swift files |
| **A data source copied per login** (breaks [CANONICAL §5](../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them)) | `CustomAccountConnections` builds a whole `Provider` from a re-serialised `scopedDefinition` for each added account and wraps its `defaultAccount` |
| **Vendor knowledge in Swift** | `BrowserAccountLogin` defaults to `CODEX_HOME` and Codex's `login` args and strips `OPENAI_API_KEY`…; `excludedEnvironment` lists ~40 vendor variables; `BinaryLocator` knows `"\(tool)-cli/\(tool.capitalized)CLI.app"` |
| **Throw-away work** | new init parameters on probes slices 2 and 5 delete (`homeDirectory`, `storedKeyOnly`, `failOnAllRegionFailures`, `accountToken`), `isolatedAccountCredentials` through `JSONSettingsRepository` |
| **A runtime downcast for a law** | `Account.label`'s getter: `provider.settings as? AccountNamingSettingsRepository` |
| **A crash at launch** | `ClaudeBarApp.init`: `preconditionFailure` when a legacy account source fails to build |

---

## 1 · Ubiquitous language

| Term | Meaning | Not to be confused with |
|---|---|---|
| **Provider** | the product you pay; how to fetch, once for every login | an account |
| **Account** | one login you pay for: who, its values, what we last saw | a data source; a provider |
| **default account** | the plain login the CLI already uses; id = provider id; never removed | "the first added one" |
| **added account** | a login beside it; id `<provider>.<acct>` | a copy of the provider |
| **account values** | the account-scope settings that fill `{{account.x}}` — a folder, a login id, a region | secrets |
| **account secret** | an account-scope secret (an API key) — a *name*, its value in the vault under that account | a value in `settings.json` |
| **way to add** (`accounts.ways`) | how the definition lets a person add one — the keys it has: `signIn` · `folder` · `form` | a data source kind |
| **signed-in folder** | the folder an added login lives in, and who made it — the person, or ClaudeBar by signing in | the default login's folder |
| **identity** | the fact that names a login (email, account id) and the rule that a fetch must still match it | the label |
| **label** | the name a person gave an account ("work") | the email |
| **display name** | what the pill says: label, else email, else the provider's name | the menu bar label |
| **menu bar label** | the shortened text in the 16 px status item — the page's, not the model's | display name |
| **worst account** | the enabled account whose status is the provider's — the callout's subject | the default account |

*Primary* is deliberately not a word here. The concept used it for "drives
the menu bar icon", which pins already say, and it would blur with
*default* (§8).

*Account*, not *connection*: #358 called added logins "connections" in Swift;
the screen says *Account* and so does CANONICAL. *Connection* stays the word
for *Test Connection* (a fetch), where it already means something else.

## 2 · The aggregate — from the root down

```text
Monitor ◆                                  the menu bar's root
├── providers: [Provider]
├── lineup → [Account]                     DERIVED — enabled accounts of enabled providers: the pills
└── selection: Account.ID
     │
     └── Provider ◆                        THE PRODUCT — one lifecycle for every login
         ├── definition ◇                  the JSON — written once
         │   ├── dataSources               may say {{account.x}}
         │   └── accounts: Accounts? ◇     NIL = this provider has one login, and no "Add Account"
         │       ├── ways → [AddAccountWay] THE WAYS TO ADD — DERIVED from which keys are present:
         │       │     signIn(command)       "Sign in with browser" — run the vendor's login into a
         │       │                           NEW folder, then the folder rule checks it
         │       │     folder(rule)          "Choose Signed-in Folder" — read who is signed in there
         │       │     form                  fill the form's ACCOUNT-scope settings (slice 5)
         │       ├── patch                 by data source kind: what an added login changes (RFC 7396)
         │       └── identity              which field names the login; a mismatch fails closed
         ├── settingsForm ◇                [Setting], each with a SCOPE: provider | account
         ├── accounts: [Account] ◆         NEVER EMPTY; [0] is the default
         │   └── Account ◆                 A LOGIN — no behaviour of its own
         │       ├── id                    `<provider>` · `<provider>.<acct>` — pins and settings keyed by it
         │       ├── label?                the person's name for it
         │       ├── values                account-scope settings (non-secret)
         │       ├── isEnabled             pause, not forget
         │       ├── usage? · sync         what we saw · fetch health — kept apart
         │       └── displayName           DERIVED — label ?? email ?? provider.name
         ├── worstAccount              DERIVED — the enabled account whose status is provider.status
         ├── bound: [Account.ID: [DataSource]]   internal — made ONCE per login from the patched,
         │                                       filled definition, with that login's vault
         └── refresh(account) · add(…) · rename(account, to:) · remove(account)

DataSource ◆                               ONE type; never knows there are accounts —
                                           it sees a definition already filled for one,
                                           and a SecretStore already scoped to one
```

**What varies is data.** There is no `AccountUsageSource`, no recipe table, no
per-vendor connection class: a provider that can have accounts says so in
`accounts`; one that cannot has `accounts: nil` and its card has no *Add
Account* button. A legacy provider (still a Swift `XxxProvider`) has
`accounts: nil` by construction — it gains accounts in the slice that turns it
into JSON, and not before.

### The ways to add — one key each in `accounts`

| Case | JSON | Carries | What it does |
|---|---|---|---|
| **folder** | `"folder": { savedAs, default, accountId: {field, savedAs}, email?, derived?, notSignedIn }` | where the login lives, which field names it | reads the folder through the definition's own credential/context lookup (filled with that folder), refuses the default folder and duplicates, saves `{savedAs: folder, accountId.savedAs: fact}` |
| **signIn** | `"signIn": { cli, args, homeVariable, unset, timeout, alsoAt }` | the vendor's login command, and where else its CLI may be | makes `~/.claudebar/accounts/<provider>/<uuid>/` (0700), runs `cli args` with `homeVariable=<folder>` and `unset` removed, waits; on exit 0 the provider checks the folder as **folder** does, recorded `madeBy: .signIn` |
| **form** | `"form": true` | — | renders the form's account-scope settings; non-secrets → `values`, secrets → the account's vault; then *Test Connection* with them before saving |

`signIn` requires `folder` (it ends in one) — a definition with one and not
the other is refused on load. `derived` — #358's
`derivedValues`, e.g. Claude's Keychain service `Claude Code-credentials-<hash8>`
— is a feature of the folder rule, so stays.

### `Account` — one login

> **Pointable as:** the *work@acme.com* pill.

| | |
|---|---|
| **Owns** | its id, label, values, how it was added (`madeBy`), enabled flag, last usage and sync state |
| **Tell it** | nothing — the provider tells it `succeed(usage)` / `fail(error)` |
| **It answers** | `displayName`, `status`, `email` (usage's, else what it was added with), `folder: SignedInFolder?` |
| **Never** | fetches; reads settings; downcasts a repository; knows a vendor; carries a secret's value |

### `Provider` — the lifecycle, once

> **Pointable as:** the *Codex* row in Settings → Providers.

| | |
|---|---|
| **Owns** | which data source is active, the fallback, the in-flight refresh per account, binding each account's data sources |
| **Tell it** | `signIn(with:under:)`, `addAccount(signedInAt:)`, `add(_ config)`, `rename(account, to:)`, `remove(account)`, `refresh(account, kind)`, `use(kind)` |
| **It answers** | `accounts`, `status`, `bestAccount`, `hasSeveralAccounts`, the ways to add (`definition.accounts?.ways`) |
| **Never** | has a second refresh path; holds an `AIProvider` inside it; switches on its id; touches the disk except through `LoginFolders` |

It owns *Add Account* because only it knows its accounts: "already listed"
and "the default login" are questions about them, so a caller never passes
`existing:` in. (`AddedAccounts` — a namespace of procedures nobody could
point at — is gone.)

### `SignedInFolder` — where an added login lives

> **Pointable as:** the folder *Choose Signed-in Folder* picks, or the one
> *Sign in with browser* makes.

| | |
|---|---|
| **Owns** | its path, and who made it (`madeBy`) |
| **It answers** | `goesWithAccount` — true only for a folder ClaudeBar made by signing in, named `<uuid>` as it names them |
| **Never** | decides from where it is on disk; deletes itself |

### Ports — what a test stubs

| Port | Real | Used by |
|---|---|---|
| `LoginFolders` (`exists` · `create` private and new · `delete`) | `DiskLoginFolders` | `Provider` (Remove, a failed sign-in), `AccountSignIn` |
| `SignInProcess` (`run(executable:…) → exit status`) | `FoundationSignInProcess` — output never read | `AccountSignIn` |
| `makeDataSource` | `DataSources.make` | `Provider` — reading who is signed in to a folder |

Each is `@Mockable`, and the tests also keep in-memory fakes, so they check
what exists afterwards rather than which calls were made.

---

## 3 · How the pieces talk

### 3.1 · Launch

```text
ClaudeBarApp.init (composition root)
  │
  │ ProviderCatalog → [ProviderDefinition]          bundled · ~/.claudebar/providers · (extensions, slice 5)
  │ settings.accounts(forProvider: id) → [ProviderAccountConfig]
  ▼
Providers.make(definition, settings, vault)
  │
  ├─ default account:  definition.dataSources ──map──▶ DataSources.make(_, secrets: vault.scoped(to: "<id>"))
  │
  └─ for each config:  provider.add(config)
        │  definition.dataSources(forAccount: config.values)     patch merged, {{account.x}} filled
        │  ── a data source the patch nulls is left out for that login
        ▼
        DataSources.make(_, secrets: vault.scoped(to: "<id>.<acct>"))
        │
        └─ fails (bad folder, unfilled {{account.x}})?  → logged by account id, account left out.
                                                          The app never crashes.
  ▼
QuotaMonitor(providers) → lineup = provider.accounts.filter(isEnabled), for every enabled provider
```

Legacy providers enter the lineup as today: one `AIProvider`, one pill.

### 3.2 · Add Account

```text
 ProviderAccountsCard                      (renders definition.accounts.ways — no switch on id)
   │
   ├─ "Sign in with browser" ──▶ provider.signIn(with:under:) ─────────────────┐
   │                               │ AccountSignIn (DataSources worker)        │
   │                               │   folders.create(<root>/<p>/<uuid>)       │
   │                               │   run signIn.cli signIn.args              │
   │                               │     env[homeVariable] = folder            │
   │                               │     env -= signIn.unset                   │
   │                               │   exit 0? else throw (folder removed)     │
   │                               ▼                                           │
   ├─ "Choose Signed-in Folder" ─▶ provider.addAccount(signedInAt:) ◀─────────┘
   │                               │ definition.dataSources(forAccount: {folder})
   │                               │ → its credential + context lookups → who
   │                               │ refuse: default login · already listed · no key
   │                               │ (a sign-in folder that fails here: folders.delete)
   │                               ▼
   │                             ProviderAccountConfig { accountId: uuid, email, values, madeBy }
   │
   └─ "Add Account" (form) ─────▶ form's account-scope settings
                                   │ provider.addAccount(filling:) — secrets → vault.save(name, "<id>.<acct>")
                                   │ provider.testConnection(draft) — before saving
                                   ▼
                                 ProviderAccountConfig { accountId: uuid, values }
                                   │
                                   ▼
               provider.add(config) — saves it ; monitor.add(account)
```

One door in: `provider.add(config)`. The three ways differ only in how the
config is *found*; none of them builds a data source.

### 3.3 · Refresh one account

```text
QuotaMonitor.refresh(account)
  ▼
Provider.refresh(account, kind)            in flight already? → await that task
  │  bound[account.id] → active DataSource (and its fallback chain)
  ▼
DataSource.fetchUsage()                    already filled for this login; vault already scoped
  │  lookUp()  ── credential from {{account.home}}/auth.json · vault account.<acct>.apiKey
  │  identity  ── the looked-up fact == the saved one?  no → DataSourceError(.lookup, sessionExpired(hint))
  │  cache?    ── per DataSource, so per login
  │  fetch → map
  ▼
Provider: account.succeed(usage, from: kind)   |   account.fail(error)  (usage kept)
```

Identity is checked where the credential is read — **once, in the lookup** —
not again in `Provider` and not before the cache.

### 3.4 · Rename · Remove · menu bar

```text
"Rename"  → provider.rename(account, to: "work")
              settings.setLabel("work", account: account.id)      ONE store for default and added
              account.label = "work"
"Remove"  → provider.remove(account)                               never the default
              settings.removeAccount · vault.delete(each secret field, "<id>.<acct>") · bound/refreshTasks dropped
              config.madeBy == .signIn → its folder is deleted too (ClaudeBar made it, nobody else uses it)
              a folder the person chose, and the CLI's own files, are never touched
Menu bar  → MenuBarAccountName.names(displayNames)                 App — shortens, numbers collisions
```

---

### 3.5 · The screens

The look is
[`multi-account-ui-design-v1.html`](../../../design-concept/multi-account/multi-account-ui-design-v1.html).
Below, each part of it is mapped to the model. Where the concept and the
model disagree, the decision and its reason are in §8.

**Popover: one provider, all its accounts at once.**

```text
┌──────────────────────────────────────────────┐
│ ClaudeBar                             ↻  ⚙   │
│ (Claude) (Codex) (Gemini) (Copilot) (Amp)    │ ← monitor.providers.enabled; selection: Provider.ID
│ ACCOUNTS  (P Personal●) (W Work●) (S Side●)  │ ← provider.accounts.enabled — a VIEW FILTER (page's)
│                                              │   shown only when there are 2 or more
│ P PERSONAL                       [Healthy]   │ ← account.displayName · account.status
│ ┌ OPUS 72% ────────┐ ┌ SONNET 88% ───────┐   │ ← account.usage.quotas
│ W WORK — ACME                    [Warning]   │
│ ┌ OPUS 18% ────────┐ ┌ SONNET 41% ───────┐   │
│ S SIDE PROJECT                [Re-auth ↻]    │ ← account.sync.lastError — FETCH health:
│ ┌ OPUS — (72% · 2h ago) ┐                    │   grey, last usage kept, never a Status colour
│ ⚠ Work — Acme is at 18% Opus — causing the   │ ← provider.worstAccount (DERIVED) — names who
│   Warning                                    │   makes provider.status what it is
└──────────────────────────────────────────────┘
```

- A provider with one account looks exactly like it does today: no
  ACCOUNTS row and no account headers.
- The dot on a chip is that account's `status` colour. Grey means its last
  fetch failed.
- Clicking a section header opens that account's card, as a pill does today.

**Settings: the Accounts card.** It replaces `CodexAccountsCard`, and every
provider with an `accounts` block gets it.

```text
┌ 👥 Accounts · 3 accounts                       [Warning] ┐
│ ⋮⋮ (P) Personal         henry@personal.dev   ⓜ  ⋯        │ ← ⋮⋮ reorder → settings order
│ ⋮⋮ (W) Work — Acme Corp henry@acme.com       ⓜ  ⋯        │ ← ⓜ = shown in the menu bar (pin)
│ ⋮⋮ (S) Side Project     dev@sideproject.io  [Re-auth]    │ ← sync failed: re-run its way to add
│ ┌ ⊕ Add Account ────────────────────────────────────┐    │ ← only when definition.accounts.ways
│ └───────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
  ⋯ = Rename · Pause (isEnabled) · Remove (not on the default)
```

- **The avatar** is the first letter of `displayName`, in a colour from a
  palette by the account's position. It is the page's choice, not a stored
  setting.
- **The email** is the login's own (`usage.accountEmail`, else the one read
  when the account was added). It is never typed in.
- **Re-auth** runs the account's way to add again, into the same place:
  - `signIn`: signs in again into the same folder;
  - `folder`: explains how to sign in again in that folder;
  - `form`: edits the key.

  The identity rule still applies: a different person in that folder fails
  closed.

**Add Account: the concept's five steps, mapped to the model.**

```text
 1 ⊕ Add Account
      │
 2 HOW?   ← definition.accounts.ways, nothing else:
      │      "Sign in with browser" (signIn) · "Choose Signed-in Folder" (folder) · "API key" (form)
      │      only one case? this step is skipped
      ▼
 3 VERIFY ← each line is one step of DataSourceError, ticked as it passes:
      │      ✓ Found a login        lookup   — the folder / the key answers
      │      ✓ Signed in as henry@  identity — the fact that names it; refused if already listed
      │      ✓ Fetched usage        fetch + mapping — the first Usage
      │      ✗ on a line: that line's reason and Retry. "Add anyway" ONLY after identity passed
      ▼
 4 NAME   ← optional label, pre-filled with the email. That is the only thing typed
      ▼
 5 DONE   → provider.add(config) → the account appears in the popover with its first usage
```

The concept's step 2 asked for a label, an email, an organization and a
colour. Here only the label is typed, and it comes last. The concept's
step 3 offered "CLI profile / API token" for every provider. Here the choices
are the cases the definition declares (§8).

---

## 4 · Invariants — each law, one owner

| Law | Owner |
|---|---|
| a provider has at least one account; the default's id is the provider id, an added one's `<provider>.<acct>` | `Provider.accounts` |
| one definition serves every account — an added login's data sources are the definition patched and filled, never a hand-built copy | `ProviderDefinition.dataSources(forAccount:)` |
| a provider without `accounts` cannot add one — the button is absent, not disabled | `ProviderDefinition.accounts` |
| an account's secret is read only from that account's vault corner; a missing one is *Key needed*, never the default's key or the environment | `SecretStore.scoped(to:)`, used by every added login's data sources |
| an added login's CLI never sees the default login's credentials: what to set and unset is the definition's `patch`, per data source | the definition (data) — run by `CLIFetcher` |
| usage shown under a login was fetched with that login's credential; a different identity fails closed with the definition's hint | `DataSource` (lookup) |
| a folder already listed, or the default login, is not added twice | `Provider` (`addAccount`) |
| sign-in never writes to an existing folder and saves nothing on failure, cancel or timeout | `AccountSignIn` |
| display name is label, else email, else the provider's name | `Account.displayName` |
| one refresh per account in flight; a failed refresh keeps the last usage | `Provider` |
| today's usage is read from one login's local logs — Claude's default login's — so only that login shows it; guest passes likewise | `UsageHistory` (keyed by lineup id) · `Account.guestPasses` |
| removing deletes only what ClaudeBar made — the account's settings, its vault corner, and its folder when it goes with the account; never a folder the person chose or the CLI's files | `Provider.remove`, asking `SignedInFolder.goesWithAccount` |
| a data source whose key lookup ClaudeBar cannot see (`fetch: script`) declares an `identity`, or the definition is refused on load | `ProviderDefinition` validation (`DefinitionError`) |
| the data source choice is the provider's; a login the patch leaves without it uses the next on the fallback chain, and its usage says which | `Provider` |
| a menu bar name is shortened for width and never widens to a full email | `MenuBarAccountName` (App) |
| an account is added only once its identity is known; *Add anyway* exists only after that step passed | `Provider` (`addAccount`) |
| accounts keep the order the person gave them; the default is found by `isDefault`, not by position | `Provider.accounts` |
| the provider's status names the account that causes it | `Provider.worstAccount` |

Two laws #358 put in two places, now one each: the identity check (it ran in
`DataSource` **and** in `Provider.refresh`'s bridge branch) and display naming
(in `Account.name`, `Account.accountDescription` **and** `StatusItemLabelDriver`).

## 5 · The tells

```swift
// Card
if let ways = provider.definition.accounts?.ways { AddAccountMenu(ways: ways) }
try await provider.signIn()                                    // sign in, check, add, save
try provider.addAccount(signedInAt: url)                       // check, add, save
provider.rename(account, to: name)
provider.remove(account)

// Composition root
let vault = ProviderVault()
Providers.make(definition, settings: settings, vault: vault)   // binds every saved account

// Page
Text(account.displayName)
MenuBarAccountName.names(displayNames)
```

Not: `LegacyAccountConnections.shared.recipe(for: provider.id)`,
`switch provider.id { case "minimax": … }`, `settings as? AccountNamingSettingsRepository`.

---

## 6 · Refactoring PR #358

| #358 piece | Becomes |
|---|---|
| `claude.json` `accounts` (folder, patch, identity, `derivedValues`) | **kept** — re-flow the file to its original formatting |
| context identity (`"context.account.email"` parsed as a string) | **built**: `IdentityField` — `"account"`, `"$credential.x"` or `"$context.file.field"`, written as the mapping writes paths, decoded once; used by `identity.field`, `folder.accountId.field` and `folder.email` |
| `DataSource.fetchUsage` checks identity before the cache | **built**: checked with the lookup, before and after each fetch; a cached usage is what that login showed when it was fetched |
| `BrowserAccountLogin` (Infrastructure, Codex defaults) | **built**: `AccountSignIn` in `DataSources`, driven by `accounts.signIn` in `codex.json` / `claude.json` (Claude: `claude auth login --claudeai`); the process behind `SignInProcess`, folders behind `LoginFolders` |
| `AddedAccounts` (a static namespace) | **gone**: `provider.addAccount(signedInAt:)` and `provider.signIn(…)`; the deletable-folder rule is `SignedInFolder.goesWithAccount` |
| `BinaryLocator.findInApplicationBundles` | **built** as `signIn.alsoAt: [paths]` — checked only when the CLI isn't on the PATH |
| `Provider.rename`, `ProviderAccountConfig.named` | **built**: `Provider` receives `any MultiAccountSettingsRepository`, so `rename` and `remove` save without a downcast; the default login's name is `setDefaultAccountLabel` (`providers.<id>.defaultAccountLabel`); the unused `activeAccountId` is gone |
| `Account.name` / `accountDisplayName` / `accountDescription` / `isNamedByAccount` | **built**: one `displayName`; `name` (the pill) is the product's while `provider.hasSeveralAccounts` is false; `nameFromEmail` is gone |
| `AccountMenuBarLabel` (Domain) | **built**: `MenuBarAccountName` in App ([CANONICAL §1](../../architecture/CANONICAL_MODEL.md#1--the-tree): not in the model). Named so, not `MenuBarLabel`, which is already the quota text |
| `ProviderAccountsCard` | **kept**, rendering `accounts.ways` and the form's account scope; no `switch provider.id` |
| `CodexAccountsCard` | folded into `ProviderAccountsCard` |
| `withDailyUsage` / `guestPasses` default-only | **built**: today's usage moved out of `Provider.refresh` into `UsageHistory` (Domain), beside the providers as [CANONICAL §1](../../architecture/CANONICAL_MODEL.md#1--the-tree) asks — keyed by the login whose logs it reads, read when the popover opens or refreshes, never in the background. Guest passes stay an `Account` law |

### What dies

`AccountUsageSource` · the bridge `Provider.init(profile:…makeAccountSource:)`
and `accountSources` · `LegacyAccountUsageSource` · `LegacyAccountConnections` ·
`AccountConnectionRecipe` · `AccountCommandContext` · `CustomAccountConnections`
· `ExtensionAccountConnections` · `ScopedCredentialRepository` (→
`SecretStore.scoped(to:)`) · `AccountNamingSettingsRepository` · the probe init
parameters added for accounts · `isolatedAccountCredentials` ·
`docs/features/multi-account/universal-design.md` (this doc replaces it) · the
per-provider "Accounts" paragraphs for providers that have `accounts: nil`.

## 7 · Build sequence

Each slice one PR, test first, green.

| # | Slice | Pins |
|---|---|---|
| 1 ✅ | **Claude accounts as data** — #358's `claude.json` block, typed `identity`, identity in lookup only; `ClaudeAccountsTests` | a Claude folder adds; another email in it fails closed; default untouched |
| 2 ✅ | **Rename + display name** — `Account.displayName`, `setLabel` for default and added, `MenuBarAccountName` in App | labels survive relaunch; one login shows the product name; collisions number, never widen |
| 3 ✅ | **`accounts.signIn` + the ways to add** — `AccountSignIn` worker, `codex.json`/`claude.json` declare it; `signIn.alsoAt`; `SignedInFolder`, `LoginFolders` | cancel/timeout/fail leave no folder and no config; env carries only `homeVariable`, `unset` removed; *Remove* of a signed-in account deletes its folder, of a chosen one never — README's *Remove* paragraph updated with the screen (slice 4) |
| 4 ✅ | **one Accounts card** (§3.5) — renders `accounts.ways`, reorder, menu-bar pin, Rename · Pause · Remove, Re-auth; the 4-step Add Account sheet with VERIFY by step; `CodexAccountsCard` goes | a provider with `accounts: nil` shows no button; *Add anyway* is absent until identity passed; order survives relaunch |
| 6 ✅ | **popover by provider** (§3.5) — `selection: Provider.ID`; account sections, view-filter chips, `worstAccount` callout; CANONICAL §8's build truth updated | one account looks like today; a failed fetch is grey with its last usage, never a Status colour; the callout names the account |
| 5 ✅ | **`form` + scoped secrets** (`SecretStore.scoped(to:)`, `SecretVault`) — account-scope settings in the form; custom definitions can declare `accounts` | an added account's missing key is *Key needed*, never the default's |
| — | legacy providers | gain accounts in TARGET slices 2 and 5, when they become JSON — by adding an `accounts` block, nothing else |

## 8 · Open questions

Each answered from two questions: *what does the person believe they did?*
and *who owns the thing?* — never from what is easiest to build.

- ~~**Sign-in folder lifetime** — delete the folder `signIn` made on *Remove*?~~
  **Yes — and only that folder.** The person never saw that folder. What they
  did was *"sign in to my work account inside ClaudeBar"*, so *Remove* means
  *"ClaudeBar, stop holding my work login"*. A folder left behind is a live
  refresh token nobody can see, which is the opposite of what they asked for.
  A folder the person *chose* is theirs, and their terminal may use it, so it
  is never touched. The difference is **who made it**, so it is recorded when
  the account is added (`ProviderAccountConfig.madeBy: .signIn | .folder | .form`).
  It is never guessed from where the folder is. The confirmation says so:
  *"Removes work@acme.com from ClaudeBar and deletes the sign-in ClaudeBar
  kept for it."* (§3.4, §4)
- ~~**Extensions** — give them accounts before slice 5?~~ **No. They get them
  the same way every provider does, when they can say how.** To the person, an
  extension is just a provider (*Built in · Custom · Extension*). So the
  question is not *"is it an extension?"* but *"can this provider say how an
  account is added and kept apart?"*. A script is code ClaudeBar cannot see
  into. ClaudeBar can pass a login's values to it, but cannot know whether the
  script respects them. So when extensions are read as definitions (slice 5),
  their manifest declares an `accounts` block like anyone else's. **A data
  source whose key lookup ClaudeBar cannot see (`fetch: script`) must declare
  an `identity`, or the definition is refused on load.** That makes the
  script's own answer the proof, and a script that ignores its scope fails
  closed instead of showing one login's usage under another. (§4)
- ~~**Bedrock's per-profile budget** — account-scope fields on a legacy card?~~
  **A second AWS profile is a second account, and its budget is that
  account's.** The person's words are *"my limit for the work AWS account"*.
  The budget belongs to the login whose money it guards
  ([CANONICAL §5](../../architecture/CANONICAL_MODEL.md#5--the-laws-on-the-node-that-owns-them):
  a budget judges one account's cost). Bedrock gets this when it becomes JSON
  in slice 5:
  - `accounts.form` with `profile` as an account value, chosen from
    `~/.aws/config`;
  - `budget` as an account-scope setting.

  Until then Bedrock has one account, and today's `bedrock.dailyBudget` is
  that account's budget. There is no interim adapter.
- ~~**One data source choice, or one per account?**~~ **One, the provider's.**
  *DATA SOURCE* sits on the provider's card, and to the person it means *"how
  ClaudeBar asks Codex"*, not *"how it asks for work@"*. An added login whose
  `patch` leaves out the active kind (a form account with only a key has no
  CLI) uses the first remaining data source on the active one's fallback
  chain. Its pill says which one (*via API*), so the difference is never
  silent. **Built** (`ProviderTests`): the refresh starts at the next data source on the chain the login has. (§4)
- ~~**Can the default account be renamed?**~~ **Yes.** Two people with
  *personal* and *work* logins do not think of one of them as the "default".
  That is ClaudeBar's word for the login the CLI already uses. *Rename* works
  on every account. *Remove* is the only command the default refuses, because
  that login belongs to the CLI. (§3.4)
- ~~**"Primary" account, for the menu bar icon?**~~ **No. The menu bar
  already says which accounts it shows, through pins.** The concept used
  *Primary* to mean *"this one drives the icon"*. Today the person picks up
  to three entries in *Menu Bar* settings, and each account is pinnable. A
  second word for the same choice gives two answers to *"why is this in my
  menu bar?"*. The card's ⓜ is that pin. *Primary* would also blur with
  *default*, which means something else: the login the CLI uses.
- ~~**Type the email, organization and colour when adding?**~~ **No. Only an
  optional name is typed, and it comes last.** The email and organization
  are facts about the login. ClaudeBar reads them, and a typed one could
  disagree with the login it labels, which is exactly the mistake the
  identity rule exists to stop. Colour is the page's, by position. So the
  name step comes after VERIFY, pre-filled with the email that was found.
- ~~**"CLI profile / API token" as the choice of how to fetch?**~~ **The
  choices are the definition's ways to add.** `claude --profile` does not
  exist: a Claude login lives in a config folder. Every provider's honest
  choices are different, which is why they are data (`accounts.ways`). A
  provider with one way skips the step.
- ~~**"Add anyway" when verification fails?**~~ **Only after identity
  passed.** If ClaudeBar knows *who* the login is but the fetch failed
  (offline, an expired session), the account is real. It is added, and shows
  *Re-auth* with nothing fetched yet. If no login was found, there is nobody
  to monitor and nothing to name, so there is no *Add anyway*.
- ~~**Do the popover's account chips pause monitoring?**~~ **No. They only
  filter the view.** Pausing stops refreshes and notifications. A chip
  tapped to tidy the popover must not silence an alert. Pause lives on the
  Accounts card (*Pause*, `isEnabled`). A hidden account still counts toward
  the provider's status, and the callout names it, so a hidden account can
  never be the unexplained cause of a warning.
- ~~**One pill per account (today), or one per provider with its accounts
  inside (the concept)?**~~ **One per provider.** People think *"how is my
  Claude?"* first and *"which login?"* second. With per-account pills, three
  logins cost three tabs, and the popover never shows them side by side.
  `Monitor.selection` becomes a `Provider.ID`. `lineup` stays `[Account]`
  for the menu bar and notifications. CANONICAL §1, §3 and §5 were updated
  together with this answer. The code follows in slice 6.
- ~~**Can the person reorder accounts, the default included?**~~ **Yes.**
  The order is theirs. *Personal* above *Work* is a preference, not a fact
  about the CLI. The default is found by `isDefault`, never by being first,
  so it can move like the others.
- ~~**One Swift adapter so every provider has accounts now?**~~ **No.** It
  builds a second lifecycle and four `switch id` tables, and every line of it
  is deleted when the provider becomes JSON (§ What is wrong today).
