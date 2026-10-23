---
description: Who uses ClaudeBar and what they ask — the people, the moments from glancing at the menu bar, fixing and adding a provider, to switching logins, following a session and looking back, the words each screen prints and the command each lands on; read first, before any design change.
---

# ClaudeBar — user journeys

> **#1 of 5** in [the design](ARCHITECTURE.md) · **Answers:** who is asking,
> and what · **Builds on:** nothing — every other document answers this one ·
> **Next:** [CANONICAL_MODEL.md](CANONICAL_MODEL.md)
>
> Where a journey and the model disagree, the journey wins and the model moves.
>
> **The mockup:** [provider-user-journeys.html](../../design-concept/provider-user-journeys.html)
> — open it in a browser; ← → step through the moments, `#7` jumps to one.

---

## 1 · The people

| Who | Wants | Journey |
|---|---|---|
| **Mia** — Claude Code and Codex all day | to know, without opening anything, whether she can keep going | *Glance* |
| **Raj** — Codex stopped updating | the app to say what is wrong and where to fix it, in one place | *Fix* |
| **Ken** — pays for a gateway ClaudeBar doesn't ship (OpenRouter) | to track its credits without writing a script | *Add* |
| **Lin** — runs the team's internal LLM gateway | her team to get the provider without anyone retyping it | *Share* |
| **Mia**, again — a personal and a work login | the next `claude` to start on the one with room, without signing out | *Switch* |
| **Ana** — long Claude Code sessions, often in another window | to know when Claude needs her, or is done, without watching the terminal | *Follow* |
| **Tom** — on a subscription, curious what it's worth | what he used, day by day, and what it would have cost on the API | *Look back* |
| **Mia**, away from her desk | her quota on her phone | *Carry* |

Each journey is a promise. A screen that serves none of them is a screen to
question; a person here that no screen serves is a gap.

## 2 · The moments

Each row: what the person sees (the words the screen prints), what they do,
the command that lands on the domain, and the node that answers.

| # | Moment | Sees | Does | Command | Node |
|---|---|---|---|---|---|
| 1 | Mia glances at the menu bar | *38%*, amber | nothing | `monitor.lowestQuota` | `Monitor` → worst `Quota.status` |
| 2 | Mia opens the popover | *Session · Weekly · Spark*, *% left*, *Resets in 1h 12m*, *Running hot*, *EXTRA USAGE*, *Updated 2m ago · via RPC*, *PLUS* | switches to a lighter model for an hour | `account.usage` | `Usage` → `[Quota]` · `Cost` · `Plan` |
| 2a | Mia has two Codex logins | one **Codex** tab in the popover: **ACCOUNTS** *Personal* and *Work — Acme* side by side, each with its own quotas, and a **PAUSED** row for a login she stopped watching; Settings lists one **Codex** with *Add Account…* and a toggle per login | pauses *work* on the weekend from the popover — right-click the login, **Pause**; later clicks *work* when *me* runs low, or **Resume** on Monday | `monitor.pause(_:)` · `resume(_:)` · `monitor.select(account)` · `provider.bestAccount` | `Provider` (the product) → `[Account]` (the logins) |
| 2b | Mia adds her work Codex | **Add Account…** — *Sign in with browser*, *Choose Signed-in Folder*, or the form's *API KEY*; then *Work — Acme* beside *Personal*, each with its own quotas | signs in to work in the browser | `provider.signIn()` · `provider.addAccount(signedInAt:)` · `addAccount(filling:)` | `Account` — shown only through its own sign-in: the default one is signed in on this Mac, an added one through its folder or key |
| 3 | Raj sees Codex fail | *Couldn't read your key* · *Session expired. Run `codex` in terminal to log in again.* · last usage dimmed, *Last seen 3h ago* | logs in, or opens settings | `account.sync.lastError` | `DataSourceError(step: .lookup)`; `usage` kept |
| 3a | Raj has only the Codex app, no `codex` command | *NOT SET UP* — *CLI not found* — though the app on his Mac carries one | expects nothing to do | `provider.refresh(account)` | the definition says where its CLI may be; no setting needed (#458) |
| 4 | Raj opens Codex settings | *DATA SOURCE: RPC · API*, *KEY LOOKUP ORDER*, *Test Connection*, *Built in* | switches to RPC, tests | `provider.use("rpc")` · `dataSource.fetchUsage()` | `Provider.dataSources` · `CredentialLookup` |
| 5 | Ken: *Add Provider* | *Start from: API · CLI · File · Copy a provider*, *Import…* | chooses API | `ProviderDefinition.blank(.http)` · `definition.copy()` | `ProviderDefinition` (unsaved) |
| 6 | Ken: *Connect* | *URL*, *Key lookup order: Environment variable · API key*, *Sent as*, *Test Connection*, *200 OK* | pastes his key, tests | `dataSource.fetchResponse()` | `Fetch.http` · `CredentialLookup` → `Response` |
| 7 | Ken: *Map fields* | *Response*, *Remaining · Limit · Resets*, *never — a balance*, a live card | clicks `12.4`, then `50` | `mapping.quotas.append(.money(remaining:of:))` | `Mapping.json` → `Quota.left = money`, `window = nil` |
| 8 | Ken: *Look* | *Name*, *Symbol · colour*, *Save* | names it, saves | `catalog.add(definition)` | `ProviderProfile` · `ProviderLook` · `ProviderCatalog` |
| 9 | Ken sees it in the popover | *OpenRouter*, *$12.40 of $50.00*, *via API*, *CUSTOM* | nothing — no restart | `provider.refresh()` | one `Provider`, one `DataSource` — the types Codex uses |
| 10 | Lin exports | *Built in · Custom · Extension*, *Export…*, *no keys — they stay in your Keychain* | posts the file | `definition.exported()` | `ProviderDefinition`, secrets stripped |
| 11 | A teammate imports | *Import provider*, *It will send your key to that address*, *Key needed*, *Test Connection*, *Add* | pastes his own key, adds | `catalog.import(file)` · `definition.missingSettings` | `ProviderCatalog` · `SettingsForm` |

### Beyond the menu bar

| # | Moment | Sees | Does | Command | Node |
|---|---|---|---|---|---|
| 12 | Mia's work login runs low in the terminal | the popover: *IN USE* on *work*'s chip, *Use* on *me*'s; below 20%, *Use for New Sessions*, and a notification with the same button | clicks *Use* | `newSessions.use(account)` → `provider.inUse.use(account)` | `InUse` — the terminal's choice, not the monitor's |
| 13 | Mia's first switch | the lines ClaudeBar will add to her shell; *Add to ~/.zshrc* · *Copy — I'll Add It* | adds them | `newSessions.setUp()` | `NewSessions` · `ShellSetup` |
| 14 | Mia turns on *Switch when low* | below the threshold, new sessions move to the ticked login with the most left; a notification with *Undo* | nothing more | `inUse.switchWhenLow.isOn` | `SwitchWhenLow` |
| 15 | Ana's session waits for a permission | the notch: ⚠︎ *Needs you* and the prompt text; it never times out | answers in the terminal | — (hooks report it) | Activity: `SessionMonitor` → `NotchActivityResolver` |
| 16 | Ana's turn ends | ✓, the repo, the task count and duration; *Claude Code Finished: project — Completed 3 tasks in 12m* | nothing | — | Activity; a destination for the notification |
| 17 | Tom opens the popover | *TODAY'S USAGE*: *Cost Usage*, *Token Usage*, *Working Time*, each *Vs* yesterday; *Daily usage — last 30 days*; once turned on in Settings, *Usage — last year* as a heatmap, and *Model Mix — last year* | hovers a bar or a cell | `account.usageHistory?.days(in:)` | `UsageHistory` — the login's, read when the popover opens |
| 18 | Mia glances at her phone | the Lock Screen *ClaudeBar* Live Activity: the worst quota first, *% left*, the reset countdown | nothing | — (published on refresh) | a destination: Notify! |
| 19 | Mia wants warning sooner than 20% | Settings → Sync & Alerts: *Quota alerts*, *Alert me below 35%*; later a notification: *Claude · work is below 35% — 34% left* | adds 35%, keeps working | `quotaAlerts.add(35)`; after a refresh `quotaAlerts.review(login)` | `QuotaAlerts` — a destination, outside the monitor |
| 19a | Mia's team should hear it too | Settings → Sync & Alerts → *Webhooks*: *Add Webhook*, *Slack · JSON*, *Every login*, *Quota alerts · Status alerts*, *Send a test*, *Sent 2m ago*; in Slack: *Claude · work is below 35% — 34% left* | pastes the team's Slack URL, sends a test | `webhooks.add(url:…)` · `sendTest(_:)`; each alert → `webhooks.announce(alert)` | `Webhooks` — a destination; `QuotaAlerts` and `StatusAlerts` decide |

## 3 · What the journeys found

Thirteen findings; each is a word or a law the model must keep.

| # | Finding | From moment |
|---|---|---|
| F1 | The popover says **which data source answered** (*via RPC*, *via Terminal* after a fallback) | 2 |
| F2 | An error **names the step that failed** — *Couldn't read your key* · *Couldn't connect* · *Couldn't find the numbers* — because each sends the person somewhere different | 3 |
| F3 | Settings prints **DATA SOURCE** and the API source's **key lookup order**; the fallback is one sentence, not a setting | 4 |
| F4 | *Add Provider*'s picker is a **closed list in the words Settings already prints** — *API · CLI · File* — plus *Copy a provider* | 5 |
| F5 | *Test Connection* must **stop before mapping**: Ken has nothing mapped yet, but must see what came back | 6 |
| F6 | *Map fields* asks four questions — **Used · Remaining · Limit · Resets** — plus the currency; a balance has no percentage to ask for and *never* resets | 7 |
| F7 | A custom provider has its **look from day one** | 8 |
| F8 | The screen calls a user-made provider **CUSTOM** | 9, 10 |
| F9 | An exported provider **carries no key** | 10 |
| F10 | Import **says where the key will go** before asking for it; a *CLI* provider from someone else shows its command and asks before saving | 11 |
| F11 | Two logins of one product are **two things Mia watches** but **one thing Raj fixes**: each login is a pill and a menu-bar entry; the data source, its settings and the look are set once for Codex | 2a, 4 |
| F12 | **Pause is not remove**: a login can be switched off without losing its folder, and a paused login stays on the popover's page, dimmed and resumable — a login never disappears without saying which of the two happened; an expired key is not a red quota — it reads *Couldn't read your key*, not CRITICAL | 2a, 3 |
| F13 | **An account shows only what its own sign-in reaches.** The default account is the one signed in on this Mac — the terminal's CLI, its environment, its folders, the Keychain, the browser. An added account is signed in through the folder or the key Mia gave it, and never shows anything of this Mac: two accounts showing the same numbers is the one thing that makes her stop trusting both | 2b |

## 4 · The words the new screens print

*Add Provider* · *Start from* · *API · CLI · File* · *Copy a provider* ·
*Import* · *Connect* · *URL* · *Key lookup order* · *Environment variable* ·
*API key* · *Sent as* · *Test Connection* · *Response* · *Map fields* ·
*Used · Remaining · Limit · Resets* · *never — a balance* · *Look* · *Name* ·
*Symbol · colour* · *Save* · *Built in · Custom · Extension* · *Export* ·
*Key needed* · *Couldn't read your key · Couldn't connect · Couldn't find the
numbers* · *via API* · *ACCOUNTS* · *PAUSED* · *Pause* · *Resume* ·
*All logins paused* · *340% left across 3 logins*.

## 5 · Acceptance scenarios

The outer loop for these screens, in `Tests/AcceptanceTests`:

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

Scenario: Pausing a login from the dashboard
  Given Mia has two Codex logins and the popover is open on Codex
  When she right-clicks "Work — Acme" and presses "Pause"
  Then Work stops refreshing, leaves the menu bar and the ACCOUNTS chips, and no alert can name it
   And it is listed under PAUSED with "last seen" and a "Resume" button
  When she presses "Resume"
  Then Work counts again, with the numbers it last showed

Scenario: An added account shows only its own sign-in
  Given Mia's terminal is signed in to Codex as Personal
   And she adds Work by choosing its signed-in folder
  When the popover refreshes
  Then Work shows Work's usage
   And nothing on this Mac — its environment, ~/.codex, another tool's logs — appears under Work
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
