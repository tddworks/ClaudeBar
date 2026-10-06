# Changelog

All notable changes to ClaudeBar will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **Leaderboard web board**: the board scrolls inside its card so the globe is close by, the globe shows the tokens its countries total, and country names in its list are no longer cut in half. ([#503](https://github.com/tddworks/ClaudeBar/pull/503)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/leaderboard/README.md)

### Added
- **Share your rank**: Share on the Leaderboard's *Your rank* makes an image of your place, square or wide, with your name shown or masked, to copy, save or share. Drawn on your Mac; nothing is uploaded. ([#504](https://github.com/tddworks/ClaudeBar/pull/504)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/leaderboard/README.md#share-your-rank)
- **Oh My Pi daily usage**: today's cost and tokens, the 30-day chart and Leaderboard sharing for Oh My Pi, read from omp's own session logs — subagents and the model calls it makes outside the chat included, a forked session's copies counted once. ([#502](https://github.com/tddworks/ClaudeBar/pull/502)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/providers/omp/README.md#daily-usage)
- **Platformer's runner**: a small pixel runner walks the brick floor. It strolls when your quota is healthy, runs when it's low, falls into a pit when it's empty, and jumps for a coin after each refresh. Turn it off in Settings → Appearance → Runner. ([#505](https://github.com/tddworks/ClaudeBar/pull/505)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/themes/README.md)

---

## [0.5.7] - 2026-10-06

### Changed
- **Leaderboard** is the first tab in the popover's row, so it's always in reach; the popover still opens on your first provider. ([#501](https://github.com/tddworks/ClaudeBar/pull/501)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/leaderboard/README.md)

### Fixed
- Pop theme: a dollar balance or spend now prints in the same outlined style as a percentage, with its caption beside it, so a card's big numbers no longer look like two different fonts ([#499](https://github.com/tddworks/ClaudeBar/issues/499))

### Added
- **Platformer theme**: a Super Mario–style 8-bit level with a score line, a ? block to refresh, blocks for bars and Pixel or Classic text. ([#501](https://github.com/tddworks/ClaudeBar/pull/501)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/themes/README.md)

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
- **Quota alerts**: pick your own percentages in Settings → Sync & Alerts, and get a notification when a login's quota falls below one, once per crossing, by the account's name. ([#479](https://github.com/tddworks/ClaudeBar/pull/479)) → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/quota-alerts/README.md)

---

## [0.5.4] - 2026-10-04

### Removed
- **Breaking:** extensions' `dailyUsage`, `metricsRow` and `statusBanner` sections are no longer read; their quotas, cost and health check still show. → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/extensions/README.md) ([#471](https://github.com/tddworks/ClaudeBar/pull/471))

### Changed
- **Settings → Providers, one row per provider:** with two Claude accounts, Claude is one row showing each account's usage, its page is titled Claude, and its switch turns the whole provider on or off. Each account keeps its own Pause, and your current setup carries over. → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/multi-account/README.md) ([#471](https://github.com/tddworks/ClaudeBar/pull/471))
- A provider whose CLI isn't installed, or that you never signed in to, now reads Not set up instead of Unavailable, and shows any daily usage it can still read. → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/daily-usage/README.md) ([#198](https://github.com/tddworks/ClaudeBar/issues/198))
- Extensions now show like any provider: their settings sit on the provider's page in Settings and their secret fields move to the Keychain. → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/extensions/README.md) ([#471](https://github.com/tddworks/ClaudeBar/pull/471))

### Fixed
- **Leaderboard:** your upload stays hourly after your Mac sleeps, instead of falling hours behind, and Refresh now uploads it too. ([#468](https://github.com/tddworks/ClaudeBar/pull/468))
- In overview mode, and with several accounts, a provider with no usage no longer reads Healthy: it says Unavailable, Not set up or Syncing, like the header does. ([#259](https://github.com/tddworks/ClaudeBar/issues/259))

### Added
- **In use:** with more than one Claude or Codex login, choose which one your next `claude` / `codex` starts with, from the popover, Settings or `claudebar://use`. ClaudeBar suggests a switch when the login in use runs low, or switches for you if you turn that on. → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/in-use/README.md) ([#465](https://github.com/tddworks/ClaudeBar/pull/465))
- Claude Desktop's tokens today now show as their own card under Claude, even without Claude Code. Without it, Claude says what your limits need, with a button to set that up, instead of an error. Thanks @jsvisa. → [docs](https://github.com/tddworks/ClaudeBar/blob/main/docs/features/daily-usage/README.md) ([#198](https://github.com/tddworks/ClaudeBar/issues/198))

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

[Unreleased]: https://github.com/tddworks/ClaudeBar/compare/v0.5.7...HEAD
[0.5.7]: https://github.com/tddworks/ClaudeBar/compare/v0.5.6...v0.5.7
[0.5.6]: https://github.com/tddworks/ClaudeBar/compare/v0.5.5...v0.5.6
[0.5.5]: https://github.com/tddworks/ClaudeBar/compare/v0.5.4...v0.5.5
[0.5.4]: https://github.com/tddworks/ClaudeBar/compare/v0.5.3...v0.5.4
[0.5.3]: https://github.com/tddworks/ClaudeBar/compare/v0.5.2...v0.5.3
[0.5.2]: https://github.com/tddworks/ClaudeBar/compare/v0.5.0...v0.5.2
[0.5.0]: https://github.com/tddworks/ClaudeBar/compare/v0.4.95...v0.5.0
