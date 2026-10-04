# Kimi: design

Contributor notes for Kimi's two data sources. User-facing setup is in [README.md](README.md).

## As data

Kimi is `Modules/Providers/Resources/Providers/kimi.json` with `kimi-cli.js` and `kimi-api.js`, run by the generic engine (TARGET_ARCHITECTURE §8.2); no Swift names it. Ported from #393.

- **Region is one choice setting** whose options carry `site` and `domain`: the URL, `Origin`, `Referer`, cookie domains and dashboard are `{{setting.region.site}}` / `{{setting.region.domain}}`. Saved where the old card kept it (`kimi.region`); the old Probe Mode is the data source (`kimi.probeMode`).
- **CLI.** A `cli` (terminal) fetch with `inputDelay: 1.5`, the `💫` / `context:` auto-responses, the trust-folder Enter and the ready markers below. Checked live with Kimi Code CLI 1.x: the screen settles, `/usage` is typed, and a signed-out CLI's "Authorization failed" now asks for `/login` instead of "No quota data found".
- **API.** `KIMI_AUTH_TOKEN`, then the `kimi-auth` cookie (`browserCookies`, suffix-matched on the region's domain). `{{system.timeZone}}` fills `r-timezone`. 401/403 are *Key needed*.
- **Left and Window laws.** A limit of 0, or neither `used` nor `remaining`, is no quota rather than 100%. The rate limit's window is its own `window.duration` × `timeUnit`. The plan quota is weekly only for the three weekly plans (by limit); any other plan is "Plan" with no window, where the probe called every plan weekly. The CLI's "Monthly limit" is the month ending on its reset.
- **Accounts.** `token` is `"for": ["api"]`, `home` is `"for": ["cli"]`; *Add Account* asks for the active source's one plus Region. A CLI login runs `kimi` with `KIMI_SHARE_DIR`/`KIMI_CODE_HOME` set to its folder and `KIMI_AUTH_TOKEN`/`KIMI_API_KEY`/`KIMI_BASE_URL` unset; `requiresFiles` fails closed when the folder is gone.

## CLI mode: interactive `kimi` + `/usage`

ClaudeBar starts `kimi` with no arguments in a PTY (the TUI needs a terminal), waits for a "ready" marker, types `/usage`, and parses the captured output. Timeout: 15 s.

### Ready markers

| CLI | Marker | Why |
|---|---|---|
| Before 0.36 | `💫` prompt | Shown when the prompt accepts input |
| 0.36+ | `context:` (the status footer, e.g. `context: N% ...`) | 0.36 dropped the `💫` prompt, so the probe never typed `/usage` ([#289](https://github.com/tddworks/ClaudeBar/pull/289)) |

Both are registered as auto-responses. Each fires at most once, so older CLIs are unaffected by the second one.

### `/usage` layouts

Before 0.36:

```
╭─────────────────────────────── API Usage ───────────────────────────────╮
│  Weekly limit  ━━━━━━━━━━━━━━━━━━━━  100% left  (resets in 6d 23h 22m)  │
│  5h limit      ━━━━━━━━━━━━━━━━━━━━  100% left  (resets in 4h 22m)      │
╰─────────────────────────────────────────────────────────────────────────╯
```

0.36+ (captured from 0.36.1 and 0.41.0):

```
  ╭ Usage ───────────────────────────────────────────────────────────╮
  │   Weekly limit  ██████████████████░░  90% used  resets in 35m    │
  │   5h limit      ██░░░░░░░░░░░░░░░░░░  12% used  resets in 3h 35m │
  ╰──────────────────────────────────────────────────────────────────╯
```

2.x (captured from 2.1.1): the panel gained Session usage and Context window
sections, and new plans replaced the weekly window with a monthly total — the
plan line is now `Monthly limit`:

```
  ╭ Usage ────────────────────────────────────────────────────────────────╮
  │ Session usage                                                         │
  │   No token usage recorded yet.                                        │
  │ Context window                                                        │
  │   ░░░░░░░░░░░░░░░░░░░░      0%  (0 / 1M)                              │
  │ Plan usage                                                            │
  │   5h limit       ░░░░░░░░░░░░░░░░░░░░  0% used  resets in 2h 41m      │
  │   Monthly limit  ░░░░░░░░░░░░░░░░░░░░  2% used  resets in 24d 16h 42m │
  │                  kimi 2% · code 0%                                    │
  ╰───────────────────────────────────────────────────────────────────────╯
```

Parsing rules, line by line:

- A line is a quota line if it contains `weekly` (→ weekly), `monthly` (→ `.timeLimit("Monthly")`, a 30-day window) or `5h` / `hour` (→ session). Everything else — including the `Context window … 0%  (0 / 1M)` and `kimi 2% · code 0%` lines — is ignored.
- `N% left` is remaining; `N% used` is converted to `100 - N`, clamped at 0. The old format puts the reset in parentheses, the new one doesn't.
- Reset durations combine `d`, `h`, `m` and `s` parts (`resets in 45s` appears in the new format).
- **Keep the first line of each type.** The TUI redraws the panel on refresh and resize, which used to produce duplicate quotas.
- The raw PTY output is parsed line by line; it isn't rendered through `TerminalRenderer` the way Claude's is, and ANSI codes aren't stripped. Stripping was added (`141a065`) and removed the same day (`ceebb1c`) without a recorded reason. If a CLI release starts colouring the percentage or reset text, look here first.

### Typing `/usage` without losing it

The probe runs the CLI in a dedicated directory
(`~/Library/Application Support/ClaudeBar/Probe`, same one the Claude probe
uses). Inheriting the app's cwd is not safe: the CLI shows a one-time
**"Trust this folder?"** prompt per folder (project MCP trust), the typed
`/usage` lands in that prompt instead of the input box, and the probe reports
"No quota data found" on every run. An auto-response presses Enter on the
prompt, the choice is remembered per folder, and it never appears again.

The probe types `/usage` twice, on purpose:

1. As **delayed input** (`InteractiveRunner.Options.inputDelay`, 1.5 s). Typing
   the instant the `context:` footer first painted raced the TUI's startup
   redraw — the text landed in an input box that a redraw then discarded, the
   panel never rendered, and the probe reported "No quota data found". The
   delay lets the startup paint settle first.
2. Through the **auto-response markers** (`💫`, `context:`) as backup. Each
   marker fires at most once, and a duplicate `/usage` is harmless because
   parsing keeps the first panel occurrence.

The probe also passes a `CLICompletionRule` (`usageCompletionRule`): the
`context:` footer is present from startup while the usage panel only arrives
after a network round-trip to the billing API, so a 3 s idle gap does not mean
the screen is done. `% used` / `% left` (or an error/auth screen) marks the
settled screen. Pre-0.36 CLIs without the footer never match the pending
marker and behave as before.

### Version numbers

The 0.36 / 0.41 versions are from the #289 report, which doesn't say which package they belong to. Two CLIs install a `kimi` binary: the current Kimi Code CLI (`MoonshotAI/kimi-code`, `code.kimi.com/kimi-code/install.sh`) and the Python `kimi-cli` on PyPI, which is now archived and numbered 1.x. Read "before 0.36" in the code as "the older layout", whichever CLI printed it.

## API mode: Kimi billing gateway

```
POST <webBaseURL>/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages
Body: {"scope":["FEATURE_CODING"]}
```

A Connect-RPC endpoint used by the web console. The token is sent both as `Authorization: Bearer <token>` and as `Cookie: kimi-auth=<token>`, along with browser-like headers (`Origin`/`Referer` of the region's web base, a Chrome User-Agent, `connect-protocol-version: 1`, `x-msh-platform: web`, `r-timezone`).

### Region

Kimi runs two separate platforms — China (`kimi.com`) and International
(`kimi.ai`) — with separate accounts, cookies and quotas. The `region`
choice setting's options carry everything that differs: the usage URL,
Origin/Referer, console URL and cookie domain. The setting (`kimi.region` in
settings.json, default `china`) is filled into each login's data sources,
like MiniMax's region. The international usage URL is inferred by analogy with
the documented kimi.com endpoint and has not been verified against a live
international account.

### Token resolution

1. `KIMI_AUTH_TOKEN` from the app's process environment.
2. The `kimi-auth` cookie for the selected region's domains (`kimi.com` / `www.kimi.com`, or `kimi.ai` / `www.kimi.ai`) from browser cookie stores (SweetCookieKit, default browser import order; expired cookies skipped). This is why API mode needs Full Disk Access.

If neither resolves, the probe reports itself unavailable, so the provider is skipped without an error.

### Fields that matter

- `usages[]` → the entry with `scope == "FEATURE_CODING"`. Missing → parse error.
- `detail` is the weekly quota: `limit`, `used`, `remaining` (all **strings**), `resetTime` (ISO 8601, with or without fractional seconds). `used` and `remaining` can be missing; the other is derived from `limit`.
- `limits[]` holds rate limits. The 5-hour window is the entry with `window.duration == 300` and `window.timeUnit == "TIME_UNIT_MINUTE"`; if none matches, the first entry is used.
- The plan isn't in the response. It's inferred from the weekly `limit`: 1024 → Andante, 2048 → Moderato, 7168 → Allegretto. Other limits show no tier.

HTTP 401/403 → authentication required.
