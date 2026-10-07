# Claude probe design

Contributor notes for the Claude provider. For setup, see the [README](README.md).

## Current shape: Claude is data

Claude has no provider class or probes of its own. It is
[`ClaudeBarKit/definitions/claude.json`](../../../ClaudeBarKit/definitions/claude.json)
plus two mapping scripts beside it (the `/usage` and `/cost` screens), run by the one `Provider` and the
`DataSources` workers ([TARGET_ARCHITECTURE.md](../../architecture/TARGET_ARCHITECTURE.md)):

| Data source | Fetch | Mapping | Then |
|---|---|---|---|
| `cli` (default) | `cli`: `claude /usage --allowed-tools ""` in the probe directory, `CLAUDE_CODE_OAUTH_TOKEN` unset, `CLAUDEBAR_PROBE=1`, the ready markers, screen rendered by the terminal emulator | `claude-usage-screen.js`, with `~/.claude.json`'s account fields as context | `subscriptionRequired` hands off to `cliCost`; any other failure falls back to `api`; `folderTrustRequired` patches `projects[<probe dir>].hasTrustDialogAccepted` once and retries |
| `cliCost` (hidden) | `cli`: `claude /cost`, no ready markers | `claude-cost-screen.js` | falls back to `api` |
| `api` | `http` `GET …/api/oauth/usage`; key from `~/.claude/.credentials.json`, the Keychain item, then `CLAUDE_CODE_OAUTH_TOKEN`; OAuth refresh with a JSON body 5 minutes before `expiresAt` (written back as a number) | a JSON mapping: windows by path (over the limit stays negative, countdowns in hours), model limits from `limits[]` where `kind` is `weekly_scoped` named by the model's first word (first one wins), the plan from the credential's `subscriptionType`, and money from `spend` in minor units, else legacy `extra_usage` | cached 15 minutes (the background floor); a 429 is remembered; falls back to `cli` unless `claude.cliFallbackEnabled` is off |

The scripts run in JavaScriptCore with no file, network or process access;
reset text is parsed by the host's `humanDate()`. Daily usage and guest passes
are attached to the provider at composition (`ClaudeBarApp`). The rules below
still hold — they are now lines in `claude.json`, pinned by
`Modules/Providers/Tests/Claude*Tests.swift`. Where this page names
`ClaudeProvider`, `ClaudeUsageProbe`, `ClaudeAPIUsageProbe` or
`ClaudeCredentialLoader`, read "the definition"; those types are gone.

## Sources

| Probe | Source | Notes |
|---|---|---|
| CLI (default) | `claude /usage --allowed-tools ""` in a PTY, run from `~/Library/Application Support/ClaudeBar/Probe`, inside one shared named session (see [One shared probe session](#one-shared-probe-session)) | The screen is rendered with SwiftTerm and then scraped |
| CLI, pay-as-you-go | `claude /cost` | Used only when `/usage` says it's "only available for subscription plans", or shows the API-billing panel for an account that isn't a subscription |
| API | `GET https://api.anthropic.com/api/oauth/usage`, header `anthropic-beta: oauth-2025-04-20` | Uses the Claude Code OAuth token |
| Token refresh | `POST https://platform.claude.com/v1/oauth/token` with Claude Code's public `client_id` | Scopes: `user:profile user:inference user:sessions:claude_code` only. Asking for more scopes (e.g. `user:mcp_servers`) makes the refresh fail |
| Account identity | `~/.claude.json` → `oauthAccount` (email, display name, `billingType`) — read by every data source as the `account` context file, so the email shows whether the CLI or the API answered | CLI v2.1.79+ moved account details to a separate Status tab |
| Guest passes | `claude /passes --allowed-tools ""` in a PTY, which copies the link to the clipboard — the `guestPasses` block in `claude.json` (see [Guest passes](#guest-passes)) | Max only (#243) |
| Daily usage | `~/.claude/projects/*/*.jsonl` | Deduplicated by `(message.id, requestId)`, because Claude Code writes the same usage more than once |

## Fallback chain

`ClaudeProvider` runs the chosen mode first and, if it fails, the other one:

- **CLI → API**: unconditional. This recovers from `/usage` parse failures and from subscriptions the CLI can't see. It is deliberately *not* gated on `ClaudeAPIUsageProbe.isAvailable()`: that call is a second, independently implemented answer to "can you work?", and when it said no the rescue was skipped without a word in the log. The log attached to #317 holds 114 `Claude parse failed` lines, all from the broken CLI probe, while the user saw "Claude Unavailable" throughout; that the gate is what skipped each rescue is an **inference**, not something the log states — it records no API-probe lines at all, so the API probe either never ran or ran silently. Either way the gate saved nothing, because `isAvailable()` reads the same credentials `probe()` reads before any network call, and the probe's own error is discarded in favour of the primary one.
- **API → CLI**: unconditional, except while `claude.cliFallbackEnabled` is off (on by default). Users asked for that off switch because running the CLI in the background can cause prompts (e.g. SSH keys) — it is the one policy gate, and it stays.
- **Never after `ProbeError.rateLimited`.** The CLI uses the same backend, so falling back only makes the throttling worse.
- **Both fail**: report the *primary* error. The fallback's error is incidental and would send users after the wrong problem — but it is still logged, through the provider's `diagnose` sink (wired to `AppLog.probes` in `ClaudeBarApp.init`). Now that this path runs on every failed probe, a swallowed fallback error would be indistinguishable in the log from a fallback that never ran, which is the same blind spot the removed `isAvailable()` gate had. The line names the probe and its error and never a credential value. The Domain layer holds no logger of its own — `AppLog` lives in Infrastructure, which depends on Domain — hence the injected sink rather than a direct call.

## Hooks and the probe

- Every probe run is a full Claude Code session, so the user's SessionStart/SessionEnd hooks fire for it too — a "Claude Code Started"/"Finished" pair on every quota poll (#222). Hooks live in the user-global `~/.claude/settings.json`, so running in the dedicated probe directory does not exempt a session from them. ClaudeBar owns both ends: the sessions it spawns itself (`/usage`, `/cost`, `/passes`) carry `CLAUDEBAR_PROBE=1` (`ClaudeUsageProbe.probeEnvironment`, carried by `DefaultCLIExecutor.environmentAdditions` → `InteractiveRunner.Options`), and the `__claudebar_hook` wrapper installed by `HookInstaller` returns before the curl POST when that variable is set.
- The guarded wrapper reaches existing users because `install()` re-runs at launch when hooks are already installed (`ClaudeBarApp.init`), replacing only ClaudeBar's own matcher entries.
- A second net in `SessionEvent.isClaudeBarProbe` drops events from the probe working directory (`…/ClaudeBar/Probe` suffix) and events with no attributable working directory at all. The empty-cwd case is deliberate: a payload without `cwd` is indistinguishable from probe noise (that was the leak in #222) and couldn't name a project anyway, so dropping it costs nothing real; a genuine session always carries its directory. The env marker above stays the primary defense — this filter covers senders ClaudeBar doesn't control.

## One shared probe session

- Every probe command (`/usage`, `/cost`) runs inside **one** Claude session instead of a fresh one per poll (#132). Before this, every quota poll left a new session JSONL under `~/.claude/projects/<probe-dir-slug>/` and showed up as an anonymous "Probe" session in tools like Claude Island or the `/resume` picker.
- Only the vendor's facts are data: both CLI data sources in `claude.json` carry a `session` block on their fetch — the stable id's text (`"id": { "stable": "ClaudeBar Probe" }`), the args that create the session, the args that resume it, the output that says the id is taken (`resumeOn`), the output that says it is gone, and the output that says this CLI build refuses the flags ([ENGINE_DESIGN §2.4](../../architecture/ENGINE_DESIGN.md#24--a-command-and-a-terminal)).
- **One id per login, the same forever.** The id is a UUID derived from `ClaudeBar Probe` and the call's environment, so the default login and each added login (its `CLAUDE_CONFIG_DIR`) have their own, and an app restart keeps it. Every run creates the session under that id: `claude /usage --allowed-tools "" --session-id <uuid> --name "ClaudeBar Probe"`. Only when the CLI answers that the id is *already in use* — a CLI that kept the session — is the same id resumed: `--resume <uuid>`. Claude Code 2.1.289 keeps no `/usage`-only session, so on it every refresh is one launch (measured 6.1–7.2 s, against 8.1–8.5 s for resume-then-create). The exact "in use" wording is unverified: 2.1.289 never produces it.
- **Nobody thinks in session ids**; what a person wants is "checking my usage doesn't leave a pile of empty sessions". The id is neither a setting nor a file — it is derived each run, so nothing can drift. A plan without `id` keeps the older order (resume a remembered random id, create again when it is gone), for a CLI that keeps every session.
- If the CLI can no longer find the session (e.g. `~/.claude` was cleared — "No conversation found with session ID"), the runner forgets the id and creates the session again under a fresh one. If the installed CLI is too old for `--session-id`/`--resume`/`--name`, the runner falls back to the plain invocation and stays there for the data source's lifetime; parsing is untouched either way. A refusal must be proven: the run has to exit non-zero **and** its output has to name a flag (`unknown option '--session-id'`), because the words alone can come from a hook's transcript. Both rules are lines in the `session` block, run by `CLISessionRunner` (`Modules/DataSources/Sources/Internal/Fetch/CLISession.swift`), and `SessionMemory` is an actor, so concurrent fetches of one data source agree on it.
- Reuse changes nothing else: the `CLAUDEBAR_PROBE=1` marker still travels on every run (#222), `/usage` keeps its ready markers while `/cost` keeps none (#317), and SessionStart/SessionEnd hooks still fire once per poll — resuming a session does not skip them.

## CLI screen parsing

- **Render the whole buffer, not just the visible screen.** In recent CLI versions `/usage` grew taller than the probe's 160×50 terminal (a usage-contribution report was added), which pushed the quota sections into scrollback. The renderer now reads visible rows plus scrollback.
- **Wait for the screen to settle.** `/usage` is a *target* screen, and a capture is a wait for it, not a wait for the CLI to go quiet. There are two quiet stretches on the way there: the CLI submits `/usage` only after its SessionStart hooks finish (seconds, on a busy machine), and the Usage tab then draws its cost panel plus a "Loading usage data…" placeholder before the quota bars arrive from a second request. Going idle during either one is not "done". The PTY buffer only ever grows, so a placeholder appearing or disappearing proves nothing either way. `CLICompletionRule.claudeUsage` therefore decides readiness *positively*: the capture ends when the screen carries a marker only a settled screen has (quota data or an error), and keeps waiting until then or the probe timeout. A capture that still ends on the placeholder is reported as a probable rate limit, not a parse failure (#271, #253).
- **Match markers on the text the screen shows, not on the bytes.** A TUI redraw writes every word run at its own absolute column, so `Current session` reaches the PTY as `Curre␛[10Gt␛[12Gsession` and `38% used` as `38%␛[59Gused`. The gap between the runs is padding the terminal inserts, not bytes the CLI sent, so a phrase can be split across half a dozen of them. `CLICompletionRule` collapses each run of escapes and other non-alphanumerics into one separator, which is what the rendered screen actually says. This is not what makes most ready markers findable — 137 of the 430 `/usage` captures attached to #317 contain one as a raw literal substring. It is the *placeholder* that needs it: "Loading usage data…", added in #271, is a raw substring of 0 of those 430 and a normalised match in 12, so the raw search could never have fired on a real screen. Replaying all 430 through the rule: 0 of the 114 boot screens are accepted as finished, and 0 of the 316 good screens are held open (#317). That replay is a script in the repo — `scripts/replay-claude-usage-captures.sh` — and it compiles the real `CLICompletionRule` alongside a driver, so the numbers above can be re-measured instead of taken on trust. It carries a redacted subset of the captures; `--extract <ClaudeBar.log> <dir> --all` rebuilds the full set from a log.
- **A marker is a whole token, and a section label is a whole row.** Collapsing the padding is what makes a split phrase matchable, and it also destroys the boundaries that said where one word ended. So the rule puts them back: a marker has to begin a token, and a marker declared as a *row* (`CLICompletionRule.Marker.row`) has to end at the end of its row. Without the second test the user's own SessionStart hook — "This project has no memory yet. The current session will seed it…" — satisfies the `Current session` marker by itself, which is the same false ready #317 is about reached a different way. The CLI paints a section label as a whole row (`Current session` then a line break); the hook's words sit mid-sentence. Across the 430 captures, 27 of the `Current session` occurrences end their row and 8 continue into a sentence, so the two are separable (#317). The row-end test is per-marker, not per-phrase, because only a label earns it: the other markers are values the CLI shares a row with other content — `27% used` sits beside `Resets 4:59pm (America/New_York)`, and a redraw artifact repeats the reset text on that same line — so requiring a whole row from them would hold the capture open on finished screens. In the 430, 12 good screens carry `% used` with no `Current session` label at all and are recognised on that marker alone.
- **A section label is no longer evidence the screen has finished (Claude Code 2.1.289).** `/usage` now paints the session's cost and the plugin skill-listing footprint first, then the `Current session` label, and fills the bars from a second request — sometimes more than the 3-second idle cutoff later. With the label among the ready markers, a capture could end on the label with no number under it (a 423-character screen in a real log): `Could not find session usage`, and the refresh fell back to the API. The label is gone from `readyWhen`; a screen is finished when it shows `% used`/`% left` or an error. The hook sentence the row test guarded against can no longer end the wait at all, because no marker is a label. Measured on a real 2.1.289 capture: the label is complete at byte 3,200 of 6,665 with no percentage on screen; `% used` arrives at byte 3,392.
- **The session's "gone", "in use" and "refused" phrases are matched on the text the screen shows, as the ready markers are.** Claude Code 2.1.289 paints `No conversation found with session ID: …` word by word with cursor moves (`No␛[4Gconversation␛[17Gfound`), so a raw substring search never matched `recreateOn`: ClaudeBar kept the dead session id, handed that 423-character line to the script ("Could not find session usage") and fell back to the API on every refresh after the first (#490). `CLISessionRunner` asks `CLICompletionRule` whether the screen shows a phrase. Resuming at all is now the exception: see *One shared probe session*.
- **`/cost` runs with no completion rule at all, and there is no marker that could do better.** `claude` registers `/cost` as an *alias* of `/usage`, so this is the same screen the other executor waits for — but an API-billed account has no quota bars, and the cost panel it does show is painted in full during boot, before the command resolves. Every candidate for a "the command has run" marker was measured against the 430 captures: the five panel rows are present in 114 of the 114 boot captures as in the 316 settled ones, `esc to interrupt` in 88 of 114 boot but also 268 of 316 settled, `Esc to cancel` in 114 of 114 boot and 268 of 316 settled. Nothing the settled screen carries is missing from the boot screen, because it is the same screen. (`API Usage Billing` does separate the two — 114 of 114 boot, 0 of 316 — but that separates the two *accounts* in the log, not two states of one account, so a rule keyed on it would be a rule about billing type.) So `ClaudeUsageProbe` gives `/cost` a second executor with `completionRule: nil` and lets the ordinary idle cutoff end the capture: measured 3.7s, against 20.6s for the same screen under `.claudeUsage`, whose markers are quota-bar markers an API account never reaches. A capture taken before the panel was painted has no `Total cost` row and fails to parse rather than answering $0.00 (#317).
- **`$0.00` from `/cost` is the probe's own session, so a subscription must never be routed there.** `/cost` reports the session the probe just started, which has made no request, so it answers `$0.0000` — and a probe that *succeeds* ends the refresh, which would stop the usage API that can read a subscription's real quota from ever running. Both routes into `/cost` are therefore vetoed when `~/.claude.json` says the account is a subscription: the "only available for subscription plans" message and the API-billing cost panel. A genuinely pay-as-you-go account is unaffected and keeps its cost card (#271, #317).
- **A `/cost` screen that reports a failure is not a cost of zero.** The parse checks for the same errors `/usage` does, before it looks for a number. A throttled or logged-out CLI still paints the panel, and `$0.0000` off it used to succeed — wrong, and final (#317).
- **Deduplicate "Resets …".** When the CLI redraws with cursor positioning, wide progress-bar characters can shift columns, so a line reads `Resets 4:59pm (TZ)Resets 4:59pm (TZ)`. The parser keeps the last occurrence.
- **Reset text formats**: relative (`2h 15m`), time only (`4:59pm`), `Dec 28`, `Jan 15, 3:30pm`, `Dec 25 at 4:59am`, with or without an explicit year and a trailing `(Area/City)` timezone. Newer CLIs put the percentage on the same line (`Resets 3pm (Europe/Amsterdam)  27% used`). Dates without a year roll forward to the next future occurrence.
- **Section labels**: "Current session", "Current week (all models)", "Current week (Opus)", "Current week (Sonnet only)" / "(Sonnet)", and "Current week (Fable". The Fable label is matched only up to the opening parenthesis so that a future "(Fable 5)" still matches. Fable resets at its own time and falls back to the all-models weekly reset.
- **Trust prompt**: the CLI auto-answers "Esc to cancel", "Ready to code here?", "Press Enter to continue", "ctrl+t to disable" and "Yes, I trust this folder". If the prompt is still on screen afterwards, ClaudeBar writes `projects["<probe dir>"].hasTrustDialogAccepted = true` into `.claude.json` (respecting `CLAUDE_CONFIG_DIR`) and retries. It leaves the file alone if the file is missing, isn't valid JSON, or contains types it doesn't expect.
- **A cost panel without its header is still a cost panel.** A full-screen redraw can drop the *API Usage Billing* header and leave `Total cost` and `Total duration (API)`; those two together mean the same as the header. A subscription account is told to run `claude auth login` again; an API-billed one goes to `/cost`.
- **Rate-limit text**: "rate limited", "rate limit exceeded" and "too many requests" count as errors, but lines containing "rate limits are" don't. That excludes promotions such as "rate limits are 2x higher".

## Classifying the account

- The header text "API Usage Billing" doesn't identify an account type. Subscriptions with Extra Usage credits show it next to real quota bars. Treating that header as pay-as-you-go made the session and weekly bars disappear.
- Pay-as-you-go is detected from the explicit "/usage is only available for subscription plans" message, or from a finished cost panel with **no** percentages anywhere.
- Even then, if `billingType` in `~/.claude.json` shows a subscription (e.g. `apple_subscription`, `stripe_subscription`), the CLI probe fails instead of running `/cost` — on *both* routes above, not just the cost panel. `/cost` would *succeed* with $0.00 and stop the API fallback that can read the real quota (#271, a Max plan billed through Apple; #317 for the "only available for subscription plans" message).

## API fields

- `five_hour`, `seven_day`: `utilization` (percent used) and `resets_at` (ISO 8601).
- `seven_day_opus` and `seven_day_sonnet` are legacy and now `null`. Model-scoped limits arrive in the generic `limits[]` array as `kind: "weekly_scoped"`, with `percent` and `scope.model.display_name` (e.g. "Fable 5"). The quota key is the first word of the display name, lowercased (`fable`). It **must** match the key the CLI probe hard-codes, or a saved `model:<name>` menu-bar selection stops working when the user switches modes. Entries in `limits[]` that duplicate `five_hour`/`seven_day` are skipped for now. If those legacy fields ever go `null`, extend the loop to the `session`/`weekly_all` kinds.
- Remaining quota isn't clamped, so a model over its quota shows a negative value.
- Extra Usage: prefer `spend` (`used`, `limit`, `enabled`) and fall back to legacy `extra_usage`. A missing or `null` limit means no cap. A limit that's present but invalid drops the whole entry, so it isn't mistaken for "uncapped".
- Tier: `claude_max`/`max`, `claude_pro`/`pro`, `api`/`claude_api`.

## Credentials

- Lookup order: `~/.claude/.credentials.json` → Keychain `Claude Code-credentials` → `CLAUDE_CODE_OAUTH_TOKEN`. A setup-token has only the `user:inference` scope, so it comes last. It has no refresh token, so a 401/403 with it isn't retried.
- The Keychain is read through `/usr/bin/security find-generic-password -w`, not `SecItemCopyMatching`. The item was created by Claude Code, which has a different code signature, so `SecItemCopyMatching` prompts on every access and "Always Allow" doesn't survive a ClaudeBar rebuild. The Apple-signed `security` tool doesn't prompt (#94).
- **macOS 26 hex quirk**: `security -w` returns any password containing a byte outside printable ASCII as lowercase hex. Pretty-printed JSON has newlines, which is enough to trigger it. ClaudeBar writes compact JSON, and decodes all-hex payloads when reading (valid JSON starts with `{`, which isn't a hex digit) (#255).
- Refresh write-back merges into the existing `claudeAiOauth` object so fields ClaudeBar doesn't model (e.g. `scopes`) are kept. Claude Code reads the same record (#256).
- The credential cache expires after 5 minutes so a re-login in the CLI is picked up. It's cleared on any auth failure. A refresh token is single-use, and the CLI may already have used it (#143).
- A failed Keychain read is logged with the `security` exit status. Before this, it looked like "no credentials" to someone who was signed in (#271).
- A missing `~/.claude/.credentials.json` is *not* logged — it is the normal case on macOS, and the Keychain read that follows logs its own failure. So when `isAvailable()` says there are no credentials and nothing was logged, the file simply was not there and the Keychain read succeeded, which is not a failure to report (#317).

## Added accounts

A second Claude login lives in its own config folder, as `CLAUDE_CONFIG_DIR=<folder> claude` makes it. The `accounts` block in `claude.json` says everything; no Swift knows Claude. Design: [features/multi-account/design.md](../../features/multi-account/design.md).

- **Choosing the folder** (`accounts.folder`). The folder must hold a key (`.credentials.json`, or the Keychain item below) and `.claude.json` with `oauthAccount.emailAddress`. The email names the login (`accountId.field: $context.account.email`) and is saved as `loginEmail`. A folder with an email but no key is not a login. Neither the default folder nor a login already listed is added again.
- **Signing in** (`accounts.signIn`). `claude auth login --claudeai` runs with `CLAUDE_CONFIG_DIR` set to a new folder under `~/.claudebar/accounts/claude/`, and with the inherited Anthropic keys unset. Then that folder is checked like a chosen one. *Remove* deletes a folder made this way, and never a folder you chose. Not yet tried against a real login: whether `claude auth login` completes without a terminal attached.
- **Keychain item.** For a config folder that isn't the default, Claude Code names its Keychain item `Claude Code-credentials-<first 8 hex digits of sha256(folder)>`. `accounts.folder.derived` works this out from the chosen path and saves it as `credentialService`. A folder signed in from a terminal with a different spelling of the same path (a symlink, a trailing slash) gets a different hash, so only its `.credentials.json` is found.
- **Each data source, patched** (`accounts.patch`, RFC 7396):
  - `cli` and `cliCost` run with `CLAUDE_CONFIG_DIR` set to the folder, and unset `CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_PROFILE` and the `CLAUDE_CODE_USE_BEDROCK` / `_VERTEX` / `_FOUNDRY` switches. Without that, an inherited key would answer for the wrong account.
  - Folder trust is written into the folder's own `.claude.json`.
  - `api` looks up the folder's key only. There is no `CLAUDE_CODE_OAUTH_TOKEN` step, because a shared environment token belongs to nobody in particular. The OAuth refresh block is kept by the merge, so a refreshed token is written back to the folder's file or Keychain item.
- **Identity, fail closed.** Every data source checks `$context.account.email` against `loginEmail` before fetching. If someone else has signed in to the folder since, the account reports *Reconnect the original Claude account in this folder* and shows no usage.
- **Default login only:** today's usage (`UsageHistory`, read from the default login's local logs) and guest passes (read with the default login's CLI).

## Guest passes

*Share Claude Code* is the guest-passes capability ([CANONICAL §2.1](../../architecture/CANONICAL_MODEL.md)). Claude's facts are the `guestPasses` block in `claude.json`; one generic worker (`CLIGuestPassSource` in the Kotlin `providers` package, `ClaudeGuestPassSource` in Swift until the context switches over) runs whatever block a definition declares, and names no vendor.

```json
"guestPasses": {
  "args": ["/passes", "--allowed-tools", ""],
  "timeout": 20,
  "environment": { "set": { "CLAUDEBAR_PROBE": "1" } },
  "autoResponses": { "Esc to cancel": "\r", "Ready to code here?": "\r", "Press Enter to continue": "\r", "ctrl+t to disable": "\r" },
  "succeededWhen": ["copied to clipboard", "referral"],
  "link": "https://claude\\.ai/referral/[A-Za-z0-9_-]+",
  "count": "(\\d+)\\s*left",
  "clipboard": true
}
```

| Key | What it says | Default |
|---|---|---|
| `args`, `input`, `timeout`, `environment`, `autoResponses` | how the definition's CLI (at its *CLI location*) is run in a terminal, in the dedicated working directory — the same words a `cli` fetch uses. `CLAUDEBAR_PROBE=1` keeps ClaudeBar's own hook quiet (#222) | none, `""`, 20 s, nothing, none |
| `succeededWhen` | phrases, in any case, of which the screen (ANSI codes stripped) must show one; none → *Command did not indicate success* | any screen |
| `link` | the pattern the link to share matches — first match on the screen, else on the clipboard | required |
| `count` | a pattern, any case, whose first group is the passes left; no match → an unknown count, still shareable | no count |
| `clipboard` | the CLI copies the link instead of printing it: read the clipboard when the screen shows none | `false` |

Laws: the link is required — none on the screen or the clipboard is *Could not find referral URL*; a run that fails is an execution failure with its own words; a count below zero is none (`GuestPass`). Passes are offered only to a plan that can issue them (`AccountTier.supportsGuestPasses`, #243) and only on the default login.

## Rate limiting (API)

- A 429 stores `retryAt` from `Retry-After` (seconds or an HTTP date). If the header is missing, malformed, in the past or `0`, the wait is 5 minutes. The endpoint has been seen sending `Retry-After: 0` while still returning 429 (anthropics/claude-code#30930). Until `retryAt`, `probe()` returns straight away without touching the network.
- Successful snapshots are cached for 15 minutes. After a quiet period, even a single call has triggered a one-hour `Retry-After`, which suggests the throttle works as a penalty box. A 5-minute cache still hit it. `backgroundRefreshFloor` is 15 minutes in API mode so polling doesn't just reread the cache (#204).

## Known limits

- The default login's credential file path ignores `CLAUDE_CONFIG_DIR`. Only the trust write and `.claude.json` lookup respect it. An added login's paths all use its folder.
- The OAuth `client_id` is Claude Code's. If Claude Code changes it, token refresh breaks.
