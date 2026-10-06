---
description: Where ClaudeBar's logs are, how to filter them in Console or the terminal, and what the common provider errors mean. Use when a provider shows an error or a stale number, or when a bug report needs logs.
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
- **Line format**: `[2026-09-24T09:15:02.123Z] [INFO] [probes] claude: every data source failed; reporting Authentication required. Please log in.`, with the timestamp in UTC.
- **Levels**: `INFO`, `WARNING` and `ERROR`. Debug messages go only to the unified log (below).
- **No secrets**: tokens and API keys are never logged. Check before posting a log anyway, since it contains paths and project names.

```bash
tail -f ~/Library/Logs/ClaudeBar/ClaudeBar.log         # follow live
grep -i "probe" ~/Library/Logs/ClaudeBar/ClaudeBar.log  # provider fetch problems only
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
| **NOT SET UP**, or a card with a *Set up* button | Nothing to read your limits with yet: the CLI isn't installed, or you never signed in. The card says what it takes; any daily usage ClaudeBar can already read, such as Claude Desktop's tokens, still shows below it, and then the header shows no badge |
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

Every provider runs on the same engine, so its log lines have the same shape: `<login> <data source>: …`, where the login is the provider id (`claude`, `kimi`) or an added account's (`codex.4f2a`).

| Log line | Meaning |
|---|---|
| `<login> <source> failed (…), trying <other>` / `handed off to <other> (<reason>)` | The data source failed (or found no key) and the next one is being tried. Not an error on its own |
| `<login>: every data source failed; reporting <reason>` | Nothing answered; `<reason>` is the error the card shows |
| `<login> <source>: no <file> — refusing to run` | A file the data source needs (a signed-in folder's login) is gone. Sign in again |
| `<login> <source>: HTTP 401, refreshing the token once` / `Token refresh refused (HTTP 400, …)` | The token was refused; a refused refresh means signing in again |
| `<login> <source>: the credential changed on disk; using the new one` | The provider's own CLI renewed its login meanwhile. Fine |
| `Running <cli> to renew its login` / `<cli> isn't installed, so its login can't be renewed` | A login the CLI owns (Gemini) is being renewed by running it |
| `'<cli>' not found in PATH` / `<cli> exited with <code>` / `<cli> could not start` | The provider's CLI isn't installed where ClaudeBar looks, failed, or couldn't run. Set its location in the provider's settings |
| `<login> screen reports: <phrase>` | A CLI's screen showed an error phrase (logged out, an update notice) |
| `<login> mapping script '<file>' threw: …` | The response changed shape. Report it with the log |
| `<app> isn't running` / `<app> is running without its <value>` | A local app (Antigravity) isn't running, or started without what its server needs |
| `http step <name>: failed, going on without it` | An optional request (a project lookup) failed; the rest went ahead |
| `<namespace> metrics in <region> failed: …` | One cloud region failed (Bedrock); the others still count |
| `A key was found but its <field> isn't one this provider uses; not using it` | A key found in another tool's config points elsewhere (e.g. a Claude Code key that isn't Z.ai's) |
| `Hook HTTP server failed: …` | Port 19847 is taken, so session hooks are off ([session hooks](features/session-hooks/README.md)) |
| `Usage history: scanned <n> recent log files (…)` / `… raw records, … after dedup` | *TODAY'S USAGE* read a tool's local logs. Days that have closed are kept in `~/.claudebar/usage-history/`; deleting that folder makes the next read sum them again |
| `Usage history: price file '<file>' is missing` / `is malformed` | A provider's price list didn't load, so its usage history shows tokens without cost. Report it with the log |
| `'<tool>' at <path> is Intel-only and will run under Rosetta; macOS may name ClaudeBar in its 'apps for Intel processors' warning` | The only copy of the tool on your Mac is Intel-only, so running it is translated ([below](#support-for-apps-for-intel-processors-macos-warning)) |
| `'<tool>' resolved to <path>, which has no arm64 slice; using the native copy at <other> instead` | Two copies of the tool existed; ClaudeBar picked the native one ([below](#support-for-apps-for-intel-processors-macos-warning)) |
| `'<path>' has no slice this Mac runs natively; using /bin/zsh for PATH lookups` | Your login shell is Intel-only, so ClaudeBar asks the system shell for PATHs instead of running the shell translated ([below](#support-for-apps-for-intel-processors-macos-warning)) |

Each provider's own errors and what to do: its page under [providers/](providers/).

## Support for apps for Intel processors (macOS warning)

macOS 26 shows a notification that says *"Support for apps for Intel processors will end. This version of '<app>' contains components that will not work in future macOS releases."* When the app it names is ClaudeBar, the Intel-only component isn't ClaudeBar itself — it's a tool ClaudeBar ran on your behalf: the coding CLIs it reads quotas from, `node` behind them, or the login shell it asks for your PATH.

That matters because macOS records whichever app spawned a translated process as the one responsible. An Intel-only tool runs under Rosetta on an Apple-silicon Mac, and ClaudeBar — whose whole job is spawning those tools — gets named.

ClaudeBar avoids what it can:

- It reads a binary's architecture before running it. When several copies of a tool exist (for example an Intel-only one from an old nvm install and a native one), it picks the native one; the shell's answer still wins when there is nothing native to prefer.
- If the only copy is Intel-only, ClaudeBar still uses it — you installed it there — and logs the one line above, so the choice is never silent.
- When your login shell itself is Intel-only, ClaudeBar asks the always-universal system shell (`/bin/zsh`) for PATH lookups instead of running your shell translated.

If the warning still names ClaudeBar, find what is Intel-only and reinstall it natively:

```bash
# Which of the usual suspects are Intel-only on your arm64 Mac
for b in claude codex gemini node bun python3; do
  p=$(which $b 2>/dev/null) || continue
  lipo -archs "$p" | grep -q arm64 || echo "Intel-only: $p"
done
```

Reinstalling that tool with a native build (for example `arch -arm64` Homebrew, or an arm64 Node from nvm) makes both the Rosetta runs and the warning go away.

## Still stuck

1. Reproduce it with `log stream` (above) running.
2. Open an [issue](https://github.com/tddworks/ClaudeBar/issues) with the provider, the popover message, your ClaudeBar version (Settings → About) and the relevant log lines.

See also: [settings.md](settings.md) for where configuration and credentials live.
