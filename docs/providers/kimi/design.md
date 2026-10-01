# Kimi probe research

Contributor notes for the two Kimi probes. User-facing setup is in [README.md](README.md).

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

Parsing rules, line by line:

- A line is a quota line if it contains `weekly` (→ weekly) or `5h` / `hour` (→ session). Everything else is ignored.
- `N% left` is remaining; `N% used` is converted to `100 - N`, clamped at 0. The old format puts the reset in parentheses, the new one doesn't.
- Reset durations combine `d`, `h`, `m` and `s` parts (`resets in 45s` appears in the new format).
- **Keep the first line of each type.** The TUI redraws the panel on refresh and resize, which used to produce duplicate quotas.
- The raw PTY output is parsed line by line; it isn't rendered through `TerminalRenderer` the way Claude's is, and ANSI codes aren't stripped. Stripping was added (`141a065`) and removed the same day (`ceebb1c`) without a recorded reason. If a CLI release starts colouring the percentage or reset text, look here first.

### Version numbers

The 0.36 / 0.41 versions are from the #289 report, which doesn't say which package they belong to. Two CLIs install a `kimi` binary: the current Kimi Code CLI (`MoonshotAI/kimi-code`, `code.kimi.com/kimi-code/install.sh`) and the Python `kimi-cli` on PyPI, which is now archived and numbered 1.x. Read "before 0.36" in the code as "the older layout", whichever CLI printed it.

## API mode: Kimi billing gateway

```
POST https://www.kimi.com/apiv2/kimi.gateway.billing.v1.BillingService/GetUsages
Body: {"scope":["FEATURE_CODING"]}
```

A Connect-RPC endpoint used by the web console. The token is sent both as `Authorization: Bearer <token>` and as `Cookie: kimi-auth=<token>`, along with browser-like headers (`Origin`/`Referer` of kimi.com, a Chrome User-Agent, `connect-protocol-version: 1`, `x-msh-platform: web`, `r-timezone`).

### Token resolution

1. `KIMI_AUTH_TOKEN` from the app's process environment.
2. The `kimi-auth` cookie for `kimi.com` / `www.kimi.com` from browser cookie stores (SweetCookieKit, default browser import order; expired cookies skipped). This is why API mode needs Full Disk Access.

If neither resolves, the probe reports itself unavailable, so the provider is skipped without an error.

### Fields that matter

- `usages[]` → the entry with `scope == "FEATURE_CODING"`. Missing → parse error.
- `detail` is the weekly quota: `limit`, `used`, `remaining` (all **strings**), `resetTime` (ISO 8601, with or without fractional seconds). `used` and `remaining` can be missing; the other is derived from `limit`.
- `limits[]` holds rate limits. The 5-hour window is the entry with `window.duration == 300` and `window.timeUnit == "TIME_UNIT_MINUTE"`; if none matches, the first entry is used.
- The plan isn't in the response. It's inferred from the weekly `limit`: 1024 → Andante, 2048 → Moderato, 7168 → Allegretto. Other limits show no tier.

HTTP 401/403 → authentication required.
