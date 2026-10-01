---
description: Where ClaudeBar's logs are, how to filter them in Console or the terminal, and what the common probe errors mean. Use when a provider shows an error or a stale number, or when a bug report needs logs.
---

# Troubleshooting

Start with the error in the popover. Find it in the [tables below](#common-errors), then follow the link to that provider's Gotchas. If that doesn't explain it, the log usually does.

## Log file

ClaudeBar writes everything at info level and above to:

```
~/Library/Logs/ClaudeBar/ClaudeBar.log
```

- **Open it**: Settings → **Logs** → **Open Log File** opens it in TextEdit. Attach it to bug reports.
- **Rotation**: when the file passes 5 MB it's renamed to `ClaudeBar.old.log`, replacing any older one, and a new file starts. So you have at most about 10 MB of history.
- **Line format**: `[2026-09-24T09:15:02.123Z] [ERROR] [probes] Claude probe failed: not logged in`, with the timestamp in UTC.
- **Levels**: `INFO`, `WARNING` and `ERROR`. Debug messages go only to the unified log (below).
- **No secrets**: tokens and API keys are never logged. Check before posting a log anyway, since it contains paths and project names.

```bash
tail -f ~/Library/Logs/ClaudeBar/ClaudeBar.log         # follow live
grep -i "probe" ~/Library/Logs/ClaudeBar/ClaudeBar.log  # probe problems only
```

## Unified log (Console.app and `log`)

The same messages, plus debug ones, go to macOS's unified log under the subsystem `com.tddworks.claudebar` (the app's bundle ID, all lower case; the filter is case-sensitive).

```bash
# Last hour, every level
log show --predicate 'subsystem == "com.tddworks.claudebar"' --info --debug --last 1h

# Errors only
log show --predicate 'subsystem == "com.tddworks.claudebar" AND messageType == error' --last 1h

# One category
log show --predicate 'subsystem == "com.tddworks.claudebar" AND category == "probes"' --info --debug --last 1h

# Live, while you reproduce the problem
log stream --predicate 'subsystem == "com.tddworks.claudebar"' --info --debug
```

In Console.app, search for `subsystem:com.tddworks.claudebar` and turn on Action → Include Info Messages / Include Debug Messages.

| Category | Covers |
|---|---|
| `probes` | Running CLIs and APIs to read quota, and why they failed |
| `monitor` | Refresh scheduling across providers |
| `providers` | Provider lifecycle, extension loading |
| `network` | HTTP requests and responses |
| `credentials` | Token loading and refresh (values are never logged) |
| `hooks` | The [session hooks](features/session-hooks/README.md) server |
| `notifications` | Quota and session notifications |
| `ui` | Menu bar and window lifecycle, unhandled [URLs](features/url-schemes/README.md) |
| `updates` | Sparkle update checks |

## Common errors

### In the popover

These are the messages a provider card shows. The cause depends on the provider, so follow the provider link from the next table.

| Message | Meaning |
|---|---|
| `CLI not found: <name>` | The provider's CLI isn't on the PATH ClaudeBar sees. Install it or check its location |
| `Authentication required. Please log in.` | Not signed in, or the stored token was rejected. Sign in to the CLI or app again |
| `Session expired. …` | The sign-in or cookie expired. The rest of the message says how to renew it |
| `Please trust this folder in Claude CLI` | Claude Code is waiting on its folder-trust prompt |
| `CLI update required` | The CLI printed an update notice instead of usage. Update it |
| `Subscription required for usage data` | The account is on API billing, which has no usage limits to show |
| `No usage data available` | The provider answered but had nothing to report yet |
| `Failed to parse output: …` | The CLI or API changed its output. Report it with the log |
| `Request timed out` | The CLI or server didn't answer in time. Usually transient |
| `Rate limited. Retrying in …` | The provider's API returned HTTP 429. ClaudeBar stops calling it until then, and the next refresh after that works again |

### In the log

| Log line | Meaning | Provider |
|---|---|---|
| `Claude probe blocked: folder trust required` | Claude Code is asking whether to trust a folder | [claude](providers/claude/README.md) |
| `Claude probe failed: token has expired, re-authentication required` | Run `claude` and sign in again | [claude](providers/claude/README.md) |
| `Claude probe failed: not logged in` / `authentication error, login required` | No valid Claude Code sign-in | [claude](providers/claude/README.md) |
| `Codex probe failed: data not available yet` | Codex hasn't synced usage yet; wait a moment | [codex](providers/codex/README.md) |
| `Codex probe failed: not logged in` | Run `codex` and sign in | [codex](providers/codex/README.md) |
| `Codex probe failed: no rate limits in RPC response` | The app-server answered without limits | [codex](providers/codex/README.md) |
| `Gemini probe failed: no access token in credentials file` / `credentials file not found` | Sign in with the Gemini CLI again | [gemini](providers/gemini/README.md) |
| `Gemini probe failed: authentication required (401)` | The Gemini token was rejected. Sign in with the Gemini CLI again | [gemini](providers/gemini/README.md) |
| `Antigravity probe failed: not running and no stored credentials` | Open Antigravity, or sign in once so a stored sign-in exists | [antigravity](providers/antigravity/README.md) |
| `Zai probe failed: No API key found (…)` / `No z.ai endpoint found in Claude config` | The GLM key or z.ai base URL isn't in the Claude config or env var | [zai](providers/zai/README.md) |
| `Copilot: No GitHub token configured (check token field or env var)` | Add a token in Settings → Providers → Copilot | [copilot](providers/copilot/README.md) |
| `Copilot: Forbidden - check token permissions (403)` | The token is missing a required scope | [copilot](providers/copilot/README.md) |
| `Bedrock probe failed: no regions configured` | Set at least one AWS region | [bedrock](providers/bedrock/README.md) |
| `Cursor: No access token found in database (not logged in?)` | Sign in to Cursor | [cursor](providers/cursor/README.md) |
| `Kimi probe failed: authentication error (…)` | The kimi.com cookie was rejected | [kimi](providers/kimi/README.md) |
| `AmpCode probe failed: amp binary not found` | Install the Amp CLI | [ampcode](providers/ampcode/README.md) |
| `Kiro binary 'kiro-cli' not found in PATH` | Install the Kiro CLI | [kiro](providers/kiro/README.md) |
| `Grok: No credentials found` / `Token refresh rejected (…)` | Run `grok login` again | [grok](providers/grok/README.md) |
| `OpenCode: No Go subscription for this key (HTTP 403)` | The key works but has no OpenCode Go plan | [opencode-go](providers/opencode-go/README.md) |
| `Command Code: No API key found` | Run `cmd login`, or set the API key env var | [commandcode](providers/commandcode/README.md) |
| `MiniMax: No API key configured (check env var or settings)` | Add the key in Settings or set the env var | [minimax](providers/minimax/README.md) |
| `DeepSeek: No API key configured (check env var or settings)` | Add the key in Settings or set the env var | [deepseek](providers/deepseek/README.md) |
| `Vercel: No API key configured (check env var or settings)` | Add the key in Settings or set the env var | [vercel-gateway](providers/vercel-gateway/README.md) |
| `RPC transport: '<name>' not found in PATH` | A CLI used over RPC (such as `codex`) isn't installed where ClaudeBar looks | the provider using it |
| `Hook HTTP server failed: …` | Port 19847 is taken, so session hooks are off | [session hooks](features/session-hooks/README.md) |

Providers not listed here (alibaba, mistral, omp) log `<Provider> probe failed: <reason>` or `<Provider>: <reason>`; see [alibaba](providers/alibaba/README.md), [mistral](providers/mistral/README.md) and [omp](providers/omp/README.md).

## Still stuck

1. Reproduce it with `log stream` (above) running.
2. Open an [issue](https://github.com/tddworks/ClaudeBar/issues) with the provider, the popover message, your ClaudeBar version (Settings → About) and the relevant log lines.

See also: [settings.md](settings.md) for where configuration and credentials live.
