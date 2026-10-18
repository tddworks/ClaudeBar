---
description: Contributor design for In use — choosing which login new claude/codex sessions start with. The record file and the LoginsInUse port, Provider.inUse and its rules, NewSessions and the ShellLines port, the shell lines ShellSetup writes, Switch when low, and the notification and claudebar://use link. Read before touching In use, the shell setup or account switching.
---

# In use: design

User guide: [README.md](README.md). Mockup: `design-concept/in-use/index.html`.

**Status: BUILT.** Choosing (popover, Settings, `claudebar://use`), the one-time shell setup (zsh, bash, fish), the low suggestion and its notification, and opt-in *Switch when low*.

| For | Read |
|---|---|
| Logins, folders, `Account`, `Provider` | [multiple accounts](../providers/multi-account/design.md) |
| `claudebar://` routing | [URL schemes](../app/url-schemes/README.md) |

## The one sentence

**New sessions of a CLI start on the login whose folder is recorded for it; ClaudeBar records it, the shell reads it, and nothing else moves.**

In use is a **capability** ([CANONICAL §2.1](../../architecture/CANONICAL_MODEL.md#21--what-a-provider-owns-what-it-offers-and-what-it-isnt)): declared by `accounts.signIn` (the lines it writes are `accounts.cli.environment.set`), reached as `provider.inUse` (`nil` when not declared), never a flag on `Provider`. Pieces and flows: [TARGET §9](../../architecture/TARGET_ARCHITECTURE.md#9--in-use-as-a-capability).

```
 views · claudebar://use · notification button          (render and tell — decide nothing)
        │ newSessions.use(login) / use(providerId:account:)
        ▼
 NewSessions (Domain) ── lines not in the shell? ── waits ──▶ setUp · setUpByHand · cancel · turnOff
        │                                                    └── ShellLines (port) ← ShellSetup
        ▼
 provider.inUse: InUse (Providers) ── use(login) ──▶ LoginsInUse (port) → ~/.claudebar/in-use/<command>
        ▲                                                                          │ read on every run
 QuotaMonitor.onRefreshed ─▶ newSessions.review ─▶ inUse.review()                 ▼
        (knows no In use)        └─▶ InUseAnnouncer (port) ← InUseNotifications   $ claude → CLAUDE_CONFIG_DIR=<folder>
```

No token is copied: each login keeps its own Keychain item and refresh token. No traffic goes through ClaudeBar.

## 1 · Ubiquitous language

| Term | Meaning | Not to be confused with |
|---|---|---|
| **in use** | the login new terminal sessions of a CLI start with | the *default* login (the plain one the CLI uses on its own), the *selected* chip, an *active* account (every login is still fetched) |
| **new terminal sessions** | the next `claude` / `codex` run from a shell with the lines | running sessions, Claude Desktop, IDE extensions |
| **the record** | `~/.claudebar/in-use/<command>` — one per CLI (`claude`, `codex`): the folder, or empty for the plain login | settings.json (keeps no copy); a product's id |
| **the shell lines** | the block between `# >>> claudebar in-use >>>` markers, or fish's own file | the user's own aliases and exports |
| **worth switching** | the login in use is critical or out, and another has more left | *Switch when low* (acts, opt-in) |

## 2 · The aggregate

```
Provider
└── inUse: InUse?  ◆                  nil unless accounts.signIn is declared and a record exists
    ├── login: Account                the plain login until another is chosen
    ├── logins: [Account]             the plain login + folder logins; offersChoice when > 1
    ├── command: TerminalCommand ◇    cli + accounts.cli.environment.set
    ├── use(_) · forget(_)            forget is told by Provider.remove
    ├── worthSwitchingTo: Account?
    ├── review() → InUseNotice?       switched, or worth switching — told once per low
    └── switchWhenLow: SwitchWhenLow ◆   isOn · below · mayPick · next(from:among:)
Account: isInUse · canBeInUse (only when there is a choice) · useForNewSessions() · percentLeft

NewSessions  ◆  (Domain)             products (those with inUse) · shell · isSetUp · waiting · problem
├── state(of:) → .waitingForSetup | .worthSwitching(from, to) | .using(login, among:)
├── use(_) · use(providerId:account:) → .used | .waitingForSetup | .unknown
├── setUp() · setUpByHand() · cancel() · turnOff()
├── review(_ refreshed)              registered on QuotaMonitor.onRefreshed
├── ShellLines (port)  ← ShellSetup (Infrastructure)
└── InUseAnnouncer (port) ← InUseNotifications (Infrastructure)
```

## 3 · The tells

```swift
if let state = newSessions.state(of: product) { InUseStrip(state: state) }   // the strip renders a state
newSessions.use(login)                                                       // a chip's Use, its right-click, the Settings radio, the banner
switch newSessions.use(providerId: id, account: name) { … }                 // claudebar://use
monitor.onRefreshed { await newSessions.review($0) }                         // the composition root wires it
if let inUse = provider.inUse, inUse.offersChoice { InUseSettingsSection(inUse: inUse) }
```

Views never compare accounts, inspect folders, count logins or read quotas.

## 4 · Invariants — each law, one owner

| Law | Owner |
|---|---|
| The login in use is the plain login or a folder login of the same product; nothing recorded, or a folder no login has, is the plain login | `InUse` |
| Only the folder is recorded, nowhere else, under the CLI's name | `LoginsInUse` / `DiskLoginsInUse`, keyed by `InUse.command.name` |
| A CLI is wrapped once, however many products run it; two products on one CLI share its record, the last choice wins, and the other shows its plain login | `NewSessions.commands` (each once) · `ShellSetup` |
| Removing the login in use goes back to the plain login | `InUse.forget`, told by `Provider.remove` |
| A login worth switching to is told once per low | `InUse.review` |
| *Switch when low* is off until turned on, moves only below its threshold to a ticked login with more left | `SwitchWhenLow` |
| A login chosen before the lines exist waits; the plain login never waits | `NewSessions.use` |
| Turning off removes the lines and puts every CLI back on its plain login | `NewSessions.turnOff` |
| What the strip shows | `NewSessions.state(of:)` |
| The lines are written once, replace an alias for the CLI, and removing takes out nothing else | `ShellSetup` |
| What follows a refresh is never the Monitor's | `QuotaMonitor.onRefreshed` |
| `claudebar://use` takes exactly `provider` and `account`, each once | `URLSchemeAction` |

Changed by this feature: a folder ClaudeBar made by *Sign in with browser* was "ClaudeBar's, and nothing else uses it". Now the person's terminal may use it, through the record ([multiple accounts](../providers/multi-account/design.md)).

## 5 · Open questions

- ~~Copy tokens into the default login's place?~~ **No.** Refresh tokens rotate, so two copies log one of them out.
- ~~Symlink a fixed folder to the login in use?~~ **No.** Claude names a folder's Keychain item from a hash of its path, so a symlinked path finds no login.
- ~~Proxy the CLIs' traffic and switch per request?~~ **No.** That breaks provider terms, routes prompts through ClaudeBar, and makes coding depend on a menu bar app.
- **API-key providers** (env variables, not folders): an env-variable version of the record and lines.
- **A shell that isn't zsh, bash or fish**: the lines can be copied and adapted by hand.
