# Changelog

All notable changes to ClaudeBar will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **The daily chart's chip decides all it shows** — the 30-day total, the hovered day and each model; a login that prices nothing (OpenCode Go) drops Cost for tokens. ([#566](https://github.com/tddworks/ClaudeBar/issues/566)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/usage-history/daily-usage/README.md)

### Fixed
- **OpenCode daily usage showed no output and a 30-day total of 0**: reasoning tokens now count as output, and the Tokens chip totals tokens rather than the (zero) cost. ([#566](https://github.com/tddworks/ClaudeBar/issues/566))
- **Claude's token refresh no longer narrows your login**: a renewed token asks for the scopes your login already has, not a fixed three, so it keeps every capability the old one had (e.g. `user:mcp_servers`). ([#593](https://github.com/tddworks/ClaudeBar/issues/593)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/providers/claude/design.md)
- **Antigravity's quota shows while `agy` is open in a terminal**: ClaudeBar asks the running app, instead of failing with "Authentication required" when the `agy` session had started first. ([#594](https://github.com/tddworks/ClaudeBar/pull/594))

---

## [0.5.18] - 2026-10-21

### Fixed
- **Antigravity's Claude pool says which window it is**: its quotas read "Claude 5h" and "Claude 7d" instead of "Claude" and "Claude Weekly", so two of them side by side can be told apart. ([#589](https://github.com/tddworks/ClaudeBar/issues/589))

### Added
- **The Notify! tile's quota windows can stay where they are**: Settings → Notify! → Tile Order → Fixed positions keeps each provider's windows together and in the same place, instead of reordering the row as the percentages change. The lowest quota still colours the tile. ([#589](https://github.com/tddworks/ClaudeBar/issues/589)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/alerting/notify/README.md)
- **Antigravity, Gemini 4 Argon**: shows the separate weekly quota pool for Gemini 4 Argon (`ARGON WEEKLY`) when reported by Antigravity. ([#591](https://github.com/tddworks/ClaudeBar/pull/591)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/providers/antigravity/README.md)

---

## [0.5.17] - 2026-10-19

### Changed
- **Each added account shows only its own sign-in**: a second account never reads this Mac's keys, logs or database, and an added Codex account now falls back to its own terminal too. ([#577](https://github.com/tddworks/ClaudeBar/issues/577)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/providers/multi-account/design.md#what-an-accounts-sign-in-reaches)
- **One script engine and SQLite everywhere**: provider scripts run in a bundled QuickJS instead of JavaScriptCore, and app databases through a bundled SQLite, so Windows runs them too. Mac quotas are unchanged. ([#571](https://github.com/tddworks/ClaudeBar/pull/571), [#570](https://github.com/tddworks/ClaudeBar/issues/570)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/architecture/MODULAR_DESIGN.md#10-one-package-two-platforms)
- **Commands and scripts on Windows**: providers that run a command, a script or a JSON-RPC CLI now run on Windows, on the Mac's pipe runner. An extension's script must be a `.cmd`, `.bat` or `.exe` there. ([#580](https://github.com/tddworks/ClaudeBar/pull/580), [#579](https://github.com/tddworks/ClaudeBar/issues/579)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/architecture/MODULAR_DESIGN.md#10-one-package-two-platforms)

### Fixed
- **A provider's API key can no longer be sent anywhere but its own site**: a redirect to another address is not followed, and a key can no longer reach the log file through a failed request either — registered keys are scrubbed from every log line. ([#585](https://github.com/tddworks/ClaudeBar/pull/585))
- **An added Mistral account showed this Mac's Vibe sessions as its own**: it now shows only its own web usage. ([#578](https://github.com/tddworks/ClaudeBar/issues/578), [#577](https://github.com/tddworks/ClaudeBar/issues/577))
- **Claude's default account honours `CLAUDE_CONFIG_DIR` for its credentials file**, as it already did for its account file. ([#577](https://github.com/tddworks/ClaudeBar/issues/577))
- **OpenCode Go on OpenCode 2**: without an API key, the estimate and daily cards read opencode's database directly, so OpenCode 1 and 2 both work and spend from before an upgrade still counts. ([#566](https://github.com/tddworks/ClaudeBar/issues/566), [#572](https://github.com/tddworks/ClaudeBar/pull/572))
- **Leaderboard provider filter**: a long provider name no longer wraps inside its chip ("OpenCo / de Go"); chips stay on one line and the row scrolls, so every filter stays reachable. ([#576](https://github.com/tddworks/ClaudeBar/pull/576))

### Added
- **Bars on the All page**: Settings → General → All Page Style prints each provider as a row with a bar per quota, ordered by the windows a provider states — most state none and read tightest first. Rings stay the default. ([#575](https://github.com/tddworks/ClaudeBar/issues/575)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/monitoring/all-providers/README.md)

---

## [0.5.16] - 2026-10-16

### Changed
- **One empty account no longer turns its provider DEPLETED**: a provider's accounts are interchangeable, so its header, its All card and Settings read its healthiest account. Each account still shows its own status and reset. ([#568](https://github.com/tddworks/ClaudeBar/pull/568), [#564](https://github.com/tddworks/ClaudeBar/pull/564)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/providers/multi-account/README.md)

### Fixed
- **Windows Leaderboard days**: a day of usage is counted in your own time zone, as Windows has it, instead of GMT, so in Korea a day no longer ends at 09:00. The Mac app is unchanged. ([#567](https://github.com/tddworks/ClaudeBar/pull/567), [#565](https://github.com/tddworks/ClaudeBar/issues/565)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/architecture/MODULAR_DESIGN.md#10-one-package-two-platforms)
- **Oh My Pi, Antigravity**: each card says which models it counts, Gemini or Claude & GPT, instead of "Antigravity Weekly (2)", and the pool Claude and GPT share shows once, not twice. A menu-bar pick of an Antigravity quota needs choosing again. ([#562](https://github.com/tddworks/ClaudeBar/pull/562)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/providers/omp/design.md)
- **Stuck on Syncing... again**: stopping a CLI at its deadline no longer waits forever when the CLI is still running after being killed. ClaudeBar gives it 2 seconds, then logs a warning naming it and its process id, and moves on to the fallback. ([#561](https://github.com/tddworks/ClaudeBar/pull/561), [#550](https://github.com/tddworks/ClaudeBar/issues/550)) -> [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/providers/codex/design.md)
- **OpenCode daily usage**: the 30 days a query kept for itself now come from the range you asked for, so an older day is counted on its own day instead of read as empty and kept that way. ([#559](https://github.com/tddworks/ClaudeBar/pull/559)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/providers/opencode-go/README.md)

### Added
- **Pause an account from the popover**: right-click it and choose **Pause**. It stops refreshing, leaves the menu bar, and can no longer raise an alert, but stays on the provider's page under **PAUSED** with its last numbers and a **Resume**. ([#560](https://github.com/tddworks/ClaudeBar/pull/560)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/providers/multi-account/README.md)
- **OpenCode on the Leaderboard**: tick OpenCode when you join and your daily token totals — every provider opencode drove, Zen included — are ranked, read from opencode's own database through one read-only query. Its tokens and cost also show in the daily usage cards. ([#559](https://github.com/tddworks/ClaudeBar/pull/559)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/leaderboard/README.md)
- **Windows file paths**: shared provider definitions find app-data files on Windows as well as Mac, including redirected `APPDATA` and the newest IDE quota file. Windows execution and quota display remain phase 5. ([#556](https://github.com/tddworks/ClaudeBar/pull/556), [#555](https://github.com/tddworks/ClaudeBar/issues/555)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/architecture/ENGINE_DESIGN.md)

---

## [0.5.15] - 2026-10-13

### Fixed
- **Stuck on Syncing…**: a login shell that never finished, asked where a CLI is before a refresh starts it, no longer holds that refresh and every later one on *Syncing…*. It has 10 seconds, then ClaudeBar looks in the usual folders and logs a warning naming the shell. ([#554](https://github.com/tddworks/ClaudeBar/pull/554), [#550](https://github.com/tddworks/ClaudeBar/issues/550))
- **Oh My Pi, Qwen Cloud**: a Qwen Cloud Token Plan signed into omp shows as Qwen Cloud, not Alibaba Token Plan, and points at omp's console cookie, the step its quota needs, instead of just "No usage reported"; Grok no longer shows as "Xai Oauth". ([#553](https://github.com/tddworks/ClaudeBar/pull/553)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/providers/omp/README.md)
- **Leaderboard joining**: when the leaderboard key can't be stored, joining now stops and says so, instead of joining anyway and dropping out at the next launch with the username taken. ([#548](https://github.com/tddworks/ClaudeBar/pull/548))

### Added
- **Leaderboard, several Macs**: Settings → Leaderboard → Devices lists each Mac on your name, adds one by the code it shows (**Already a member? Add this Mac**) and removes one; a Mac with a copied key asks what it is. ([#552](https://github.com/tddworks/ClaudeBar/pull/552)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/leaderboard/README.md)
- **Leaderboard, a copied key**: a Mac whose leaderboard key came from another Mac (Migration Assistant, a restore) now notices and uploads nothing under it, so the two stop overwriting each other's days; the popover says why. The answer comes with the next Settings. ([#549](https://github.com/tddworks/ClaudeBar/pull/549)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/leaderboard/README.md)

---

## [0.5.14] - 2026-10-11

### Fixed
- **Leaderboard export**: *Export my data* in Settings → Leaderboard saves everything the server holds about you, every day you ever uploaded and which Mac sent it, as the server sent it. Before, it saved only the last 31 days, without which Mac sent each one. ([#544](https://github.com/tddworks/ClaudeBar/pull/544)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/leaderboard/README.md)

### Added
- **Cloudflare AI**: a new provider, off by default. With a read-only API token it shows today's Workers AI neurons against the free 10k, the month's Workers AI and AI Gateway tokens, the Workers Paid overage estimate and your last invoice. ([#545](https://github.com/tddworks/ClaudeBar/pull/545)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/providers/cloudflare-ai/README.md)

---

## [0.5.13] - 2026-10-11

### Removed
- **Overview Mode**: the switch in Settings → General is gone; the new **All** pill does its job in one tap. If you had it on, the popover opens on All. ([#539](https://github.com/tddworks/ClaudeBar/pull/539)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/monitoring/all-providers/README.md)

### Added
- **All providers**: an **All** pill, first in the popover, shows every provider on one page, a card each with the quota that runs out first. Click a card to open that provider; ⌘0 comes back. Settings → General → Open On makes it the first page you see. ([#539](https://github.com/tddworks/ClaudeBar/pull/539)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/monitoring/all-providers/README.md)

---

## [0.5.12] - 2026-10-10

### Changed
- **Claude Code card**: finished sessions no longer take a row each. The card shows a count (*1 needs you · 2 working · 5 done*) and rows only for sessions still going; ▾ shows the Done ones, one row per repo. *Needs you* is now red and *Done* grey, in the menu bar and notch too. ([#534](https://github.com/tddworks/ClaudeBar/pull/534)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/activity/session-hooks/README.md)

### Fixed
- **Antigravity with the app closed**: when the saved sign-in has expired, ClaudeBar runs `agy` once to renew it and shows your quota, instead of *Session expired* whenever Antigravity hadn't run for an hour. ([#541](https://github.com/tddworks/ClaudeBar/issues/541))
- **The 30-day chart**: the *Daily usage — last 30 days* card draws as soon as the popover opens, the way the cards above it do — before, it stayed invisible for a second and never appeared at all in a screenshot. ([#536](https://github.com/tddworks/ClaudeBar/pull/536))

### Added
- **Session titles**: each Claude Code session shows its title under the repo, in the popover card, the notch and notifications: the name you gave it with `/rename`, else Claude Code's own. Two terminals in one repo are told apart at a glance. ([#538](https://github.com/tddworks/ClaudeBar/pull/538)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/activity/session-hooks/README.md)
- **Your own popover title**: name the popover header your own way, such as your team's name, in place of *ClaudeBar* (Settings → Appearance → Popover Title). Leave it blank to go back. ([#532](https://github.com/tddworks/ClaudeBar/pull/532)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/app/popover-title/README.md)

---

## [0.5.11] - 2026-10-09

### Fixed
- **Codex with its login in the Keychain**: when the Codex CLI keeps its login in the macOS Keychain instead of `~/.codex/auth.json`, RPC mode now reads your usage instead of asking you to log in. ([#525](https://github.com/tddworks/ClaudeBar/issues/525))
- **Leaderboard tab on refresh**: opening the popover, Refresh or a new upload keeps your rank and the board on screen until the new ones arrive, instead of going back to *Loading…*; if updating fails, the last board stays with a note. ([#524](https://github.com/tddworks/ClaudeBar/pull/524))

### Added
- **Daily usage by model**: the 30-day chart splits by model — choose what is counted (cost, tokens, cache) and split the bars by the models the log names; hover a day to see each model's part, the unnamed line included. ([#511](https://github.com/tddworks/ClaudeBar/pull/511)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/usage-history/daily-usage/README.md)

---

## [0.5.10] - 2026-10-08

### Changed
- **Leaderboard uploads**: a day the server refuses on its own, such as one over the daily cap, no longer holds back the rest: the other days go through, and that day is sent again with each upload until it's taken or 30 days old. ([#522](https://github.com/tddworks/ClaudeBar/pull/522)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/leaderboard/README.md#gotchas)
- **"Rate limited" message**: the wait until the retry is rounded to the nearest minute, hour or day, so 29 min 59 s reads "Retrying in 30 minutes", not "in 29 minutes". ([#523](https://github.com/tddworks/ClaudeBar/pull/523)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/architecture/MODULAR_DESIGN.md#10--one-package-two-platforms)

### Fixed
- **Codex stuck on *Syncing…***: when `codex app-server` stops answering, ClaudeBar gives up after 15 seconds, tries the terminal instead and keeps refreshing, so usage no longer freezes until you relaunch. ([#517](https://github.com/tddworks/ClaudeBar/issues/517))
- **Leaderboard tab while loading**: it says *Loading…* until your rank and the board come back, instead of showing 0 tokens and an empty board. ([#521](https://github.com/tddworks/ClaudeBar/pull/521))
- **Daily usage cards**: cost, tokens and working time show one number on one line again, and Oh My Pi's get their own *TODAY'S USAGE* title instead of reading as the last account's. ([#514](https://github.com/tddworks/ClaudeBar/pull/514))

### Added
- **Mistral Vibe plan usage**: paste your chat.mistral.ai cookie and Mistral shows how much of the plan is left and when it resets, beside today's Vibe spend. ([#496](https://github.com/tddworks/ClaudeBar/issues/496)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/providers/mistral/README.md)

---

## [0.5.9] - 2026-10-07

### Fixed
- **"Support for apps for Intel processors" warning**: ClaudeBar now runs a tool's native Apple-silicon copy when one exists and asks the system shell, not an Intel-only one, for PATHs — so macOS stops naming ClaudeBar for a tool it ran. ([#251](https://github.com/tddworks/ClaudeBar/issues/251))

### Added
- **Turn the Leaderboard off**: hide its tab and stop uploads from Settings → Leaderboard, from the join form, or once joined from the tab's **Turn off ▾**, which also takes you off the globe or lets you leave. A joined member's name and days stay. ([#510](https://github.com/tddworks/ClaudeBar/pull/510)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/leaderboard/README.md#turning-it-off)
- Settings → Appearance → Popover Text Size scales the popover's text up to 1.4× and widens the window to fit. ([#364](https://github.com/tddworks/ClaudeBar/issues/364)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/settings.md)

---

## [0.5.8] - 2026-10-06

### Changed
- **Leaderboard web board**: the board scrolls inside its card so the globe is close by, the globe shows the tokens its countries total, and country names in its list are no longer cut in half. ([#503](https://github.com/tddworks/ClaudeBar/pull/503)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/leaderboard/README.md)

### Fixed
- The popover opens scrolled to the top every time, instead of where you left it last time.
- Every running Claude Code session is tracked, including ones started before ClaudeBar; before, only the newest one changed the status. The popover card lists each with its state, most pressing first; the menu bar follows the one that most needs you.
- The session card names states the way the notch does — Working, Agents working, Needs you, Done — instead of Active, Needs You and Stopped.
- A Claude Code session that has just opened, or been resumed, shows Done until you send it a prompt instead of Working; and the durations in the session card now tick while the popover is open.
- A session no longer flips back to Working when Claude Code reports a subagent stopping a moment after the turn ended; it stays Done until your next prompt.
- A session whose turn ended in an error (the connection dropped while the Mac slept, say) now shows Done instead of staying on Working: ClaudeBar listens to Claude Code's `StopFailure` hook.
- A Claude Code session that was killed without ending cleanly (a crash, a closed terminal) is dropped within 30 seconds instead of staying until ClaudeBar restarts.

### Added
- **Share your rank**: Share on the Leaderboard's *Your rank* makes an image of your place, square or wide, with your name shown or masked, to copy, save or share. Drawn on your Mac; nothing is uploaded. ([#504](https://github.com/tddworks/ClaudeBar/pull/504)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/leaderboard/README.md#share-your-rank)
- **Oh My Pi daily usage**: today's cost and tokens, the 30-day chart and Leaderboard sharing for Oh My Pi, read from omp's own session logs — subagents and the model calls it makes outside the chat included, a forked session's copies counted once. ([#502](https://github.com/tddworks/ClaudeBar/pull/502)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/providers/omp/README.md#daily-usage)
- **Platformer's runner**: a small pixel runner walks the brick floor. It strolls when your quota is healthy, runs when it's low, falls into a pit when it's empty, and jumps for a coin after each refresh. Turn it off in Settings → Appearance → Runner. ([#505](https://github.com/tddworks/ClaudeBar/pull/505)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/app/themes/README.md)

---

## [0.5.7] - 2026-10-06

### Changed
- **Leaderboard** is the first tab in the popover's row, so it's always in reach; the popover still opens on your first provider. ([#501](https://github.com/tddworks/ClaudeBar/pull/501)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/leaderboard/README.md)

### Fixed
- Pop theme: a dollar balance or spend now prints in the same outlined style as a percentage, with its caption beside it, so a card's big numbers no longer look like two different fonts ([#499](https://github.com/tddworks/ClaudeBar/issues/499))

### Added
- **Platformer theme**: a Super Mario–style 8-bit level with a score line, a ? block to refresh, blocks for bars and Pixel or Classic text. ([#501](https://github.com/tddworks/ClaudeBar/pull/501)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/app/themes/README.md)

---

## [0.5.6] - 2026-10-05

### Changed
- **Leaderboard globe**: the globe on the web board opens facing where members are, marks each country with a labelled glowing dot, and shows a country's details on a tap as well as a hover, so phones get them too. ([#493](https://github.com/tddworks/ClaudeBar/pull/493)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/leaderboard/README.md)
- **License**: ClaudeBar is now licensed under Apache 2.0 instead of MIT. It stays free and open source, and the license now also grants patent rights. → [docs](https://github.com/tddworks/ClaudeBar/blob/main/LICENSE)
- **Claude**: each refresh in CLI mode runs Claude Code once, not twice, under one ClaudeBar session that keeps its id across restarts — about 2 seconds faster, and your session hooks fire once per refresh. ([#491](https://github.com/tddworks/ClaudeBar/pull/491)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/providers/claude/design.md)

### Fixed
- **Claude**: in CLI mode, your limits are read from Claude Code again instead of switching to the API after the first refresh. ClaudeBar misread Claude Code 2.1.289's usage screen and its "no conversation found" answer. ([#490](https://github.com/tddworks/ClaudeBar/pull/490))
- **Claude**: your email stays on the account card after a refresh answered by the API. It used to show at first and vanish when the API stood in for the CLI, leaving only "Updated · via API". ([#489](https://github.com/tddworks/ClaudeBar/pull/489))

### Added
- **Grok** shows your plan (SuperGrok, SuperGrok Heavy, …) and your prepaid balance, and a reset time when xAI names only the billing period. ([#485](https://github.com/tddworks/ClaudeBar/pull/485)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/providers/grok/README.md)
- **Six new providers**, off until you turn them on: Cline and Warp limits and credits, Devin's quota from your browser sign-in, Windsurf and JetBrains AI from their apps on your Mac, and OpenAI API spend over 30 days. ([#485](https://github.com/tddworks/ClaudeBar/pull/485)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/README.md)

---

## [0.5.5] - 2026-10-05

### Changed
- **Leaderboard globe**: your country shows on the globe from the first member there who shares it, so the globe is no longer empty while members are spread out. Members and tokens for a country still show only once three members there share it, so no number is one person's own. → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/leaderboard/README.md) ([#480](https://github.com/tddworks/ClaudeBar/pull/480))

### Fixed
- **Updating** works while a debug or test copy of ClaudeBar is running: debug builds now have their own bundle ID. Update failures are logged again, without counting "no update found" as one. ([#450](https://github.com/tddworks/ClaudeBar/issues/450))
- **Leaderboard**: your row no longer shows twice. The copy under the board appears only while your place is scrolled out of sight. ([#477](https://github.com/tddworks/ClaudeBar/pull/477))
- **Codex** works with only the Codex desktop app installed: ClaudeBar runs the `codex` inside it, and a `codex` on your PATH still comes first. ([#476](https://github.com/tddworks/ClaudeBar/pull/476))
- **Gemini, Kiro, Grok and Kimi**: an added account can't reuse your usual login's folder, and a folder typed with `~` now reaches the CLI. ([#476](https://github.com/tddworks/ClaudeBar/pull/476))
- **Bedrock** reads a named AWS profile with static keys, a role or a credential process, not only SSO; **Alibaba**'s monthly window and **Claude**'s cost panel read correctly. ([#476](https://github.com/tddworks/ClaudeBar/pull/476))
- **Settings → Updates** now says which version is ready ("Version 0.5.4 is ready to install") and its button reads Install Update; the sidebar footer names the new version too, instead of only "update available". ([#473](https://github.com/tddworks/ClaudeBar/pull/473))

### Added
- **Quota alerts**: pick your own percentages in Settings → Sync & Alerts, and get a notification when a login's quota falls below one, once per crossing, by the account's name. ([#479](https://github.com/tddworks/ClaudeBar/pull/479)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/alerting/quota-alerts/README.md)

---

## [0.5.4] - 2026-10-04

### Removed
- **Breaking:** extensions' `dailyUsage`, `metricsRow` and `statusBanner` sections are no longer read; their quotas, cost and health check still show. → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/providers/extensions/README.md) ([#471](https://github.com/tddworks/ClaudeBar/pull/471))

### Changed
- **Settings → Providers, one row per provider:** with two Claude accounts, Claude is one row showing each account's usage, its page is titled Claude, and its switch turns the whole provider on or off. Each account keeps its own Pause, and your current setup carries over. → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/providers/multi-account/README.md) ([#471](https://github.com/tddworks/ClaudeBar/pull/471))
- A provider whose CLI isn't installed, or that you never signed in to, now reads Not set up instead of Unavailable, and shows any daily usage it can still read. → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/usage-history/daily-usage/README.md) ([#198](https://github.com/tddworks/ClaudeBar/issues/198))
- Extensions now show like any provider: their settings sit on the provider's page in Settings and their secret fields move to the Keychain. → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/providers/extensions/README.md) ([#471](https://github.com/tddworks/ClaudeBar/pull/471))

### Fixed
- **Leaderboard:** your upload stays hourly after your Mac sleeps, instead of falling hours behind, and Refresh now uploads it too. ([#468](https://github.com/tddworks/ClaudeBar/pull/468))
- In overview mode, and with several accounts, a provider with no usage no longer reads Healthy: it says Unavailable, Not set up or Syncing, like the header does. ([#259](https://github.com/tddworks/ClaudeBar/issues/259))

### Added
- **In use:** with more than one Claude or Codex login, choose which one your next `claude` / `codex` starts with, from the popover, Settings or `claudebar://use`. ClaudeBar suggests a switch when the login in use runs low, or switches for you if you turn that on. → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/in-use/README.md) ([#465](https://github.com/tddworks/ClaudeBar/pull/465))
- Claude Desktop's tokens today now show as their own card under Claude, even without Claude Code. Without it, Claude says what your limits need, with a button to set that up, instead of an error. Thanks @jsvisa. → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/usage-history/daily-usage/README.md) ([#198](https://github.com/tddworks/ClaudeBar/issues/198))

---

## [0.5.3] - 2026-10-04

### Added
- Leaderboard profile links: add your X, Instagram or GitHub handle when you join or in Settings → Leaderboard, and it shows as an icon after your name on the board that opens your profile. Handles aren't verified, and the board says so. ([#462](https://github.com/tddworks/ClaudeBar/pull/462))
- Leaderboard globe: opt in to put your country on the web board's globe of where ClaudeBar is used. Only your country is kept, never your city or IP; it shows once three members there opt in. An eye hides it in the popover, and Turn off removes it. ([#460](https://github.com/tddworks/ClaudeBar/pull/460))
- New OpenRouter provider: shows your OpenRouter credit balance (total credits minus usage, USD) in the menu bar. Paste an API key in Settings → Providers → OpenRouter, or point it at `OPENROUTER_API_KEY`. Off by default. ([#89](https://github.com/tddworks/ClaudeBar/issues/89))

### Fixed
- With Show Provider Logo on, the menu bar no longer shows the logo and a chart icon side by side at launch; the logo shows alone until the first reading arrives. ([#462](https://github.com/tddworks/ClaudeBar/pull/462))

---

## [0.5.2] - 2026-10-04

### Added
- Leaderboard: join with a username from the new Leaderboard tab, share daily token totals from Claude, Codex or Mistral, and see your rank today, this week or this month. Only token counts leave your Mac; leaving deletes them. ([#459](https://github.com/tddworks/ClaudeBar/pull/459))
- Codex daily usage: today's and the last 30 days' Codex tokens now show beside Claude's, read from Codex's session logs. ([#459](https://github.com/tddworks/ClaudeBar/pull/459))

### Fixed
- Codex in API mode no longer shows a made-up "$1000 of $1000" API cost when your ChatGPT account has no Codex credits; the card now appears only when you have credits. ([#444](https://github.com/tddworks/ClaudeBar/issues/444))

### Changed
- Breaking: the CLI theme's menu bar icon is now an outline terminal that fills in while Claude Code works, in your quota's status colour. It replaces the two terminals shown side by side; nothing to change on your side. Applies with the readout off. ([#445](https://github.com/tddworks/ClaudeBar/pull/445))
- The Pop theme's cards now match its design: outlined percentages with "left" beside them, striped bars on every card, the reset time in bold beside a pace sticker, a lavender extra-usage card with its budget, and a one-piece Cost / Tokens / Cache picker. ([#452](https://github.com/tddworks/ClaudeBar/pull/452))

---

## [0.5.0] - 2026-10-03

### Added
- Show Provider Logo (Settings → Menu Bar) starts the menu bar readout with the provider's logo even when it's the only one. Off by default. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- Pop theme: cream dotted paper, thick ink outlines, hard shadows, candy-coloured status and chunky numbers, with each menu-bar quota as a candy chip. Pick it in Settings → Appearance. ([#435](https://github.com/tddworks/ClaudeBar/pull/435))
- Hide account emails: the eye beside the account in the popover, or Settings → Menu Bar → Hide Account Emails, masks emails as s•••@g•••.com in the popover and menu bar, and remembers it. ([#375](https://github.com/tddworks/ClaudeBar/issues/375))
- Each added Claude account now shows its own today's usage and 30-day chart, read from its own config folder's logs, instead of none. ([#358](https://github.com/tddworks/ClaudeBar/issues/358))
- A Daily usage — last 30 days chart below today's usage cards shows each day's cost, tokens or cache use, with the 30-day total; hover a bar for its day. Past days are kept, so only today's logs are read. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- Settings → Appearance → Native menu bar icons gives every provider account a monochrome mark that follows light and dark menu bars, while keeping quota colors. Off by default. ([#380](https://github.com/tddworks/ClaudeBar/pull/380))

### Changed
- Menu bar: Show Names for Multiple Accounts now explains that names appear only when the same provider has multiple enabled accounts, and no longer promises account details on hover. ([#390](https://github.com/tddworks/ClaudeBar/pull/390))
- Claude's daily usage cost now prices cache writes kept for an hour at the 1-hour rate instead of the 5-minute one. Claude Code writes most of its cache that way, so estimates were about 10% low. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- Claude's daily usage cost uses current list prices for the newest models (Opus 5.5, Sonnet 5.5, Fable 5.1, Opus 4.5–4.7, Sonnet 4.5), and Claude's prices now live in a data file. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- Mistral's today and yesterday totals now come from the same Usage History as Claude's; nothing changes on screen. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- Oh My Pi shows a capped dollar limit as money left of its cap, and its cards use their full labels in the menu bar. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- AWS Bedrock shows today's spend as one cost card with a line per model, judged by your daily budget instead of a "Daily Budget" quota. Profile changes apply without a restart, and AWS errors show instead of hiding Bedrock. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- Antigravity's 5-hour quotas show a 5-hour window, where some showed a week. With the app closed, a stale sign-in now says so instead of "not running". ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- Gemini supports separate accounts, each signed in under its own `GEMINI_CLI_HOME` folder, and no longer shows a guessed 7-day window on its quotas. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- Alibaba supports separate accounts, each with its own API key or console cookie and region. A pasted cookie is tried before the browser's, and the monthly window is the real billing month. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- Copilot supports separate accounts, each with its own token, and works with just the GitHub CLI signed in (`gh auth login`). An unlimited plan shows its plan instead of a made-up 100% card, and an organization seat's entered usage is used only while GitHub reports none. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- Kimi supports separate accounts: a session token and region on the API, or a separate signed-in folder on the CLI. A signed-out CLI now asks you to sign in, and a plan with no stated period or limit no longer shows a made-up weekly 100%. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- Z.ai supports separate accounts, each with its own key and platform, and a saved key can go to Zhipu as well as Z.ai. Claude Code no longer needs to be installed, and a key in Claude Code's settings is only used when it points at Z.ai. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- OpenCode Go supports separate accounts, each with its own API key. Without a key, its local estimate shows dollars left of each cap and waits out rate limits. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- Grok supports separate accounts, each signed in under its own folder, and no longer shows a made-up 100% or weekly card when xAI reports no usage or no period. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- Cursor supports separate accounts, each with its own access token. An unlimited plan shows its plan rather than a 100% card. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- Kiro supports separate accounts, each signed in under its own home folder. Bonus credits show as their own card with no made-up weekly window, and the monthly window is the real month. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- Amp supports separate accounts, each with its own access token, and shows the Free allowance as dollars of its ceiling. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- Command Code supports separate accounts, each with its own API key, and waits out Command Code's rate limits instead of retrying at once. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- Vercel Gateway supports separate accounts, each with its own API key. Your saved key and environment variable name carry over. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- A provider's Settings form now says when a key is already saved in your Keychain, and Clear removes a saved key or puts a setting back to its default. ([#402](https://github.com/tddworks/ClaudeBar/pull/402))
- MiniMax supports separate accounts, each with its own API key and region. Your saved region, key and environment variable name carry over; the key moves to your Keychain. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- Settings → Providers shows the same Data source, Settings and Accounts sections for every provider built from a definition. A CLI provider you add runs your command directly and reports when it fails. ([#399](https://github.com/tddworks/ClaudeBar/pull/399))
- DeepSeek supports separate accounts with their own API keys, names and menu-bar pins, preserves existing sign-ins, and shows balances in their billing currency. ([#331](https://github.com/tddworks/ClaudeBar/issues/331))
- Claude's daily cost and token cards load much faster when you open the popover: ClaudeBar reads only the session log lines written since the last open, instead of re-reading every log from today and yesterday. ([#378](https://github.com/tddworks/ClaudeBar/pull/378))

## Older releases

[0.4](docs/changelog/0.4.md) · [0.3](docs/changelog/0.3.md) · [0.2](docs/changelog/0.2.md) · [0.1](docs/changelog/0.1.md)

[Unreleased]: https://github.com/tddworks/ClaudeBar/compare/v0.5.18...HEAD
[0.5.18]: https://github.com/tddworks/ClaudeBar/compare/v0.5.17...v0.5.18
[0.5.17]: https://github.com/tddworks/ClaudeBar/compare/v0.5.16...v0.5.17
[0.5.16]: https://github.com/tddworks/ClaudeBar/compare/v0.5.15...v0.5.16
[0.5.15]: https://github.com/tddworks/ClaudeBar/compare/v0.5.14...v0.5.15
[0.5.14]: https://github.com/tddworks/ClaudeBar/compare/v0.5.13...v0.5.14
[0.5.13]: https://github.com/tddworks/ClaudeBar/compare/v0.5.12...v0.5.13
[0.5.12]: https://github.com/tddworks/ClaudeBar/compare/v0.5.11...v0.5.12
[0.5.11]: https://github.com/tddworks/ClaudeBar/compare/v0.5.10...v0.5.11
[0.5.10]: https://github.com/tddworks/ClaudeBar/compare/v0.5.9...v0.5.10
[0.5.9]: https://github.com/tddworks/ClaudeBar/compare/v0.5.8...v0.5.9
[0.5.8]: https://github.com/tddworks/ClaudeBar/compare/v0.5.7...v0.5.8
[0.5.7]: https://github.com/tddworks/ClaudeBar/compare/v0.5.6...v0.5.7
[0.5.6]: https://github.com/tddworks/ClaudeBar/compare/v0.5.5...v0.5.6
[0.5.5]: https://github.com/tddworks/ClaudeBar/compare/v0.5.4...v0.5.5
[0.5.4]: https://github.com/tddworks/ClaudeBar/compare/v0.5.3...v0.5.4
[0.5.3]: https://github.com/tddworks/ClaudeBar/compare/v0.5.2...v0.5.3
[0.5.2]: https://github.com/tddworks/ClaudeBar/compare/v0.5.0...v0.5.2
[0.5.0]: https://github.com/tddworks/ClaudeBar/compare/v0.4.95...v0.5.0
