---
description: The provider redesign seen from outside in — four people, twelve moments from glancing at the menu bar to adding and sharing a custom provider, the words each screen prints, the command each lands on, and the twelve findings that changed the canonical model; read before designing a provider screen or changing a provider-facing type.
---

# Provider journeys — outside in

> The canonical model was harvested from the screens ClaudeBar has. The
> redesign adds screens it does not have yet — *Add Provider*, *Import*,
> *Export* — so this document walks them FIRST, as the people who will use
> them, and only then says what the model must be. Where a journey and the
> model disagree, the journey wins and the model moves.
>
> **The mockup:** [provider-user-journeys.html](../../design-concept/provider-user-journeys.html)
> — open it in a browser; ← → step through the moments, `#7` jumps to one.
>
> | Question | Document |
> |---|---|
> | *What does a person do, and what does the screen say?* | **this one** |
> | *What are the nodes, the words, the laws?* | [CANONICAL_MODEL.md](CANONICAL_MODEL.md) |
> | *How does a provider run?* | [TARGET_ARCHITECTURE.md](TARGET_ARCHITECTURE.md) |
> | *Which module holds it?* | [MODULAR_DESIGN.md](MODULAR_DESIGN.md) |
> | *Every behaviour the app has today, as BDD scenarios* | [USER_BEHAVIORS.md](USER_BEHAVIORS.md) |

---

## 1 · The people

| Who | Wants | Journey |
|---|---|---|
| **Mia** — Claude Code and Codex all day | to know, without opening anything, whether she can keep going | *Glance* |
| **Raj** — Codex stopped updating | the app to say what is wrong and where to fix it, in one place | *Fix* |
| **Ken** — pays for a gateway ClaudeBar doesn't ship (OpenRouter) | to track its credits without writing a script | *Add* |
| **Lin** — runs the team's internal LLM gateway | her team to get the provider without anyone retyping it | *Share* |

Today only Mia and Raj are served. Ken can only write an extension — a
manifest and a shell script — and Lin can only send that folder around.

## 2 · The moments

Each row: what the person sees (the words the screen prints), what they do,
the command that lands on the domain, and the node that answers.

| # | Moment | Sees | Does | Command | Node |
|---|---|---|---|---|---|
| 1 | Mia glances at the menu bar | *38%*, amber | nothing | `monitor.lowestQuota` | `Monitor` → worst `Quota.status` |
| 2 | Mia opens the popover | *Session · Weekly · Spark*, *% left*, *Resets in 1h 12m*, *Running hot*, *EXTRA USAGE*, *Updated 2m ago · via RPC*, *PLUS* | switches to a lighter model for an hour | `account.usage` | `Usage` → `[Quota]` · `Cost` · `Plan` |
| 2a | Mia has two Codex logins | two pills, *Codex · me@…* and *Codex · work@…*, both pinned in the menu bar; Settings lists one **Codex** with *Add Account…* and a toggle per login | pauses *work* on the weekend; later clicks *work* when *me* runs low | `monitor.select(account)` · `account.disable()` · `provider.bestAccount` | `Provider` (the product) → `[Account]` (the logins) |
| 3 | Raj sees Codex fail | *Couldn't read your key* · *Session expired. Run `codex` in terminal to log in again.* · last usage dimmed, *Last seen 3h ago* | logs in, or opens settings | `account.sync.lastError` | `DataSourceError(step: .lookup)`; `usage` kept |
| 4 | Raj opens Codex settings | *DATA SOURCE: RPC · API*, *KEY LOOKUP ORDER*, *Test Connection*, *Built in* | switches to RPC, tests | `provider.use("rpc")` · `dataSource.fetchUsage()` | `Provider.dataSources` · `CredentialLookup` |
| 5 | Ken: *Add Provider* | *Start from: API · CLI · File · Copy a provider*, *Import…* | chooses API | `ProviderDefinition.blank(.http)` · `definition.copy()` | `ProviderDefinition` (unsaved) |
| 6 | Ken: *Connect* | *URL*, *Key lookup order: Environment variable · API key*, *Sent as*, *Test Connection*, *200 OK* | pastes his key, tests | `dataSource.fetchResponse()` | `Fetch.http` · `CredentialLookup` → `Response` |
| 7 | Ken: *Map fields* | *Response*, *Remaining · Limit · Resets*, *never — a balance*, a live card | clicks `12.4`, then `50` | `mapping.quotas.append(.money(remaining:of:))` | `Mapping.json` → `Quota.left = money`, `window = nil` |
| 8 | Ken: *Look* | *Name*, *Symbol · colour*, *Save* | names it, saves | `catalog.add(definition)` | `ProviderProfile` · `ProviderLook` · `ProviderCatalog` |
| 9 | Ken sees it in the popover | *OpenRouter*, *$12.40 of $50.00*, *via API*, *CUSTOM* | nothing — no restart | `provider.refresh()` | one `Provider`, one `DataSource` — the types Codex uses |
| 10 | Lin exports | *Built in · Custom · Extension*, *Export…*, *no keys — they stay in your Keychain* | posts the file | `definition.exported()` | `ProviderDefinition`, secrets stripped |
| 11 | A teammate imports | *Import provider*, *It will send your key to that address*, *Key needed*, *Test Connection*, *Add* | pastes his own key, adds | `catalog.import(file)` · `definition.missingSettings` | `ProviderCatalog` · `SettingsForm` |

## 3 · What the journeys changed

Twelve findings. Each is now in the canonical model; the column says where.

| # | Finding | From moment | Model change |
|---|---|---|---|
| F1 | The popover says **which data source answered** (*via RPC*, *via Terminal* after a fallback) | 2 | `Usage.source: kind` |
| F2 | An error **names the step that failed** — *Couldn't read your key* · *Couldn't connect* · *Couldn't find the numbers* — because each sends the person somewhere different | 3 | `DataSourceError.step: lookup · fetch · mapping` |
| F3 | Settings prints **DATA SOURCE** and the API source's **key lookup order**; the fallback is one sentence, not a setting | 4 | confirms `DataSource`, `CredentialLookup`, `fallback` |
| F4 | *Add Provider*'s picker is a **closed list in the words Settings already prints** — *API · CLI · File* — plus *Copy a provider* | 5 | `Fetch` stays a closed sum; the picker offers `http` · `cli` · `file` (RPC, Terminal and CloudWatch stay built-in only); `definition.copy()` mints a new id |
| F5 | *Test Connection* must **stop before mapping**: Ken has nothing mapped yet, but must see what came back | 6 | a public **`Response`** (status · headers · body); `dataSource.fetchResponse()`; `fetchUsage() = mapping.read(fetchResponse())` |
| F6 | *Map fields* asks four questions — **Used · Remaining · Limit · Resets** — plus the currency; a balance has no percentage to ask for and *never* resets | 7 | the `JSONMapping` vocabulary is those words; `Left` and `Window` laws made visible |
| F7 | A custom provider has its **look from day one** | 8 | `ProviderLook` in the definition for every origin — built-ins must catch up (target slice 3) |
| F8 | The screen calls a user-made provider **CUSTOM** | 9, 10 | the model's *declared* kind is renamed **custom**; origins are `builtIn` · `custom` · `extension` |
| F9 | An exported provider **carries no key** | 10 | law on `ProviderDefinition`: a secret is a reference, never a value, and `exported()` keeps only the lookup order and the setting's name |
| F10 | Import **says where the key will go** before asking for it; a *CLI* provider from someone else shows its command and asks before saving | 11 | law on `ProviderCatalog.import`; answers the model's open question about commands from the UI |
| F11 | Two logins of one product are **two things Mia watches** but **one thing Raj fixes**: each login is a pill and a menu-bar entry; the data source, its settings and the look are set once for Codex | 2a, 4 | `Provider` is the product, `Account` a login; accounts are simultaneous (no `active`); one definition, the account's values filled at fetch time |
| F12 | **Pause is not remove**: a login can be switched off without losing its folder; and an expired key is not a red quota — it reads *Couldn't read your key*, not CRITICAL | 2a, 3 | `Account.isEnabled`; `Account.status` (quota health) apart from `Account.sync` (fetch health) |

## 4 · The words the new screens print

These join the harvested words in [the model §0](CANONICAL_MODEL.md#0--how-to-read-it):

*Add Provider* · *Start from* · *API · CLI · File* · *Copy a provider* ·
*Import* · *Connect* · *URL* · *Key lookup order* · *Environment variable* ·
*API key* · *Sent as* · *Test Connection* · *Response* · *Map fields* ·
*Used · Remaining · Limit · Resets* · *never — a balance* · *Look* · *Name* ·
*Symbol · colour* · *Save* · *Built in · Custom · Extension* · *Export* ·
*Key needed* · *Couldn't read your key · Couldn't connect · Couldn't find the
numbers* · *via API*.

## 5 · Acceptance scenarios

The outer loop for the slices that build these screens (target slice 6), in
the shape of [USER_BEHAVIORS.md](USER_BEHAVIORS.md):

```gherkin
Scenario: Add a custom provider from an API
  Given Ken has an OpenRouter key
  When he adds a provider from "API" with URL "https://openrouter.ai/api/v1/auth/key"
   And enters his key and presses "Test Connection"
  Then he sees the response, status 200
  When he maps Remaining to "data.limit_remaining" and Limit to "data.limit"
   And names it "OpenRouter" and saves
  Then "OpenRouter" appears in the popover with "$12.40" "of $50.00"
   And its card shows no reset and no percentage

Scenario: A failed key lookup names its step
  Given Codex's API data source and an expired ~/.codex/auth.json
  When Codex refreshes
  Then the popover says "Couldn't read your key"
   And the last usage stays on screen, marked "Last seen"

Scenario: An exported provider carries no key
  Given a custom provider whose API key is in the Keychain
  When it is exported
  Then the file names the key's setting and lookup order
   And contains no key

Scenario: Importing a CLI provider asks first
  Given a provider file whose data source is a CLI command
  When it is imported
  Then the command is shown before anything is saved or run
```

## 6 · Open

- **Several quotas from one response** (*+ Add another quota*): one mapping
  per quota, or a repeat over an array the person points at? Codex's
  `additional_rate_limits[]` says the repeat must exist; whether the sheet
  offers it, or only the JSON, is a UI question.
- **Editing a built-in.** *Copy a provider* makes a custom copy. Should a
  built-in ever be edited in place? The model says no — its definition ships
  with the app.
- **Where Import comes from.** A file today; a URL or a shared gallery later
  needs the same *it will send your key to that address* step.
