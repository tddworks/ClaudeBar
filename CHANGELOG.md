# Changelog

All notable changes to ClaudeBar will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Settings → Appearance → Native menu bar icons gives every provider account a monochrome mark that follows light and dark menu bars, while keeping quota colors. Off by default. ([#380](https://github.com/tddworks/ClaudeBar/pull/380))

### Changed
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

---

## [0.4.95] - 2026-10-02

### Added
- CLI location: when ClaudeBar can't find Claude's or Codex's CLI, or finds the wrong one, choose the program in Settings → Providers → Configuration. It applies at once, to every account and to sign-in. ([#361](https://github.com/tddworks/ClaudeBar/pull/361))
- Settings → Providers lists the providers you turned on first, so the one you use isn't at the bottom of the list. ([#141](https://github.com/tddworks/ClaudeBar/issues/141))
- Popover: a provider with several accounts is one tab, its accounts side by side. Chips hide one from view without pausing it, and a line names the account behind a warning. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- Providers you made with Add Provider can have more than one account: Add Account asks for each account's API key, kept in your Keychain for that account only. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- Claude and Codex accounts: Settings → Providers → Accounts adds a login by signing in with your browser or choosing a signed-in folder, then names, reorders, pins, pauses, removes and re-signs-in each one. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- Hide quotas you don't use: Settings → Providers → a provider → Quotas. A hidden quota disappears everywhere (popover, menu bar, Touch Bar, notch, status export, Notify!) and no longer sets a status or an alert. ([#140](https://github.com/tddworks/ClaudeBar/issues/140))
- Menu bar: turn off Show Account Labels in Menu Bar in Settings to hide account names and emails while keeping icons, quotas, and hover details. ([#365](https://github.com/tddworks/ClaudeBar/pull/365))
- Share a provider you made: Export… saves it as a file without your keys; Import… shows where it sends a key and any command it runs before you add it, then asks for your own key. ([#355](https://github.com/tddworks/ClaudeBar/issues/355))
- Add Provider: track a service ClaudeBar doesn't ship. Settings → Providers → Add Provider… starts from an API, a command, a file or a copy; test it, click the numbers to map them, name it. Keys stay in your Keychain. ([#354](https://github.com/tddworks/ClaudeBar/issues/354))
- Claude and Codex: the popover says which data source answered ("via RPC", or "via Terminal" after a fallback) and, when a refresh fails, which step went wrong ("Couldn't read your key"), keeping the last usage dimmed. ([#351](https://github.com/tddworks/ClaudeBar/issues/351))

### Fixed
- MiniMax no longer shows 0% left on every model: it reads the Token Plan endpoint and shows each model's 5-hour and weekly windows, with request counts for older plans. ([#359](https://github.com/tddworks/ClaudeBar/pull/359))
- A prepaid balance (Vercel, Copilot, Cursor, Grok, Command Code, Amp) shows its money in the menu bar instead of "100%", and no longer claims a pace. Pace only uses a provider's real window, never one guessed from a quota's name. ([#329](https://github.com/tddworks/ClaudeBar/pull/329))
- Notifications, provider pills, the Touch Bar, the status export and Notify! now follow the burn-rate warning setting like the menu bar does, so a quota that's on pace no longer sends a warning while the menu bar says healthy. ([#357](https://github.com/tddworks/ClaudeBar/issues/357))

### Changed
- Claude's CLI data source now reuses a single session named "ClaudeBar Probe" instead of creating a new empty session on every refresh, so `~/.claude/projects` and session pickers stay clean. ([#132](https://github.com/tddworks/ClaudeBar/issues/132))
- Claude and Codex settings: one Data source section replaces Probe Mode. It shows where ClaudeBar looks for your key, says what happens if a source fails, and has a Test Connection button. Your choices carry over. ([#352](https://github.com/tddworks/ClaudeBar/issues/352))
- Claude and Codex now run from built-in provider definitions instead of their own code: a first step toward adding providers from Settings. Usage, settings, accounts and the menu bar stay the same; please report anything that reads differently. ([#329](https://github.com/tddworks/ClaudeBar/pull/329))

---

## [0.4.94] - 2026-10-01

### Changed
- Breaking: Claude's Dashboard button (⌘D) now opens your usage page on claude.ai on a subscription (Max, Pro, Team) instead of the Console billing page. Pay-as-you-go API accounts still get the Console; on a subscription, open console.anthropic.com yourself if you need it. ([#328](https://github.com/tddworks/ClaudeBar/pull/328))

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- Codex: add separate ChatGPT accounts, identify them by email, and pin both quotas in the menu bar. Each login keeps its own usage and refreshes. [#308](https://github.com/tddworks/ClaudeBar/issues/308)
- Z.ai: paste your GLM API key in Settings → Providers → Z.ai → API KEY. It wins over the settings.json token and env vars, and works even when no Z.ai URL is in settings.json (quota then comes from api.z.ai).
- Codex: the GPT-5.3-Codex-Spark research preview has its own 5h and weekly windows, separate from your main limits. Those Spark windows now show as extra rows after your session and weekly gauges. ([#178](https://github.com/tddworks/ClaudeBar/issues/178))
- Popover keyboard shortcuts: Escape closes the popover (or an open share overlay first), and ⌘1–⌘9 switch between the provider pills. Tooltips on the pills and action buttons now show each shortcut (⌘D, ⌘R, ⌘S, ⌘, and ⌘Q already worked).
- Kimi: API mode has a Region picker (Settings → Providers → Kimi → Kimi Configuration): China (kimi.com) or International (kimi.ai), matching the platform your account is signed in to. The console link follows the region. https://github.com/tddworks/ClaudeBar/issues/new

### Fixed
- Kimi: CLI mode failed with "No quota data found" because the CLI's one-time "Trust this folder?" prompt swallowed the typed `/usage`. The probe now runs in its own folder (trusted once), reads the CLI 2.x "Monthly limit" layout, and types `/usage` after the startup paint settles. https://github.com/tddworks/ClaudeBar/issues/new
- ClaudeBar no longer grows in memory the longer it runs. It could reach several GB after a day or two and then peg the CPU and freeze the menu bar panel. [#313](https://github.com/tddworks/ClaudeBar/issues/313)
- Z.ai: the auth env var is now also read through your login shell, so a key exported in `~/.zshrc` or `~/.bash_profile` is found even when ClaudeBar starts from Finder or Login Items. [#170](https://github.com/tddworks/ClaudeBar/issues/170)
- Cost Usage no longer counts dollars for models you run locally. With Claude Code pointed at ollama or LM Studio the card kept adding Anthropic Sonnet prices; it now shows $0.00, while Token Usage keeps counting. ([#190](https://github.com/tddworks/ClaudeBar/issues/190))
- Claude no longer shows as "Unavailable" while you're working in it. The `/usage` probe accepted the CLI's boot screen as finished, so slow SessionStart hooks produced a capture with nothing to read. It now waits for the Usage screen. ([#317](https://github.com/tddworks/ClaudeBar/issues/317))
- Claude's cost fallback is fast again and no longer invents a $0.00. The `/cost` capture waited out the full 20s timeout, and a screen that reported a failure was read as a cost of nothing. ([#317](https://github.com/tddworks/ClaudeBar/issues/317))
- Claude now always falls back between its two probe modes when one fails. A pre-check could report the other probe unusable and skip the rescue, silently, leaving "Claude Unavailable" on screen — in both directions. ([#317](https://github.com/tddworks/ClaudeBar/issues/317))
- The "Claude Code Started" / "Claude Code Finished" pair that fired on every quota poll is gone: sessions ClaudeBar spawns itself are now marked and its installed hooks skip them. ([#222](https://github.com/tddworks/ClaudeBar/issues/222))
- Codex: the probe no longer stalls on Codex 0.150's "Do you trust the contents of this directory?" prompt. Codex now runs in ClaudeBar's own probe folder and the prompt is answered for you, so the Codex tab shows your usage again. https://github.com/tddworks/ClaudeBar/issues/267
- Codex (RPC mode): starting the app, opening the popover or Settings no longer risks launching the ChatGPT login in your browser. Refreshes you didn't click stay passive until you refresh or connect once. ClaudeBar never starts the Codex login itself. https://github.com/tddworks/ClaudeBar/issues/216
- `claudebar://open` now opens the popover and `claudebar://refresh` refreshes, instead of both opening the Settings window. Also fixes tapping the Touch Bar widget. https://github.com/tddworks/ClaudeBar/pull/310
- Cursor now shows Auto and API cards when those fields are in the usage response, next to Monthly. The menu bar still defaults to Monthly; set the secondary quota to API to see both. ([#303](https://github.com/tddworks/ClaudeBar/issues/303))
- Touch Bar gauges now colour by their quota's status. In Remaining and Pace modes the colour was keyed to the displayed number as if it were usage, so 93% remaining drew red with a `!` and 18% remaining drew blue.

---

## [0.4.93] - 2026-09-24

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- Custom status colors. Settings → Appearance → Status Colors has a color well for each level (healthy, warning, critical, depleted). A custom color overrides the theme in the menu bar label, the popover, the notch, and Settings. "Reset to defaults" restores the theme. ([#200](https://github.com/tddworks/ClaudeBar/issues/200))
- High Contrast switch in the same card: a built-in palette that clears 4.5:1 on both light and dark menu bars and follows the bar's appearance. The stock theme greens and ambers measured under 2:1 on a light menu bar. Custom colors win over High Contrast for the levels you set. ([#200](https://github.com/tddworks/ClaudeBar/issues/200))

### Fixed
- Antigravity now shows your quota with the app closed. With no language server running, the probe reported "Command did not complete within the timeout" on every refresh and never reached the Cloud Code fallback that reads your stored sign-in. ([#301](https://github.com/tddworks/ClaudeBar/issues/301))
- Codex: the menu bar countdown now ticks and matches the other providers ("2:33", "2d"), and pace-aware colors work for Codex. ([#298](https://github.com/tddworks/ClaudeBar/issues/298))
- Extensions: providers now show the SF Symbol from their manifest's `icon` in the menu bar, popover, Touch Bar and Settings, instead of a question mark. An unknown symbol still falls back to the question mark. ([#302](https://github.com/tddworks/ClaudeBar/issues/302))

---

## [0.4.92] - 2026-09-12

### Changed
- Bug fixes and improvements.

---

## [0.4.91] - 2026-09-09

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- The Notify! quota tile can now live on the iPhone Home Screen as well as the Lock Screen. Notify! added Home Screen widgets in its September 2026 update, and a screen widget carries exactly the content a Live Activity does, so the same tile ClaudeBar already builds (up to six quota windows, a progress bar and the reset countdown) can sit there permanently instead of appearing and vanishing with a job. It has its own switch in Settings then Notify!, is on once you link a device, and is placed through iOS's own widget picker after adding it under Settings then Home Screen Widgets in Notify!. If your copy of Notify! is not serving Home Screen widgets yet, ClaudeBar treats that as "not yet" rather than an error and quietly tries again later.

---

## [0.4.90] - 2026-09-05

### Changed
- Bug fixes and improvements.

---

## [0.4.89] - 2026-09-04

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- Quota state can now be published to an iPhone Lock Screen through [Notify!](https://getnotifyapp.com), so the number the app exists for is readable without opening the laptop. ClaudeBar keeps two things on the phone: a Live Activity showing up to six quota windows with a progress bar, and a Lock Screen widget whose gauge is one quota you pick (or whichever needs attention most). Percentages are remaining, the same as everywhere else in the app, so a full ring means a full quota. To set it up, get Notify! (https://getnotifyapp.com), open it once on the phone so Live Activities are allowed to start, then copy the device ID and token out of the app into Settings → Notify!. The Live Activity needs an iPhone or iPad ID. A Mac or browser ID keeps the widget gauge perfectly well, but Notify! cannot start a Live Activity on one, so ClaudeBar disables that switch and says why instead of publishing into nothing; a group ID owns no Lock Screen at all and gets neither. Either surface can be switched off on its own. This is off by default and sends provider names, window labels and remaining percentages to a third-party service; the device token is stored in the Keychain, never in `settings.json`, falling back to ClaudeBar's app credentials on a self-built copy whose ad-hoc signature the Keychain will not accept.
- `JSONSettingsRepository` now conforms to `MultiAccountSettingsRepository`, persisting per-provider accounts under `providers.{id}.accounts` and the active account under `providers.{id}.activeAccountId`. Nothing changes for existing installs: a provider with no `accounts` key reads back an empty list, which is the single-account path, so no migration runs. Removing the active account clears the active pointer rather than leaving it dangling at an account that is gone. (#164)

---

## [0.4.88] - 2026-09-02

### Fixed
- Claude no longer reports a $0.00 cost card instead of quota on a subscription the CLI could not see. A Max plan billed through Apple renders `/usage` as the API-billing cost panel, and ClaudeBar answered it with `/cost` — which succeeds, so the app never tried the usage API that can still read the real quota. `~/.claude.json` knows the account is a subscription (`billingType`), and that now vetoes the `/cost` route: genuine pay-as-you-go accounts still get their cost card, subscriptions fall through to the API probe. (#271)
- A failed Keychain read no longer passes for "no credentials". On macOS `claude login` writes only the Keychain, so a denied read surfaced as "Authentication required. Please log in." to someone already logged in, with nothing in the log to say why. The `security` exit status and its error are now logged, along with which places were searched. (#271)

---

## [0.4.87] - 2026-09-02

### Fixed
- Quota cards no longer draw their text mirrored. After a refresh, the fields whose value had just changed could come back upside down — a different set each time. The rolling digit animation on card headline numbers, which renders them through a separate morphing text layer, is gone; the numbers now update in place. Card rows also get ids that stay unique when a provider reports two cards of the same quota type, so no row can borrow another's drawing. (#272)

---

## [0.4.86] - 2026-09-01

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- Claude Code's session and quota state can now be shown in the notch. With nothing running it reports the selected provider's most depleted quota, so the number the app exists for is readable without opening anything. A running session takes the notch over — repository, elapsed time, and how many subagents are fanned out — then hands it back when the turn ends. Hovering expands it into the session list, quota cards and today's usage, with buttons to refresh that provider or snooze the notch for 30 minutes. Off by default: turn it on in Settings → General → Notch Live Activity. Displays without a physical notch, including every external monitor, get a virtual one sized to the menu bar. (#274)
- ClaudeBar now registers Claude Code's `Notification` hook alongside the session hooks it already installed, so it can tell that Claude is blocked waiting on a permission prompt instead of showing the session as merely active. That state outranks everything else in the notch and stays put until it is answered. (#274)

### Fixed
- Claude no longer reports "Failed to parse output: Could not find session usage" when the CLI is simply slow to answer. `claude /usage` paints its cost panel and a "Loading usage data…" placeholder immediately, then fills the quota bars in from a separate request; the probe stopped at the first 3-second lull and captured the placeholder. It now waits for the screen to settle — quota bars, or the error that replaced them. A capture that still ends on the placeholder says the usage endpoint may be rate limited instead of blaming the parser, and a `/usage` screen that renders an API-billing cost panel with no quota at all falls back to `/cost`. (#271, #253)
- The quota bar no longer contradicts the number above it. In "Remaining" mode an 87% card drew a 13% bar, because the bar tracked usage while the headline tracked what was left. The bar again shares the headline's scale: it starts full and drains as quota is consumed, inverting only in "Used" mode. The pace tick moves back onto the same scale. (#268)

---

## [0.4.85] - 2026-08-25

### Fixed
- Refreshing the Claude OAuth token no longer strips fields ClaudeBar does not model (notably `scopes`) from `claudeAiOauth`. The credential is shared with Claude Code, so a write-back handed it back an incomplete record. (#256)
- Claude credentials stored in the Keychain could not be read back on macOS 26, leaving the API probe reporting "No credentials found" until the next `claude` login. `security -w` returns any password holding a non-printable-ASCII byte as hex, and the pretty-printed JSON ClaudeBar wrote contained newlines. Payloads are now written compact, and hex-encoded items left behind by earlier builds are decoded on read. (#255)

---

## [0.4.84] - 2026-08-25

### Fixed
- Codex usage could not be retrieved at all ("Could not find usage limits in Codex output"). The Codex CLI dropped `untrusted` from `--ask-for-approval`, so both the app-server and the TTY fallback exited at argument parsing. (#259)
- The header badge no longer shows a green "HEALTHY" for a provider that failed to probe; it now reads "UNAVAILABLE", or "NO DATA" before the first refresh. (#259)

---

## [0.4.83] - 2026-08-25

### Fixed
- OpenCode Go usage now comes from the official `/zen/go/v1/usage` endpoint, so the numbers match the opencode.ai dashboard instead of a local-DB estimate that only saw this machine's messages (#249). The API key is read from `OPENCODE_API_KEY` or opencode's `auth.json`; the local-DB probe remains as a fallback when no key is configured.

---

## [0.4.82] - 2026-08-24

### Changed
- Bug fixes and improvements.

---

## [0.4.81] - 2026-08-21

### Changed
- Bug fixes and improvements.

---

## [0.4.80] - 2026-08-19

### Changed
- Bug fixes and improvements.

---

## [0.4.79] - 2026-08-13

### Changed
- Bug fixes and improvements.

---

## [0.4.78] - 2026-08-13

### Fixed
- The menu bar reset countdown now shows hours with minutes in "H:MM" form
  (e.g. "3:58") instead of truncating to whole hours ("3h"), which could
  understate the remaining time by up to 59 minutes compared with the panel's
  "3h 58m" detail. Day-level ("2d") and minute-level ("45m") labels are
  unchanged. (#246)

---

## [0.4.77] - 2026-08-12

### Fixed
- The "Share Claude Code" button no longer appears on Claude Pro, API, or
  not-yet-identified accounts. Anthropic issues invitation links to Max
  subscribers only, so on other plans the button could do nothing but fail
  silently. When a Max account's link fetch does fail, the popover now
  explains why instead of ignoring the click, and the failure no longer marks
  Claude's usage data as unavailable. (#243)

---

## [0.4.76] - 2026-08-09

### Changed
- Bug fixes and improvements.

---

## [0.4.75] - 2026-08-04

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- Grok Build (xAI) provider: monitors weekly credit usage and per-product
  limits (Grok Build, Grok Imagine, Grok Voice) via the same billing endpoint
  the `grok` CLI uses. Reads OAuth credentials from `~/.grok/auth.json`,
  refreshing expired tokens against the recorded OIDC issuer, and shows the
  period reset countdown plus on-demand overflow usage once a cap is
  configured. (#234)

### Fixed
- Popover scrolling no longer trembles or snaps back while dragging upward.
  The card grids were `LazyVGrid`s inside the popover's vertical `ScrollView`,
  so lazy height estimation kept correcting the scroll offset mid-gesture as
  cells materialized. Cards now lay out eagerly — the popover shows a few
  dozen at most, so laziness bought nothing — and the scroll view knows exact
  content heights up front.
- Long account discriminators no longer flood the menu bar. Oh My Pi quota
  labels embed an account token to keep multi-account quota keys unique
  (e.g. "Claude 7d · jkjk987654321012"), and the dual-window menu bar label
  rendered the whole thing. Aggregated quotas now carry a condensed menu-bar
  title that truncates tokens longer than 8 characters to a 7-character
  prefix plus an ellipsis ("Claude 7d · jkjk987…"); the menu bar and the
  quota picker chips in Settings prefer it, while the full label — and
  therefore every persisted quota key — stays unchanged. Condensed titles
  that collide across accounts sharing a prefix get a numeric suffix
  ("jkjk987… (2)") so the chips stay distinguishable.

---

## [0.4.73] - 2026-07-19

### Fixed
- Cursor no longer shows "EMPTY" for Pro/paid accounts that have bonus credits.
  The probe derived remaining usage from the `used`/`limit` fields, which cover
  only the *included* base allotment; once that base is consumed (`used == limit`)
  it reported 0% remaining even when plenty of bonus capacity was left. It now
  uses Cursor's authoritative `totalPercentUsed` and the full `breakdown.total`
  capacity (included + bonus), matching the "You've used X%" figure in Cursor's
  own UI.
- The pace tick under quota progress bars now explains itself: hovering the
  bar shows a mode-aware tooltip ("steady usage would leave ~N% remaining by
  now"), so the marker no longer reads as a misaligned rendering glitch.

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- Claude Extra Usage now reads the current OAuth `spend` payload (with the
  legacy `extra_usage` shape as a tolerant fallback), converts minor units with
  exponent-aware decimal math, and renders spend as a distinct "EXTRA USAGE"
  card with capped remaining budget or an explicit "No monthly cap" state.
- Oh My Pi (`omp`) USD limits now render as monetary spend meters: capped rows
  show "$X of $Y" while preserving their percentage-driven status and progress,
  and uncapped rows become account notes such as "$X spent · no cap" instead of
  being dropped or assigned a fabricated percentage.

### Fixed
- Grouped provider notes now accumulate in source order rather than overwriting
  one another, so spend notes and other account notes remain visible together.
- Claude's configured API budget now applies only to API-cost cards; it no
  longer supplies a misleading cap for uncapped Extra Usage.
- Oh My Pi quota cards no longer show raw machine window ids. For Kimi,
  the 5-hour rate-limit card now reads "5h" (derived from the reported
  window duration) instead of "300TIME_UNIT_MINUTE", and the total-quota
  card shows Kimi's own "Total quota" label instead of "DEFAULT".
  Label-derived card titles also drop a duplicated provider prefix
  (Gemini) and redundant shared-window meter words (Copilot). Card
  titles only: full quota labels and persisted quota keys are unchanged,
  so existing menu-bar selections keep working.

---

## [0.4.72] - 2026-07-15

### Fixed
- Oh My Pi no longer shows duplicate "No usage reported" account rows when
  org-less stale credentials share an email with an account that already
  reported usage; organization-scoped failures remain visible.

---

## [0.4.71] - 2026-07-13

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- Oh My Pi (`omp`) provider: shows the rate-limit windows of every account the
  harness is signed into (Claude, Codex, Z.ai, ...) via `omp usage --json`. Each
  window appears as its own quota with reset countdown; pace math uses the
  window duration reported by the CLI, multiple accounts on the same upstream
  provider are disambiguated per account, and accounts without usable quota
  data — fetch failures (`accountsWithoutUsage`) or providers that report
  zero limits by design (e.g. Ollama) — are listed as explicit
  "No usage reported" rows instead of being dropped.
- Aggregated provider cards (Oh My Pi) group their quotas into one
  collapsible section per upstream account — with compact card titles,
  a worst-status badge per section, and an inline "No usage reported"
  line for accounts without quota data — and the popover's content area
  now caps at the screen height and scrolls, so the action bar can no
  longer be pushed off-screen.
- CLI probes now run with a PATH that includes the common install directories
  and the resolved binary's own directory, and `~/.bun/bin` is searched when
  locating tools — bun/node-shebang CLIs (like `omp`) now work from the
  menu bar (launchd) context where the login-shell PATH is unavailable.

### Fixed
- Time-limit quota labels are no longer force-capitalized in the UI
  ("MCP" was displayed as "Mcp").

---

## [0.4.70] - 2026-07-02

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- Claude Fable 5 weekly limit is now parsed from both the CLI `/usage` output
  ("Current week (Fable)") and the OAuth usage API's new `limits` array, shown as a
  quota card in the window and selectable as a menu-bar metric. The API-side parsing
  is generic over model-scoped limits, so future scoped models appear automatically.

### Fixed
- Claude CLI probe no longer fails on every tick with recent Claude CLI versions.
  The `/usage` screen grew taller than the probe's 50-row terminal (usage-contribution
  report), scrolling the quota sections off the visible screen; the terminal renderer
  now includes scrollback, so all sections are parsed again.

---

## [0.4.69] - 2026-06-25

### Fixed
- Menu-bar usage text no longer freezes or disappears after system sleep. SwiftUI's
  `MenuBarExtra` label hosting can permanently stop receiving updates after wake (the
  dropdown kept working while the label — and the refresh-loop restarts attached to it —
  went dead until relaunch). The menu-bar pixels and the background-refresh lifecycle are
  now driven imperatively (AppKit `NSStatusItem` via MenuBarExtraAccess + observation
  tracking), independent of SwiftUI view invalidation. (#192)
- Menu-bar status item no longer sticks on a lone colored session glyph with no usage
  number after long idle. Even with the imperative driver, the label only repainted when
  SwiftUI observation fired, which can go quiet after idle while probes keep succeeding.
  The status item is now repainted on every background-refresh tick, the Claude Code
  session glyph is shown only while a session is actively working (not on the end-of-turn
  "stopped" state, which previously stuck forever), and the last-known number is kept when
  a quota window is briefly unavailable. Claude Code sessions also recover from "stopped"
  on the next prompt via a new `UserPromptSubmit` hook so the indicator tracks real activity.

---

## [0.4.68] - 2026-06-10

### Fixed
- Daily Usage cost & token cards no longer overcount. Claude Code writes the same usage
  multiple times (streamed content blocks, parallel tool calls, resumed/branched sessions);
  totals are now deduplicated by message ID to match `claude /cost`. Displayed numbers will
  drop accordingly — this corrects prior inflation (often ~2–4×), not a loss of data. (#207)

---

## [0.4.67] - 2026-06-09

### Changed
- Bug fixes and improvements.

---

## [0.4.66] - 2026-06-08

### Changed
- Bug fixes and improvements.

---

## [0.4.65] - 2026-06-02

### Changed
- Bug fixes and improvements.

---

## [0.4.64] - 2026-05-29

### Changed
- Bug fixes and improvements.

---

## [0.4.63] - 2026-05-15

### Changed
- Bug fixes and improvements.

---

## [0.4.62] - 2026-05-14

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **[OpenCode Go](https://opencode.ai/go) quota tracking**: New `OpenCodeProvider` monitors OpenCode Go usage windows (5hr/$12, weekly/$30, monthly/$60) by querying the local OpenCode SQLite database via `opencode db --format json`. Session, weekly, and monthly quotas are displayed with percentage remaining and reset times.

### Fixed
- **Gemini quota now reports real usage instead of dummy 100%**: The probe used to discover a project via `cloudresourcemanager.googleapis.com/v1/projects`, which fails for personal-OAuth users (no GCP scope). Without a project, `cloudcode-pa retrieveUserQuota` returns a meaningless three-bucket "all 100%" response — the same symptom reported in #124 (quotas frozen at 100%) and the cause behind #122 (Gemini 3 models missing). `GeminiProjectRepository` now calls the same `cloudcode-pa loadCodeAssist` bootstrap that gemini-cli itself uses and surfaces the resulting `cloudaicompanionProject`, so the quota request returns accurate per-user numbers including `gemini-3-*-preview` buckets.

### Changed
- **Gemini quotas sort by usage**: Models with the lowest remaining fraction (most used) now appear first in the menu, with model ID as a stable tiebreaker. Previously sorted alphabetically, which buried the model you actually need to watch.
- **Gemini quotas collapse tier-aliased duplicates**: The Code Assist API exposes one tier-level quota under multiple model IDs (e.g. `gemini-2.5-pro`, `gemini-3-pro-preview`, and `gemini-3.1-pro-preview` all return the same Pro-tier bucket). The probe now collapses aliases that share both tier and `(remainingFraction, resetTime)` into a single row labeled with the newest version, so 7 effectively-duplicate rows become 3 distinct quotas (Pro / Flash / Flash-Lite).

---

## [0.4.61] - 2026-05-08

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Optional menu bar quota percentage**: A new setting shows the active provider's quota percentage directly in the menu bar next to the icon, so you can see usage at a glance without opening the popover. Configurable in Settings, with optional pace-aware status coloring driven by `burnRateThreshold`.

### Fixed
- **Z.ai weekly/monthly token quotas no longer collide with session quota**: Z.ai's GLM Coding Plan API returns multiple `TOKENS_LIMIT` entries distinguished only by an integer `unit` field. The previous parser mapped every entry to `.session`, causing the weekly token cap — the most important number on the GLM Coding Plan — to silently overwrite (or be overwritten by) the 5-hour session quota. Entries are now disambiguated by `unit`, so session, weekly, and monthly token limits are tracked independently.

---

## [0.4.60] - 2026-05-02

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Cache visibility on Claude daily usage cards**: Token Usage now shows the total *with* cache included plus a "X% from cache" subtitle, and Cost Usage shows a "Saved $X (Y%)" line — making the value of prompt caching visible at a glance.
- `DailyUsageStat` exposes `inputTokens`, `outputTokens`, `cacheCreationTokens`, `cacheReadTokens`, `cachedSavings`, plus `cacheHitRate`, `totalTokensWithCache`, and formatted helpers for downstream consumers.
- `ModelPricing.savings(for:)` estimates dollars saved by cache hits (`cache_read × (input_price − cache_read_price)`).

### Fixed
- **Token Usage card no longer excludes cache tokens**: previously displayed `input + output` only, which under-reported total volume by ~10–100× on cache-heavy workflows.
- **SwiftTerm Metal duplicate task build error** (tuist/tuist#9111): SwiftTerm now builds as a `.framework` instead of `.staticFramework`, avoiding Tuist 4.78.1+ duplicating `Shaders.metal` into both Sources and Resources phases.

---

## [0.4.59] - 2026-04-15

### Changed
- Bug fixes and improvements.

---

## [0.4.58] - 2026-04-01

### Changed
- Bug fixes and improvements.

---

## [0.4.57] - 2026-03-23

### Changed
- Bug fixes and improvements.

---

## [0.4.56] - 2026-03-22

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- Mistral provider backed by Vibe session logs for quota monitoring.

### Fixed
- Mistral probe now uses Vibe's `session_total_llm_tokens` and `session_cost` fields for accurate usage tracking.

---

## [0.4.55] - 2026-03-20

### Changed
- Bug fixes and improvements.

---

## [0.4.54] - 2026-03-20

### Changed
- Bug fixes and improvements.

---

## [0.4.53] - 2026-03-19

### Fixed
- **Claude account info empty on CLI v2.1.79+**: The Claude CLI now uses a tabbed TUI where account info (email, organization) is on the Status tab, not the Usage tab. The probe now reads account info from `~/.claude.json` (`oauthAccount`) as a fallback, so the account card displays correctly without extra CLI calls.

### Refactored
- **Extract `ClaudeAccountInfoResolver`**: Account info resolution logic extracted from `ClaudeUsageProbe` into a dedicated `ClaudeAccountInfoResolver` that reads `~/.claude.json` → `oauthAccount`. Introduced `AccountInfo` domain value object with `displayName`, `isEmpty`, and `initialLetter` computed properties. Improves SRP and testability — the probe now delegates account identity resolution instead of owning it.

---

## [0.4.52] - 2026-03-18

### Changed
- Bug fixes and improvements.

---

## [0.4.51] - 2026-03-17

### Changed
- Bug fixes and improvements.

---

## [0.4.50] - 2026-03-17

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Extensions System**: Raycast-style user extensions for custom provider monitoring. Drop a folder with a `manifest.json` and probe scripts into `~/.claudebar/extensions/` to add your own provider. Each extension defines composable sections (`quotaGrid`, `metricsRow`, `dailyUsage`, `costUsage`, `statusBanner`, `healthCheck`) with per-section probe commands and independent refresh intervals. Probe scripts can be any language (bash, python, swift) — just output JSON to stdout. Extensions auto-register as providers with custom branding (icon, colors) and appear in the provider pills alongside built-in providers. See `docs/features/extensions.md` for the full spec and example.
- **Built-in Health Check for Extensions**: Extensions can now define a `healthCheck` section with a URL endpoint — no probe script needed. ClaudeBar pings the URL and renders Status (UP/DOWN with HTTP code) and Latency cards automatically. Configure via `"probe": { "builtIn": "healthCheck", "url": "https://..." }` in `manifest.json`.

---

## [0.4.49] - 2026-03-17

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Custom Web Card per Provider**: Configure a custom URL for any provider to display an embedded web page as an additional card below the quota cards. Useful for third-party dashboards like [claude.owo.nz](https://claude.owo.nz/). Set via Settings → Providers → Custom Card URL field. The page is rendered inline with WKWebView, scaled to fit the card, with an "open in browser" button.

### Fixed
- **SwiftTerm Metal duplicate build error**: Resolved the `Unexpected duplicate tasks: MetalLink` build failure caused by Tuist adding `Shaders.metal` to both Sources and Resources build phases. Fixed via `EXCLUDED_SOURCE_FILE_NAMES` in Tuist package settings, eliminating the need for the post-generation fix script.

---

## [0.4.48] - 2026-03-16

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Burn Rate Warnings**: New pace-aware warning system that alerts based on consumption rate rather than fixed usage thresholds. Instead of warning at arbitrary percentages (e.g., 57% used = warning), it calculates whether you're on track to exhaust your quota before the period resets. For example, 57% used with 85% of the session elapsed is healthy (burn rate 0.67), while 53% used with only 8.5% of the week elapsed is a real warning (burn rate 6.2). Configurable threshold multiplier (1.2x–3.0x) in Settings. Disabled by default — opt in via Settings → Burn Rate Warnings. Critical (<20%) and depleted (0%) thresholds remain absolute as a safety net. ([#151](https://github.com/tddworks/ClaudeBar/issues/151))

---

## [0.4.47] - 2026-03-12

---

## [0.4.46] - 2026-03-12

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Alibaba Coding Plan Provider**: Monitor your Alibaba Coding Plan usage quotas directly from the menu bar. Supports three quota windows — 5-hour session, weekly, and monthly — with reset times and progress tracking. Authenticate via API key or browser cookies (auto-extract with SweetCookieKit or paste manually). Supports both International (`modelstudio.console.alibabacloud.com`) and China Mainland (`bailian.console.aliyun.com`) regions.

---

## [0.4.45] - 2026-03-12

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Daily Usage Cards Toggle**: New setting to show/hide daily usage report cards (API Cost, Token Usage, Working Time) in the menu bar. Useful for users who don't use the Claude API or prefer a cleaner view. Toggle in Settings → Display.

### Improved
- **Settings Storage Migration**: Migrated all settings from UserDefaults to a unified JSON file (`~/.claudebar/settings.json`). Settings are now backed by `JSONSettingsRepository` with dot-notation key paths, making them easier to inspect, debug, and test. Credentials (GitHub token, MiniMax API key) remain in UserDefaults for now.
- **Settings Architecture**: `AppSettings` now exposes typed provider accessors (`settings.claude`, `settings.copilot`, etc.) via ISP sub-protocols, replacing direct `UserDefaultsProviderSettingsRepository.shared` calls throughout the codebase.

### Fixed
- **Daily Usage Report**: Fixed daily usage cards not appearing when today's usage is $0.00 but yesterday has data. The report now shows whenever either today or the previous day has usage data.

### Technical
- Added `JSONSettingsStore` for thread-safe JSON file I/O with nested dot-notation key paths
- Added `JSONSettingsRepository` implementing all settings protocols (`AppSettingsRepository`, `ClaudeSettingsRepository`, `CopilotSettingsRepository`, `BedrockSettingsRepository`, `KimiSettingsRepository`, `MiniMaxSettingsRepository`, `HookSettingsRepository`, etc.)
- Added `AppSettingsRepository` domain protocol with `@Mockable` for testability
- Refactored `AppSettings` to use `JSONSettingsRepository` as private backing store with typed protocol accessors
- Added `showDailyUsageCards` setting end-to-end (toggle → AppSettings → JSONSettingsRepository → settings.json)
- 87+ new settings tests (JSONSettingsStore: 18, JSONSettingsRepository app: 20, provider: 29)
- Reorganized provider tests into subfolder structure (`Tests/DomainTests/Provider/Claude/`, `Copilot/`, etc.)
- Added `AlibabaUsageProbe` with console RPC and API key fetch strategies, resilient DataV2 envelope parsing
- Added `AlibabaProvider`, `AlibabaRegion`, `AlibabaCookieSource` domain models
- Added `AlibabaSettingsRepository` sub-protocol (ISP) for region, cookie source, and credentials
- 20 new Alibaba provider tests (17 parsing + 3 probe behavior)

---

## [0.4.44] - 2026-03-11

---

## [0.4.43] - 2026-03-11

---

## [0.4.43] - 2026-03-11

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Daily Usage Report Cards**: See your daily Claude Code cost, token usage, and working time right in the menu bar. ClaudeBar now analyzes your local session files (`~/.claude/projects/`) and displays three new cards below the quota cards:
  - **Cost Usage** — Estimated daily spend based on token counts and Anthropic's published model pricing (Opus, Sonnet, Haiku)
  - **Token Usage** — Total tokens consumed (input, output, and cache)
  - **Working Time** — Time spent in Claude Code sessions, estimated from message timestamps
  - Each card shows a comparison delta vs the previous day (e.g., "Vs Mar 10 -$27.47 (4.9%)")
  - Only scans recently modified files for fast performance even with thousands of sessions

---

## [0.4.42] - 2026-03-09

---

## [0.4.41] - 2026-03-08

---

## [0.4.40] - 2026-03-04

### Fixed
- **Cursor Enterprise Plan Support**: Fixed quota monitoring for enterprise accounts where `limitType` is `"team"`. Previously the parser always threw `"No usage data found"` because `individualUsage.plan.limit` is `0` on enterprise plans. The parser now falls back to `breakdown.total` for the individual credit limit and reads `teamUsage.onDemand` as an additional team quota source (reported in [#136](https://github.com/tddworks/ClaudeBar/issues/136)).

## [0.4.38] - 2026-02-25

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Claude Setup-Token Support**: ClaudeBar now recognizes users who authenticate via `claude setup-token`. The app loads the `CLAUDE_CODE_OAUTH_TOKEN` environment variable as a credential source and gracefully falls back to stored credentials (file/keychain) that have full scope, so quota monitoring continues to work seamlessly regardless of how you authenticated (contributed by [@brendandebeasi](https://github.com/brendandebeasi) in [#129](https://github.com/tddworks/ClaudeBar/pull/129)).

### Fixed
- **MiniMax Region Support**: MiniMax settings now include a region selector (International vs. China) to point to the correct API endpoint. Previously the app hardcoded the China-region URL (`minimaxi.com`), preventing international users from fetching quota data. Select your region in Settings → MiniMax to fix connection issues (contributed by [@BryanQQYue](https://github.com/BryanQQYue) in [#125](https://github.com/tddworks/ClaudeBar/issues/125)).

## [0.4.37] - 2026-02-24

### Fixed
- **Codex process leak**: Fixed a critical bug where ClaudeBar would spawn a new `codex app-server` process on every usage refresh without ever terminating it. Over time this caused thousands of orphaned processes that degraded system performance (reported in [#113](https://github.com/tddworks/ClaudeBar/issues/113)). The locally-created `ProcessRPCTransport` is now properly closed after each RPC call via `defer`.

## [0.4.36] - 2026-02-16

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Cursor Support**: Monitor your [Cursor](https://cursor.com) IDE subscription usage (included requests and on-demand spending) directly from the menu bar. Supports Pro, Business, Free, and Ultra plans with automatic tier detection.
  - Reads auth token from Cursor's local SQLite database automatically
  - Calls `cursor.com/api/usage-summary` for real-time usage data
  - Displays monthly included requests and on-demand usage
- **Overview Mode AppLogo**: The header now displays the ClaudeBar logo when Overview mode is enabled, instead of the last selected provider's icon.

### Fixed
- **Cursor API parsing**: Fixed parsing to match the real Cursor API response structure (`individualUsage.plan` and `individualUsage.onDemand`).

### Technical
- Added `CursorProvider` domain model following Kiro/AmpCode pattern
- Added `CursorUsageProbe` with HTTP API + SQLite token extraction
- Added Cursor visual identity (icon, brand color, gradient)
- 15+ parsing tests covering all Cursor response formats

## [0.4.35] - 2026-02-15

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Kiro Support**: Monitor your [Kiro](https://kiro.dev) (by AWS) AI coding assistant usage quotas via `kiro-cli`. Displays weekly bonus credits and monthly regular credits with reset time tracking.
  - Install with `uv tool install kiro-cli` and authenticate via Kiro IDE
  - Automatically parses usage data from `kiro-cli /usage` output

### Fixed
- **MiniMax Branding**: Renamed "MiniMaxi" to "MiniMax" for correct branding consistency (#116).

### Technical
- Added `KiroProvider` domain model and `KiroUsageProbe` with CLI output parsing
- Added `SimpleCLIExecutor` for lightweight Process-based CLI execution
- Migrated Kiro tests from XCTest to Swift Testing

## [0.4.34] - 2026-02-15

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **MiniMax Support**: Monitor your [MiniMax](https://www.minimax.io) Coding Plan usage quota directly from the menu bar. Queries the MiniMax API for remaining coding plan credits.
  - Configurable API key and environment variable support in Settings
  - Test connection button to verify API key

### Fixed
- **Docs**: Corrected release build command in CLAUDE.md and README (`-C Release` → `-configuration Release`).

### Technical
- Added `MiniMaxiProvider` domain model with API-based quota tracking
- Added `MiniMaxiUsageProbe` querying `/v1/api/openplatform/coding_plan/remains`
- Added `MiniMaxiSettingsRepository` sub-protocol for API key and env var configuration
- Parsing and probe unit tests

## [0.4.33] - 2026-02-14

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Claude Code Session Tracking**: Real-time monitoring of Claude Code sessions via hooks. When Claude Code is running, ClaudeBar shows session status directly in the menu bar and popover:
  - **Menu bar indicator**: A terminal icon appears next to the quota icon with phase-colored status (green = active, blue = subagents working, orange = stopped)
  - **Session card**: Detailed session info in the popover showing phase, task count, active subagents, duration, and working directory
  - **System notifications**: Get notified when a session starts ("Claude Code Started") and finishes ("Claude Code Finished — Completed 3 tasks in 2m 5s")
- **Hook Settings**: New "Claude Code Hooks" section in Settings with a single toggle to enable/disable. Automatically installs/uninstalls hooks in `~/.claude/settings.json`. Server starts/stops reactively when the toggle changes.
- **Copilot Internal API Probe**: New dual probe mode for GitHub Copilot, supporting Business and Enterprise plans where the Billing API returns 404. Switchable in Settings between "Billing API" (default) and "Copilot API" (`copilot_internal/user`) modes.

### Fixed
- **HookHTTPServer deadlock**: Removed `queue.sync` calls inside NWListener callbacks that already run on the same serial queue, preventing a crash on startup.
- **Hook format**: Updated hook installer to use Claude Code's new matcher-based format (`{"matcher": ".*", "hooks": [...]}`) instead of the deprecated flat format.

### Technical
- Added `SessionEvent`, `ClaudeSession`, and `SessionMonitor` (`@MainActor`) domain models for session lifecycle tracking
- Added `HookHTTPServer` using Network.framework (`NWListener`) for localhost-only event reception on port 19847
- Added `SessionEventParser` for parsing Claude Code hook JSON payloads
- Added `HookInstaller` with atomic writes and corruption-safe JSON handling
- Added `PortDiscovery` for writing/reading `~/.claude/claudebar-hook-port`
- Added `HookSettingsRepository` protocol and JSON-backed implementation
- Added `CopilotProbeMode` enum, `CopilotInternalAPIProbe`, and dual probe support in `CopilotProvider`
- Added `com.apple.security.network.server` entitlement for `NWListener`
- Added `AppLog.hooks` logging category
- Extracted `ClaudeSession.Phase.label` and `.color` extensions to deduplicate phase display logic
- Added `HookConstants.defaultPort` as single source of truth for port 19847

## [0.4.32] - 2026-02-12

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Overview Mode**: New "Overview" toggle in Settings to display all enabled providers at once in a single scrollable view. Ideal for juggling multiple AI assistants (Claude + Codex + Kimi + ...) throughout the day — see all your quotas at a glance without switching between pills.

### Technical
- Added `overviewModeEnabled` setting to `AppSettings`
- Added scrollable overview layout with per-provider sections reusing existing stat cards, capped at 80% screen height

## [0.4.31] - 2026-02-12

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Kimi Support**: Monitor your [Kimi](https://www.kimi.com/code/console) AI coding assistant usage quota directly from the menu bar. Displays weekly quota and 5-hour session rate limit with automatic tier detection (Andante/Moderato/Allegretto).
- **Kimi Dual Probe Mode**: Kimi now supports both CLI and API modes, switchable in Settings:
  - **CLI Mode (Recommended)**: Launches the interactive `kimi` CLI and sends `/usage`. No Full Disk Access needed — just install `kimi` CLI (`uv tool install kimi-cli`).
  - **API Mode**: Calls the Kimi API directly using browser cookie authentication via [SweetCookieKit](https://github.com/steipete/SweetCookieKit). Requires Full Disk Access to read browser cookies.
- **Provider Icon**: New Kimi icon with blue/cyan branded styling in the provider list.

### Technical
- Added `SweetCookieKit` dependency for cross-browser cookie extraction
- Implemented `KimiCLIUsageProbe` with interactive CLI execution and `/usage` output parsing
- Implemented `KimiUsageProbe` (API mode) with Connect-RPC API integration and JWT session header extraction
- Implemented `KimiTokenProvider` with env var → browser cookie fallback chain
- Added `KimiProvider` domain model with dual-probe support (CLI + API) and probe mode switching
- Added `KimiProbeMode` enum and `KimiSettingsRepository` sub-protocol (ISP pattern)
- Added Kimi configuration card in Settings with CLI/API probe mode picker
- Added visual identity (icon, theme color, gradient) for Kimi provider
- Registered Kimi provider in `ClaudeBarApp` startup with both probes
- Comprehensive test coverage: CLI parsing tests (18), CLI probe behavior tests (6), API probe tests (8), provider domain tests (18)

## [0.4.28] - 2026-02-10

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Amp Code Support**: Monitor your [Amp](https://ampcode.com) (by Sourcegraph) AI coding assistant usage quota directly from the menu bar. Automatically detects the `amp` CLI and displays your usage and plan tier.
- **Amp Tier Detection**: Automatically identifies your Amp subscription tier (Free, Pro, etc.) for accurate quota display.
- **Provider Icon**: New Amp icon with branded styling in the provider list.

### Improved
- **Privacy Protection**: Amp probe sanitizes personal information from log output to prevent PII leaks.
- **Probe Performance**: Optimized regex compilation in Amp probe for faster quota parsing.

### Technical
- Implemented `AmpCodeUsageProbe` with CLI output parsing and tier detection via regex
- Added `AmpCodeProvider` domain model with observable state and settings persistence
- Added visual identity (icon, theme color, gradient) for Amp provider
- Registered Amp provider in `ClaudeBarApp` startup
- Comprehensive test coverage for probe parsing (130+ lines), probe behavior (127+ lines), and tier detection

## [0.4.26] - 2026-02-09

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Launch at Login**: New toggle in Settings to automatically start ClaudeBar when you log in to your Mac. Uses macOS native `SMAppService` — no helper app required.
- **Pace Tick Mark**: Visual tick mark below the consumption bar showing your expected usage pace. ([#96](https://github.com/tddworks/ClaudeBar/pull/96) - thanks [@frankhommers](https://github.com/frankhommers)!)

### Fixed
- **Claude API Cost Display**: API cost is now correctly converted from cents to dollars in Claude API mode. ([#95](https://github.com/tddworks/ClaudeBar/issues/95))

### Improved
- **README Screenshots**: Compressed screenshots from ~38 MB to ~2.8 MB for faster page loading on GitHub.

## [0.4.2] - 2026-02-04

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Codex API Mode**: New alternative to RPC mode that fetches quota data directly via the ChatGPT backend API. Faster than RPC mode (no subprocess spawning), with automatic OAuth token refresh. Switch between modes in Settings → Codex Configuration.
- **Codex Configuration Card**: New settings panel to choose between RPC mode (default, uses `codex app-server` JSON-RPC) and API mode (direct HTTP API calls using OAuth credentials from `~/.codex/auth.json`).

### Improved
- **Codebase Organization**: Reorganized Infrastructure and Domain layers from mechanism-based grouping (`CLI/`, `Adapters/`, `AWS/`) to provider-based grouping (`Claude/`, `Codex/`, `Gemini/`, etc.), making it easier to find all files related to a specific provider.

### Technical
- Added `CodexAPIUsageProbe` calling `https://chatgpt.com/backend-api/wham/usage` with OAuth token refresh via `https://auth.openai.com/oauth/token`
- Added `CodexCredentialLoader` for loading OAuth credentials from `~/.codex/auth.json`
- Added `CodexProbeMode` enum (`.rpc`, `.api`) and `CodexSettingsRepository` protocol for probe mode persistence
- Extended `CodexProvider` with dual probe support (RPC + API) and mode switching
- Reorganized `Sources/Infrastructure/` into provider-level folders (`Claude/`, `Codex/`, `Gemini/`, `Copilot/`, `Antigravity/`, `Zai/`, `Bedrock/`, `Shared/`)
- Reorganized `Sources/Domain/Provider/` and `Tests/InfrastructureTests/` to mirror the same provider-first structure

## [0.4.1] - 2026-02-04

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Remaining / Used Display Toggle**: Switch between "25% Remaining" and "75% Used" views for all quota cards. Choose whichever framing makes more sense for your workflow — see how much you have left, or how much you've consumed. Toggle in Settings → Quota Display.

### Technical
- Added `UsageDisplayMode` enum in Domain layer with `.remaining` and `.used` cases
- Added `displayPercent(mode:)` and `displayProgressPercent(mode:)` methods to `UsageQuota`
- Added `usageDisplayMode` to `AppSettings` (default: `.remaining`)
- Updated `WrappedStatCard` and `QuotaCardView` to use display mode for percentage and label
- Added "Quota Display" settings card with two-button toggle
- 12 new tests covering display mode enum, percent calculation, and progress bar behavior

## [0.4.0] - 2026-02-03

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Claude API Mode**: New alternative to CLI mode that fetches quota data directly via Anthropic's OAuth API. Faster than CLI mode (no subprocess spawning), with automatic token refresh. Switch between modes in Settings → Claude Configuration.
- **Claude Configuration Card**: New settings panel to choose between CLI mode (default, uses `claude /usage` command) and API mode (direct HTTP API calls using OAuth credentials).
- **Copilot Manual Usage Override**: For users with organization-based Copilot subscriptions where API data isn't available, manually enter your usage from GitHub settings. Supports both request counts (e.g., "99") and percentages (e.g., "198%").
- **Copilot Monthly Limit Configuration**: Choose your Copilot plan tier (Free/Pro: 50, Business: 300, Enterprise: 1000, Pro+: 1500) for accurate quota calculations.
- **Over-Quota Display**: Negative percentages now display correctly when you've exceeded your quota limit (e.g., -98% when using 99 of 50 requests).

### Improved
- **Better Error Messages**: When Claude API session expires, shows user-friendly message: "Session expired. Run `claude` in terminal to log in again."
- **Gemini Quota Accuracy**: Falls back to any available GCP project when primary project isn't found, ensuring quota data is displayed.
- **Auto-Trust Probe Directory**: Automatically trusts the probe working directory when Claude CLI shows trust dialog, eliminating manual intervention.
- **CLAUDE_CONFIG_DIR Support**: Respects custom Claude configuration directory for trust file location.

### Fixed
- **Copilot Dashboard URL**: Now links directly to GitHub Copilot features page for easier usage viewing.
- **Copilot Usage Period Reset**: Manual usage entries automatically clear when billing period changes.
- **Schema Validation**: Guards against unexpected config file schemas to prevent crashes.

### Technical
- Added `ClaudeAPIUsageProbe` with OAuth token refresh via `https://platform.claude.com/v1/oauth/token`
- Added `ClaudeCredentialLoader` for loading OAuth credentials from `~/.claude/.credentials.json` or Keychain
- Added `ClaudeProbeMode` enum and `ClaudeSettingsRepository` protocol for probe mode persistence
- Extended `ClaudeProvider` with dual probe support (CLI + API) and mode switching
- Added `ProbeError.sessionExpired` case with user-friendly error description
- Migrated build system to Tuist for dependency management
- Updated aws-sdk-swift and SwiftTerm dependencies

## [0.3.15] - 2026-01-23

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **AWS Bedrock Support**: Monitor your AWS Bedrock AI usage directly from the menu bar. Track daily costs, token counts, and per-model breakdowns for your Claude, Llama, and other Bedrock models. ([#75](https://github.com/tddworks/ClaudeBar/pull/75) - thanks [@tomstetson](https://github.com/tomstetson)!)
- **Bedrock Usage Card**: New dedicated view showing daily costs, input/output token counts, and detailed per-model usage breakdown
- **Provider Icon**: New Bedrock provider icon with AWS orange theme for easy identification

### Improved
- **AWS SSO Authentication**: Full support for AWS SSO profile-based authentication using `SSOAWSCredentialIdentityResolver`, making it easy to use your existing AWS profiles
- **Cross-Region Inference**: Properly handles regional prefixes (us., eu., etc.) in model IDs for accurate pricing across regions
- **Model Pricing**: Added Claude Haiku 4.5 model pricing for accurate cost calculations

### Fixed
- **CloudWatch Period Calculation**: Fixed period calculation to be multiples of 60 seconds as required by CloudWatch API
- **CloudWatch Filters**: Removed problematic filters that could cause incomplete usage data

### Technical
- Implemented `BedrockUsageProbe` with CloudWatch metrics integration
- Added `SSOAWSCredentialIdentityResolver` for profile-based SSO credential resolution
- Created `BedrockUsageCard` SwiftUI view with cost and token breakdown display
- Extended visual identity system with Bedrock-specific colors and styling
- Added pricing normalization for cross-region inference model ID prefixes
- Bundled pricing data for Claude Haiku 4.5 model

## [0.3.12] - 2026-01-20

### Changed
- **Background Sync Disabled by Default**: Background sync is now disabled by default. Each Claude CLI spawn triggers a warmup session (even with zero prompts), and frequent background syncs can cause these sessions to stack up. The Claude Code team has addressed this in recent versions, so if you've updated to the latest Claude CLI, you can safely re-enable background sync in Settings → Background Sync.

## [0.3.6] - 2026-01-11

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **SwiftTerm Integration**: Added SwiftTerm terminal emulator library to properly render Claude CLI output. This fixes parsing issues with Claude Code v2.1.4+ which uses advanced terminal UI with cursor movements that previously corrupted captured output.

### Improved
- **Simplified Parsing**: Removed complex fuzzy matching and cursor movement heuristics. Terminal output is now properly rendered before parsing, producing clean text like a real terminal display.
- **Better Quota Accuracy**: Terminal rendering ensures "Current session" and other quota labels are parsed correctly even when the CLI uses cursor positioning to redraw the screen.

### Fixed
- **Sonnet Quota Display**: Fixed "Current week (Sonnet only)" being incorrectly labeled as "Opus" in the quota display. Sonnet and Opus quotas are now tracked and displayed separately.
- **Null Character Handling**: Fixed terminal buffer extraction to properly handle null characters from empty cells, which caused extracted text to include invisible padding.

### Technical
- Added SwiftTerm dependency (1.2.0+) for VT100/Xterm terminal emulation
- Created `TerminalRenderer` utility in `Sources/Infrastructure/Adapters/` that handles cursor movements, screen clearing, and ANSI escape sequences
- Replaced `stripANSICodes()` in `ClaudeUsageProbe` with `renderTerminalOutput()` using SwiftTerm
- Updated `Project.swift` to include SwiftTerm in Infrastructure target for Tuist builds
- Removed fuzzy regex matching (`matchesFuzzy`) - no longer needed with proper terminal rendering

## [0.3.4] - 2026-01-08

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Background Sync**: Your quota data now syncs automatically in the background, so it's always fresh when you open the menu. No more waiting! Configure sync intervals (30s, 1min, 2min, or 5min) in Settings → Background Sync.
- **Fresh App Logo**: Updated app icon with a refreshed design.

### Improved
- **Better CLI Detection**: Fixed issues finding Claude, Codex, and other CLI tools on systems with custom shell configurations. The app now uses your login shell to properly resolve PATH ([#45](https://github.com/tddworks/ClaudeBar/issues/45)).

### Fixed
- **Update Window Focus**: The update dialog now properly comes to the front when checking for updates.

### Technical
- Added `backgroundSyncEnabled` and `backgroundSyncInterval` settings to `AppSettings`
- Implemented background sync lifecycle in `MenuContentView` with start/stop/restart controls
- Added Background Sync settings card to Settings UI with interval picker
- Uses existing `QuotaMonitor.startMonitoring()` infrastructure for efficient polling
- Added `shellPath()` to `InteractiveRunner` for accurate shell environment resolution

## [0.3.0] - 2026-01-05

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Pluggable Theme System**: ClaudeBar now supports multiple visual themes with a protocol-based architecture. Switch themes instantly from Settings to match your workflow and preferences.
- **CLI Terminal Theme**: New monochrome, terminal-inspired theme for developers who prefer a classic command-line aesthetic. Features monospace fonts, green accents, and a retro terminal look.
- **Theme-Specific Menu Bar Icons**: Each theme can display its own custom menu bar icon, providing a cohesive visual experience across the entire app.

### Improved
- **Enhanced Christmas Theme**: Refreshed festive color palette with improved reds, greens, and golds. Updated gradients and glass effects for a more polished holiday feel.
- **Smoother UI**: Refined corner radius on cards and pills for a more consistent visual appearance across all themes.
- **Menu Width**: Adjusted menu content width for better readability.

### Fixed
- **Menu Bar Status Display**: The menu bar icon now correctly reflects the selected provider's status instead of showing incorrect state.

### Technical
- Introduced `AppThemeProvider` protocol for pluggable theme architecture
- Added `ThemeRegistry` for runtime theme management and discovery
- Created SwiftUI environment integration with `@Environment(\.appTheme)` support
- Implemented built-in themes: Dark, Light, CLI, Christmas, and System (auto-switching)
- Added `statusBarIconName` property to themes for custom menu bar icons
- Moved theme colors to static properties within theme structs for better encapsulation
- Added comprehensive theme system design documentation

## [0.2.15] - 2026-01-05

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Claude API Billing Support**: Users with API Usage Billing accounts (pay-per-use) can now monitor their Claude usage. The app automatically detects billing plan type and uses the `/cost` command to display total cost and API duration when `/usage` is unavailable.
- **Z.ai Environment Variable Fallback**: Configure a custom environment variable for GLM authentication in Settings, useful when you have multiple API keys or non-standard setups.
- **Custom Z.ai Config Path**: Specify a custom path to your Z.ai configuration file if it's not in the default Claude Code settings location.
- **Copilot Environment Variable Support**: Configure a custom environment variable for GitHub Copilot authentication, with validation to ensure the variable exists.

### Improved
- **Easier Log Access**: "Open Logs" now opens the log file directly in TextEdit instead of the folder, making it quicker to view logs.
- **Z.ai Settings UI**: Added chevron indicator to show expand/collapse state for Z.ai configuration section.
- **Better Z.ai Error Messages**: Error messages now include the config path being used, making troubleshooting easier.
- **CLI Diagnostics**: When Claude CLI is not found, the app now logs PATH and CLAUDE_CONFIG_DIR environment variables to help diagnose installation issues.

### Fixed
- **UI Layout Issues** ([#40](https://github.com/tddworks/ClaudeBar/issues/40)): Fixed layout constraints that caused views to break on certain screen sizes.
- **Claude Detection for API Accounts** ([#37](https://github.com/tddworks/ClaudeBar/issues/37)): Fixed issue where users with API Usage Billing accounts couldn't see Claude quota information.

### Technical
- Extended `ProbeError` with `subscriptionRequired` case for API billing detection
- Implemented `/cost` command parsing with cost value and API duration extraction
- Added ISP-based repository hierarchy for provider-specific settings (`ZaiSettingsRepository`, `CopilotSettingsRepository`)
- Namespaced settings keys with dot-notation prefixes for cleaner storage
- Added `NotificationAlerter` unit tests
- Comprehensive test coverage for API billing detection and cost parsing

## [0.2.14] - 2026-01-03

### Fixed
- **Layout Constraint Crash**: Fixed potential crash from layout constraints in background views.

### Technical
- Added skill guides for bug fixing and improvements following Chicago School TDD

## [0.2.13] - 2026-01-02

### Improved
- **Settings Scrolling**: Settings view now scrolls on small screens, ensuring all options remain accessible regardless of display size.

### Fixed
- **Provider Selection After Restart**: Disabled providers no longer appear selected after app restart. The app now automatically switches to the first enabled provider.

### Technical
- `QuotaMonitor` now maintains selection invariants (auto-selects valid provider on init and when providers are disabled)
- Added `setProviderEnabled()` API for toggling providers with automatic selection handling

## [0.2.12] - 2026-01-02

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Provider Enable/Disable**: Toggle individual AI providers on/off from Settings. Disabled providers are hidden from the menu bar and excluded from quota monitoring.
- **Copilot Credential Management**: GitHub Copilot now manages its own credentials (token and username) directly within the provider, making setup more intuitive.

### Changed
- **Simplified Architecture**: Streamlined codebase with cleaner separation of concerns
  - Views now consume domain models directly from `QuotaMonitor`
  - Provider settings persisted via injectable repositories for better testability
  - Credential management moved from global settings to individual providers

### Removed
- **Z.ai Demo Mode**: Removed demo mode toggle - Z.ai provider now always uses real credentials

### Fixed
- **Z.ai Icon**: Now displays the correct Z.ai provider icon

### Technical
- Introduced `ProviderSettingsRepository` protocol for provider enable/disable persistence
- Introduced `CredentialRepository` protocol for token/credential storage
- Moved `CopilotProvider` credentials from `AppSettings` to provider-owned state
- `QuotaMonitor` now owns `AIProviders` repository with delegation methods
- Removed `AppState` layer - views consume `QuotaMonitor` directly
- Added comprehensive test coverage for ZaiProvider (22 tests)
- Refactored tests to follow Chicago School TDD (state-based, no verify calls)

## [0.2.11] - 2026-01-01

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Share Claude Pass**: Share referral links with friends to give them a free week of Claude Code! Click the gift icon (🎁) in the action bar when Claude is selected to copy or open your referral link.

### Improved
- **Cleaner Action Bar**: Share button is now a compact icon that fits seamlessly alongside Settings and Close buttons
- **Button Text Stability**: Fixed issue where action button labels could wrap to multiple lines

### Technical
- Added `ClaudePass` domain model with referral URL and optional pass count
- Implemented `ClaudePassProbe` that executes `claude /passes` and reads referral link from clipboard
- Added `ClaudePassProbing` protocol for testability with dependency injection
- Created `SharePassOverlay` view component with copy-to-clipboard and open-in-browser actions
- Extended `ClaudeProvider` with `fetchPasses()` method and guest pass state management
- Added share gradient to theme system for consistent styling
- Comprehensive test coverage (30 tests) for domain model, probe parsing, and provider integration

## [0.2.10] - 2025-12-31

### Improved
- **Z.ai Quota Reset Time**: Now displays when your Z.ai quota will reset, helping you plan your usage effectively

### Technical
- Added flexible date parsing for Z.ai API responses (supports ISO-8601 with timezone and milliseconds)

## [0.2.9] - 2025-12-31

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Z.ai GLM Coding Plan Support**: Monitor your [Z.ai GLM Coding Plan](https://z.ai/subscribe) usage quota directly from the menu bar. Automatically detects Z.ai configuration in Claude Code settings and displays your 5-hour session limit and MCP usage in real-time.
- **Provider Icon**: New Z.ai icon with blue branding in the provider list

### Technical
- Implemented `ZaiUsageProbe` with Bearer authentication and config file parsing (supports `env` and `providers` formats)
- Added `ZaiProvider` domain model with observable state
- Added `QuotaType.timeLimit` for semantic mapping of time-based quotas (MCP usage)
- Comprehensive test coverage (27 tests) for parsing, behavior, and error handling

## [0.2.8] - 2025-12-30

### Fixed
- Bug fixes and improvements.

## [0.2.7] - 2025-12-29

### Fixed
- **Antigravity Quota Parsing**: Fixed issue where models with only reset time but no remaining fraction (like "Gemini 3 Flash") were incorrectly excluded from quota display. Missing `remainingFraction` now correctly indicates 0% remaining.

## [0.2.6] - 2025-12-29

### Improved
- **Cleaner Menu Layout**: Replaced scroll view with dynamic height layout for a smoother, more native menu bar experience
- **Smarter Quota Alerts**: Improved notification timing - alerts now request permission after the app fully launches, fixing issues on menu bar apps
- **Better Alert Messages**: Clearer, more actionable quota alert messages when your usage is running low

### Fixed
- **Notification Permission**: Fixed issue where notification permission requests were being denied on first launch

### Technical
- Refactored notification system with cleaner domain naming (`QuotaAlerter`, `QuotaStatusListener`)
- Merged notification infrastructure into single `QuotaAlerter` class for simpler architecture
- Added detailed authorization status logging for easier troubleshooting

## [0.2.5] - 2025-12-29

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Google Antigravity Support**: Monitor your Antigravity AI assistant usage quota directly from the menu bar alongside Claude, Codex, Gemini, and GitHub Copilot
- **Local Server Detection**: Automatically detects running Antigravity language server and retrieves quota information via local API
- **Provider Icon**: New Antigravity icon in the provider list for easy identification

### Improved
- **Developer Documentation**: New TDD-based skill guide for adding AI providers, making it easier for contributors to add support for additional assistants
- **Secure Localhost Connections**: Added dedicated network client for handling self-signed certificates on localhost connections

### Technical
- Implemented `AntigravityUsageProbe` with process detection via `ps` and `lsof`
- Added CSRF token extraction from process arguments for secure API calls
- Created `InsecureLocalhostNetworkClient` adapter for self-signed cert handling
- Added `AntigravityProvider` domain model with observable state
- Comprehensive test coverage for process detection, API parsing, and error handling

## [0.2.4] - 2025-12-29

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Dual-Output Logging**: Logs now write to both OSLog (for developers via Console.app) and persistent files (for users) at `~/Library/Logs/ClaudeBar/ClaudeBar.log`
- **Open Logs Button**: New "Open Logs Folder" button in Settings for easy access to log files when troubleshooting
- **Comprehensive Error Logging**: All AI provider probes now log detailed error information for easier debugging

### Improved
- **Better Troubleshooting**: Users can now share log files when reporting issues, making it easier to diagnose problems
- **Automatic Log Rotation**: Log files automatically rotate at 5MB to prevent disk space issues
- **Thread-Safe Logging**: File logging is designed for safe concurrent access

### Technical
- Added `FileLogger` with automatic directory creation and 5MB rotation
- Created `AppLog` facade that unifies OSLog and file output
- Debug level logs go to OSLog only; info/warning/error go to both outputs
- Added unit tests for ANSI stripping in log content

## [0.2.3] - 2025-12-28

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Beta Updates Channel**: Opt into beta releases to get early access to new features before they're widely available
- **Dual Update Tracks**: Stable and beta releases now coexist - stable users get stable updates, beta users get the latest beta

### Improved
- **Smarter Update Feed**: The appcast now maintains both the latest stable and beta versions, ensuring you always get the right update for your preference
- **Reliable Version Detection**: Build numbers are now properly validated to prevent version confusion

### Technical
- Added comprehensive unit tests for update channel handling (17 test scenarios)
- Improved release workflow documentation for beta releases

## [0.2.2] - 2025-12-26

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- Update Notification Badge: See a visual indicator on the settings button when a new version is available
- Version Info Display: View the available update version directly in the menu

## [0.2.1] - 2025-12-26

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- **Auto-Update Toggle**: Control automatic update checks from Settings
- **Update Progress Indicator**: See visual feedback when checking for updates

### Improved
- **Smarter Update Checks**: Updates are now checked when you open the menu, giving you control instead of running in the background
- **Cleaner Update Dialog**: Release notes now display with better formatting
- **More Reliable CLI Interaction**: Better handling of CLI prompts and improved timeout for quota fetching

## [0.2.0] - 2025-12-25

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- CHANGELOG.md as single source of truth for release notes
- `extract-changelog.sh` script to parse version-specific notes
- Sparkle checks for updates when menu opens (instead of automatic background checks)
- Improved release notes HTML formatting in update dialog

### Changed
- Release workflow uses CHANGELOG.md instead of auto-generated notes

### Fixed
- Sparkle warning about background app not implementing gentle reminders

## [0.1.0] - 2025-12-15

### Added
- Accounts: with one Codex account the tab shows "Codex" again; with several, each shows its name or email. Menu bar labels stay short (`work`, `Side Project`) and are numbered when alike instead of widening to a full email. ([#308](https://github.com/tddworks/ClaudeBar/issues/308))
- Initial release
- Claude CLI usage monitoring
- Codex CLI usage monitoring
- Menu bar interface with quota display
- Automatic refresh every 5 minutes

[Unreleased]: https://github.com/tddworks/ClaudeBar/compare/v0.4.95...HEAD
[0.4.95]: https://github.com/tddworks/ClaudeBar/compare/v0.4.94...v0.4.95
[0.4.94]: https://github.com/tddworks/ClaudeBar/compare/v0.4.93...v0.4.94
[0.4.93]: https://github.com/tddworks/ClaudeBar/compare/v0.4.92...v0.4.93
[0.4.92]: https://github.com/tddworks/ClaudeBar/compare/v0.4.91...v0.4.92
[0.4.91]: https://github.com/tddworks/ClaudeBar/compare/v0.4.90...v0.4.91
[0.4.90]: https://github.com/tddworks/ClaudeBar/compare/v0.4.89...v0.4.90
[0.4.89]: https://github.com/tddworks/ClaudeBar/compare/v0.4.88...v0.4.89
[0.4.88]: https://github.com/tddworks/ClaudeBar/compare/v0.4.87...v0.4.88
[0.4.87]: https://github.com/tddworks/ClaudeBar/compare/v0.4.86...v0.4.87
[0.4.86]: https://github.com/tddworks/ClaudeBar/compare/v0.4.85...v0.4.86
[0.4.85]: https://github.com/tddworks/ClaudeBar/compare/v0.4.84...v0.4.85
[0.4.84]: https://github.com/tddworks/ClaudeBar/compare/v0.4.83...v0.4.84
[0.4.83]: https://github.com/tddworks/ClaudeBar/compare/v0.4.82...v0.4.83
[0.4.82]: https://github.com/tddworks/ClaudeBar/compare/v0.4.81...v0.4.82
[0.4.81]: https://github.com/tddworks/ClaudeBar/compare/v0.4.80...v0.4.81
[0.4.80]: https://github.com/tddworks/ClaudeBar/compare/v0.4.79...v0.4.80
[0.4.79]: https://github.com/tddworks/ClaudeBar/compare/v0.4.78...v0.4.79
[0.4.78]: https://github.com/tddworks/ClaudeBar/compare/v0.4.77...v0.4.78
[0.4.77]: https://github.com/tddworks/ClaudeBar/compare/v0.4.76...v0.4.77
[0.4.76]: https://github.com/tddworks/ClaudeBar/compare/v0.4.75...v0.4.76
[0.4.75]: https://github.com/tddworks/ClaudeBar/compare/v0.4.73...v0.4.75
[0.4.73]: https://github.com/tddworks/ClaudeBar/compare/v0.4.72...v0.4.73
[0.4.72]: https://github.com/tddworks/ClaudeBar/compare/v0.4.71...v0.4.72
[0.4.71]: https://github.com/tddworks/ClaudeBar/compare/v0.4.70...v0.4.71
[0.4.70]: https://github.com/tddworks/ClaudeBar/compare/v0.4.69...v0.4.70
[0.4.69]: https://github.com/tddworks/ClaudeBar/compare/v0.4.68...v0.4.69
[0.4.68]: https://github.com/tddworks/ClaudeBar/compare/v0.4.67...v0.4.68
[0.4.67]: https://github.com/tddworks/ClaudeBar/compare/v0.4.66...v0.4.67
[0.4.66]: https://github.com/tddworks/ClaudeBar/compare/v0.4.65...v0.4.66
[0.4.65]: https://github.com/tddworks/ClaudeBar/compare/v0.4.64...v0.4.65
[0.4.64]: https://github.com/tddworks/ClaudeBar/compare/v0.4.63...v0.4.64
[0.4.63]: https://github.com/tddworks/ClaudeBar/compare/v0.4.62...v0.4.63
[0.4.62]: https://github.com/tddworks/ClaudeBar/compare/v0.4.61...v0.4.62
[0.4.61]: https://github.com/tddworks/ClaudeBar/compare/v0.4.60...v0.4.61
[0.4.60]: https://github.com/tddworks/ClaudeBar/compare/v0.4.59...v0.4.60
[0.4.59]: https://github.com/tddworks/ClaudeBar/compare/v0.4.58...v0.4.59
[0.4.58]: https://github.com/tddworks/ClaudeBar/compare/v0.4.57...v0.4.58
[0.4.57]: https://github.com/tddworks/ClaudeBar/compare/v0.4.56...v0.4.57
[0.4.56]: https://github.com/tddworks/ClaudeBar/compare/v0.4.55...v0.4.56
[0.4.55]: https://github.com/tddworks/ClaudeBar/compare/v0.4.54...v0.4.55
[0.4.54]: https://github.com/tddworks/ClaudeBar/compare/v0.4.53...v0.4.54
[0.4.53]: https://github.com/tddworks/ClaudeBar/compare/v0.4.52...v0.4.53
[0.4.52]: https://github.com/tddworks/ClaudeBar/compare/v0.4.51...v0.4.52
[0.4.51]: https://github.com/tddworks/ClaudeBar/compare/v0.4.50...v0.4.51
[0.4.50]: https://github.com/tddworks/ClaudeBar/compare/v0.4.49...v0.4.50
[0.4.49]: https://github.com/tddworks/ClaudeBar/compare/v0.4.48...v0.4.49
[0.4.48]: https://github.com/tddworks/ClaudeBar/compare/v0.4.47...v0.4.48
[0.4.47]: https://github.com/tddworks/ClaudeBar/compare/v0.4.46...v0.4.47
[0.4.46]: https://github.com/tddworks/ClaudeBar/compare/v0.4.45...v0.4.46
[0.4.45]: https://github.com/tddworks/ClaudeBar/compare/v0.4.44...v0.4.45
[0.4.44]: https://github.com/tddworks/ClaudeBar/compare/v0.4.43...v0.4.44
[0.4.43]: https://github.com/tddworks/ClaudeBar/compare/v0.4.43...v0.4.43
[0.4.43]: https://github.com/tddworks/ClaudeBar/compare/v0.4.42...v0.4.43
[0.4.42]: https://github.com/tddworks/ClaudeBar/compare/v0.4.41...v0.4.42
[0.4.41]: https://github.com/tddworks/ClaudeBar/compare/v0.4.40...v0.4.41
[0.4.40]: https://github.com/tddworks/ClaudeBar/compare/v0.4.38...v0.4.40
[0.4.38]: https://github.com/tddworks/ClaudeBar/compare/v0.4.37...v0.4.38
[0.4.28]: https://github.com/tddworks/ClaudeBar/compare/v0.4.27...v0.4.28
[0.4.26]: https://github.com/tddworks/ClaudeBar/compare/v0.4.2...v0.4.26
[0.4.2]: https://github.com/tddworks/ClaudeBar/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/tddworks/ClaudeBar/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/tddworks/ClaudeBar/compare/v0.3.15...v0.4.0
[0.3.15]: https://github.com/tddworks/ClaudeBar/compare/v0.3.12...v0.3.15
[0.3.12]: https://github.com/tddworks/ClaudeBar/compare/v0.3.6...v0.3.12
[0.3.6]: https://github.com/tddworks/ClaudeBar/compare/v0.3.4...v0.3.6
[0.3.4]: https://github.com/tddworks/ClaudeBar/compare/v0.3.0...v0.3.4
[0.3.0]: https://github.com/tddworks/ClaudeBar/compare/v0.2.15...v0.3.0
[0.2.15]: https://github.com/tddworks/ClaudeBar/compare/v0.2.14...v0.2.15
[0.2.14]: https://github.com/tddworks/ClaudeBar/compare/v0.2.13...v0.2.14
[0.2.13]: https://github.com/tddworks/ClaudeBar/compare/v0.2.12...v0.2.13
[0.2.12]: https://github.com/tddworks/ClaudeBar/compare/v0.2.11...v0.2.12
[0.2.11]: https://github.com/tddworks/ClaudeBar/compare/v0.2.10...v0.2.11
[0.2.10]: https://github.com/tddworks/ClaudeBar/compare/v0.2.9...v0.2.10
[0.2.9]: https://github.com/tddworks/ClaudeBar/compare/v0.2.8...v0.2.9
[0.2.8]: https://github.com/tddworks/ClaudeBar/compare/v0.2.7...v0.2.8
[0.2.7]: https://github.com/tddworks/ClaudeBar/compare/v0.2.6...v0.2.7
[0.2.6]: https://github.com/tddworks/ClaudeBar/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/tddworks/ClaudeBar/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/tddworks/ClaudeBar/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/tddworks/ClaudeBar/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/tddworks/ClaudeBar/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/tddworks/ClaudeBar/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/tddworks/ClaudeBar/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/tddworks/ClaudeBar/releases/tag/v0.1.0
